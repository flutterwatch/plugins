// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Host-side unit tests. The native CoreLocation backend is replaced with a
// fake so permission mapping and the fix-polling flow are verified off-device;
// the real CLLocationManager path is exercised on a physical watch.

import 'dart:async';

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
    GeolocatorWatchos.pollInterval = const Duration(milliseconds: 1);
    geo = GeolocatorWatchos();
  });

  tearDown(() {
    GeolocatorWatchos.backendOverride = null;
    GeolocatorWatchos.pollInterval = const Duration(milliseconds: 200);
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
    // Grant after the request lands.
    scheduleMicrotask(() => fake.status = 4);
    final LocationPermission result = await geo.requestPermission();
    expect(fake.requestPermissionCount, 1);
    expect(result, LocationPermission.whileInUse);
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

  test('getPositionStream emits fixes and stops on cancel', () async {
    fake.fix = _fix();
    final Position first = await geo.getPositionStream().first;
    expect(first.latitude, 37.7749);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(fake.stopCount, greaterThanOrEqualTo(1));
  });
}
