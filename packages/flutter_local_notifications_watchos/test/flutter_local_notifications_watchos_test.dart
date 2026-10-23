// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Host-side unit tests. UNUserNotificationCenter is replaced with a fake that
// records what native would be asked and answers as the native header
// documents. The calls go through the app-facing FlutterLocalNotificationsPlugin,
// with the target platform set to iOS as the watch reports it, so the routing
// to this implementation is checked too.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_watchos/flutter_local_notifications_watchos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class _FakeBackend implements NotificationsWatchosBackend {
  final List<Map<String, Object?>> added = <Map<String, Object?>>[];
  Map<String, Object?>? initialized;
  final List<String> calls = <String>[];
  final Map<int, Object?> answers = <int, Object?>{};
  final Map<int, Object?> results = <int, Object?>{};
  final List<Map<String, Object?>> responses = <Map<String, Object?>>[];
  String launch = '{"launched": false, "response": null}';
  void Function(int kind)? handler;
  int _next = 1;

  /// What every request answers, unless [answers] names one.
  Object? defaultAnswer = <String, Object?>{};

  int _request(String name) {
    calls.add(name);
    final int id = _next++;
    // Answered asynchronously, as UserNotifications does.
    scheduleMicrotask(() {
      results[id] = answers.containsKey(id) ? answers[id] : defaultAnswer;
      handler?.call(1);
    });
    return id;
  }

  void tap(Map<String, Object?> response) {
    responses.add(response);
    handler?.call(2);
  }

  @override
  int initialize(String settingsJson) {
    initialized = (jsonDecode(settingsJson) as Map<Object?, Object?>)
        .cast<String, Object?>();
    return _request('initialize');
  }

  @override
  int requestPermissions(String optionsJson) =>
      _request('requestPermissions $optionsJson');
  @override
  int checkPermissions() => _request('checkPermissions');
  @override
  int add(String notificationJson) {
    added.add((jsonDecode(notificationJson) as Map<Object?, Object?>)
        .cast<String, Object?>());
    return _request('add');
  }

  @override
  void cancel(int id) => calls.add('cancel $id');
  @override
  void cancelAll({required bool pendingOnly}) =>
      calls.add(pendingOnly ? 'cancelAllPending' : 'cancelAll');
  @override
  int pending() => _request('pending');
  @override
  int active() => _request('active');
  @override
  String launchDetails() => launch;
  @override
  String? pollResponses() {
    if (responses.isEmpty) {
      return null;
    }
    final String json = jsonEncode(responses);
    responses.clear();
    return json;
  }

  @override
  String? takeRequestResult(int id) =>
      results.containsKey(id) ? jsonEncode(results.remove(id)) : null;
  @override
  void setSignalHandler(void Function(int kind)? h) => handler = h;
}

