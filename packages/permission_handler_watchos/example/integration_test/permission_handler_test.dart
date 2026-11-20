// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by the MIT license that can be found
// in the LICENSE file.
//
// Against the real watch, through permission_handler's own API: every
// symbol resolves, every permission answers, and the answers that need no
// prompt are the ones the iOS implementation gives. Run it on a Simulator
// with the app installed afresh (flutter-watchos test does that):
//   flutter-watchos test integration_test/permission_handler_test.dart \
//     -d <watch-sim>
// Two cases depend on location and skip themselves otherwise: one needs it
// not determined, the other allowed "while using" only. The Simulator keeps
// a location answer across installs, so set it before a run:
//   xcrun simctl privacy <watch-sim> reset location \
//     com.example.permissionHandlerExample.watchkitapp
// or `grant location` in place of `reset location`.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every permission answers with a status', (WidgetTester _) async {
    for (final Permission permission in Permission.values) {
      expect(await permission.status, isA<PermissionStatus>(),
          reason: '$permission');
    }
  });

  testWidgets('a permission watchOS lacks answers as on iOS',
      (WidgetTester _) async {
    expect(await Permission.camera.status, PermissionStatus.denied);
    expect(
        await Permission.camera.request(), PermissionStatus.permanentlyDenied);
    expect(await Permission.phone.serviceStatus, ServiceStatus.disabled);
  });

  testWidgets('storage, critical alerts and Siri answer as on iOS',
      (WidgetTester _) async {
    expect(await Permission.storage.status, PermissionStatus.granted);
    expect(await Permission.storage.request(), PermissionStatus.granted);
    // The example has neither the Critical Alerts entitlement nor Siri, so
    // neither has been asked for. Its Info.plist does not set
    // PermissionHandlerWatchosSiri, so Siri is not even asked about:
    // INPreferences ends an app without the Siri entitlement.
    expect(await Permission.criticalAlerts.status, PermissionStatus.denied);
    expect(await Permission.assistant.status, PermissionStatus.denied);
  });

  testWidgets('location services answer', (WidgetTester _) async {
    expect(await Permission.location.serviceStatus, isA<ServiceStatus>());
  });

  testWidgets('"always" before "when in use" fails as on iOS',
      (WidgetTester _) async {
    // Only meaningful while location is not determined.
    if (await Permission.locationWhenInUse.status != PermissionStatus.denied) {
      markTestSkipped('location is answered already: reset it first with '
          'xcrun simctl privacy <watch-sim> reset location '
          'com.example.permissionHandlerExample.watchkitapp');
      return;
    }
    await expectLater(
      Permission.locationAlways.request(),
      throwsA(isA<PlatformException>().having((PlatformException e) => e.code,
          'code', 'MISSING_WHENINUSE_PERMISSION')),
    );
  });

  testWidgets('"always" can still be asked for after "when in use"',
      (WidgetTester _) async {
    // Only meaningful with location allowed "while using" only. A fresh
    // install has not asked for "always", so it reads denied, not permanently
    // denied, as in permission_handler_apple 9.6.4.
    if (await Permission.locationWhenInUse.status != PermissionStatus.granted ||
        await Permission.locationAlways.status == PermissionStatus.granted) {
      markTestSkipped('needs location allowed "while using" only: grant it '
          'first with xcrun simctl privacy <watch-sim> grant location '
          'com.example.permissionHandlerExample.watchkitapp');
      return;
    }
    expect(await Permission.locationAlways.status, PermissionStatus.denied);
  });
}
