// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Host-side unit tests. The native LocalAuthentication backend is replaced
// with a fake so the authenticate flow is verified off-device; the real
// LAContext path is exercised by the example's integration_test.

import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';
import 'package:local_auth_watchos/local_auth_watchos.dart';

/// Backend whose evaluation stays pending until the test resolves it.
class _FakeBackend implements LocalAuthWatchosBackend {
  bool deviceSupported = true;
  bool biometrics = false;

  /// 0 pending, 1 success, 2 failure. Starts pending, like a prompt on screen.
  int state = 0;

  /// What [resolve] settles to.
  int result = 1;

  int startCount = 0;
  int stopCount = 0;
  bool? lastBiometricOnly;

  Pointer<NativeFunction<LocalAuthResolvedNative>>? _callback;

  /// Whether native would currently signal Dart.
  bool get isRegistered => _callback != null;

  @override
  void setCallback(Pointer<NativeFunction<LocalAuthResolvedNative>> cb) =>
      _callback = cb == nullptr ? null : cb;

  /// Settles the evaluation the way the LAContext reply block would.
  ///
  /// Calls the real callback pointer, so the test goes through the actual
  /// NativeCallable trampoline rather than around it.
  void resolve() {
    state = result;
    _callback?.asFunction<void Function(int)>()(0);
  }

  @override
  bool isDeviceSupported() => deviceSupported;

  @override
  bool supportsBiometrics() => biometrics;

  /// Models a policy the device cannot evaluate: LAContext's reply block runs
  /// synchronously inside `evaluatePolicy`, so the result is already there
  /// before Dart could observe a signal.
  bool resolveInsideStart = false;

  @override
  void startAuthenticate(String reason, bool biometricOnly) {
    startCount++;
    lastBiometricOnly = biometricOnly;
    state = resolveInsideStart ? result : 0;
  }

  @override
  int poll() => state;

  @override
  void stop() => stopCount++;
}

void main() {
  late _FakeBackend fake;
  late LocalAuthWatchos auth;

  setUp(() {
    fake = _FakeBackend();
    LocalAuthWatchos.backendOverride = fake;
    auth = LocalAuthWatchos();
  });

  tearDown(() {
    LocalAuthWatchos.backendOverride = null;
    LocalAuthWatchos.timeout = const Duration(minutes: 2);
  });

  test('registerWith installs the watchOS implementation', () {
    LocalAuthWatchos.registerWith();
    expect(LocalAuthPlatform.instance, isA<LocalAuthWatchos>());
  });

  test('authenticate resolves when native signals success', () async {
    final Future<bool> pending = auth.authenticate(
        localizedReason: 'Unlock', authMessages: const <AuthMessages>[]);
    await pumpEventQueue();

    // Still waiting: the prompt is on screen and nobody has answered it.
    expect(fake.startCount, 1);
    expect(fake.isRegistered, isTrue);

    fake.resolve();
    expect(await pending, isTrue);
    expect(fake.isRegistered, isFalse,
        reason: 'the callback must be unregistered once the future settles');
  });

  test('resolves an evaluation that finished before the first signal',
      () async {
    // A policy the device cannot evaluate fails immediately — synchronously,
    // inside startAuthenticate — so the signal has been and gone before Dart
    // could register for it. Without the check after start, this would hang.
    fake.resolveInsideStart = true;
    fake.result = 2;

    final bool ok = await auth.authenticate(
        localizedReason: 'Unlock', authMessages: const <AuthMessages>[]);
    expect(ok, isFalse);
  });

  test('gives up and cancels if the prompt is never answered', () async {
    LocalAuthWatchos.timeout = const Duration(milliseconds: 20);
    final bool ok = await auth.authenticate(
        localizedReason: 'Unlock', authMessages: const <AuthMessages>[]);
    expect(ok, isFalse);
    expect(fake.stopCount, 1, reason: 'a timed-out evaluation must be cancelled');
  });

  test('authenticate returns false when the evaluation fails', () async {
    fake.result = 2;
    final Future<bool> pending = auth.authenticate(
        localizedReason: 'Unlock', authMessages: const <AuthMessages>[]);
    await pumpEventQueue();
    fake.resolve();
    expect(await pending, isFalse);
  });

  test('biometricOnly option is forwarded to native', () async {
    final Future<bool> pending = auth.authenticate(
      localizedReason: 'Unlock',
      authMessages: const <AuthMessages>[],
      options: const AuthenticationOptions(biometricOnly: true),
    );
    await pumpEventQueue();
    fake.resolve();
    await pending;
    expect(fake.lastBiometricOnly, isTrue);
  });

  test('biometrics are unavailable on watchOS', () async {
    expect(await auth.deviceSupportsBiometrics(), isFalse);
    expect(await auth.getEnrolledBiometrics(), isEmpty);
  });

  test('isDeviceSupported reflects the native passcode check', () async {
    expect(await auth.isDeviceSupported(), isTrue);
    fake.deviceSupported = false;
    expect(await auth.isDeviceSupported(), isFalse);
  });

  test('stopAuthentication cancels the native evaluation', () async {
    expect(await auth.stopAuthentication(), isTrue);
    expect(fake.stopCount, 1);
  });
}
