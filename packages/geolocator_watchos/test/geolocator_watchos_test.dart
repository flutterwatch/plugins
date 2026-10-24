// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Host-side unit tests. The native CoreLocation backend is replaced with a
// fake so permission mapping and the fix-delivery flow are verified off-device;
// the real CLLocationManager path is exercised on a physical watch.

import 'dart:async';

import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_apple/geolocator_apple.dart'
    show ActivityType, AppleSettings;
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:geolocator_watchos/geolocator_watchos.dart';

class _FakeBackend implements GeolocatorWatchosBackend {
  bool serviceEnabled = true;
  int serviceChecks = 0;
  int status = 4; // authorizedWhenInUse
  List<double>? fix;
  int count = 0;
  int startCount = 0;
  int stopCount = 0;
  int requestPermissionCount = 0;

  /// What the single-request manager delivers once asked, or null for
  /// nothing.
  List<double>? singleFix;
  int requestLocationCount = 0;
  int stopRequestCount = 0;
  int? lastRequestAccuracy;
  final List<int> requestedAccuracies = <int>[];

  /// What CoreLocation hands over as the stream starts, or null for nothing.
  List<double>? fixOnStart;

  @override
  bool isServiceEnabled() {
    serviceChecks++;
    return serviceEnabled;
  }

  @override
  int checkPermission() => status;
  @override
  void requestPermission() => requestPermissionCount++;
  int lastAccuracyIndex = -1;
  double lastDistanceFilter = -1;
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
    lastDistanceFilter = distanceFilter;
    lastActivityType = activityType;
    lastAllowBackground = allowBackground;
    final List<double>? first = fixOnStart;
    if (first != null) {
      deliver(first);
    }
  }

  @override
  void requestLocation(int accuracyIndex) {
    requestLocationCount++;
    lastRequestAccuracy = accuracyIndex;
    requestedAccuracies.add(accuracyIndex);
    final List<double>? next = singleFix;
    if (next != null) {
      deliver(next);
    }
  }

  @override
  void stopLocationRequest() => stopRequestCount++;
  @override
  List<double>? readPosition() => fix;
  @override
  int positionCount() => count;
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

  /// Fires the native signal of [kind], as a CLLocationManager delegate
  /// callback does.
  void signal(int kind) => _callback?.asFunction<void Function(int)>()(kind);

  /// Delivers [next] the way a location update would.
  void deliver(List<double> next) {
    fix = next;
    count++;
    signal(GeolocatorWatchosSignal.position);
  }
}

/// Settings whose `toJson()` names an activity type no geolocator version
/// has.
class _UnknownActivitySettings extends LocationSettings {
  const _UnknownActivitySettings();

  @override
  Map<String, dynamic> toJson() =>
      super.toJson()..addAll(<String, dynamic>{'activityType': 42});
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
    fake.signal(GeolocatorWatchosSignal.authorization);

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

  group('getCurrentPosition', () {
    test('asks the single-request manager and maps its fix', () async {
      fake.singleFix = _fix();
      final Position pos = await geo.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.low));
      expect(pos.latitude, 37.7749);
      expect(pos.longitude, -122.4194);
      expect(pos.accuracy, 5.0);
      expect(fake.requestLocationCount, 1);
      expect(fake.lastRequestAccuracy, LocationAccuracy.low.index);
      expect(fake.stopRequestCount, 1);
      expect(fake.startCount, 0, reason: "the stream's manager is not used");
    });

