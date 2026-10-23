// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `flutter_local_notifications`, over dart:ffi.
//
// flutter_local_notifications routes every iOS call to
// `IOSFlutterLocalNotificationsPlugin` and checks the platform instance's
// type before using it, so on the watch (where `defaultTargetPlatform` is
// iOS) the implementation has to be one. This class extends it and answers
// every method through UNUserNotificationCenter
// (`watchos/Classes/flutter_local_notifications_watchos_ffi.m`) instead of
// the method channel, which does not run on watchOS.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'src/backend.dart';

export 'src/backend.dart' show NotificationsWatchosBackend;

/// watchOS implementation of `flutter_local_notifications`.
///
/// Apps use `FlutterLocalNotificationsPlugin` as on iOS: pass `iOS:`
/// settings to `initialize` and `iOS:` details to `show` and the scheduling
/// calls, because the watch reports itself as iOS.
class FlutterLocalNotificationsWatchos
    extends IOSFlutterLocalNotificationsPlugin {
  /// Test hook: set before first use to replace the native backend.
  @visibleForTesting
  static NotificationsWatchosBackend? backendOverride;

  static NotificationsWatchosBackend? _backend;

  NotificationsWatchosBackend get _b =>
      backendOverride ?? (_backend ??= FfiNotificationsWatchosBackend());

  /// Registers this implementation as the platform instance on watchOS.
  static void registerWith() {
    FlutterLocalNotificationsPlatform.instance =
        FlutterLocalNotificationsWatchos();
  }

  DidReceiveNotificationResponseCallback? _onResponse;
  bool _initialized = false;
  bool _registered = false;
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};

  // ---- Requests -----------------------------------------------------------

  void _update() {
    final bool wanted = _initialized || _pending.isNotEmpty;
    if (wanted == _registered) {
      return;
    }
    _registered = wanted;
    _b.setSignalHandler(wanted ? _onSignal : null);
  }

  void _onSignal(int kind) {
    switch (kind) {
      case NotificationsSignal.request:
        _drainRequests();
      case NotificationsSignal.responses:
        _drainResponses();
    }
  }

  void _drainRequests() {
    for (final int id in _pending.keys.toList()) {
      final String? json = _b.takeRequestResult(id);
      if (json == null) {
        continue;
      }
      final Completer<Object?> completer = _pending.remove(id)!;
      final Object? result = jsonDecode(json);
      if (result is Map<Object?, Object?> && result['error'] is Map) {
        final Map<Object?, Object?> error =
            result['error']! as Map<Object?, Object?>;
        completer.completeError(PlatformException(
          code: error['code'] as String? ?? 'error',
          message: error['message'] as String?,
        ));
      } else {
        completer.complete(result);
      }
    }
    _update();
  }

  Future<Object?> _await(int id) {
    final Completer<Object?> completer = Completer<Object?>();
    _pending[id] = completer;
    _update();
    // The result may have landed before the handler was registered.
    _drainRequests();
    return completer.future;
  }

  void _drainResponses() {
    final String? json = _b.pollResponses();
    if (json == null) {
      return;
    }
    for (final Object? item in jsonDecode(json) as List<Object?>) {
      if (item is Map<Object?, Object?>) {
        _onResponse?.call(_response(item));
      }
    }
  }

  static NotificationResponse _response(Map<Object?, Object?> r) =>
      NotificationResponse(
        id: (r['id'] as num?)?.toInt(),
        actionId: r['actionId'] as String?,
        payload: r['payload'] as String?,
        notificationResponseType:
            NotificationResponseType.values[(r['type']! as num).toInt()],
      );

  // ---- Validation, as flutter_local_notifications does it -----------------

  static void _validateId(int id) {
    if (id > 0x7FFFFFFF || id < -0x80000000) {
      throw ArgumentError.value(
          id, 'id', 'must fit within the size of a 32-bit integer');
    }
  }

  // ---- Serialization ------------------------------------------------------

  static int _bits(Iterable<Object> options, int Function(Object) value) =>
      options.fold(0, (int all, Object o) => all | value(o));

  static Map<String, Object?> _details(DarwinNotificationDetails? d) =>
      d == null
          ? const <String, Object?>{}
          : <String, Object?>{
              'presentAlert': d.presentAlert,
              'presentSound': d.presentSound,
              'presentBadge': d.presentBadge,
              'presentBanner': d.presentBanner,
              'presentList': d.presentList,
              'subtitle': d.subtitle,
              'badgeNumber': d.badgeNumber,
              'threadIdentifier': d.threadIdentifier,
              'categoryIdentifier': d.categoryIdentifier,
              'interruptionLevel': d.interruptionLevel?.index,
              'criticalSoundVolume': d.criticalSoundVolume,
              'dismissIsolate': d.dismissIsolate?.index,
              'attachments': d.attachments
                  ?.map((DarwinNotificationAttachment a) => <String, Object?>{
                        'filePath': a.filePath,
                        'identifier': a.identifier,
                        'hideThumbnail': a.hideThumbnail,
                      })
                  .toList(),
            };

  Future<void> _add({
    required int id,
    required String? title,
    required String? body,
    required String? payload,
    required DarwinNotificationDetails? details,
    required Map<String, Object?> trigger,
  }) async {
    _validateId(id);
    await _await(_b.add(jsonEncode(<String, Object?>{
      'id': id,
      'title': title,
      'body': body,
      'payload': payload ?? '',
      'details': _details(details),
      'trigger': trigger,
    })));
  }

  // ---- IOSFlutterLocalNotificationsPlugin ---------------------------------

  /// Sets the categories and default presentation, asks for the permissions
  /// [settings] request, and starts handing taps to
  /// [onDidReceiveNotificationResponse].
  ///
  /// [onDidReceiveBackgroundNotificationResponse] is not used: on the watch
  /// every tap reaches the app's own isolate, through
  /// [onDidReceiveNotificationResponse]. That includes background actions,
  /// and dismissals of notifications whose details set `dismissIsolate`,
  /// whichever isolate it names.
  ///
  /// As on iOS, the result is false when [settings] ask for none of the
  /// alert, sound, badge, critical and app-settings permissions.
  @override
  Future<bool?> initialize({
    required DarwinInitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
        onDidReceiveBackgroundNotificationResponse,
  }) async {
    _onResponse = onDidReceiveNotificationResponse;
    _initialized = true;
    _update();
    final Object? result = await _await(_b.initialize(jsonEncode(
      <String, Object?>{
        'categories': <Object?>[
          for (final DarwinNotificationCategory c
              in settings.notificationCategories)
            <String, Object?>{
              'identifier': c.identifier,
              'options': _bits(c.options,
                  (Object o) => (o as DarwinNotificationCategoryOption).value),
              'actions': <Object?>[
                for (final DarwinNotificationAction a in c.actions)
                  <String, Object?>{
                    'identifier': a.identifier,
                    'title': a.title,
                    'options': _bits(
                        a.options,
                        (Object o) =>
                            (o as DarwinNotificationActionOption).value),
                  },
              ],
            },
        ],
        'defaults': <String, Object?>{
          'presentAlert': settings.defaultPresentAlert,
          'presentSound': settings.defaultPresentSound,
          'presentBadge': settings.defaultPresentBadge,
          'presentBanner': settings.defaultPresentBanner,
          'presentList': settings.defaultPresentList,
        },
        'request': <String, Object?>{
          'alert': settings.requestAlertPermission,
          'sound': settings.requestSoundPermission,
          'badge': settings.requestBadgePermission,
          'provisional': settings.requestProvisionalPermission,
          'critical': settings.requestCriticalPermission,
          'providesAppNotificationSettings':
              settings.requestProvidesAppNotificationSettings,
        },
      },
    )));
    // Taps that arrived since native started queueing them.
    _drainResponses();
    return (result as Map<Object?, Object?>?)?['granted'] == true;
  }

  @override
  Future<bool?> requestPermissions({
    bool sound = false,
    bool alert = false,
    bool badge = false,
    bool provisional = false,
    bool critical = false,
    bool carPlay = false,
    bool providesAppNotificationSettings = false,
  }) async {
    final Object? result = await _await(_b.requestPermissions(jsonEncode(
      <String, bool>{
        'alert': alert,
        'sound': sound,
        'badge': badge,
        'provisional': provisional,
        'critical': critical,
        'providesAppNotificationSettings': providesAppNotificationSettings,
      },
    )));
    return (result as Map<Object?, Object?>?)?['granted'] == true;
  }

  @override
  Future<NotificationsEnabledOptions?> checkPermissions() async {
    final Map<Object?, Object?> r =
        (await _await(_b.checkPermissions()))! as Map<Object?, Object?>;
    bool flag(String key) => r[key] == true;
    return NotificationsEnabledOptions(
      isEnabled: flag('isEnabled'),
      isAlertEnabled: flag('isAlertEnabled'),
      isSoundEnabled: flag('isSoundEnabled'),
      isBadgeEnabled: flag('isBadgeEnabled'),
      isProvisionalEnabled: flag('isProvisionalEnabled'),
      isCriticalEnabled: flag('isCriticalEnabled'),
      isProvidesAppNotificationSettingsEnabled:
          flag('isProvidesAppNotificationSettingsEnabled'),
    );
  }

  /// watchOS has no notification settings page an app can open.
  @override
  Future<bool?> openAppNotificationSettings() async => false;

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    DarwinNotificationDetails? notificationDetails,
    String? payload,
  }) =>
      _add(
        id: id,
        title: title,
        body: body,
        payload: payload,
        details: notificationDetails,
        trigger: const <String, Object?>{'type': 'now'},
      );

  @override
  Future<void> zonedSchedule({
    required int id,
    String? title,
    String? body,
    required tz.TZDateTime scheduledDate,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
    DarwinNotificationDetails? notificationDetails,
  }) {
    if (matchDateTimeComponents == null &&
        scheduledDate.isBefore(DateTime.now())) {
      throw ArgumentError.value(
          scheduledDate, 'scheduledDate', 'Must be a date in the future');
    }
    return _add(
      id: id,
      title: title,
      body: body,
      payload: payload,
      details: notificationDetails,
      trigger: <String, Object?>{
        'type': 'calendar',
        'epochMs': scheduledDate.millisecondsSinceEpoch,
        'timeZone': scheduledDate.location.name,
        'match': matchDateTimeComponents?.index,
      },
    );
  }

  @override
  Future<void> periodicallyShow({
    required int id,
    String? title,
    String? body,
    required RepeatInterval repeatInterval,
    DarwinNotificationDetails? notificationDetails,
    String? payload,
  }) =>
      _add(
        id: id,
        title: title,
        body: body,
        payload: payload,
        details: notificationDetails,
        trigger: <String, Object?>{
          'type': 'interval',
          'seconds': switch (repeatInterval) {
            RepeatInterval.everyMinute => 60,
            RepeatInterval.hourly => 3600,
            RepeatInterval.daily => 86400,
            RepeatInterval.weekly => 604800,
          },
          'repeats': true,
        },
      );

  @override
  Future<void> periodicallyShowWithDuration({
    required int id,
    String? title,
    String? body,
    required Duration repeatDurationInterval,
    DarwinNotificationDetails? notificationDetails,
    String? payload,
  }) {
    if (repeatDurationInterval.inMilliseconds <
        Duration.millisecondsPerMinute) {
      throw ArgumentError.value(repeatDurationInterval,
          'repeatDurationInterval', 'must be one minute or more');
    }
    return _add(
      id: id,
      title: title,
      body: body,
      payload: payload,
      details: notificationDetails,
      trigger: <String, Object?>{
        'type': 'interval',
        'seconds': repeatDurationInterval.inMilliseconds / 1000,
        'repeats': true,
      },
    );
  }

  @override
  Future<void> cancel({required int id}) async {
    _validateId(id);
    _b.cancel(id);
  }

  @override
  Future<void> cancelAll() async => _b.cancelAll(pendingOnly: false);

  @override
  Future<void> cancelAllPendingNotifications() async =>
      _b.cancelAll(pendingOnly: true);

  @override
  Future<List<PendingNotificationRequest>>
      pendingNotificationRequests() async => <PendingNotificationRequest>[
            for (final Object? p
                in (await _await(_b.pending()))! as List<Object?>)
              if (p is Map<Object?, Object?>)
                PendingNotificationRequest(
                  (p['id']! as num).toInt(),
                  p['title'] as String?,
                  p['body'] as String?,
                  p['payload'] as String?,
                ),
          ];

  @override
  Future<List<ActiveNotification>> getActiveNotifications() async =>
      <ActiveNotification>[
        for (final Object? n in (await _await(_b.active()))! as List<Object?>)
          if (n is Map<Object?, Object?>)
            ActiveNotification(
              id: (n['id'] as num?)?.toInt(),
              title: n['title'] as String?,
              body: n['body'] as String?,
              payload: n['payload'] as String?,
              groupKey: n['threadIdentifier'] as String?,
            ),
      ];

  /// The tap that launched the app, if one did: a tap on a notification, or
  /// on an action that opens the app, that arrived before this was first
  /// asked and before [initialize] ran. A background action or a dismissal
  /// is never the launch.
  ///
  /// The host hands the tap over on the main thread while Dart runs on its
  /// own, so it can come in after this was asked. It is not lost then: it
  /// reaches `onDidReceiveNotificationResponse` once [initialize] has run.
  @override
  Future<NotificationAppLaunchDetails?>
      getNotificationAppLaunchDetails() async {
    final Map<Object?, Object?> d =
        jsonDecode(_b.launchDetails()) as Map<Object?, Object?>;
    final Object? response = d['response'];
    return NotificationAppLaunchDetails(
      d['launched'] == true,
      notificationResponse:
          response is Map<Object?, Object?> ? _response(response) : null,
    );
  }
}
