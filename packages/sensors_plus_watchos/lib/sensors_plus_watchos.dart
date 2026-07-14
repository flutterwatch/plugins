// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `sensors_plus`, implemented over dart:ffi.
//
// Method-channel plugins are not supported on watchOS, so this package follows
// the FFI plugin model: `watchos/Classes/sensors_plus_watchos_ffi.m` streams
// CoreMotion samples into a cached latest value, and this class polls that
// value on a timer at the requested sampling period — the same poll-based
// approach the battery_plus_watchos / connectivity_plus_watchos streams use.
//
// The barometer is intentionally not implemented: it is a separate CoreMotion
// altimeter API, so `barometerEventStream` keeps the base UnimplementedError.

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:sensors_plus_platform_interface/sensors_plus_platform_interface.dart';

/// The native sensor operations, behind an interface so unit tests can feed
/// canned samples off-device (see [SensorsPlusWatchos.backendOverride]).
///
/// Each `read*` returns the latest `[x, y, z]`, or null when no sample is
/// available yet (e.g. on the Simulator, which has no motion hardware).
abstract class SensorsPlusWatchosBackend {
  void startAccelerometer(int intervalMicros);
  List<double>? readAccelerometer();
  void stopAccelerometer();

  void startUserAccelerometer(int intervalMicros);
  List<double>? readUserAccelerometer();
  void stopUserAccelerometer();

  void startGyroscope(int intervalMicros);
  List<double>? readGyroscope();
  void stopGyroscope();

  void startMagnetometer(int intervalMicros);
  List<double>? readMagnetometer();
  void stopMagnetometer();
}

/// watchOS implementation of [SensorsPlatform].
base class SensorsPlusWatchos extends SensorsPlatform {
  /// Test hook: set before first use to replace the native backend with a fake.
  static SensorsPlusWatchosBackend? backendOverride;

  static SensorsPlusWatchosBackend? _backend;

  static SensorsPlusWatchosBackend get _b =>
      backendOverride ?? (_backend ??= _FfiBackend());

  /// Registers this implementation as the default `sensors_plus` platform
  /// implementation on watchOS.
  static void registerWith() {
    SensorsPlatform.instance = SensorsPlusWatchos();
  }

  @override
  Stream<AccelerometerEvent> accelerometerEventStream({
    Duration samplingPeriod = SensorInterval.normalInterval,
  }) =>
      _poll<AccelerometerEvent>(
        samplingPeriod,
        _b.startAccelerometer,
        _b.readAccelerometer,
        _b.stopAccelerometer,
        (List<double> v, DateTime t) =>
            AccelerometerEvent(v[0], v[1], v[2], t),
      );

  @override
  Stream<UserAccelerometerEvent> userAccelerometerEventStream({
    Duration samplingPeriod = SensorInterval.normalInterval,
  }) =>
      _poll<UserAccelerometerEvent>(
        samplingPeriod,
        _b.startUserAccelerometer,
        _b.readUserAccelerometer,
        _b.stopUserAccelerometer,
        (List<double> v, DateTime t) =>
            UserAccelerometerEvent(v[0], v[1], v[2], t),
      );

  @override
  Stream<GyroscopeEvent> gyroscopeEventStream({
    Duration samplingPeriod = SensorInterval.normalInterval,
  }) =>
      _poll<GyroscopeEvent>(
        samplingPeriod,
        _b.startGyroscope,
        _b.readGyroscope,
        _b.stopGyroscope,
        (List<double> v, DateTime t) => GyroscopeEvent(v[0], v[1], v[2], t),
      );

  @override
  Stream<MagnetometerEvent> magnetometerEventStream({
    Duration samplingPeriod = SensorInterval.normalInterval,
  }) =>
      _poll<MagnetometerEvent>(
        samplingPeriod,
        _b.startMagnetometer,
        _b.readMagnetometer,
        _b.stopMagnetometer,
        (List<double> v, DateTime t) => MagnetometerEvent(v[0], v[1], v[2], t),
      );

  /// Builds a broadcast stream that starts native updates on first listen,
  /// polls [read] every [samplingPeriod], and stops updates on cancel.
  Stream<T> _poll<T>(
    Duration samplingPeriod,
    void Function(int intervalMicros) start,
    List<double>? Function() read,
    void Function() stop,
    T Function(List<double> xyz, DateTime timestamp) build,
  ) {
    final int micros = samplingPeriod.inMicroseconds <= 0
        ? SensorInterval.normalInterval.inMicroseconds
        : samplingPeriod.inMicroseconds;
    final Duration period = Duration(microseconds: micros);
    late StreamController<T> controller;
    Timer? timer;

    void tick(Timer _) {
      final List<double>? xyz = read();
      if (xyz != null) {
        controller.add(build(xyz, DateTime.now()));
      }
    }

    controller = StreamController<T>.broadcast(
      onListen: () {
        start(micros);
        timer = Timer.periodic(period, tick);
      },
      onCancel: () {
        timer?.cancel();
        timer = null;
        stop();
      },
    );
    return controller.stream;
  }
}

