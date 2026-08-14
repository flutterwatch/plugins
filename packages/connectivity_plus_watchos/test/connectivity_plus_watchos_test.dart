// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:ffi';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:connectivity_plus_watchos/connectivity_plus_watchos.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mutable fake bindings — no FFI.
class _FakeBindings extends ConnectivityPlusWatchosBindings {
  _FakeBindings() : super.forTesting();

  int code = 1; // wifi

  Pointer<NativeFunction<ConnectivityChangedNative>>? _callback;

  @override
  int get current => code;

  @override
  void setCallback(Pointer<NativeFunction<ConnectivityChangedNative>> cb) =>
      _callback = cb == nullptr ? null : cb;

  /// Whether native would currently signal Dart.
  bool get isRegistered => _callback != null;

  /// Simulates an NWPathMonitor update.
  ///
  /// Calls the real callback pointer rather than reaching into the stream, so
  /// the test exercises the actual NativeCallable trampoline — including the
  /// fact that it delivers asynchronously.
  void fireChange() =>
      _callback?.asFunction<void Function(int)>()(0);
}

void main() {
  late _FakeBindings fake;

  setUp(() {
    fake = _FakeBindings();
    ConnectivityPlusWatchos.bindingsOverride = fake;
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
    await pumpEventQueue();

    // A signal with the same value must not emit — the native side already
    // filters, but a listener attached mid-change would otherwise see a repeat.
    fake.fireChange();
    await pumpEventQueue();

    fake.code = 0; // dropped to none
    fake.fireChange();

    expect(await firstTwo, <List<ConnectivityResult>>[
      <ConnectivityResult>[ConnectivityResult.wifi],
      <ConnectivityResult>[ConnectivityResult.none],
    ]);
  });

  test('a second listener is seeded and both see changes', () async {
    // Native holds a single callback pointer, and a broadcast onListen fires
    // only on zero-to-one: registering per subscription let the newcomer
    // silence the incumbent, and seeding in onListen left the newcomer
    // without a current value at all.
    final c = ConnectivityPlusWatchos();
    fake.code = 1; // wifi

    final List<List<ConnectivityResult>> first = <List<ConnectivityResult>>[];
    final StreamSubscription<List<ConnectivityResult>> a =
        c.onConnectivityChanged.listen(first.add);
    await pumpEventQueue();

    final List<List<ConnectivityResult>> second = <List<ConnectivityResult>>[];
    final StreamSubscription<List<ConnectivityResult>> b =
        c.onConnectivityChanged.listen(second.add);
    await pumpEventQueue();

    expect(second.single, <ConnectivityResult>[ConnectivityResult.wifi],
        reason: 'a late listener learns what the network is without waiting');

    fake.code = 0;
    fake.fireChange();
    await pumpEventQueue();

    expect(first.last, <ConnectivityResult>[ConnectivityResult.none],
        reason: 'the first listener was not silenced by the second');
    expect(second.last, <ConnectivityResult>[ConnectivityResult.none]);

    await a.cancel();
    await b.cancel();
  });

  test('cancelling one listener leaves the other registered', () async {
    final c = ConnectivityPlusWatchos();
    final List<List<ConnectivityResult>> kept = <List<ConnectivityResult>>[];
    final StreamSubscription<List<ConnectivityResult>> a =
        c.onConnectivityChanged.listen((_) {});
    final StreamSubscription<List<ConnectivityResult>> b =
        c.onConnectivityChanged.listen(kept.add);
    await pumpEventQueue();

    await a.cancel();
    expect(fake.isRegistered, isTrue,
        reason: 'one listener is left, so native must keep signalling');

    fake.code = 2;
    fake.fireChange();
    await pumpEventQueue();
    expect(kept.last, <ConnectivityResult>[ConnectivityResult.mobile]);

    await b.cancel();
    expect(fake.isRegistered, isFalse);
  });

  test('registers on listen and unregisters on cancel', () async {
    final c = ConnectivityPlusWatchos();
    expect(fake.isRegistered, isFalse);

    final StreamSubscription<List<ConnectivityResult>> sub =
        c.onConnectivityChanged.listen((_) {});
    await pumpEventQueue();
    expect(fake.isRegistered, isTrue);

    await sub.cancel();
    expect(fake.isRegistered, isFalse,
        reason: 'native must stop waking an isolate nobody is listening in');
  });
}
