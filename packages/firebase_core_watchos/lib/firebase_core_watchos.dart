// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `firebase_core`, implemented over dart:ffi.
//
// Method-channel plugins are not supported on watchOS, so this package
// follows the FFI plugin model: `watchos/Classes/firebase_core_watchos_ffi.m`
// bridges the Firebase Apple SDK (`FirebaseCore`, linked via the SwiftPM
// dependency declared in `watchos/Package.swift`) behind a handful of C
// symbols returning JSON, the CLI force-loads the compiled archive into the
// watch binary, and this class resolves the symbols via
// `DynamicLibrary.process()`.

import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';

/// FFI bindings to the native firebase_core_watchos C functions.
///
/// Each method marshals its arguments into C strings, calls the native
/// function, copies the returned JSON, frees the native buffer, and decodes
/// it. Overridable for tests via [FirebaseCoreWatchos.bindingsOverride]: the
/// [FirebaseCoreWatchosBindings.forTesting] constructor skips FFI
/// initialization so fakes work off-device.
class FirebaseCoreWatchosBindings {
  /// Creates bindings that look up native symbols in the current process.
  FirebaseCoreWatchosBindings() : _lib = DynamicLibrary.process();

  /// Constructor for fakes/mocks — skips FFI initialization.
  FirebaseCoreWatchosBindings.forTesting() : _lib = null;

  final DynamicLibrary? _lib;

