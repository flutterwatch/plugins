// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `sensors_plus`, implemented over dart:ffi.
//
// Method-channel plugins are not supported on watchOS, so this package follows
// the FFI plugin model: `watchos/Classes/sensors_plus_watchos_ffi.m` streams
// CoreMotion samples into a cached latest value and wakes Dart through a
// `NativeCallable.listener`, which re-reads the cache. One event per sample,
// no timer.
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

  /// Registers the function native calls when a sample lands, or `nullptr`
  /// to stop. One callback serves all four sensors; the kind it is passed
  /// says which produced the sample.
  void setCallback(Pointer<NativeFunction<SensorSampleNative>> callback);
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
      _push<AccelerometerEvent>(
        1,
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
      _push<UserAccelerometerEvent>(
        2,
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
      _push<GyroscopeEvent>(
        3,
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
      _push<MagnetometerEvent>(
        4,
        samplingPeriod,
        _b.startMagnetometer,
        _b.readMagnetometer,
        _b.stopMagnetometer,
        (List<double> v, DateTime t) => MagnetometerEvent(v[0], v[1], v[2], t),
      );

  /// Builds a broadcast stream that starts native updates on first listen and
  /// emits one event per CoreMotion sample of [kind], stopping on cancel.
  ///
  /// One event per native sample, not one per Dart tick. The old
  /// `Timer.periodic` ran on a clock independent of CoreMotion's, so at the
  /// same nominal rate it would re-read a sample it had already emitted, or
  /// skip one entirely — aliasing that is invisible until you look at
  /// timestamps.
  ///
  /// Two subscriptions to the same sensor are independent: both receive every
  /// sample, and the sensor stops only when the last of them cancels. They do
  /// share one native sampling interval, though — the most recent `start`
  /// wins, as it does in CoreMotion itself.
  Stream<T> _push<T>(
    int kind,
    Duration samplingPeriod,
    void Function(int intervalMicros) start,
    List<double>? Function() read,
    void Function() stop,
    T Function(List<double> xyz, DateTime timestamp) build,
  ) {
    final int micros = samplingPeriod.inMicroseconds <= 0
        ? SensorInterval.normalInterval.inMicroseconds
        : samplingPeriod.inMicroseconds;
    late StreamController<T> controller;
    bool Function()? stopListening;

    controller = StreamController<T>.broadcast(
      onListen: () {
        stopListening = _Emitters.listen(_b, kind, () {
          final List<double>? xyz = read();
          if (xyz != null) {
            controller.add(build(xyz, DateTime.now()));
          }
        });
        start(micros);
      },
      onCancel: () {
        // Only the last subscriber for this sensor may stop it.
        final bool wasLast = stopListening?.call() ?? true;
        stopListening = null;
        if (wasLast) {
          stop();
        }
      },
    );
    return controller.stream;
  }
}

/// Signature of the native→Dart sample signal.
typedef SensorSampleNative = Void Function(Int64);

/// Fan-out for the single native callback slot.
///
/// Native holds **one** callback pointer, not one per sensor and not one per
/// subscription, so every subscriber shares a trampoline that dispatches on
/// the kind it is handed. Keying by sensor alone would let a second
/// subscription to the same sensor overwrite the first's emit callback and
/// silence it, and let either one's cancel stop the sensor under the other.
class _Emitters {
  static final Map<int, Set<void Function()>> _byKind =
      <int, Set<void Function()>>{};
  static NativeCallable<SensorSampleNative>? _callable;

  /// Which backend the trampoline is currently registered with, or null when
  /// it is not registered at all.
  ///
  /// Tracked because the backend is swappable (`backendOverride`): registering
  /// once and never again would leave a replaced backend permanently silent.
  static SensorsPlusWatchosBackend? _registeredWith;

  /// Calls [emit] for every sample of [kind], and returns a function that
  /// stops it and reports whether it was the last subscriber for that sensor.
  static bool Function() listen(
      SensorsPlusWatchosBackend backend, int kind, void Function() emit) {
    _byKind.putIfAbsent(kind, () => <void Function()>{}).add(emit);
    if (!identical(_registeredWith, backend)) {
      final NativeCallable<SensorSampleNative> c = _callable ??= () {
        final NativeCallable<SensorSampleNative> created =
            NativeCallable<SensorSampleNative>.listener((int k) {
          // Copied: an emitter may remove itself while being notified.
          for (final void Function() e
              in _byKind[k]?.toList() ?? const <void Function()>[]) {
            e();
          }
        });
        // A sensor subscription should not, by itself, keep the isolate alive.
        created.keepIsolateAlive = false;
        return created;
      }();
      _registeredWith = backend;
      backend.setCallback(c.nativeFunction);
    }
    return () {
      final Set<void Function()>? emitters = _byKind[kind];
      if (emitters == null) {
        return true;
      }
      emitters.remove(emit);
      if (emitters.isNotEmpty) {
        return false;
      }
      _byKind.remove(kind);
      if (_byKind.isEmpty) {
        backend.setCallback(nullptr);
        // The trampoline itself is kept and reused on the next listen: native
        // may be between reading the pointer and calling it, an empty map
        // already makes a late signal a no-op, and a NativeCallable is only
        // reclaimed by close() — so discarding it would leak one per cycle.
        _registeredWith = null;
      }
      return true;
    };
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

  late final void Function(Pointer<NativeFunction<SensorSampleNative>>)
      _setCallback = _lib.lookupFunction<
              Void Function(Pointer<NativeFunction<SensorSampleNative>>),
              void Function(Pointer<NativeFunction<SensorSampleNative>>)>(
          'sensors_plus_watchos_set_callback');

  @override
  void setCallback(Pointer<NativeFunction<SensorSampleNative>> callback) =>
      _setCallback(callback);

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