void main() {
  late _FakeBackend fake;
  late FlutterLocalNotificationsPlugin plugin;

  setUpAll(tzdata.initializeTimeZones);

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    fake = _FakeBackend();
    FlutterLocalNotificationsWatchos.backendOverride = fake;
    FlutterLocalNotificationsWatchos.registerWith();
    plugin = FlutterLocalNotificationsPlugin();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    FlutterLocalNotificationsWatchos.backendOverride = null;
  });

  test('the watchOS implementation is what iOS calls resolve to', () {
    expect(FlutterLocalNotificationsPlatform.instance,
        isA<FlutterLocalNotificationsWatchos>());
    expect(
        plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>(),
        isA<FlutterLocalNotificationsWatchos>());
  });

  test('initialize sends the categories, defaults and requests', () async {
    fake.defaultAnswer = <String, Object?>{'granted': true};
    final bool? granted = await plugin.initialize(
      settings: InitializationSettings(
        iOS: DarwinInitializationSettings(
          requestSoundPermission: false,
          defaultPresentBanner: false,
          notificationCategories: <DarwinNotificationCategory>[
            DarwinNotificationCategory(
              'lap',
              actions: <DarwinNotificationAction>[
                DarwinNotificationAction.plain('resume', 'Resume',
                    options: <DarwinNotificationActionOption>{
                      DarwinNotificationActionOption.foreground,
                    }),
              ],
              options: <DarwinNotificationCategoryOption>{
                DarwinNotificationCategoryOption.customDismissAction,
              },
            ),
          ],
        ),
      ),
    );
    expect(granted, isTrue);
    final Map<String, Object?> sent = fake.initialized!;
    expect(sent['categories'], <Object?>[
      <String, Object?>{
        'identifier': 'lap',
        'options': 1,
        'actions': <Object?>[
          <String, Object?>{
            'identifier': 'resume',
            'title': 'Resume',
            'options': 4
          },
        ],
      },
    ]);
    expect(
        (sent['defaults']! as Map<Object?, Object?>)['presentBanner'], false);
    expect((sent['request']! as Map<Object?, Object?>)['sound'], false);
    expect((sent['request']! as Map<Object?, Object?>)['alert'], true);
    expect(
        (sent['request']!
            as Map<Object?, Object?>)['providesAppNotificationSettings'],
        false);
  });

  test('requestPermissions asks for app notification settings too', () async {
    fake.defaultAnswer = <String, Object?>{'granted': true};
    await plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()!
        .requestPermissions(alert: true, providesAppNotificationSettings: true);
    final String call = fake.calls
        .singleWhere((String c) => c.startsWith('requestPermissions '));
    final Map<Object?, Object?> options =
        jsonDecode(call.substring('requestPermissions '.length))
            as Map<Object?, Object?>;
    expect(options['alert'], true);
    expect(options['providesAppNotificationSettings'], true);
  });

  test('a tap after initialize reaches the callback', () async {
    final List<NotificationResponse> taps = <NotificationResponse>[];
    await plugin.initialize(
      settings:
          const InitializationSettings(iOS: DarwinInitializationSettings()),
      onDidReceiveNotificationResponse: taps.add,
    );
    fake.tap(<String, Object?>{
      'id': 7,
      'actionId': 'resume',
      'payload': 'run',
      'type': 1,
    });
    await pumpEventQueue();
    expect(taps.single.id, 7);
    expect(taps.single.actionId, 'resume');
    expect(taps.single.payload, 'run');
    expect(taps.single.notificationResponseType,
        NotificationResponseType.selectedNotificationAction);
  });

  test('a tap queued before initialize reaches the callback once it runs',
      () async {
    // What native does with a launch tap watchOS hands over after Dart has
    // already asked for the launch details.
    fake.tap(<String, Object?>{
      'id': 8,
      'actionId': null,
      'payload': 'late',
      'type': 0,
    });
    final List<NotificationResponse> taps = <NotificationResponse>[];
    await plugin.initialize(
      settings:
          const InitializationSettings(iOS: DarwinInitializationSettings()),
      onDidReceiveNotificationResponse: taps.add,
    );
    expect(taps.single.id, 8);
    expect(taps.single.payload, 'late');
  });

  test('the launch tap is reported by getNotificationAppLaunchDetails',
      () async {
    fake.launch = jsonEncode(<String, Object?>{
      'launched': true,
      'response': <String, Object?>{
        'id': 3,
        'actionId': null,
        'payload': 'p',
        'type': 0,
      },
    });
    final NotificationAppLaunchDetails? details =
        await plugin.getNotificationAppLaunchDetails();
    expect(details!.didNotificationLaunchApp, isTrue);
    expect(details.notificationResponse!.id, 3);
    expect(details.notificationResponse!.notificationResponseType,
        NotificationResponseType.selectedNotification);
  });

  test('show adds an immediate notification with its details', () async {
    await plugin.show(
      id: 1,
      title: 'Lap 3',
      body: '5:30 /km',
      notificationDetails: const NotificationDetails(
        iOS: DarwinNotificationDetails(
          subtitle: 'Run',
          presentSound: false,
          threadIdentifier: 'run',
          categoryIdentifier: 'lap',
          interruptionLevel: InterruptionLevel.timeSensitive,
          criticalSoundVolume: 0.5,
          dismissIsolate: NotificationDismissedIsolate.main,
        ),
      ),
      payload: 'lap-3',
    );
    final Map<String, Object?> n = fake.added.single;
    expect(n['id'], 1);
    expect(n['title'], 'Lap 3');
    expect(n['body'], '5:30 /km');
    expect(n['payload'], 'lap-3');
    expect(n['trigger'], <String, Object?>{'type': 'now'});
    final Map<Object?, Object?> d = n['details']! as Map<Object?, Object?>;
    expect(d['subtitle'], 'Run');
    expect(d['presentSound'], false);
    expect(d['threadIdentifier'], 'run');
    expect(d['categoryIdentifier'], 'lap');
    expect(d['interruptionLevel'], InterruptionLevel.timeSensitive.index);
    expect(d['criticalSoundVolume'], 0.5);
    expect(d['dismissIsolate'], NotificationDismissedIsolate.main.index);
  });

  test('zonedSchedule sends the instant, its zone and the repeat', () async {
    final tz.Location istanbul = tz.getLocation('Europe/Istanbul');
    final tz.TZDateTime at =
        tz.TZDateTime.now(istanbul).add(const Duration(hours: 1));
    await plugin.zonedSchedule(
      id: 2,
      title: 'Stretch',
      body: null,
      scheduledDate: at,
      notificationDetails: const NotificationDetails(),
      androidScheduleMode: AndroidScheduleMode.inexact,
      matchDateTimeComponents: DateTimeComponents.time,
    );
    expect(fake.added.single['trigger'], <String, Object?>{
      'type': 'calendar',
      'epochMs': at.millisecondsSinceEpoch,
      'timeZone': 'Europe/Istanbul',
      'match': DateTimeComponents.time.index,
    });
  });

  test('a one-time schedule in the past is refused', () {
    expect(
      () => plugin.zonedSchedule(
        id: 2,
        title: null,
        body: null,
        scheduledDate:
            tz.TZDateTime.now(tz.UTC).subtract(const Duration(minutes: 1)),
        notificationDetails: const NotificationDetails(),
        androidScheduleMode: AndroidScheduleMode.inexact,
      ),
      throwsArgumentError,
    );
  });

  test('repeat intervals become seconds', () async {
    for (final RepeatInterval interval in RepeatInterval.values) {
      await plugin.periodicallyShow(
        id: interval.index,
        title: null,
        body: null,
        repeatInterval: interval,
        notificationDetails: const NotificationDetails(),
        androidScheduleMode: AndroidScheduleMode.inexact,
      );
    }
    expect(
        fake.added
            .map((Map<String, Object?> n) =>
                (n['trigger']! as Map<Object?, Object?>)['seconds'])
            .toList(),
        <int>[60, 3600, 86400, 604800]);
    await plugin.periodicallyShowWithDuration(
      id: 9,
      title: null,
      body: null,
      repeatDurationInterval: const Duration(minutes: 90),
      notificationDetails: const NotificationDetails(),
      androidScheduleMode: AndroidScheduleMode.inexact,
    );
    expect(fake.added.last['trigger'], <String, Object?>{
      'type': 'interval',
      'seconds': 5400.0,
      'repeats': true,
    });
  });

  test('cancel calls reach native', () async {
    await plugin.cancel(id: 4);
    await plugin.cancelAll();
    await plugin.cancelAllPendingNotifications();
    expect(fake.calls, <String>['cancel 4', 'cancelAll', 'cancelAllPending']);
  });

  test('pending and delivered notifications are listed', () async {
    fake.defaultAnswer = <Object?>[
      <String, Object?>{
        'id': 5,
        'title': 't',
        'body': 'b',
        'payload': 'p',
        'threadIdentifier': 'run',
      },
    ];
    final List<PendingNotificationRequest> pending =
        await plugin.pendingNotificationRequests();
    expect(pending.single.id, 5);
    expect(pending.single.payload, 'p');
    final List<ActiveNotification> active =
        await plugin.getActiveNotifications();
    expect(active.single.groupKey, 'run');
  });

  test('a failed request is a PlatformException', () async {
    fake.defaultAnswer = <String, Object?>{
      'error': <String, Object?>{'code': 'add', 'message': 'no'},
    };
    await expectLater(
      plugin.show(id: 1, title: 'x', body: null),
      throwsA(isA<PlatformException>()
          .having((PlatformException e) => e.code, 'code', 'add')),
    );
  });

  test('an id beyond 32 bits is refused', () {
    expect(() => plugin.show(id: 0x80000000, title: null, body: null),
        throwsArgumentError);
  });

  test('checkPermissions maps the settings', () async {
    fake.defaultAnswer = <String, Object?>{
      'isEnabled': true,
      'isAlertEnabled': true,
      'isSoundEnabled': false,
      'isBadgeEnabled': false,
      'isProvisionalEnabled': false,
      'isCriticalEnabled': false,
      'isProvidesAppNotificationSettingsEnabled': true,
    };
    final NotificationsEnabledOptions? options = await plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()!
        .checkPermissions();
    expect(options!.isEnabled, isTrue);
    expect(options.isSoundEnabled, isFalse);
    expect(options.isProvidesAppNotificationSettingsEnabled, isTrue);
  });
}
