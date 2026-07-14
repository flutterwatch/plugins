// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Runs on the watch simulator against the real CoreMotion-backed FFI
// implementation.
//
// The Simulator has no motion hardware, so the streams do not emit there. The
// on-device proof is that: (1) the watchOS implementation is registered, and
// (2) subscribing/reading through the FFI resolves every symbol and does not
// crash. When an event does arrive (on real hardware) it is well-formed.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:sensors_plus_watchos/sensors_plus_watchos.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('watchOS implementation is registered', (WidgetTester _) async {
    expect(SensorsPlatform.instance, isA<SensorsPlusWatchos>());
  });

  testWidgets('accelerometer stream can be subscribed and cancelled',
      (WidgetTester _) async {
    // Resolving the FFI symbols and driving the poll loop must not throw.
    // On the Simulator no sample arrives within the window; on a real watch
    // the first event is a well-formed AccelerometerEvent.
    AccelerometerEvent? first;
    final Stream<AccelerometerEvent> stream = accelerometerEventStream(
        samplingPeriod: const Duration(milliseconds: 20));
    final sub = stream.listen((AccelerometerEvent e) => first ??= e);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await sub.cancel();
    if (first != null) {
      expect(first!.x, isA<double>());
      expect(first!.y, isA<double>());
      expect(first!.z, isA<double>());
    }
  });

  testWidgets('gyroscope and magnetometer streams resolve their symbols',
      (WidgetTester _) async {
    final gyro = gyroscopeEventStream().listen((_) {});
    final mag = magnetometerEventStream().listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await gyro.cancel();
    await mag.cancel();
  });
}
