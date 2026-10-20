// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// flutter_local_notifications' own example app is built for phones and needs
// flutter_timezone, which has no watchOS implementation, so this
// watch-sized demo stands in for it. The official integration test in
// integration_test/ is upstream's, unchanged.

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

final FlutterLocalNotificationsPlugin _notifications =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  runApp(const NotificationsExampleApp());
}

/// A watch app that shows and schedules notifications.
class NotificationsExampleApp extends StatelessWidget {
  /// The example app.
  const NotificationsExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: const NotificationsPage(),
      );
}

/// Show, schedule, list and cancel.
class NotificationsPage extends StatefulWidget {
  /// The one page.
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  String _status = 'starting';
  int _next = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final NotificationAppLaunchDetails? launch =
        await _notifications.getNotificationAppLaunchDetails();
    final bool? granted = await _notifications.initialize(
      settings: const InitializationSettings(
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (NotificationResponse r) {
        setState(() => _status = 'tapped #${r.id} ${r.payload ?? ''}');
      },
    );
    setState(() {
      _status = launch?.didNotificationLaunchApp == true
          ? 'launched by #${launch!.notificationResponse?.id}'
          : granted == true
              ? 'allowed'
              : 'not allowed';
    });
  }

  Future<void> _show() async {
    final int id = _next++;
    await _notifications.show(
      id: id,
      title: 'Lap ${id + 1}',
      body: 'Pace 5:30 /km',
      payload: 'lap-$id',
    );
    setState(() => _status = 'shown #$id');
  }

  Future<void> _schedule() async {
    final int id = _next++;
    await _notifications.zonedSchedule(
      id: id,
      title: 'Time to stretch',
      body: 'Scheduled 10 seconds ago',
      scheduledDate: tz.TZDateTime.now(tz.UTC).add(const Duration(seconds: 10)),
      notificationDetails: const NotificationDetails(),
      androidScheduleMode: AndroidScheduleMode.inexact,
      payload: 'stretch-$id',
    );
    final int pending =
        (await _notifications.pendingNotificationRequests()).length;
    setState(() => _status = 'scheduled #$id, $pending pending');
  }

  Future<void> _cancelAll() async {
    await _notifications.cancelAll();
    setState(() => _status = 'cancelled');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 28, 12, 24),
          children: <Widget>[
            Text(_status,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            FilledButton(onPressed: _show, child: const Text('Show now')),
            FilledButton.tonal(
                onPressed: _schedule, child: const Text('In 10 seconds')),
            TextButton(onPressed: _cancelAll, child: const Text('Cancel all')),
          ],
        ),
      );
}
