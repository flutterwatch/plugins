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

  /// The native code before the path monitor's first update.
  static const int unknown = -1;

  /// Every native call, in order: `register`, `unregister` or `current`.
  final List<String> calls = <String>[];

  Pointer<NativeFunction<ConnectivityChangedNative>>? _callback;

  @override
  int get current {
    calls.add('current');
    return code;
  }

  @override
  void setCallback(Pointer<NativeFunction<ConnectivityChangedNative>> cb) {
    calls.add(cb == nullptr ? 'unregister' : 'register');
    _callback = cb == nullptr ? null : cb;
  }

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
  final Duration defaultFirstValueTimeout =
      ConnectivityPlusWatchos.firstValueTimeout;

  setUp(() {
    fake = _FakeBindings();
    ConnectivityPlusWatchos.bindingsOverride = fake;
  });

  tearDown(() {
    ConnectivityPlusWatchos.firstValueTimeout = defaultFirstValueTimeout;
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

  group('first value', () {
    // The native cache starts as unknown (-1) until NWPathMonitor delivers its
    // first path. These cases deliver through the real NativeCallable.listener
    // (fireChange), which fakeAsync does not control, so they run with real
    // async and pumpEventQueue, and shorten the bound where they wait it out.

    test('the bound is one second', () {
      expect(defaultFirstValueTimeout, const Duration(seconds: 1));
    });

    test('checkConnectivity registers before it reads', () async {
      final c = ConnectivityPlusWatchos();
      fake.code = 1;
      await c.checkConnectivity();
      expect(fake.calls, <String>['register', 'current', 'unregister']);
    });

    test('checkConnectivity: unknown then wifi gives [wifi]', () async {
      final c = ConnectivityPlusWatchos();
      fake.code = _FakeBindings.unknown;
      bool done = false;
      final Future<List<ConnectivityResult>> result =
          c.checkConnectivity().whenComplete(() => done = true);
      await pumpEventQueue();
      expect(done, isFalse, reason: 'unknown is not an answer; it waits');

      fake.code = 1;
      fake.fireChange();
      expect(await result, <ConnectivityResult>[ConnectivityResult.wifi]);
      expect(fake.isRegistered, isFalse,
          reason: 'the check unregisters once it has its answer');
    });

    test('checkConnectivity: unknown past the bound gives [none]', () async {
      ConnectivityPlusWatchos.firstValueTimeout =
          const Duration(milliseconds: 200);
      final c = ConnectivityPlusWatchos();
      fake.code = _FakeBindings.unknown;
      bool done = false;
      final Future<List<ConnectivityResult>> result =
          c.checkConnectivity().whenComplete(() => done = true);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(done, isFalse, reason: 'the bound has not passed yet');

      expect(await result, <ConnectivityResult>[ConnectivityResult.none]);
      expect(fake.isRegistered, isFalse);
    });

    test('the stream registers before it reads', () async {
      final c = ConnectivityPlusWatchos();
      fake.code = 1;
      final StreamSubscription<List<ConnectivityResult>> sub =
          c.onConnectivityChanged.listen((_) {});
      await pumpEventQueue();
      expect(fake.calls.take(2), <String>['register', 'current']);
      await sub.cancel();
    });

    test("the stream's first event is the first known value", () async {
      final c = ConnectivityPlusWatchos();
      fake.code = _FakeBindings.unknown;
      final List<List<ConnectivityResult>> events =
          <List<ConnectivityResult>>[];
      final StreamSubscription<List<ConnectivityResult>> sub =
          c.onConnectivityChanged.listen(events.add);
      await pumpEventQueue();
      expect(events, isEmpty, reason: 'unknown is not sent as none');

      fake.code = 1;
      fake.fireChange();
      await pumpEventQueue();
      expect(events, <List<ConnectivityResult>>[
        <ConnectivityResult>[ConnectivityResult.wifi],
      ]);
      await sub.cancel();
    });

    test('the stream sends none after the bound, then the real value',
        () async {
      ConnectivityPlusWatchos.firstValueTimeout =
          const Duration(milliseconds: 100);
      final c = ConnectivityPlusWatchos();
      fake.code = _FakeBindings.unknown;
      final List<List<ConnectivityResult>> events =
          <List<ConnectivityResult>>[];
      final StreamSubscription<List<ConnectivityResult>> sub =
          c.onConnectivityChanged.listen(events.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(events, isEmpty, reason: 'the bound has not passed yet');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(events, <List<ConnectivityResult>>[
        <ConnectivityResult>[ConnectivityResult.none],
      ]);

      fake.code = 1;
      fake.fireChange();
      await pumpEventQueue();
      expect(events, <List<ConnectivityResult>>[
        <ConnectivityResult>[ConnectivityResult.none],
        <ConnectivityResult>[ConnectivityResult.wifi],
      ]);
      await sub.cancel();
    });

    test('cancelling while unknown sends nothing later', () async {
      ConnectivityPlusWatchos.firstValueTimeout =
          const Duration(milliseconds: 50);
      final c = ConnectivityPlusWatchos();
      fake.code = _FakeBindings.unknown;
      final List<List<ConnectivityResult>> events =
          <List<ConnectivityResult>>[];
      final StreamSubscription<List<ConnectivityResult>> sub =
          c.onConnectivityChanged.listen(events.add);
      await sub.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(events, isEmpty);
      expect(fake.isRegistered, isFalse);
    });
  });
}
