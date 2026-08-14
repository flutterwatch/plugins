// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `geolocator`, implemented over dart:ffi.
//
// Method-channel plugins are not supported on watchOS, so this package follows
// the FFI plugin model: `watchos/Classes/geolocator_watchos_ffi.m` wraps
// CoreLocation (CLLocationManager) and caches the latest fix on a delegate;
// this class resolves the symbols via `DynamicLibrary.process()` and polls the
// cached fix (the same poll-based approach the other streaming plugins use).

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

/// Native CoreLocation operations, behind an interface so unit tests can feed
/// canned fixes off-device (see [GeolocatorWatchos.backendOverride]).
abstract class GeolocatorWatchosBackend {
  bool isServiceEnabled();

  /// Raw CLAuthorizationStatus (0 notDetermined … 4 authorizedWhenInUse).
  int checkPermission();

  void requestPermission();

  void startUpdates(int accuracyIndex, double distanceFilter);

  void requestLocation();

  /// The latest fix as the 10 doubles documented in the C header, or null.
  List<double>? readPosition();

  void stopUpdates();

  /// Registers the function native calls when a new fix lands, or `nullptr`
  /// to stop.
  void setCallback(Pointer<NativeFunction<GeolocatorFixNative>> callback);
}

/// watchOS implementation of [GeolocatorPlatform].
base class GeolocatorWatchos extends GeolocatorPlatform {
  /// Test hook: set before first use to replace the native backend with a fake.
  static GeolocatorWatchosBackend? backendOverride;

  /// How often the Dart side polls the native fix while awaiting one.
  /// How long to wait for the user to answer the system permission prompt.
  ///
  /// The prompt has no timeout of its own; this only bounds the future.
  static Duration permissionTimeout = const Duration(minutes: 2);

  static GeolocatorWatchosBackend? _backend;

  static GeolocatorWatchosBackend get _b =>
      backendOverride ?? (_backend ??= _FfiBackend());

  /// Registers this implementation as the default `geolocator` platform
  /// implementation on watchOS.
  static void registerWith() {
    GeolocatorPlatform.instance = GeolocatorWatchos();
  }

  static LocationPermission _mapStatus(int raw) {
    switch (raw) {
      case 3: // authorizedAlways
        return LocationPermission.always;
      case 4: // authorizedWhenInUse
        return LocationPermission.whileInUse;
      case 1: // restricted
      case 2: // denied
        return LocationPermission.deniedForever;
      case 0: // notDetermined
      default:
        return LocationPermission.denied;
    }
  }

  static Position _toPosition(List<double> v) => Position(
        longitude: v[1],
        latitude: v[0],
        timestamp: DateTime.fromMillisecondsSinceEpoch(v[9].toInt()),
        accuracy: v[2],
        altitude: v[3],
        altitudeAccuracy: v[4],
        heading: v[5],
        headingAccuracy: v[6],
        speed: v[7],
        speedAccuracy: v[8],
      );

  @override
  Future<bool> isLocationServiceEnabled() async => _b.isServiceEnabled();

  @override
  Future<LocationPermission> checkPermission() async =>
      _mapStatus(_b.checkPermission());

  @override
  Future<LocationPermission> requestPermission() async {
    final int current = _b.checkPermission();
    if (current != 0) {
      return _mapStatus(current);
    }
    final Completer<int> completer = Completer<int>();

    void check() {
      final int status = _b.checkPermission();
      if (status != 0 && !completer.isCompleted) {
        completer.complete(status);
      }
    }

    // Registered before the prompt: the user can answer faster than the call
    // to request it returns.
    final void Function() stopListening = _Notifier.listen(_b, check);
    _b.requestPermission();
    check();

    try {
      final int status = await completer.future.timeout(
        permissionTimeout,
        onTimeout: () => 0,
      );
      return _mapStatus(status);
    } finally {
      stopListening();
    }
  }

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async {
    final List<double>? fix = _b.readPosition();
    return fix == null ? null : _toPosition(fix);
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    final LocationPermission permission = await checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const PermissionDeniedException(
          'Location permission is denied on this device.');
    }
    final LocationAccuracy accuracy =
        locationSettings?.accuracy ?? LocationAccuracy.best;
    final Duration timeLimit =
        locationSettings?.timeLimit ?? const Duration(seconds: 30);
    final double distanceFilter =
        (locationSettings?.distanceFilter ?? 0).toDouble();

    final Completer<Position> completer = Completer<Position>();

    void check() {
      final List<double>? fix = _b.readPosition();
      if (fix != null && !completer.isCompleted) {
        completer.complete(_toPosition(fix));
      }
    }

    final void Function() stopListening = _Notifier.listen(_b, check);
    _b.requestLocation();
    _b.startUpdates(accuracy.index, distanceFilter);
    // A cached fix may already satisfy this, in which case no delegate callback
    // is coming and waiting for one would burn the whole time limit.
    check();

    try {
      return await completer.future.timeout(
        timeLimit,
        onTimeout: () => throw TimeoutException(
            'Failed to obtain a location fix within $timeLimit.'),
      );
    } finally {
      stopListening();
      _b.stopUpdates();
    }
  }

  @override
  Stream<Position> getPositionStream({
    LocationSettings? locationSettings,
  }) {
    final LocationAccuracy accuracy =
        locationSettings?.accuracy ?? LocationAccuracy.best;
    final double distanceFilter =
        (locationSettings?.distanceFilter ?? 0).toDouble();
    late StreamController<Position> controller;
    List<double>? last;
    void Function()? stopListening;

    void emitIfNew() {
      final List<double>? fix = _b.readPosition();
      if (fix != null && !_sameFix(fix, last)) {
        last = fix;
        controller.add(_toPosition(fix));
      }
    }

    controller = StreamController<Position>.broadcast(
      onListen: () {
        stopListening = _Notifier.listen(_b, emitIfNew);
        _b.startUpdates(accuracy.index, distanceFilter);
        // CLLocationManager delivers the last known fix immediately on start,
        // which can land before the callback is in place.
        emitIfNew();
      },
      onCancel: () {
        stopListening?.call();
        stopListening = null;
        _b.stopUpdates();
      },
    );
    return controller.stream;
  }

  static bool _sameFix(List<double> a, List<double>? b) =>
      b != null && a[0] == b[0] && a[1] == b[1] && a[9] == b[9];
}

