// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Host-side unit tests. The native side is replaced with a fake that answers
// as the header documents, asynchronously as the system does, so the
// request-id round trip, the statuses and the errors are checked off-device.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:permission_handler_watchos/permission_handler_watchos.dart';

class _FakeBackend implements PermissionHandlerWatchosBackend {
  /// The status each permission number answers with.
  final Map<int, int> statuses = <int, int>{};

  /// The status a request moves each permission number to.
  final Map<int, int> grantedOnRequest = <int, int>{};

  /// The error a request of a permission number fails with.
  final Map<int, Map<String, Object?>> errors = <int, Map<String, Object?>>{};

  /// The service status of each permission number.
  final Map<int, int> services = <int, int>{};

  final List<String> calls = <String>[];
  final Map<int, Object?> _results = <int, Object?>{};
  void Function(int kind)? _handler;
  int _next = 1;

  /// How many requests are being answered at this moment.
  int inFlight = 0;
  int mostInFlight = 0;

  bool get isRegistered => _handler != null;

  int _answerLater(Object? answer) {
    final int id = _next++;
    inFlight++;
    mostInFlight = inFlight > mostInFlight ? inFlight : mostInFlight;
    scheduleMicrotask(() {
      inFlight--;
      _results[id] = answer;
      _handler?.call(PermissionHandlerWatchosSignal.result);
    });
    return id;
  }

  @override
  int check(int permission) {
    calls.add('check $permission');
    return _answerLater(<String, Object?>{'status': statuses[permission] ?? 0});
  }

  @override
  int service(int permission) {
    calls.add('service $permission');
    return _answerLater(
        <String, Object?>{'service': services[permission] ?? 2});
  }

  @override
  int request(int permission) {
    calls.add('request $permission');
    final Map<String, Object?>? error = errors[permission];
    if (error != null) {
      return _answerLater(<String, Object?>{'error': error});
    }
    statuses[permission] = grantedOnRequest[permission] ?? 4;
    return _answerLater(<String, Object?>{'status': statuses[permission]});
  }

  @override
  String? takeResult(int request) => _results.containsKey(request)
      ? jsonEncode(_results.remove(request))
      : null;

  @override
  void setSignalHandler(void Function(int kind)? handler) => _handler = handler;
}

void main() {
  late _FakeBackend fake;
  late PermissionHandlerPlatform handler;

  setUp(() {
    fake = _FakeBackend();
    PermissionHandlerWatchos.backendOverride = fake;
    PermissionHandlerWatchos.registerWith();
    handler = PermissionHandlerPlatform.instance;
  });

  tearDown(() => PermissionHandlerWatchos.backendOverride = null);

  test('registerWith installs the watchOS implementation', () {
    expect(handler, isA<PermissionHandlerWatchos>());
  });

  test('a status is read by the permission\'s number', () async {
    fake.statuses[Permission.locationWhenInUse.value] = 1;
    fake.statuses[Permission.notification.value] = 5;
    fake.statuses[Permission.contacts.value] = 3;
    expect(await handler.checkPermissionStatus(Permission.locationWhenInUse),
        PermissionStatus.granted);
    expect(await handler.checkPermissionStatus(Permission.notification),
        PermissionStatus.provisional);
    expect(await handler.checkPermissionStatus(Permission.contacts),
        PermissionStatus.limited);
    expect(fake.isRegistered, isFalse, reason: 'nothing waits any more');
  });

  test('a service status is read', () async {
    fake.services[Permission.location.value] = 1;
    fake.services[Permission.bluetooth.value] = 0;
    expect(await handler.checkServiceStatus(Permission.location),
        ServiceStatus.enabled);
    expect(await handler.checkServiceStatus(Permission.bluetooth),
        ServiceStatus.disabled);
    expect(await handler.checkServiceStatus(Permission.microphone),
        ServiceStatus.notApplicable);
  });

  test('permissions are asked for one at a time, in order', () async {
    fake.grantedOnRequest[Permission.notification.value] = 1;
    final Map<Permission, PermissionStatus> statuses =
        await handler.requestPermissions(<Permission>[
      Permission.notification,
      Permission.camera,
    ]);
    expect(statuses, <Permission, PermissionStatus>{
      Permission.notification: PermissionStatus.granted,
      Permission.camera: PermissionStatus.permanentlyDenied,
    });
    expect(fake.calls, <String>[
      'request ${Permission.notification.value}',
      'request ${Permission.camera.value}',
    ]);
    expect(fake.mostInFlight, 1);
  });

  test('a missing usage description is a PlatformException', () async {
    fake.errors[Permission.contacts.value] = <String, Object?>{
      'code': 'MISSING_USAGE_DESCRIPTION',
      'message': 'The app has no NSContactsUsageDescription.',
    };
    await expectLater(
      handler.requestPermissions(<Permission>[Permission.contacts]),
      throwsA(isA<PlatformException>().having((PlatformException e) => e.code,
          'code', 'MISSING_USAGE_DESCRIPTION')),
    );
    expect(fake.isRegistered, isFalse);
  });

  test('the watch shows no rationale and opens no settings', () async {
    expect(
        await handler.shouldShowRequestPermissionRationale(Permission.location),
        isFalse);
    expect(await handler.openAppSettings(), isFalse);
    expect(fake.calls, isEmpty);
  });
}
