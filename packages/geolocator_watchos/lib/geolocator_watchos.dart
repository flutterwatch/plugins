// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `geolocator`, implemented over dart:ffi.
//
// Method-channel plugins are not supported on watchOS, so this package follows
// the FFI plugin model: `watchos/Classes/geolocator_watchos_ffi.m` wraps
// CoreLocation (CLLocationManager) and caches the latest fix on a delegate,
// which wakes Dart through a `NativeCallable.listener`; this class resolves
// the symbols via `DynamicLibrary.process()` and re-reads what it waits on.
//
// `AppleSettings` from geolocator_apple is read through `toJson()`, so its
// `activityType` and `allowBackgroundLocationUpdates` reach CoreLocation
// without this package depending on geolocator_apple.

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

/// Native CoreLocation operations, behind an interface so unit tests can feed
/// canned fixes off-device (see [GeolocatorWatchos.backendOverride]).
abstract class GeolocatorWatchosBackend {
  /// Whether system location services are enabled.
  bool isServiceEnabled();

  /// Raw CLAuthorizationStatus (0 notDetermined … 4 authorizedWhenInUse).
  int checkPermission();

  /// Asks for when-in-use authorization. The answer arrives later; read it
  /// with [checkPermission].
  void requestPermission();

  /// Starts continuous updates at [accuracyIndex] (the `LocationAccuracy`
  /// index) with [distanceFilter] in metres (0 or less means none).
  ///
  /// [activityType] is a `CLActivityType` raw value, or 0 for CoreLocation's
  /// default. [allowBackground] turns on background updates when the
  /// `Info.plist`'s `UIBackgroundModes` has `location`, and is ignored
  /// otherwise.
  void startUpdates(
    int accuracyIndex,
    double distanceFilter, {
    int activityType = 0,
    bool allowBackground = false,
  });

  /// Asks for a single fix.
  void requestLocation();

  /// The latest fix as the 10 doubles documented in the C header, or null.
  List<double>? readPosition();

  /// Stops continuous updates.
  void stopUpdates();

  /// The `LocationAccuracyStatus` index the wearer allows: 0 reduced,
  /// 1 precise.
  int accuracyAuthorization();

  /// Asks for temporary full accuracy, explained by [purposeKey]. Returns
  /// false without asking when the `Info.plist` has no
  /// `NSLocationTemporaryUsageDescriptionDictionary`.
  bool requestTemporaryFullAccuracy(String purposeKey);

  /// How many temporary full-accuracy requests have finished.
  int accuracyRequestsDone();

  /// Registers the function native calls when a new fix lands, the
  /// authorization or accuracy changes, or an accuracy request ends; or
  /// `nullptr` to stop.
  void setCallback(Pointer<NativeFunction<GeolocatorFixNative>> callback);
}