/// Signature of the native→Dart new-fix signal.
typedef GeolocatorFixNative = Void Function(Int64);

/// Fan-out for the single native callback slot.
///
/// Native holds **one** callback pointer, but several things wait on it at
/// once — a position stream, a `getCurrentPosition` awaiting its first fix, a
/// `requestPermission` awaiting the prompt. Registering per consumer would let
/// whichever finished last unregister the others, so they share one trampoline
/// and every waiter is notified.
class _Notifier {
  static final Set<void Function()> _listeners = <void Function()>{};
  static NativeCallable<GeolocatorFixNative>? _callable;

  /// Which backend the trampoline is currently registered with.
  ///
  /// Tracked because the backend is swappable (`backendOverride`): registering
  /// once and never again would leave a replaced backend permanently silent.
  static GeolocatorWatchosBackend? _registeredWith;

  /// Calls [listener] whenever CoreLocation reports anything, and returns a
  /// function that stops it.
  static void Function() listen(
      GeolocatorWatchosBackend backend, void Function() listener) {
    _listeners.add(listener);
    if (!identical(_registeredWith, backend)) {
      final NativeCallable<GeolocatorFixNative> c = _callable ??= () {
        final NativeCallable<GeolocatorFixNative> created =
            NativeCallable<GeolocatorFixNative>.listener((int _) {
          // Copied: a listener may remove itself while being notified.
          for (final void Function() l in _listeners.toList()) {
            l();
          }
        });
        // Waiting on a fix should not, by itself, keep the isolate alive.
        created.keepIsolateAlive = false;
        return created;
      }();
      _registeredWith = backend;
      backend.setCallback(c.nativeFunction);
    }
    return () {
      _listeners.remove(listener);
      if (_listeners.isEmpty) {
        backend.setCallback(nullptr);
        // The trampoline itself is kept and reused on the next listen: native
        // may be between reading the pointer and calling it, an empty listener
        // set already makes a late signal a no-op, and a NativeCallable is
        // only reclaimed by close() — so discarding it would leak one per
        // listen/cancel cycle.
        _registeredWith = null;
      }
    };
  }
}

typedef _IntNative = Int32 Function();
typedef _IntDart = int Function();
typedef _VoidNative = Void Function();
typedef _VoidDart = void Function();
typedef _StartNative = Void Function(Int32, Double);
typedef _StartDart = void Function(int, double);
typedef _ReadNative = Int32 Function(Pointer<Double>);
typedef _ReadDart = int Function(Pointer<Double>);

/// Resolves the CoreLocation C symbols and marshals the fix buffer.
class _FfiBackend implements GeolocatorWatchosBackend {
  _FfiBackend() : _lib = DynamicLibrary.process();

  final DynamicLibrary _lib;
  final Pointer<Double> _buf = calloc<Double>(10);

  late final _IntDart _serviceEnabled = _lib.lookupFunction<_IntNative,
      _IntDart>('geolocator_watchos_is_service_enabled');
  late final _IntDart _checkPermission = _lib.lookupFunction<_IntNative,
      _IntDart>('geolocator_watchos_check_permission');
  late final _VoidDart _requestPermission = _lib.lookupFunction<_VoidNative,
      _VoidDart>('geolocator_watchos_request_permission');
  late final _StartDart _startUpdates = _lib.lookupFunction<_StartNative,
      _StartDart>('geolocator_watchos_start_updates');
  late final _VoidDart _requestLocation = _lib.lookupFunction<_VoidNative,
      _VoidDart>('geolocator_watchos_request_location');
  late final _ReadDart _readPosition = _lib.lookupFunction<_ReadNative,
      _ReadDart>('geolocator_watchos_read_position');
  late final _VoidDart _stopUpdates = _lib.lookupFunction<_VoidNative,
      _VoidDart>('geolocator_watchos_stop_updates');
  late final void Function(Pointer<NativeFunction<GeolocatorFixNative>>)
      _setCallback = _lib.lookupFunction<
              Void Function(Pointer<NativeFunction<GeolocatorFixNative>>),
              void Function(Pointer<NativeFunction<GeolocatorFixNative>>)>(
          'geolocator_watchos_set_callback');

  @override
  bool isServiceEnabled() => _serviceEnabled() == 1;

  @override
  int checkPermission() => _checkPermission();

  @override
  void requestPermission() => _requestPermission();

  @override
  void startUpdates(int accuracyIndex, double distanceFilter) =>
      _startUpdates(accuracyIndex, distanceFilter);

  @override
  void requestLocation() => _requestLocation();

  @override
  List<double>? readPosition() {
    if (_readPosition(_buf) != 1) {
      return null;
    }
    return <double>[
      for (int i = 0; i < 10; i++) _buf[i],
    ];
  }

  @override
  void stopUpdates() => _stopUpdates();

  @override
  void setCallback(Pointer<NativeFunction<GeolocatorFixNative>> callback) =>
      _setCallback(callback);
}
