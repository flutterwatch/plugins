// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Supplementary watchOS test, next to upstream's
// flutter_local_notifications_test.dart (which it does not replace).
//
// The cases that need permission to notify ask for it, which shows a system
// prompt with no one to answer it on an unattended run, so they run only with
// --dart-define=FLNW_PROMPT=true, where someone allows the prompt (a run
// installs the app afresh, so it comes back each time). Without it the suite
// asks for nothing and those cases are skipped.
//
// Native hands every answer to Dart as JSON, and a flag that reaches JSON as
// 1 instead of true reads as false in Dart. These tests read the flags from
// the real notification center, where a fake backend cannot catch that.

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Whether someone answers the permission prompt on this run
/// (`--dart-define=FLNW_PROMPT=true`). The cases that need permission to
/// notify are skipped without it.
const bool _prompt = bool.fromEnvironment('FLNW_PROMPT');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();

  setUpAll(() async {
    tzdata.initializeTimeZones();
    await plugin.initialize(
      settings: const InitializationSettings(
        iOS: DarwinInitializationSettings(
          requestAlertPermission: _prompt,
          requestSoundPermission: _prompt,
          requestBadgePermission: _prompt,
        ),
      ),
    );
  });

  tearDown(() => plugin.cancelAll());

  testWidgets('a launch no notification started reports none',
      (WidgetTester _) async {
    final NotificationAppLaunchDetails? details =
        await plugin.getNotificationAppLaunchDetails();
    expect(details!.didNotificationLaunchApp, isFalse);
    expect(details.notificationResponse, isNull);
  });

  testWidgets('checkPermissions reports the alerts the app was allowed',
      (WidgetTester _) async {
    final NotificationsEnabledOptions? options = await plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()!
        .checkPermissions();
    expect(options!.isEnabled, isTrue);
    expect(options.isAlertEnabled, isTrue);
    expect(options.isBadgeEnabled, isFalse);
  }, skip: !_prompt);

  testWidgets('a scheduled notification is pending until it is cancelled',
      (WidgetTester _) async {
    await plugin.zonedSchedule(
      id: 1001,
      title: 'Stretch',
      body: 'In an hour',
      scheduledDate: tz.TZDateTime.now(tz.UTC).add(const Duration(hours: 1)),
      notificationDetails: const NotificationDetails(),
      androidScheduleMode: AndroidScheduleMode.inexact,
      payload: 'stretch',
    );
    final PendingNotificationRequest pending =
        (await plugin.pendingNotificationRequests())
            .singleWhere((PendingNotificationRequest p) => p.id == 1001);
    expect(pending.title, 'Stretch');
    expect(pending.payload, 'stretch');

    await plugin.cancel(id: 1001);
    expect(
      (await plugin.pendingNotificationRequests())
          .where((PendingNotificationRequest p) => p.id == 1001),
      isEmpty,
    );
  }, skip: !_prompt);

  testWidgets('a shown notification is listed as delivered',
      (WidgetTester _) async {
    await plugin.show(id: 1002, title: 'Lap 1', body: '5:30 /km');
    // Delivery is asynchronous; give the notification center a moment.
    List<ActiveNotification> active = <ActiveNotification>[];
    for (int i = 0; i < 20; i++) {
      active = await plugin.getActiveNotifications();
      if (active.any((ActiveNotification n) => n.id == 1002)) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    expect(active.singleWhere((ActiveNotification n) => n.id == 1002).title,
        'Lap 1');
  }, skip: !_prompt);
}