/// watchOS implementation of [GeolocatorPlatform].
base class GeolocatorWatchos extends GeolocatorPlatform {
  /// Test hook: set before first use to replace the native backend with a fake.
  static GeolocatorWatchosBackend? backendOverride;

  /// How long to wait for the user to answer a system permission prompt.
  ///
  /// The prompt has no timeout of its own; this only bounds the future.
  static Duration permissionTimeout = const Duration(minutes: 2);

  static GeolocatorWatchosBackend? _backend;

  /// A cached fix older than this, from before a request, is not an answer
  /// to it: CoreLocation hands over its last fix first, however old.
  static const Duration _freshness = Duration(seconds: 5);

  /// Position streams and pending `getCurrentPosition` calls. They share the
  /// one CLLocationManager, which stops only when the last of them ends.
  static int _users = 0;

  static void _release() {
    _users--;
    if (_users == 0) {
      _b.stopUpdates();
    }
  }

  static double _notBefore() =>
      (DateTime.now().millisecondsSinceEpoch - _freshness.inMilliseconds)
          .toDouble();

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
    final Duration timeLimit =
        locationSettings?.timeLimit ?? const Duration(seconds: 30);

    final Completer<Position> completer = Completer<Position>();
    final double notBefore = _notBefore();

    void check() {
      final List<double>? fix = _b.readPosition();
      if (fix != null && fix[9] >= notBefore && !completer.isCompleted) {
        completer.complete(_toPosition(fix));
      }
    }

    final void Function() stopListening = _Notifier.listen(_b, check);
    // A position stream already running keeps its own settings; this only
    // waits for its next fix.
    if (_users == 0) {
      _b.requestLocation();
      _start(locationSettings);
    }
    _users++;
    // A recent cached fix may already satisfy this, in which case no delegate
    // callback is coming and waiting for one would burn the whole time limit.
    check();

    try {
      return await completer.future.timeout(
        timeLimit,
        onTimeout: () => throw TimeoutException(
            'Failed to obtain a location fix within $timeLimit.'),
      );
    } finally {
      stopListening();
      _release();
    }
  }

  @override
  Stream<Position> getPositionStream({
    LocationSettings? locationSettings,
  }) {
    late StreamController<Position> controller;
    List<double>? last;
    double notBefore = 0;
    void Function()? stopListening;

    void emitIfNew() {
      final List<double>? fix = _b.readPosition();
      if (fix != null && fix[9] >= notBefore && !_sameFix(fix, last)) {
        last = fix;
        controller.add(_toPosition(fix));
      }
    }

    controller = StreamController<Position>.broadcast(
      onListen: () {
        notBefore = _notBefore();
        stopListening = _Notifier.listen(_b, emitIfNew);
        _start(locationSettings);
        _users++;
        // CLLocationManager delivers the last known fix immediately on start,
        // which can land before the callback is in place.
        emitIfNew();
      },
      onCancel: () {
        stopListening?.call();
        stopListening = null;
        _release();
      },
    );
    return controller.stream;
  }

  static bool _sameFix(List<double> a, List<double>? b) =>
      b != null && a[0] == b[0] && a[1] == b[1] && a[9] == b[9];

  /// The `CLActivityType` raw value for each geolocator `ActivityType` index:
  /// automotiveNavigation, fitness, otherNavigation, airborne, other,
  /// maritime.
  static const List<int> _clActivityTypes = <int>[2, 3, 4, 5, 1, 6];

  /// Starts updates with [settings], including what an `AppleSettings`
  /// carries beyond the base class: its `toJson()` has `activityType` and
  /// `allowBackgroundLocationUpdates`.
  static void _start(LocationSettings? settings) {
    final Map<String, dynamic> json =
        settings?.toJson() ?? const <String, dynamic>{};
    final Object? activity = json['activityType'];
    _b.startUpdates(
      (settings?.accuracy ?? LocationAccuracy.best).index,
      (settings?.distanceFilter ?? 0).toDouble(),
      activityType:
          activity is int && activity >= 0 && activity < _clActivityTypes.length
              ? _clActivityTypes[activity]
              : 0,
      allowBackground: json['allowBackgroundLocationUpdates'] == true,
    );
  }

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() async =>
      LocationAccuracyStatus.values[_b.accuracyAuthorization()];

  /// Asks for full accuracy for this session.
  ///
  /// [purposeKey] names an entry of the `Info.plist`'s
  /// `NSLocationTemporaryUsageDescriptionDictionary`, whose text the prompt
  /// shows. Throws [PermissionDefinitionsNotFoundException] when the
  /// `Info.plist` has no such dictionary, as geolocator does on iOS.
  @override
  Future<LocationAccuracyStatus> requestTemporaryFullAccuracy({
    required String purposeKey,
  }) async {
    final int before = _b.accuracyRequestsDone();
    final Completer<void> completer = Completer<void>();

    void check() {
      if (_b.accuracyRequestsDone() > before && !completer.isCompleted) {
        completer.complete();
      }
    }

    // Registered before the prompt, which the wearer may answer at once.
    final void Function() stopListening = _Notifier.listen(_b, check);
    try {
      if (!_b.requestTemporaryFullAccuracy(purposeKey)) {
        throw const PermissionDefinitionsNotFoundException(
          'The temporary accuracy dictionary key is not set in the Info.plist',
        );
      }
      check();
      await completer.future.timeout(permissionTimeout, onTimeout: () {});
      return LocationAccuracyStatus.values[_b.accuracyAuthorization()];
    } finally {
      stopListening();
    }
  }

  /// Whether location services are on, starting with the current answer,
  /// then each change.
  ///
  /// CoreLocation reports a change of the system switch as an authorization
  /// change, which is when this re-reads it.
  @override
  Stream<ServiceStatus> getServiceStatusStream() =>
      Stream<ServiceStatus>.multi((MultiStreamController<ServiceStatus> c) {
        ServiceStatus? last;
        void emit() {
          final ServiceStatus now = _b.isServiceEnabled()
              ? ServiceStatus.enabled
              : ServiceStatus.disabled;
          if (now != last) {
            last = now;
            c.add(now);
          }
        }

        final void Function() stopListening = _Notifier.listen(_b, emit);
        // Creates the location manager, whose delegate reports the changes.
        _b.checkPermission();
        emit();
        c.onCancel = stopListening;
      }, isBroadcast: true);
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
typedef _StartNative = Void Function(Int32, Double, Int32, Int32);
typedef _StartDart = void Function(int, double, int, int);
typedef _Int64Native = Int64 Function();
typedef _Int64Dart = int Function();
typedef _ReadNative = Int32 Function(Pointer<Double>);
typedef _ReadDart = int Function(Pointer<Double>);

