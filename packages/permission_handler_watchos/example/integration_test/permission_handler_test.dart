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
    // neither has been asked for. Its Info.plist has no
    // NSSiriUsageDescription, so Siri is not even asked about: INPreferences
    // ends an app without the Siri entitlement.
    expect(await Permission.criticalAlerts.status, PermissionStatus.denied);
    expect(await Permission.assistant.status, PermissionStatus.denied);
  });

  testWidgets('location services answer', (WidgetTester _) async {
    expect(await Permission.location.serviceStatus, isA<ServiceStatus>());
  });

  testWidgets('"always" before "when in use" fails as on iOS',
      (WidgetTester _) async {
    // Only meaningful on a fresh install, where location is not determined.
    if (await Permission.locationWhenInUse.status != PermissionStatus.denied) {
      return;
    }
    await expectLater(
      Permission.locationAlways.request(),
      throwsA(isA<PlatformException>().having((PlatformException e) => e.code,
          'code', 'MISSING_WHENINUSE_PERMISSION')),
    );
  });
}
