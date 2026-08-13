// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Host-side unit tests. The native CoreMotion backend is replaced with a fake
// that emits canned samples, so the stream/poll machinery is verified
// off-device; the real sensors are exercised on a physical watch (the
// Simulator has no motion hardware).

import 'dart:async';
import 'dart:ffi';

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

  Pointer<NativeFunction<SensorSampleNative>>? _callback;

  /// Whether native would currently wake Dart.
  bool get isRegistered => _callback != null;

  @override
  void setCallback(Pointer<NativeFunction<SensorSampleNative>> cb) =>
      _callback = cb == nullptr ? null : cb;

  /// Delivers a sample of [kind] the way a CoreMotion handler would, through
  /// the real NativeCallable trampoline.
  void deliver(int kind) => _callback?.asFunction<void Function(int)>()(kind);
}

/// Sensor kinds, mirrored from the native header.
const int kAccel = 1;
const int kUserAccel = 2;
const int kGyro = 3;
const int kMag = 4;

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
    final List<AccelerometerEvent> seen = <AccelerometerEvent>[];
    final StreamSubscription<AccelerometerEvent> sub = sensors
        .accelerometerEventStream(
            samplingPeriod: const Duration(milliseconds: 10))
        .listen(seen.add);
    await pumpEventQueue();
    expect(fake.accelStarts, 1);
    expect(fake.isRegistered, isTrue);

    fake.deliver(kAccel);
    await pumpEventQueue();

    expect(seen.single.x, 1);
    expect(seen.single.y, 2);
    expect(seen.single.z, 3);

    await sub.cancel();
    expect(fake.accelStops, greaterThanOrEqualTo(1));
  });

  test('one event per native sample, not one per tick', () async {
    // The point of the push conversion: the old Timer ran on its own clock and
    // so could emit the same cached sample twice, or miss one entirely.
    final List<AccelerometerEvent> seen = <AccelerometerEvent>[];
    final StreamSubscription<AccelerometerEvent> sub =
        sensors.accelerometerEventStream().listen(seen.add);
    await pumpEventQueue();

    fake.deliver(kAccel);
    fake.deliver(kAccel);
    fake.deliver(kAccel);
    await pumpEventQueue();

    expect(seen, hasLength(3));
    await sub.cancel();
  });

  test('a sample of one kind does not emit on another sensor stream',
      () async {
    // All four share one native callback, so the fan-out has to respect kinds.
    final List<GyroscopeEvent> gyro = <GyroscopeEvent>[];
    final List<MagnetometerEvent> mag = <MagnetometerEvent>[];
    final StreamSubscription<GyroscopeEvent> gyroSub =
        sensors.gyroscopeEventStream().listen(gyro.add);
    final StreamSubscription<MagnetometerEvent> magSub =
        sensors.magnetometerEventStream().listen(mag.add);
    await pumpEventQueue();

    fake.deliver(kGyro);
    await pumpEventQueue();

    expect(gyro, hasLength(1));
    expect(mag, isEmpty);

    await gyroSub.cancel();
    await magSub.cancel();
  });

  test('no native sample yields no events (Simulator behaviour)', () async {
    fake.sample = null;
    final List<GyroscopeEvent> seen = <GyroscopeEvent>[];
    final StreamSubscription<GyroscopeEvent> sub =
        sensors.gyroscopeEventStream().listen(seen.add);
    await pumpEventQueue();

    fake.deliver(kGyro);
    await pumpEventQueue();

    expect(seen, isEmpty);
    await sub.cancel();
  });

  test('every sensor stream maps its triple', () async {
    Future<T> firstOf<T>(Stream<T> stream, int kind) async {
      final Future<T> first = stream.first;
      await pumpEventQueue();
      fake.deliver(kind);
      return first;
    }

    expect((await firstOf(sensors.userAccelerometerEventStream(), kUserAccel)).x,
        1);
    expect((await firstOf(sensors.gyroscopeEventStream(), kGyro)).y, 2);
    expect((await firstOf(sensors.magnetometerEventStream(), kMag)).z, 3);
  });
}
