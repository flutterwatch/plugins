// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Host-side unit tests. The extended runtime session is replaced with a fake
// whose state the tests move, so the wait for the session to start, and the
// answers for each way it can go, are checked off-device.

import 'dart:ffi';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';
import 'package:wakelock_plus_watchos/wakelock_plus_watchos.dart';

class _FakeBackend implements WakelockPlusWatchosBackend {
  bool sessionMode = true;
  int nativeState = 0;
  int error = 0;
  int starts = 0;
  int stops = 0;

  /// What a start turns into once the system answers: 2 runs, 0 refuses.
  int? startsInto = 2;

  Pointer<NativeFunction<Void Function(Int64)>>? _callback;

  bool get isRegistered => _callback != null;

  void signal() => _callback?.asFunction<void Function(int)>()(0);

  @override
  bool hasSessionMode() => sessionMode;

  @override
  void start() {
    starts++;
    nativeState = 1;
    final int? into = startsInto;
    if (into != null) {
      // The system answers later, as WatchKit does.
      Future<void>.delayed(const Duration(milliseconds: 5), () {
        nativeState = into;
        signal();
      });
    }
  }

  @override
  void stop() {
    stops++;
    nativeState = 0;
  }

  @override
  int state() => nativeState;

  @override
  int lastError() => error;

  @override
  void setCallback(Pointer<NativeFunction<Void Function(Int64)>> cb) =>
      _callback = cb == nullptr ? null : cb;
}

void main() {
  late _FakeBackend fake;
  late WakelockPlusWatchos wakelock;

  setUp(() {
    fake = _FakeBackend();
    WakelockPlusWatchos.backendOverride = fake;
    wakelock = WakelockPlusWatchos();
  });

  tearDown(() {
    WakelockPlusWatchos.backendOverride = null;
    WakelockPlusWatchos.startTimeout = const Duration(seconds: 5);
  });

  test('registerWith installs the watchOS implementation', () {
    WakelockPlusWatchos.registerWith();
    expect(WakelockPlusPlatformInterface.instance, isA<WakelockPlusWatchos>());
  });

  test('on waits for the session to run, off ends it', () async {
    expect(await wakelock.enabled, isFalse);
    await wakelock.toggle(enable: true);
    expect(fake.starts, 1);
    expect(await wakelock.enabled, isTrue);
    expect(fake.isRegistered, isFalse, reason: 'nothing waits any more');

    await wakelock.toggle(enable: false);
    expect(fake.stops, 1);
    expect(await wakelock.enabled, isFalse);
  });

  test('on while already on starts nothing more', () async {
    await wakelock.toggle(enable: true);
    await wakelock.toggle(enable: true);
    expect(fake.starts, 1);
  });

  test('without a session type in the Info.plist, on does nothing', () async {
    fake.sessionMode = false;
    await wakelock.toggle(enable: true);
    expect(fake.starts, 0);
    expect(await wakelock.enabled, isFalse);
  });

  test('a session the system refuses fails with its error code', () async {
    fake
      ..startsInto = 0
      ..error = 7; // WKExtendedRuntimeSessionErrorNotApprovedToStartSession
    await expectLater(
      wakelock.toggle(enable: true),
      throwsA(isA<PlatformException>()
          .having(
              (PlatformException e) => e.code, 'code', 'session_invalidated')
          .having((PlatformException e) => e.details, 'details', 7)),
    );
    expect(await wakelock.enabled, isFalse);
  });

  test('a session that never answers gives up after the timeout', () async {
    WakelockPlusWatchos.startTimeout = const Duration(milliseconds: 20);
    fake.startsInto = null;
    await wakelock.toggle(enable: true);
    expect(fake.isRegistered, isFalse);
    expect(await wakelock.enabled, isFalse, reason: 'starting is not on');
  });

  test('a session that ended on its own reads as off', () async {
    await wakelock.toggle(enable: true);
    fake.nativeState = 0; // expired
    expect(await wakelock.enabled, isFalse);
  });
}