    test('throws when permission is denied', () async {
      fake.status = 2; // denied -> deniedForever
      await expectLater(
        geo.getCurrentPosition(),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('times out when no fix arrives, and stops asking', () async {
      await expectLater(
        geo.getCurrentPosition(
            locationSettings:
                const LocationSettings(timeLimit: Duration(milliseconds: 10))),
        throwsA(isA<TimeoutException>()),
      );
      expect(fake.stopRequestCount, 1);
    });

    test('the fix cached before the request is not the answer', () async {
      fake.fix = _fix()..[0] = 1.0;
      final Future<Position> pending = geo.getCurrentPosition(
          locationSettings:
              const LocationSettings(timeLimit: Duration(seconds: 2)));
      await pumpEventQueue();
      // A signal without a new fix, as a failed update sends.
      fake.signal(GeolocatorWatchosSignal.position);
      await pumpEventQueue();
      fake.deliver(_fix()..[0] = 10.0);
      expect((await pending).latitude, 10.0);
    });

    test('two at once share the single-request manager', () async {
      final Future<Position> a = geo.getCurrentPosition();
      final Future<Position> b = geo.getCurrentPosition();
      await pumpEventQueue();
      expect(fake.requestLocationCount, 2);
      fake.deliver(_fix()..[0] = 12.0);
      expect((await a).latitude, 12.0);
      expect((await b).latitude, 12.0);
      expect(fake.stopRequestCount, 1, reason: 'stopped once both are done');
    });

    Future<Position> request(LocationAccuracy accuracy) =>
        geo.getCurrentPosition(
            locationSettings: LocationSettings(accuracy: accuracy));

    test(
        'pending calls run at the most accurate accuracy any of them asked for',
        () async {
      final List<Future<Position>> pending = <Future<Position>>[
        request(LocationAccuracy.low),
        request(LocationAccuracy.best),
        request(LocationAccuracy.medium),
      ];
      await pumpEventQueue();
      expect(fake.requestedAccuracies, <int>[
        LocationAccuracy.low.index,
        LocationAccuracy.best.index,
        LocationAccuracy.best.index,
      ]);
      fake.deliver(_fix());
      await Future.wait(pending);

      // With none pending, the next call runs at its own accuracy.
      fake.singleFix = _fix();
      await request(LocationAccuracy.low);
      expect(fake.requestedAccuracies.last, LocationAccuracy.low.index);
    });

    test('reduced is the least accurate, bestForNavigation the most', () async {
      final List<Future<Position>> pending = <Future<Position>>[
        request(LocationAccuracy.reduced),
        request(LocationAccuracy.lowest),
        request(LocationAccuracy.bestForNavigation),
        request(LocationAccuracy.best),
      ];
      await pumpEventQueue();
      expect(fake.requestedAccuracies, <int>[
        LocationAccuracy.reduced.index,
        LocationAccuracy.lowest.index,
        LocationAccuracy.bestForNavigation.index,
        LocationAccuracy.bestForNavigation.index,
      ]);
      fake.deliver(_fix());
      await Future.wait(pending);
    });

    test('a call that times out leaves the others at the accuracy they share',
        () async {
      final Future<Position> best = request(LocationAccuracy.best);
      final Future<Position> short = geo.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: Duration(milliseconds: 10)));
      await expectLater(short, throwsA(isA<TimeoutException>()));
      expect(fake.stopRequestCount, 0, reason: 'one call is still pending');
      final Future<Position> medium = request(LocationAccuracy.medium);
      await pumpEventQueue();
      expect(fake.requestedAccuracies, <int>[
        LocationAccuracy.best.index,
        LocationAccuracy.best.index,
        LocationAccuracy.best.index,
      ]);
      fake.deliver(_fix());
      await Future.wait(<Future<Position>>[best, medium]);
      expect(fake.stopRequestCount, 1);
    });
  });

  test('getLastKnownPosition returns null when there is no fix', () async {
    expect(await geo.getLastKnownPosition(), isNull);
    fake.fix = _fix();
    expect((await geo.getLastKnownPosition())!.latitude, 37.7749);
  });

  group('getPositionStream', () {
    test('emits the fix CoreLocation hands over at start, however old',
        () async {
      fake.fixOnStart = _fix()..[9] = 1700000000000.0;
      final Position first = await geo.getPositionStream().first;
      expect(first.timestamp.millisecondsSinceEpoch, 1700000000000);
      expect(fake.stopCount, 1);
    });

    test('emits each fix native delivers, and nothing else', () async {
      final List<Position> seen = <Position>[];
      final StreamSubscription<Position> sub =
          geo.getPositionStream().listen(seen.add);
      await pumpEventQueue();
      expect(fake.isRegistered, isTrue);

      final List<double> moved = _fix()..[0] = 40.7128; // New York
      fake.deliver(moved);
      await pumpEventQueue();
      // A second fix at the same place is a fix too.
      fake.deliver(moved);
      await pumpEventQueue();
      // Signals without a new fix are not.
      fake.signal(GeolocatorWatchosSignal.position);
      fake.signal(GeolocatorWatchosSignal.authorization);
      await pumpEventQueue();

      expect(seen.map((Position p) => p.latitude), <double>[40.7128, 40.7128]);

      await sub.cancel();
      expect(fake.isRegistered, isFalse);
      expect(fake.stopCount, 1);
    });

    test('a second call gets the running stream, with its settings', () async {
      final Stream<Position> first = geo.getPositionStream(
          locationSettings: AppleSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: 25));
      final StreamSubscription<Position> a = first.listen((_) {});
      final Stream<Position> second = geo.getPositionStream(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.low));
      expect(identical(first, second), isTrue);
      final StreamSubscription<Position> b = second.listen((_) {});
      await pumpEventQueue();
      expect(fake.startCount, 1);
      expect(fake.lastAccuracyIndex, LocationAccuracy.bestForNavigation.index);
      expect(fake.lastDistanceFilter, 25);
      expect(fake.lastAllowBackground, isTrue);

      await a.cancel();
      expect(fake.stopCount, 0, reason: 'the second listener remains');
      await b.cancel();
      expect(fake.stopCount, 1);

      // Once it has ended, a new stream starts with its own settings.
      final StreamSubscription<Position> c = geo
          .getPositionStream(
              locationSettings:
                  const LocationSettings(accuracy: LocationAccuracy.low))
          .listen((_) {});
      await pumpEventQueue();
      expect(fake.startCount, 2);
      expect(fake.lastAccuracyIndex, LocationAccuracy.low.index);
      await c.cancel();
    });

    test(
        'a single fix during a distance-filtered stream does not wait for '
        'the stream', () async {
      final StreamSubscription<Position> sub = geo
          .getPositionStream(
              locationSettings: const LocationSettings(distanceFilter: 100))
          .listen((_) {});
      await pumpEventQueue();
      expect(fake.startCount, 1);

      // The wearer stands still: the stream delivers nothing, the
      // single-request manager does.
      fake.singleFix = _fix()..[0] = 20.0;
      final Position pos = await geo.getCurrentPosition(
          locationSettings:
              const LocationSettings(timeLimit: Duration(seconds: 2)));
      expect(pos.latitude, 20.0);
      expect(fake.requestLocationCount, 1);
      expect(fake.startCount, 1, reason: 'the stream keeps its settings');
      expect(fake.stopCount, 0, reason: 'the stream still runs');

      await sub.cancel();
      expect(fake.stopCount, 1);
    });
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
      fake.signal(GeolocatorWatchosSignal.accuracy);
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
      fake.signal(GeolocatorWatchosSignal.authorization);
      await pumpEventQueue();
      // no change: not repeated
      fake.signal(GeolocatorWatchosSignal.authorization);
      await pumpEventQueue();
      fake.serviceEnabled = true;
      fake.signal(GeolocatorWatchosSignal.authorization);
      await pumpEventQueue();

      expect(seen, <ServiceStatus>[
        ServiceStatus.enabled,
        ServiceStatus.disabled,
        ServiceStatus.enabled,
      ]);
      await sub.cancel();
      expect(fake.isRegistered, isFalse);
    });

    test('a fix does not re-read the services switch', () async {
      final StreamSubscription<ServiceStatus> sub =
          geo.getServiceStatusStream().listen((_) {});
      await pumpEventQueue();
      final int checks = fake.serviceChecks;
      fake.deliver(_fix());
      await pumpEventQueue();
      expect(fake.serviceChecks, checks);
      await sub.cancel();
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
              locationSettings: AppleSettings(
                  accuracy: LocationAccuracy.bestForNavigation,
                  activityType: ActivityType.fitness))
          .listen((_) {});
      await pumpEventQueue();
      expect(fake.lastActivityType, 3, reason: 'CLActivityTypeFitness');
      expect(fake.lastAllowBackground, isTrue,
          reason: "AppleSettings' default");
      expect(fake.lastAccuracyIndex, LocationAccuracy.bestForNavigation.index);
      await sub.cancel();
    });

    test('every geolocator activity type reaches its CLActivityType', () async {
      // CLActivityType raw values; 6 is the maritime value native maps.
      const Map<ActivityType, int> expected = <ActivityType, int>{
        ActivityType.other: 1,
        ActivityType.automotiveNavigation: 2,
        ActivityType.fitness: 3,
        ActivityType.otherNavigation: 4,
        ActivityType.airborne: 5,
        ActivityType.maritime: 6,
      };
      for (final ActivityType type in ActivityType.values) {
        final StreamSubscription<Position> sub = geo
            .getPositionStream(
                locationSettings: AppleSettings(activityType: type))
            .listen((_) {});
        await pumpEventQueue();
        expect(fake.lastActivityType, expected[type], reason: type.name);
        await sub.cancel();
      }
    });

    test('an unknown activity index leaves the default', () async {
      final StreamSubscription<Position> sub = geo
          .getPositionStream(locationSettings: const _UnknownActivitySettings())
          .listen((_) {});
      await pumpEventQueue();
      expect(fake.lastActivityType, 0);
      await sub.cancel();
    });
  });
}
