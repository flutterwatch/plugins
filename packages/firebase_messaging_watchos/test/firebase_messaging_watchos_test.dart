// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Host-side unit tests: the native FirebaseMessaging backend is faked,
// asserting that the Dart class maps platform-interface calls onto the right
// FFI requests, rebuilds notification settings and messages from the JSON
// results, and pumps queued messages into the platform-interface streams.

import 'dart:async';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:firebase_messaging_platform_interface/firebase_messaging_platform_interface.dart';
import 'package:firebase_messaging_watchos/firebase_messaging_watchos.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _settingsMap({
  int authorizationStatus = 2,
  int alert = 2,
  int sound = 2,
}) {
  return <String, Object?>{
    'authorizationStatus': authorizationStatus,
    'alert': alert,
    'announcement': -1,
    'badge': -1,
    'carPlay': -1,
    'criticalAlert': 0,
    'lockScreen': -1,
    'notificationCenter': 2,
    'sound': sound,
    'timeSensitive': -1,
    'providesAppNotificationSettings': -1,
  };
}

Map<String, Object?> _messageMap(String id) {
  return <String, Object?>{
    'messageId': id,
    'data': <String, Object?>{'k': 'v'},
    'notification': <String, Object?>{'title': 'Hi', 'body': 'There'},
  };
}

class _FakeBindings extends FirebaseMessagingWatchosBindings {
  _FakeBindings() : super.forTesting();

  final List<Map<String, Object?>> beginRequests = <Map<String, Object?>>[];
  final List<Map<String, Object?>> configureRequests = <Map<String, Object?>>[];
  final List<String> takeKinds = <String>[];

  /// Result the next completed operation resolves to.
  Map<String, Object?> opResult = <String, Object?>{};

  /// How many polls report pending before the result is served.
  int pendingPolls = 0;

  /// The token/APNs state served to [state].
  Map<String, Object?> stateMap = <String, Object?>{
    'tokenGeneration': 0,
    'fcmToken': null,
    'apnsToken': null,
    'apnsError': null,
  };

  bool autoInit = true;

  /// Queued messages served, in order, keyed by kind ("foreground"/"opened").
  final Map<String, List<Object?>> queues = <String, List<Object?>>{};

  /// Initial-message payload served to `takeMessages('initial')`.
  Map<String, Object?>? initialMessage;

  int _nextToken = 1;

  @override
  Map<String, Object?> begin(Map<String, Object?> request) {
    beginRequests.add(request);
    return <String, Object?>{'token': _nextToken++};
  }

  @override
  Map<String, Object?> poll(int token) {
    if (pendingPolls > 0) {
      pendingPolls -= 1;
      return <String, Object?>{'pending': true};
    }
    return opResult;
  }

  @override
  Map<String, Object?> state() => stateMap;

  @override
  Map<String, Object?> takeMessages(String kind) {
    takeKinds.add(kind);
    if (kind == 'initial') {
      final Map<String, Object?>? message = initialMessage;
      initialMessage = null;
      return <String, Object?>{'message': message};
    }
    final List<Object?> messages = queues.remove(kind) ?? const <Object?>[];
    return <String, Object?>{'messages': messages};
  }

  @override
  Map<String, Object?> configure(Map<String, Object?> request) {
    configureRequests.add(request);
    switch (request['op']) {
      case 'getAutoInit':
        return <String, Object?>{'enabled': autoInit};
      case 'setAutoInit':
        autoInit = request['enabled']! as bool;
        return <String, Object?>{'ok': true};
      default:
        return <String, Object?>{'ok': true};
    }
  }
}

