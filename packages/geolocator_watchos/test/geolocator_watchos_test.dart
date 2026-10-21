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
  int lastAccuracyIndex = -1;
  int lastActivityType = -1;
  bool? lastAllowBackground;

  @override
  void startUpdates(
    int accuracyIndex,
    double distanceFilter, {
    int activityType = 0,
    bool allowBackground = false,
  }) {
    startCount++;
    lastAccuracyIndex = accuracyIndex;
    lastActivityType = activityType;
    lastAllowBackground = allowBackground;
  }

  @override
  void requestLocation() {}
  @override
  List<double>? readPosition() => fix;
  @override
  void stopUpdates() => stopCount++;

  int accuracy = 1; // precise
  bool hasTemporaryUsageDictionary = true;
  int accuracyDone = 0;
  final List<String> purposeKeys = <String>[];

  @override
  int accuracyAuthorization() => accuracy;
  @override
  bool requestTemporaryFullAccuracy(String purposeKey) {
    purposeKeys.add(purposeKey);
    return hasTemporaryUsageDictionary;
  }

  @override
  int accuracyRequestsDone() => accuracyDone;

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

/// What geolocator_apple's `AppleSettings.toJson()` adds to the base class,
/// without depending on geolocator_apple here.
class _AppleLikeSettings extends LocationSettings {
  const _AppleLikeSettings({
    required this.activityTypeIndex,
    required this.allowBackground,
  }) : super(accuracy: LocationAccuracy.bestForNavigation);