typedef _StartNative = Void Function(Int64);
typedef _StartDart = void Function(int);
typedef _ReadNative = Int32 Function(Pointer<Double>);
typedef _ReadDart = int Function(Pointer<Double>);
typedef _StopNative = Void Function();
typedef _StopDart = void Function();

/// Resolves the CoreMotion C symbols and marshals the 3-double sample buffer.
class _FfiBackend implements SensorsPlusWatchosBackend {
  _FfiBackend() : _lib = DynamicLibrary.process();

  final DynamicLibrary _lib;

  // One reusable native buffer per sensor (each stream polls independently).
  final Pointer<Double> _accelBuf = calloc<Double>(3);
  final Pointer<Double> _userBuf = calloc<Double>(3);
  final Pointer<Double> _gyroBuf = calloc<Double>(3);
  final Pointer<Double> _magBuf = calloc<Double>(3);

  _StartDart _start(String name) =>
      _lib.lookupFunction<_StartNative, _StartDart>(name);
  _ReadDart _read(String name) =>
      _lib.lookupFunction<_ReadNative, _ReadDart>(name);
  _StopDart _stop(String name) =>
      _lib.lookupFunction<_StopNative, _StopDart>(name);

  late final _StartDart _startAccel =
      _start('sensors_plus_watchos_start_accelerometer');
  late final _ReadDart _readAccel =
      _read('sensors_plus_watchos_read_accelerometer');
  late final _StopDart _stopAccel =
      _stop('sensors_plus_watchos_stop_accelerometer');

  late final _StartDart _startUser =
      _start('sensors_plus_watchos_start_user_accelerometer');
  late final _ReadDart _readUser =
      _read('sensors_plus_watchos_read_user_accelerometer');
  late final _StopDart _stopUser =
      _stop('sensors_plus_watchos_stop_user_accelerometer');

  late final _StartDart _startGyro =
      _start('sensors_plus_watchos_start_gyroscope');
  late final _ReadDart _readGyro =
      _read('sensors_plus_watchos_read_gyroscope');
  late final _StopDart _stopGyro =
      _stop('sensors_plus_watchos_stop_gyroscope');

  late final _StartDart _startMag =
      _start('sensors_plus_watchos_start_magnetometer');
  late final _ReadDart _readMag =
      _read('sensors_plus_watchos_read_magnetometer');
  late final _StopDart _stopMag =
      _stop('sensors_plus_watchos_stop_magnetometer');

  List<double>? _copy(int available, Pointer<Double> buf) {
    if (available != 1) {
      return null;
    }
    return <double>[buf[0], buf[1], buf[2]];
  }

  @override
  void startAccelerometer(int intervalMicros) => _startAccel(intervalMicros);
  @override
  List<double>? readAccelerometer() => _copy(_readAccel(_accelBuf), _accelBuf);
  @override
  void stopAccelerometer() => _stopAccel();

  @override
  void startUserAccelerometer(int intervalMicros) => _startUser(intervalMicros);
  @override
  List<double>? readUserAccelerometer() => _copy(_readUser(_userBuf), _userBuf);
  @override
  void stopUserAccelerometer() => _stopUser();

  @override
  void startGyroscope(int intervalMicros) => _startGyro(intervalMicros);
  @override
  List<double>? readGyroscope() => _copy(_readGyro(_gyroBuf), _gyroBuf);
  @override
  void stopGyroscope() => _stopGyro();

  @override
  void startMagnetometer(int intervalMicros) => _startMag(intervalMicros);
  @override
  List<double>? readMagnetometer() => _copy(_readMag(_magBuf), _magBuf);
  @override
  void stopMagnetometer() => _stopMag();
}
