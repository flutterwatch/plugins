// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Host-side unit tests. The native CoreLocation backend is replaced with a
// fake so permission mapping and the fix-polling flow are verified off-device;
// the real CLLocationManager path is exercised on a physical watch.

import 'dart:async';

import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:geolocator_watchos/geolocator_watchos.dart';

class _FakeBackend implements GeolocatorWatchosBackend {
  bool serviceEnabled = true;
  int status = 4; // authorizedWhenInUse
  List<double>? fix;
  int startCount = 0;
  int stopCount = 0;
  int requestPermissionCount = 0;

  @override
  bool isServiceEnabled() => serviceEnabled;
  @override
  int checkPermission() => status;
  @override
  void requestPermission() => requestPermissionCount++;
  @override
  void startUpdates(int accuracyIndex, double distanceFilter) => startCount++;
  @override
  void requestLocation() {}
  @override
  List<double>? readPosition() => fix;
  @override
  void stopUpdates() => stopCount++;

  Pointer<NativeFunction<GeolocatorFixNative>>? _callback;

  /// Whether native would currently wake Dart.
  bool get isRegistered => _callback != null;

  @override
  void setCallback(Pointer<NativeFunction<GeolocatorFixNative>> cb) =>
      _callback = cb == nullptr ? null : cb;

  /// Fires the native signal, as any CLLocationManager delegate callback does.
  void signal() => _callback?.asFunction<void Function(int)>()(0);

  /// Delivers [next] the way a location update would.
  void deliver(List<double> next) {
    fix = next;
    signal();
  }
}

/// A representative fix: San Francisco, with distinct field values.
List<double> _fix() => <double>[
      37.7749, // latitude
      -122.4194, // longitude
      5.0, // accuracy
      12.0, // altitude
      3.0, // altitudeAccuracy
      90.0, // heading
      1.0, // headingAccuracy
      0.0, // speed
      0.5, // speedAccuracy
      1700000000000.0, // timestamp millis
    ];

void main() {
  late _FakeBackend fake;
  late GeolocatorWatchos geo;

  setUp(() {
    fake = _FakeBackend();
    GeolocatorWatchos.backendOverride = fake;
    geo = GeolocatorWatchos();
  });

  tearDown(() {
    GeolocatorWatchos.backendOverride = null;
  });

  test('registerWith installs the watchOS implementation', () {
    GeolocatorWatchos.registerWith();
    expect(GeolocatorPlatform.instance, isA<GeolocatorWatchos>());
  });

  test('checkPermission maps CLAuthorizationStatus', () async {
    fake.status = 3;
    expect(await geo.checkPermission(), LocationPermission.always);
    fake.status = 4;
    expect(await geo.checkPermission(), LocationPermission.whileInUse);
    fake.status = 2;
    expect(await geo.checkPermission(), LocationPermission.deniedForever);
    fake.status = 0;
    expect(await geo.checkPermission(), LocationPermission.denied);
  });

  test('requestPermission requests when undetermined, then maps the result',
      () async {
    fake.status = 0;
    final Future<LocationPermission> pending = geo.requestPermission();
    await pumpEventQueue();
    expect(fake.requestPermissionCount, 1);

    // The user answers the prompt; CoreLocation reports it through
    // locationManagerDidChangeAuthorization, not through any pollable value.
    fake.status = 4;
    fake.signal();

    expect(await pending, LocationPermission.whileInUse);
  });

  test('requestPermission gives up if the prompt is never answered', () async {
    GeolocatorWatchos.permissionTimeout = const Duration(milliseconds: 20);
    fake.status = 0;
    expect(await geo.requestPermission(), LocationPermission.denied);
    GeolocatorWatchos.permissionTimeout = const Duration(minutes: 2);
  });

  test('isLocationServiceEnabled forwards the native value', () async {
    expect(await geo.isLocationServiceEnabled(), isTrue);
    fake.serviceEnabled = false;
    expect(await geo.isLocationServiceEnabled(), isFalse);
  });

  test('getCurrentPosition returns a mapped Position and stops updates',
      () async {
    fake.fix = _fix();
    final Position pos = await geo.getCurrentPosition();
    expect(pos.latitude, 37.7749);
    expect(pos.longitude, -122.4194);
    expect(pos.accuracy, 5.0);
    expect(fake.startCount, 1);
    expect(fake.stopCount, 1);
  });

  test('getCurrentPosition throws when permission is denied', () async {
    fake.status = 2; // denied -> deniedForever
    expect(
      geo.getCurrentPosition(),
      throwsA(isA<PermissionDeniedException>()),
    );
  });

  test('getCurrentPosition times out when no fix arrives', () async {
    fake.fix = null;
    expect(
      geo.getCurrentPosition(
          locationSettings: const LocationSettings(
              timeLimit: Duration(milliseconds: 10))),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('getLastKnownPosition returns null when there is no fix', () async {
    expect(await geo.getLastKnownPosition(), isNull);
    fake.fix = _fix();
    expect((await geo.getLastKnownPosition())!.latitude, 37.7749);
  });

  test('getPositionStream emits the fix already available on listen', () async {
    // CLLocationManager hands over its last known fix as soon as updates
    // start, which can land before the callback is registered.
    fake.fix = _fix();
    final Position first = await geo.getPositionStream().first;
    expect(first.latitude, 37.7749);
    expect(fake.stopCount, greaterThanOrEqualTo(1));
  });

  test('getPositionStream emits each new fix native signals', () async {
    final List<Position> seen = <Position>[];
    final StreamSubscription<Position> sub =
        geo.getPositionStream().listen(seen.add);
    await pumpEventQueue();
    expect(fake.isRegistered, isTrue);

    final List<double> moved = _fix()..[0] = 40.7128; // New York
    fake.deliver(moved);
    await pumpEventQueue();

    // The same fix again must not emit — a repeated signal is not movement.
    fake.deliver(moved);
    await pumpEventQueue();

    expect(seen.map((Position p) => p.latitude), <double>[40.7128]);

    await sub.cancel();
    expect(fake.isRegistered, isFalse);
    expect(fake.stopCount, greaterThanOrEqualTo(1));
  });
}
