// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// On-device smoke test. The firebase_messaging pub example targets a live
// Firebase project + a physical device with a real APNs environment, so — as
// with firebase_core/firebase_auth/firebase_storage — this instead verifies the
// real native path on the watch simulator: that FirebaseMessaging links,
// resolves an instance for the configured app, maps notification settings over
// the FFI bridge, and drives token/topic calls without crashing the bridge.
//
// The watch simulator has no APNs environment, so `getToken` cannot mint a real
// FCM token; the assertions tolerate a null token or a mapped error while still
// proving the native call round-trips (permission + settings are the positive
// checks).

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_messaging_example/firebase_options.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  });

  testWidgets('resolves a messaging instance and reports it is supported',
      (WidgetTester tester) async {
    final FirebaseMessaging messaging = FirebaseMessaging.instance;
    expect(await FirebaseMessaging.instance.isSupported(), isTrue);
    // The instance is bound to the default app.
    expect(messaging.app.name, defaultFirebaseAppName);
  });

  testWidgets('requestPermission returns mapped notification settings',
      (WidgetTester tester) async {
    final NotificationSettings settings =
        await FirebaseMessaging.instance.requestPermission();
    // Any real authorization status is fine; the sim may auto-grant or deny.
    expect(settings.authorizationStatus, isA<AuthorizationStatus>());
    // Capabilities watchOS does not expose are reported as notSupported.
    expect(settings.badge, AppleNotificationSetting.notSupported);
    expect(settings.showPreviews, AppleShowPreviewSetting.notSupported);
  });

  testWidgets('getNotificationSettings round-trips through the native SDK',
      (WidgetTester tester) async {
    final NotificationSettings settings =
        await FirebaseMessaging.instance.getNotificationSettings();
    expect(settings.authorizationStatus, isA<AuthorizationStatus>());
  });

  testWidgets('getToken drives the native path without crashing the bridge',
      (WidgetTester tester) async {
    // No APNs environment on the simulator, so the token is expected to be
    // null (or the call maps to a FirebaseException); either proves the native
    // round-trip completed.
    try {
      final String? token = await FirebaseMessaging.instance.getToken();
      expect(token, anyOf(isNull, isA<String>()));
    } on FirebaseException catch (e) {
      expect(e.plugin, 'firebase_messaging');
      expect(e.code, isNotEmpty);
    }
  });

  testWidgets('topic subscription drives the native path',
      (WidgetTester tester) async {
    // Subscription needs a valid FCM token, which the sim cannot mint; a mapped
    // error is the acceptable outcome and still exercises the native call.
    try {
      await FirebaseMessaging.instance.subscribeToTopic('flutterwatch-smoke');
      await FirebaseMessaging.instance
          .unsubscribeFromTopic('flutterwatch-smoke');
    } on FirebaseException catch (e) {
      expect(e.plugin, 'firebase_messaging');
      expect(e.code, isNotEmpty);
    }
  });
}
