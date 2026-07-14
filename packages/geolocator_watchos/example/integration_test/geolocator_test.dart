// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Runs on the watch simulator against the real CoreLocation-backed FFI
// implementation.
//
// The non-interactive query methods are safe to drive headlessly. The
// interactive permission prompt and a live location fix are verified manually
// on a physical Apple Watch (with a simulated route); they present system UI
// that cannot be answered from an automated test.

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_watchos/geolocator_watchos.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('watchOS implementation is registered', (WidgetTester _) async {
    expect(GeolocatorPlatform.instance, isA<GeolocatorWatchos>());
  });

  testWidgets('isLocationServiceEnabled resolves to a bool',
      (WidgetTester _) async {
    expect(await Geolocator.isLocationServiceEnabled(), isA<bool>());
  });

  testWidgets('checkPermission resolves to a LocationPermission',
      (WidgetTester _) async {
    expect(await Geolocator.checkPermission(), isA<LocationPermission>());
  });

  testWidgets('getLastKnownPosition resolves to a Position or null',
      (WidgetTester _) async {
    final Position? pos = await Geolocator.getLastKnownPosition();
    if (pos != null) {
      expect(pos.latitude, isA<double>());
      expect(pos.longitude, isA<double>());
    }
  });
}