void main() {
  late _FakeBindings fake;
  late FirebaseMessagingWatchos messaging;

  setUp(() {
    fake = _FakeBindings();
    FirebaseMessagingWatchos.bindingsOverride = fake;
    FirebaseMessagingWatchos.opPollInterval = const Duration(milliseconds: 1);
    FirebaseMessagingWatchos.messagePumpInterval =
        const Duration(milliseconds: 5);
    messaging = FirebaseMessagingWatchos();
  });

  tearDown(() {
    FirebaseMessagingWatchos.stopMessagePump();
    FirebaseMessagingWatchos.bindingsOverride = null;
  });

  test('registerWith installs the platform instance', () {
    FirebaseMessagingWatchos.registerWith();
    expect(FirebaseMessagingPlatform.instance, isA<FirebaseMessagingWatchos>());
  });

  test('getToken registers for notifications, waits for APNs, then resolves',
      () async {
    // APNs token appears immediately (fake state already populated).
    fake.stateMap['apnsToken'] = 'aabbcc';
    fake.opResult = <String, Object?>{'fcmToken': 'fcm-123'};
    final String? token = await messaging.getToken();
    expect(token, 'fcm-123');
    expect(fake.beginRequests.single['op'], 'getToken');
  });

  test('getToken triggers remote-notification registration when APNs is absent',
      () async {
    fake.opResult = <String, Object?>{'fcmToken': 'fcm-1'};
    // apnsError short-circuits the wait so the test does not hang 8s.
    fake.stateMap['apnsError'] = 'no APNs in this environment';
    await messaging.getToken();
    expect(
      fake.configureRequests.any((Map<String, Object?> r) =>
          r['op'] == 'registerForRemoteNotifications'),
      isTrue,
    );
  });

  test('getAPNSToken reads the native state', () async {
    fake.stateMap['apnsToken'] = 'deadbeef';
    expect(await messaging.getAPNSToken(), 'deadbeef');
  });

  test('deleteToken issues the delete op', () async {
    fake.opResult = <String, Object?>{'ok': true};
    await messaging.deleteToken();
    expect(fake.beginRequests.single['op'], 'deleteToken');
  });

  test('requestPermission forwards options and maps settings', () async {
    fake.opResult = <String, Object?>{'settings': _settingsMap()};
    final NotificationSettings settings = await messaging.requestPermission(
      provisional: true,
      sound: false,
    );
    final Map<String, Object?> request = fake.beginRequests.single;
    expect(request['op'], 'requestPermission');
    expect(request['provisional'], isTrue);
    expect(request['sound'], isFalse);
    expect(settings.authorizationStatus, AuthorizationStatus.authorized);
    expect(settings.alert, AppleNotificationSetting.enabled);
    expect(settings.badge, AppleNotificationSetting.notSupported);
    expect(settings.showPreviews, AppleShowPreviewSetting.notSupported);
  });

  test('getNotificationSettings maps a denied status', () async {
    fake.opResult = <String, Object?>{
      'settings': _settingsMap(authorizationStatus: 1, alert: 1),
    };
    final NotificationSettings settings =
        await messaging.getNotificationSettings();
    expect(settings.authorizationStatus, AuthorizationStatus.denied);
    expect(settings.alert, AppleNotificationSetting.disabled);
  });

  test('subscribeToTopic / unsubscribeFromTopic send the topic', () async {
    fake.opResult = <String, Object?>{'ok': true};
    await messaging.subscribeToTopic('news');
    await messaging.unsubscribeFromTopic('news');
    expect(fake.beginRequests[0],
        <String, Object?>{'op': 'subscribeToTopic', 'topic': 'news'});
    expect(fake.beginRequests[1],
        <String, Object?>{'op': 'unsubscribeFromTopic', 'topic': 'news'});
  });

  test('setForegroundNotificationPresentationOptions configures presentation',
      () async {
    await messaging.setForegroundNotificationPresentationOptions(
        alert: true, sound: true);
    final Map<String, Object?> request = fake.configureRequests.single;
    expect(request['op'], 'setForegroundPresentation');
    expect(request['alert'], isTrue);
    expect(request['sound'], isTrue);
  });

  test('auto-init round-trips through configure', () async {
    await messaging.setAutoInitEnabled(false);
    expect(fake.autoInit, isFalse);
    expect(messaging.isAutoInitEnabled, isFalse);
  });

  test('getInitialMessage returns the launch payload once', () async {
    fake.initialMessage = _messageMap('init-1');
    final RemoteMessage? first = await messaging.getInitialMessage();
    expect(first!.messageId, 'init-1');
    expect(first.notification!.title, 'Hi');
    final RemoteMessage? second = await messaging.getInitialMessage();
    expect(second, isNull);
  });

  test('the message pump feeds onMessage and onMessageOpenedApp', () async {
    fake.queues['foreground'] = <Object?>[_messageMap('fg-1')];
    fake.queues['opened'] = <Object?>[_messageMap('op-1')];

    final Future<RemoteMessage> onMessage =
        FirebaseMessagingPlatform.onMessage.stream.first;
    final Future<RemoteMessage> onOpened =
        FirebaseMessagingPlatform.onMessageOpenedApp.stream.first;

    FirebaseMessagingWatchos.startMessagePump();

    expect((await onMessage).messageId, 'fg-1');
    expect((await onOpened).messageId, 'op-1');
  });

  test('onTokenRefresh emits when the token generation advances', () async {
    fake.stateMap['tokenGeneration'] = 1;
    fake.stateMap['fcmToken'] = 'first';
    final Future<String> next = messaging.onTokenRefresh.first;
    // Advance the generation; the polling timer should observe and emit.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    fake.stateMap['tokenGeneration'] = 2;
    fake.stateMap['fcmToken'] = 'refreshed';
    expect(await next, 'refreshed');
  });

  test('a native error surfaces as FirebaseException', () async {
    fake.opResult = <String, Object?>{
      'error': 'Topic name is invalid.',
      'code': 'invalid-argument',
    };
    await expectLater(
      messaging.subscribeToTopic('bad topic'),
      throwsA(isA<FirebaseException>()
          .having((FirebaseException e) => e.code, 'code', 'invalid-argument')),
    );
  });

  test('isSupported is true on watchOS', () async {
    expect(await messaging.isSupported(), isTrue);
  });
}
