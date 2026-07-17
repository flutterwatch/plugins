// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// On-device smoke test. firebase_core has no upstream integration_test, so —
// as with geolocator — this verifies the real native path on the watch
// simulator: that the Firebase Apple SDK links, its component system
// registers, and FIRApp.configure runs end-to-end over the FFI bridge.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_example/firebase_options.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('initializes the default Firebase app on watchOS', (WidgetTester tester) async {
    final FirebaseApp app = await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    expect(app.name, defaultFirebaseAppName);
    expect(app.options.projectId, isNotEmpty);
    expect(Firebase.apps, isNotEmpty);

    // The registry reads back through the native SDK.
    expect(Firebase.app().name, defaultFirebaseAppName);
  });

  testWidgets('initializes a named secondary app', (WidgetTester tester) async {
    final FirebaseApp app = await Firebase.initializeApp(
      name: 'secondary',
      options: DefaultFirebaseOptions.currentPlatform,
    );
    expect(app.name, 'secondary');
    expect(Firebase.apps.map((FirebaseApp a) => a.name), contains('secondary'));
  });
}