  final int activityTypeIndex;
  final bool allowBackground;

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      'pauseLocationUpdatesAutomatically': false,
      'activityType': activityTypeIndex,
      'showBackgroundLocationIndicator': false,
      'allowBackgroundLocationUpdates': allowBackground,
    });
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
      DateTime.now().millisecondsSinceEpoch.toDouble(), // timestamp millis
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
    await expectLater(
      geo.getCurrentPosition(),
      throwsA(isA<PermissionDeniedException>()),
    );
  });

  test('getCurrentPosition times out when no fix arrives', () async {
    fake.fix = null;
    await expectLater(
      geo.getCurrentPosition(
          locationSettings:
              const LocationSettings(timeLimit: Duration(milliseconds: 10))),
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

  group('accuracy', () {
    test('getLocationAccuracy maps the authorization', () async {
      fake.accuracy = 1;
      expect(await geo.getLocationAccuracy(), LocationAccuracyStatus.precise);
      fake.accuracy = 0;
      expect(await geo.getLocationAccuracy(), LocationAccuracyStatus.reduced);
    });

    test('requestTemporaryFullAccuracy waits for the answer', () async {
      fake.accuracy = 0;
      bool done = false;
      final Future<LocationAccuracyStatus> pending = geo
          .requestTemporaryFullAccuracy(purposeKey: 'Route')
          .then((LocationAccuracyStatus s) {
        done = true;
        return s;
      });
      await pumpEventQueue();
      expect(fake.purposeKeys, <String>['Route']);
      expect(done, isFalse, reason: 'the wearer has not answered yet');

      fake.accuracy = 1;
      fake.accuracyDone++;
      fake.signal();
      expect(await pending, LocationAccuracyStatus.precise);
      expect(fake.isRegistered, isFalse);
    });

    test(
        'requestTemporaryFullAccuracy throws without the Info.plist '
        'dictionary', () async {
      fake.hasTemporaryUsageDictionary = false;
      await expectLater(
        geo.requestTemporaryFullAccuracy(purposeKey: 'Route'),
        throwsA(isA<PermissionDefinitionsNotFoundException>()),
      );
      expect(fake.isRegistered, isFalse);
    });

    test('requestTemporaryFullAccuracy returns the accuracy on timeout',
        () async {
      GeolocatorWatchos.permissionTimeout = const Duration(milliseconds: 20);
      fake.accuracy = 0;
      expect(await geo.requestTemporaryFullAccuracy(purposeKey: 'Route'),
          LocationAccuracyStatus.reduced);
      GeolocatorWatchos.permissionTimeout = const Duration(minutes: 2);
    });
  });

  group('service status', () {
    test('starts with the current status, then each change', () async {
      final List<ServiceStatus> seen = <ServiceStatus>[];
      final StreamSubscription<ServiceStatus> sub =
          geo.getServiceStatusStream().listen(seen.add);
      await pumpEventQueue();

      // The trampoline runs asynchronously and re-reads the status, so each
      // change is let through before the next.
      fake.serviceEnabled = false;
      fake.signal();
      await pumpEventQueue();
      fake.signal(); // no change: not repeated
      await pumpEventQueue();
      fake.serviceEnabled = true;
      fake.signal();
      await pumpEventQueue();

      expect(seen, <ServiceStatus>[
        ServiceStatus.enabled,
        ServiceStatus.disabled,
        ServiceStatus.enabled,
      ]);
      await sub.cancel();
      expect(fake.isRegistered, isFalse);
    });

    test('a second listener starts with the status now', () async {
      final StreamSubscription<ServiceStatus> first =
          geo.getServiceStatusStream().listen((_) {});
      fake.serviceEnabled = false;
      expect(await geo.getServiceStatusStream().first, ServiceStatus.disabled);
      await first.cancel();
    });
  });

  group('settings', () {
    test('plain settings leave the activity type and background off', () async {
      final StreamSubscription<Position> sub = geo
          .getPositionStream(
              locationSettings:
                  const LocationSettings(accuracy: LocationAccuracy.medium))
          .listen((_) {});
      await pumpEventQueue();
      expect(fake.lastAccuracyIndex, LocationAccuracy.medium.index);
      expect(fake.lastActivityType, 0);
      expect(fake.lastAllowBackground, isFalse);
      await sub.cancel();
    });

    test('AppleSettings fitness and background reach CoreLocation', () async {
      final StreamSubscription<Position> sub = geo
          .getPositionStream(
              locationSettings: const _AppleLikeSettings(
                  activityTypeIndex: 1, allowBackground: true))
          .listen((_) {});
      await pumpEventQueue();
      expect(fake.lastActivityType, 3, reason: 'CLActivityTypeFitness');
      expect(fake.lastAllowBackground, isTrue);
      expect(fake.lastAccuracyIndex, LocationAccuracy.bestForNavigation.index);
      await sub.cancel();
    });

    test('every geolocator activity type maps to its CLActivityType', () async {
      // automotiveNavigation, fitness, otherNavigation, airborne, other,
      // maritime.
      const List<int> expected = <int>[2, 3, 4, 5, 1, 6];
      for (int i = 0; i < expected.length; i++) {
        fake.fix = _fix();
        await geo.getCurrentPosition(
            locationSettings: _AppleLikeSettings(
                activityTypeIndex: i, allowBackground: false));
        expect(fake.lastActivityType, expected[i]);
      }
    });

    test('an unknown activity index leaves the default', () async {
      fake.fix = _fix();
      await geo.getCurrentPosition(
          locationSettings: const _AppleLikeSettings(
              activityTypeIndex: 42, allowBackground: false));
      expect(fake.lastActivityType, 0);
    });
  });

  group('sharing the location manager', () {
    test('a one-shot during a stream leaves the stream running', () async {
      final StreamSubscription<Position> sub =
          geo.getPositionStream().listen((_) {});
      await pumpEventQueue();
      expect(fake.startCount, 1);

      fake.fix = _fix();
      await geo.getCurrentPosition();
      expect(fake.stopCount, 0, reason: 'the stream still needs updates');
      expect(fake.startCount, 1, reason: 'the stream keeps its settings');

      await sub.cancel();
      expect(fake.stopCount, 1);
    });

    test('two streams: the first cancel does not stop the second', () async {
      final StreamSubscription<Position> a =
          geo.getPositionStream().listen((_) {});
      final StreamSubscription<Position> b =
          geo.getPositionStream().listen((_) {});
      await pumpEventQueue();
      await a.cancel();
      expect(fake.stopCount, 0);
      await b.cancel();
      expect(fake.stopCount, 1);
    });

    test('a stale cached fix is not the current position', () async {
      fake.fix = _fix()..[9] = 1700000000000.0;
      final Future<Position> pending = geo.getCurrentPosition(
          locationSettings:
              const LocationSettings(timeLimit: Duration(seconds: 2)));
      await pumpEventQueue();
      fake.deliver(_fix()..[0] = 10.0);
      expect((await pending).latitude, 10.0);
    });

    test('a stream does not start with a stale cached fix', () async {
      fake.fix = _fix()..[9] = 1700000000000.0;
      final List<Position> seen = <Position>[];
      final StreamSubscription<Position> sub =
          geo.getPositionStream().listen(seen.add);
      await pumpEventQueue();
      expect(seen, isEmpty);
      fake.deliver(_fix()..[0] = 11.0);
      await pumpEventQueue();
      expect(seen.single.latitude, 11.0);
      await sub.cancel();
    });
  });
}
