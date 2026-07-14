// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Host-side unit tests. The native CoreMotion backend is replaced with a fake
// that emits canned samples, so the stream/poll machinery is verified
// off-device; the real sensors are exercised on a physical watch (the
// Simulator has no motion hardware).

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus_platform_interface/sensors_plus_platform_interface.dart';
import 'package:sensors_plus_watchos/sensors_plus_watchos.dart';

/// Backend that reports a fixed sample for every sensor and records start/stop.
class _FakeBackend implements SensorsPlusWatchosBackend {
  int accelStarts = 0;
  int accelStops = 0;
  List<double>? sample = <double>[1, 2, 3];

  @override
  void startAccelerometer(int intervalMicros) => accelStarts++;
  @override
  List<double>? readAccelerometer() => sample;
  @override
  void stopAccelerometer() => accelStops++;

  @override
  void startUserAccelerometer(int intervalMicros) {}
  @override
  List<double>? readUserAccelerometer() => sample;
  @override
  void stopUserAccelerometer() {}

  @override
  void startGyroscope(int intervalMicros) {}
  @override
  List<double>? readGyroscope() => sample;
  @override
  void stopGyroscope() {}

  @override
  void startMagnetometer(int intervalMicros) {}
  @override
  List<double>? readMagnetometer() => sample;
  @override
  void stopMagnetometer() {}
}

void main() {
  late _FakeBackend fake;
  late SensorsPlusWatchos sensors;

  setUp(() {
    fake = _FakeBackend();
    SensorsPlusWatchos.backendOverride = fake;
    sensors = SensorsPlusWatchos();
  });

  tearDown(() => SensorsPlusWatchos.backendOverride = null);

  test('registerWith installs the watchOS implementation', () {
    SensorsPlusWatchos.registerWith();
    expect(SensorsPlatform.instance, isA<SensorsPlusWatchos>());
  });

  test('accelerometer stream emits mapped events and starts/stops native',
      () async {
    final Stream<AccelerometerEvent> stream = sensors.accelerometerEventStream(
        samplingPeriod: const Duration(milliseconds: 10));
    final AccelerometerEvent event = await stream.first;
    expect(event.x, 1);
    expect(event.y, 2);
    expect(event.z, 3);
    expect(fake.accelStarts, 1);
    // Cancelling the last listener stops native updates.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(fake.accelStops, greaterThanOrEqualTo(1));
  });

  test('no native sample yields no events (Simulator behaviour)', () async {
    fake.sample = null;
    final Stream<GyroscopeEvent> stream = sensors.gyroscopeEventStream(
        samplingPeriod: const Duration(milliseconds: 5));
    final Object marker = Object();
    final Object result = await stream.first
        .then<Object>((GyroscopeEvent e) => e)
        .timeout(const Duration(milliseconds: 60), onTimeout: () => marker);
    expect(result, same(marker));
  });

  test('every sensor stream maps its triple', () async {
    expect((await sensors.userAccelerometerEventStream().first).x, 1);
    expect((await sensors.gyroscopeEventStream().first).y, 2);
    expect((await sensors.magnetometerEventStream().first).z, 3);
  });
}