/// Resolves the CoreLocation C symbols and marshals the fix buffer.
class _FfiBackend implements GeolocatorWatchosBackend {
  _FfiBackend() : _lib = DynamicLibrary.process();

  final DynamicLibrary _lib;
  final Pointer<Double> _buf = calloc<Double>(10);

  late final _IntDart _serviceEnabled =
      _lib.lookupFunction<_IntNative, _IntDart>(
          'geolocator_watchos_is_service_enabled');
  late final _IntDart _checkPermission =
      _lib.lookupFunction<_IntNative, _IntDart>(
          'geolocator_watchos_check_permission');
  late final _VoidDart _requestPermission =
      _lib.lookupFunction<_VoidNative, _VoidDart>(
          'geolocator_watchos_request_permission');
  late final _StartDart _startUpdates =
      _lib.lookupFunction<_StartNative, _StartDart>(
          'geolocator_watchos_start_updates');
  late final _VoidDart _requestLocation =
      _lib.lookupFunction<_VoidNative, _VoidDart>(
          'geolocator_watchos_request_location');
  late final _ReadDart _readPosition =
      _lib.lookupFunction<_ReadNative, _ReadDart>(
          'geolocator_watchos_read_position');
  late final _VoidDart _stopUpdates =
      _lib.lookupFunction<_VoidNative, _VoidDart>(
          'geolocator_watchos_stop_updates');
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
  void startUpdates(
    int accuracyIndex,
    double distanceFilter, {
    int activityType = 0,
    bool allowBackground = false,
  }) =>
      _startUpdates(
          accuracyIndex, distanceFilter, activityType, allowBackground ? 1 : 0);

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

  late final _IntDart _accuracyAuthorization =
      _lib.lookupFunction<_IntNative, _IntDart>(
          'geolocator_watchos_accuracy_authorization');
  late final int Function(Pointer<Utf8>) _requestTemporaryFullAccuracy =
      _lib.lookupFunction<Int32 Function(Pointer<Utf8>),
              int Function(Pointer<Utf8>)>(
          'geolocator_watchos_request_temporary_full_accuracy');
  late final _Int64Dart _accuracyRequestsDone =
      _lib.lookupFunction<_Int64Native, _Int64Dart>(
          'geolocator_watchos_accuracy_requests_done');

  @override
  int accuracyAuthorization() => _accuracyAuthorization();

  @override
  bool requestTemporaryFullAccuracy(String purposeKey) => using(
        (Arena arena) =>
            _requestTemporaryFullAccuracy(
                purposeKey.toNativeUtf8(allocator: arena)) ==
            1,
      );

  @override
  int accuracyRequestsDone() => _accuracyRequestsDone();

  @override
  void setCallback(Pointer<NativeFunction<GeolocatorFixNative>> callback) =>
      _setCallback(callback);
}
