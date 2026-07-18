// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `firebase_messaging`, implemented over dart:ffi.
//
// Method-channel plugins are not supported on watchOS, so this package
// follows the FFI plugin model: `watchos/Classes/firebase_messaging_watchos_ffi.m`
// bridges the Firebase Apple SDK (`FirebaseMessaging`, linked via the SwiftPM
// dependency declared in `watchos/Package.swift`) behind C symbols returning
// JSON, the CLI force-loads the compiled archive into the watch binary, and
// this class resolves the symbols via `DynamicLibrary.process()`.
//
// The APNs device token reaches the process through the app-level
// WKApplicationDelegate; the flutter-watchos runner's
// FlutterWatchOSAppDelegate rebroadcasts those callbacks as NSNotifications
// that the native layer observes. Received messages queue natively; a Dart
// pump drains them into the platform interface's onMessage /
// onMessageOpenedApp streams.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging_platform_interface/firebase_messaging_platform_interface.dart';

/// FFI bindings to the native firebase_messaging_watchos C functions.
///
/// Overridable for tests via [FirebaseMessagingWatchos.bindingsOverride]: the
/// [FirebaseMessagingWatchosBindings.forTesting] constructor skips FFI
/// initialization so fakes work off-device.
class FirebaseMessagingWatchosBindings {
  /// Creates bindings that look up native symbols in the current process.
  FirebaseMessagingWatchosBindings() : _lib = DynamicLibrary.process();

  /// Constructor for fakes/mocks — skips FFI initialization.
  FirebaseMessagingWatchosBindings.forTesting() : _lib = null;

  final DynamicLibrary? _lib;