  late final Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>) _configure =
      _lib!.lookupFunction<
          Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>)>(
        'firebase_core_watchos_configure',
      );

  late final Pointer<Utf8> Function(Pointer<Utf8>) _options = _lib!
      .lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Utf8>)>('firebase_core_watchos_options');

  late final Pointer<Utf8> Function() _apps = _lib!.lookupFunction<
      Pointer<Utf8> Function(), Pointer<Utf8> Function()>('firebase_core_watchos_apps');

  late final Pointer<Utf8> Function(Pointer<Utf8>) _delete = _lib!
      .lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Utf8>)>('firebase_core_watchos_delete');

  late final Pointer<Utf8> Function(Pointer<Utf8>, bool) _setAutoDataCollection =
      _lib!.lookupFunction<
          Pointer<Utf8> Function(Pointer<Utf8>, Bool),
          Pointer<Utf8> Function(Pointer<Utf8>, bool)>(
        'firebase_core_watchos_set_auto_data_collection',
      );

  late final void Function(Pointer<Utf8>) _free = _lib!.lookupFunction<
      Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>('firebase_core_watchos_free');

  /// Decodes and frees a native JSON string result.
  Object? _consume(Pointer<Utf8> ptr) {
    if (ptr == nullptr) {
      return <String, Object?>{'error': 'Native call returned null.', 'code': 'internal'};
    }
    final String jsonString = ptr.toDartString();
    _free(ptr);
    return json.decode(jsonString);
  }

  /// Configures a Firebase app. [name] is empty for the default app;
  /// [optionsJson] is empty to configure the default app from a bundled plist.
  Map<String, Object?> configure(String name, String optionsJson) {
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    final Pointer<Utf8> optionsPtr = optionsJson.toNativeUtf8();
    try {
      return (_consume(_configure(namePtr, optionsPtr)) as Map).cast<String, Object?>();
    } finally {
      calloc.free(namePtr);
      calloc.free(optionsPtr);
    }
  }

  /// Reads the app-info for an already-configured app.
  Map<String, Object?> options(String name) {
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    try {
      return (_consume(_options(namePtr)) as Map).cast<String, Object?>();
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Returns app-info for every configured app.
  List<Object?> apps() => _consume(_apps()) as List<Object?>;

  /// Deletes a configured app.
  Map<String, Object?> delete(String name) {
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    try {
      return (_consume(_delete(namePtr)) as Map).cast<String, Object?>();
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Sets automatic data collection for an app.
  Map<String, Object?> setAutoDataCollection(String name, bool enabled) {
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    try {
      return (_consume(_setAutoDataCollection(namePtr, enabled)) as Map)
          .cast<String, Object?>();
    } finally {
      calloc.free(namePtr);
    }
  }
}

/// watchOS implementation of [FirebasePlatform].
class FirebaseCoreWatchos extends FirebasePlatform {
  /// Test hook: set before first use to replace the FFI bindings.
  static FirebaseCoreWatchosBindings? bindingsOverride;

  static FirebaseCoreWatchosBindings? _bindings;

  static FirebaseCoreWatchosBindings get _b =>
      bindingsOverride ?? (_bindings ??= FirebaseCoreWatchosBindings());

  final Map<String, FirebaseAppWatchos> _apps = <String, FirebaseAppWatchos>{};

  /// Registers this implementation as the default `firebase_core` platform
  /// implementation on watchOS.
  static void registerWith() {
    FirebasePlatform.instance = FirebaseCoreWatchos();
  }

  @override
  List<FirebaseAppPlatform> get apps {
    for (final Object? info in _b.apps()) {
      if (info is Map) {
        final FirebaseAppWatchos app = _appFromInfo(info.cast<String, Object?>());
        _apps[app.name] = app;
      }
    }
    return _apps.values.toList(growable: false);
  }

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async {
    final String nativeName = (name == null || name == defaultFirebaseAppName) ? '' : name;
    final String optionsJson = options != null ? json.encode(options.asMap) : '';
    final Map<String, Object?> result = _b.configure(nativeName, optionsJson);
    _throwIfError(result);
    final FirebaseAppWatchos app = _appFromInfo(result);
    _apps[app.name] = app;
    return app;
  }

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) {
    final FirebaseAppWatchos? cached = _apps[name];
    if (cached != null) {
      return cached;
    }
    final String nativeName = name == defaultFirebaseAppName ? '' : name;
    final Map<String, Object?> result = _b.options(nativeName);
    if (result.containsKey('error')) {
      throw FirebaseException(
        plugin: 'core',
        code: 'no-app',
        message: 'No Firebase App "$name" has been created - '
            'call Firebase.initializeApp()',
      );
    }
    final FirebaseAppWatchos app = _appFromInfo(result);
    _apps[app.name] = app;
    return app;
  }

  FirebaseAppWatchos _appFromInfo(Map<String, Object?> info) {
    final Map<String, Object?> optionsMap =
        (info['options'] as Map).cast<String, Object?>();
    final FirebaseOptions options = _optionsFromMap(optionsMap);
    return FirebaseAppWatchos(
      info['name'] as String,
      options,
      isAutomaticDataCollectionEnabled:
          info['isAutomaticDataCollectionEnabled'] as bool? ?? true,
      bindings: _b,
      onDeleted: (String appName) => _apps.remove(appName),
    );
  }

  // Rebuilds a FirebaseOptions from the native `asMap`-shaped JSON. The
  // platform interface dropped `FirebaseOptions.fromMap` in v8, so map the
  // fields explicitly (missing required fields fall back to empty strings —
  // a plist-configured app always supplies them).
  static FirebaseOptions _optionsFromMap(Map<String, Object?> map) {
    return FirebaseOptions(
      apiKey: map['apiKey'] as String? ?? '',
      appId: map['appId'] as String? ?? '',
      messagingSenderId: map['messagingSenderId'] as String? ?? '',
      projectId: map['projectId'] as String? ?? '',
      authDomain: map['authDomain'] as String?,
      databaseURL: map['databaseURL'] as String?,
      storageBucket: map['storageBucket'] as String?,
      measurementId: map['measurementId'] as String?,
      trackingId: map['trackingId'] as String?,
      deepLinkURLScheme: map['deepLinkURLScheme'] as String?,
      androidClientId: map['androidClientId'] as String?,
      iosClientId: map['iosClientId'] as String?,
      iosBundleId: map['iosBundleId'] as String?,
      appGroupId: map['appGroupId'] as String?,
      recaptchaSiteKey: map['recaptchaSiteKey'] as String?,
    );
  }

  void _throwIfError(Map<String, Object?> result) => _throwIfErrorResult(result);
}

// The plugin's single error contract: a native result map carrying an
// "error" key becomes a FirebaseException.
void _throwIfErrorResult(Map<String, Object?> result) {
  if (result.containsKey('error')) {
    throw FirebaseException(
      plugin: 'core',
      code: result['code'] as String? ?? 'unknown',
      message: result['error'] as String?,
    );
  }
}

/// watchOS implementation of [FirebaseAppPlatform].
class FirebaseAppWatchos extends FirebaseAppPlatform {
  /// Creates an app handle backed by the native FirebaseCore app of the same
  /// [name].
  FirebaseAppWatchos(
    super.name,
    super.options, {
    required bool isAutomaticDataCollectionEnabled,
    required FirebaseCoreWatchosBindings bindings,
    required void Function(String name) onDeleted,
  })  : _isAutomaticDataCollectionEnabled = isAutomaticDataCollectionEnabled,
        _bindings = bindings,
        _onDeleted = onDeleted;

  bool _isAutomaticDataCollectionEnabled;
  final FirebaseCoreWatchosBindings _bindings;
  final void Function(String name) _onDeleted;

  @override
  bool get isAutomaticDataCollectionEnabled => _isAutomaticDataCollectionEnabled;

  @override
  Future<void> setAutomaticDataCollectionEnabled(bool enabled) async {
    final Map<String, Object?> result = _bindings.setAutoDataCollection(name, enabled);
    _throwIfErrorResult(result);
    _isAutomaticDataCollectionEnabled = enabled;
  }

  @override
  Future<void> setAutomaticResourceManagementEnabled(bool enabled) async {
    // watchOS has no UIApplication-style background resource management to
    // toggle; this is a no-op, matching the absence of the capability.
  }

  @override
  Future<void> delete() async {
    _bindings.delete(name);
    _onDeleted(name);
  }
}
