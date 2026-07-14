// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:connectivity_plus_watchos/connectivity_plus_watchos.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mutable fake bindings — no FFI.
class _FakeBindings extends ConnectivityPlusWatchosBindings {
  _FakeBindings() : super.forTesting();

  int code = 1; // wifi

  @override
  int get current => code;
}

void main() {
  late _FakeBindings fake;

  setUp(() {
    fake = _FakeBindings();
    ConnectivityPlusWatchos.bindingsOverride = fake;
    ConnectivityPlusWatchos.pollInterval = const Duration(milliseconds: 10);
  });

  test('registerWith installs the watchOS implementation', () {
    ConnectivityPlusWatchos.registerWith();
    expect(ConnectivityPlatform.instance, isA<ConnectivityPlusWatchos>());
  });

  test('checkConnectivity maps every native code', () async {
    final c = ConnectivityPlusWatchos();
    fake.code = 0;
    expect(await c.checkConnectivity(), <ConnectivityResult>[ConnectivityResult.none]);
    fake.code = 1;
    expect(await c.checkConnectivity(), <ConnectivityResult>[ConnectivityResult.wifi]);
    fake.code = 2;
    expect(await c.checkConnectivity(), <ConnectivityResult>[ConnectivityResult.mobile]);
    fake.code = 3;
    expect(await c.checkConnectivity(), <ConnectivityResult>[ConnectivityResult.ethernet]);
    fake.code = 4;
    expect(await c.checkConnectivity(), <ConnectivityResult>[ConnectivityResult.other]);
  });

  test('onConnectivityChanged emits current, then only on change', () async {
    final c = ConnectivityPlusWatchos();
    fake.code = 1; // wifi
    final Future<List<List<ConnectivityResult>>> firstTwo =
        c.onConnectivityChanged.take(2).toList();
    await Future<void>.delayed(const Duration(milliseconds: 25));
    fake.code = 0; // dropped to none
    expect(await firstTwo, <List<ConnectivityResult>>[
      <ConnectivityResult>[ConnectivityResult.wifi],
      <ConnectivityResult>[ConnectivityResult.none],
    ]);
  });
}