  late final Pointer<Utf8> Function(Pointer<Utf8>) _begin = _lib!
      .lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Utf8>)>('firebase_messaging_watchos_begin');

  late final Pointer<Utf8> Function(int) _poll = _lib!.lookupFunction<
      Pointer<Utf8> Function(Int64),
      Pointer<Utf8> Function(int)>('firebase_messaging_watchos_poll');

  late final Pointer<Utf8> Function() _state = _lib!.lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('firebase_messaging_watchos_state');

  late final Pointer<Utf8> Function(Pointer<Utf8>) _takeMessages =
      _lib!.lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>),
              Pointer<Utf8> Function(Pointer<Utf8>)>(
          'firebase_messaging_watchos_take_messages');

  late final Pointer<Utf8> Function(Pointer<Utf8>) _configure =
      _lib!.lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>),
              Pointer<Utf8> Function(Pointer<Utf8>)>(
          'firebase_messaging_watchos_configure');

  late final void Function(Pointer<Utf8>) _free = _lib!.lookupFunction<
      Void Function(Pointer<Utf8>),
      void Function(Pointer<Utf8>)>('firebase_messaging_watchos_free');

  /// Decodes and frees a native JSON string result.
  Map<String, Object?> _consume(Pointer<Utf8> ptr) {
    if (ptr == nullptr) {
      return <String, Object?>{
        'error': 'Native call returned null.',
        'code': 'internal',
      };
    }
    final String jsonString = ptr.toDartString();
    _free(ptr);
    return (json.decode(jsonString) as Map).cast<String, Object?>();
  }

  Map<String, Object?> _call1(
    Pointer<Utf8> Function(Pointer<Utf8>) fn,
    String arg,
  ) {
    final Pointer<Utf8> ptr = arg.toNativeUtf8();
    try {
      return _consume(fn(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Starts an asynchronous operation; returns `{"token": N}`.
  Map<String, Object?> begin(Map<String, Object?> request) =>
      _call1(_begin, json.encode(request));

  /// Polls an operation; `{"pending": true}` until the result is ready.
  Map<String, Object?> poll(int token) => _consume(_poll(token));

  /// Reads the plugin's token state.
  Map<String, Object?> state() => _consume(_state());

  /// Drains a message queue ("foreground"/"opened") or takes the initial
  /// message ("initial").
  Map<String, Object?> takeMessages(String kind) =>
      _call1(_takeMessages, kind);

  /// Applies synchronous configuration.
  Map<String, Object?> configure(Map<String, Object?> request) =>
      _call1(_configure, json.encode(request));
}

/// watchOS implementation of [FirebaseMessagingPlatform].
class FirebaseMessagingWatchos extends FirebaseMessagingPlatform {
  /// Creates the platform implementation, optionally bound to [appInstance].
  FirebaseMessagingWatchos({super.appInstance});

  /// Test hook: set before first use to replace the FFI bindings.
  static FirebaseMessagingWatchosBindings? bindingsOverride;

  /// How often a pending native operation is polled for its result.
  static Duration opPollInterval = const Duration(milliseconds: 40);

  /// How often the message pump drains the native queues (and the
  /// token-refresh stream checks the token generation).
  static Duration messagePumpInterval = const Duration(milliseconds: 300);

  static FirebaseMessagingWatchosBindings? _bindings;

  static FirebaseMessagingWatchosBindings get _b =>
      bindingsOverride ?? (_bindings ??= FirebaseMessagingWatchosBindings());

  static final Map<String, FirebaseMessagingWatchos> _instances =
      <String, FirebaseMessagingWatchos>{};

  static Timer? _messagePump;

  bool _autoInitEnabled = true;

  /// Registers this implementation as the default `firebase_messaging`
  /// platform implementation on watchOS and starts the message pump that
  /// feeds [FirebaseMessagingPlatform.onMessage] /
  /// [FirebaseMessagingPlatform.onMessageOpenedApp].
  static void registerWith() {
    FirebaseMessagingPlatform.instance = FirebaseMessagingWatchos();
    startMessagePump();
  }

  /// Starts (or restarts) the periodic drain of the native message queues.
  static void startMessagePump() {
    _messagePump?.cancel();
    _messagePump = Timer.periodic(messagePumpInterval, (_) {
      // Skip the FFI round-trips while nothing listens; undrained messages
      // just accumulate natively and are delivered on the first listen.
      if (!FirebaseMessagingPlatform.onMessage.hasListener &&
          !FirebaseMessagingPlatform.onMessageOpenedApp.hasListener) {
        return;
      }
      for (final Object? map in _drain('foreground')) {
        if (map is Map) {
          FirebaseMessagingPlatform.onMessage
              .add(RemoteMessage.fromMap(map.cast<String, dynamic>()));
        }
      }
      for (final Object? map in _drain('opened')) {
        if (map is Map) {
          FirebaseMessagingPlatform.onMessageOpenedApp
              .add(RemoteMessage.fromMap(map.cast<String, dynamic>()));
        }
      }
    });
  }

  /// Stops the message pump (tests).
  static void stopMessagePump() {
    _messagePump?.cancel();
    _messagePump = null;
  }

  static List<Object?> _drain(String kind) {
    final Map<String, Object?> result = _b.takeMessages(kind);
    return result['messages'] as List<Object?>? ?? const <Object?>[];
  }

  @override
  FirebaseMessagingPlatform delegateFor({required FirebaseApp app}) {
    return _instances[app.name] ??= FirebaseMessagingWatchos(appInstance: app);
  }

  @override
  FirebaseMessagingPlatform setInitialValues({bool? isAutoInitEnabled}) {
    _autoInitEnabled = isAutoInitEnabled ?? _autoInitEnabled;
    return this;
  }

  @override
  bool get isAutoInitEnabled {
    final Map<String, Object?> result =
        _b.configure(<String, Object?>{'op': 'getAutoInit'});
    if (result['enabled'] is bool) {
      _autoInitEnabled = result['enabled']! as bool;
    }
    return _autoInitEnabled;
  }

  @override
  Future<void> setAutoInitEnabled(bool enabled) async {
    _throwIfError(_b.configure(
        <String, Object?>{'op': 'setAutoInit', 'enabled': enabled}));
    _autoInitEnabled = enabled;
  }

  @override
  Future<RemoteMessage?> getInitialMessage() async {
    final Map<String, Object?> result = _b.takeMessages('initial');
    final Object? message = result['message'];
    return message is Map
        ? RemoteMessage.fromMap(message.cast<String, dynamic>())
        : null;
  }

  @override
  void registerBackgroundMessageHandler(BackgroundMessageHandler handler) {
    // watchOS has no background-isolate mechanism; background data messages
    // are not delivered to Dart. Foreground messages flow via onMessage.
  }

  @override
  Future<String?> getToken({String? serviceWorkerScriptPath, String? vapidKey}) async {
    // FirebaseMessaging needs the APNs device token first; trigger the
    // registration and give the delegate callback a moment to arrive.
    Map<String, Object?> state = _b.state();
    if (state['apnsToken'] == null) {
      _throwIfError(_b.configure(
          <String, Object?>{'op': 'registerForRemoteNotifications'}));
      final DateTime deadline =
          DateTime.now().add(const Duration(seconds: 8));
      while (state['apnsToken'] == null &&
          state['apnsError'] == null &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        state = _b.state();
      }
    }
    final Map<String, Object?> result =
        await _awaitOp(<String, Object?>{'op': 'getToken'});
    return result['fcmToken'] as String?;
  }

  @override
  Future<void> deleteToken() async {
    await _awaitOp(<String, Object?>{'op': 'deleteToken'});
  }

  @override
  Future<String?> getAPNSToken() async {
    return _b.state()['apnsToken'] as String?;
  }

  @override
  Stream<String> get onTokenRefresh {
    late StreamController<String> controller;
    Timer? timer;
    int? lastGeneration;
    void poll() {
      final Map<String, Object?> state = _b.state();
      final int generation = state['tokenGeneration'] as int? ?? 0;
      final String? token = state['fcmToken'] as String?;
      if (lastGeneration == null) {
        // Baseline only: onTokenRefresh reports refreshes, not the current
        // token.
        lastGeneration = generation;
        return;
      }
      if (generation != lastGeneration && token != null) {
        lastGeneration = generation;
        controller.add(token);
      }
    }

    controller = StreamController<String>(
      onListen: () {
        poll();
        timer = Timer.periodic(messagePumpInterval, (_) => poll());
      },
      onCancel: () {
        timer?.cancel();
        timer = null;
      },
    );
    return controller.stream;
  }

  @override
  Future<NotificationSettings> getNotificationSettings() async {
    final Map<String, Object?> result =
        await _awaitOp(<String, Object?>{'op': 'getNotificationSettings'});
    return _settingsFromMap(
        (result['settings']! as Map).cast<String, Object?>());
  }

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<NotificationSettings> requestPermission({
    bool alert = true,
    bool announcement = false,
    bool badge = true,
    bool carPlay = false,
    bool criticalAlert = false,
    bool provisional = false,
    bool sound = true,
    bool providesAppNotificationSettings = false,
  }) async {
    final Map<String, Object?> result = await _awaitOp(<String, Object?>{
      'op': 'requestPermission',
      'alert': alert,
      'announcement': announcement,
      'badge': badge,
      'criticalAlert': criticalAlert,
      'provisional': provisional,
      'sound': sound,
    });
    return _settingsFromMap(
        (result['settings']! as Map).cast<String, Object?>());
  }

  @override
  Future<void> setForegroundNotificationPresentationOptions({
    bool alert = false,
    bool badge = false,
    bool sound = false,
  }) async {
    _throwIfError(_b.configure(<String, Object?>{
      'op': 'setForegroundPresentation',
      'alert': alert,
      'badge': badge,
      'sound': sound,
    }));
  }

  @override
  Future<void> subscribeToTopic(String topic) async {
    await _awaitOp(<String, Object?>{'op': 'subscribeToTopic', 'topic': topic});
  }

  @override
  Future<void> unsubscribeFromTopic(String topic) async {
    await _awaitOp(
        <String, Object?>{'op': 'unsubscribeFromTopic', 'topic': topic});
  }

  @override
  Future<void> setDeliveryMetricsExportToBigQuery(bool enabled) async {
    // Android/web only; nothing to configure on watchOS.
  }

  // --- Internals ---------------------------------------------------------

  Future<Map<String, Object?>> _awaitOp(Map<String, Object?> request) async {
    final Map<String, Object?> begin = _b.begin(request);
    _throwIfError(begin);
    final int token = begin['token']! as int;
    while (true) {
      final Map<String, Object?> result = _b.poll(token);
      if (result['pending'] != true) {
        _throwIfError(result);
        return result;
      }
      await Future<void>.delayed(opPollInterval);
    }
  }

  static NotificationSettings _settingsFromMap(Map<String, Object?> map) {
    return NotificationSettings(
      authorizationStatus: _authorizationStatus(map['authorizationStatus']),
      alert: _setting(map['alert']),
      announcement: _setting(map['announcement']),
      badge: _setting(map['badge']),
      carPlay: _setting(map['carPlay']),
      criticalAlert: _setting(map['criticalAlert']),
      lockScreen: _setting(map['lockScreen']),
      notificationCenter: _setting(map['notificationCenter']),
      showPreviews: AppleShowPreviewSetting.notSupported,
      sound: _setting(map['sound']),
      timeSensitive: _setting(map['timeSensitive']),
      providesAppNotificationSettings:
          _setting(map['providesAppNotificationSettings']),
    );
  }

  // UNAuthorizationStatus raw values.
  static AuthorizationStatus _authorizationStatus(Object? raw) {
    return switch (raw) {
      1 => AuthorizationStatus.denied,
      2 => AuthorizationStatus.authorized,
      3 => AuthorizationStatus.provisional,
      4 => AuthorizationStatus.authorized, // ephemeral
      _ => AuthorizationStatus.notDetermined,
    };
  }

  // UNNotificationSetting raw values; -1 marks capabilities watchOS lacks.
  static AppleNotificationSetting _setting(Object? raw) {
    return switch (raw) {
      1 => AppleNotificationSetting.disabled,
      2 => AppleNotificationSetting.enabled,
      _ => AppleNotificationSetting.notSupported,
    };
  }

  static void _throwIfError(Map<String, Object?> result) {
    if (result.containsKey('error')) {
      throw FirebaseException(
        plugin: 'firebase_messaging',
        code: result['code'] as String? ?? 'unknown',
        message: result['error'] as String?,
      );
    }
  }
}
