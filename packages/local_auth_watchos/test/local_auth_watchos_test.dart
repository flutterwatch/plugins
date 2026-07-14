// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Host-side unit tests. The native LocalAuthentication backend is replaced
// with a fake so the poll/authenticate flow is verified off-device; the real
// LAContext path is exercised by the example's integration_test.

import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';
import 'package:local_auth_watchos/local_auth_watchos.dart';

/// Backend that resolves the poll after [pollsUntilResult] polls with [result].
class _FakeBackend implements LocalAuthWatchosBackend {
  bool deviceSupported = true;
  bool biometrics = false;
  int pollsUntilResult = 2;
  int result = 1; // 1 success, 2 failure

  int startCount = 0;
  int stopCount = 0;
  int _polls = 0;
  bool? lastBiometricOnly;

  @override
  bool isDeviceSupported() => deviceSupported;

  @override
  bool supportsBiometrics() => biometrics;

  @override
  void startAuthenticate(String reason, bool biometricOnly) {
    startCount++;
    lastBiometricOnly = biometricOnly;
    _polls = 0;
  }

  @override
  int poll() {
    _polls++;
    return _polls >= pollsUntilResult ? result : 0;
  }

  @override
  void stop() => stopCount++;
}

void main() {
  late _FakeBackend fake;
  late LocalAuthWatchos auth;

  setUp(() {
    fake = _FakeBackend();
    LocalAuthWatchos.backendOverride = fake;
    LocalAuthWatchos.pollInterval = const Duration(milliseconds: 1);
    auth = LocalAuthWatchos();
  });

  tearDown(() {
    LocalAuthWatchos.backendOverride = null;
    LocalAuthWatchos.pollInterval = const Duration(milliseconds: 120);
  });

  test('registerWith installs the watchOS implementation', () {
    LocalAuthWatchos.registerWith();
    expect(LocalAuthPlatform.instance, isA<LocalAuthWatchos>());
  });

  test('authenticate polls until success', () async {
    final bool ok = await auth.authenticate(
        localizedReason: 'Unlock', authMessages: const <AuthMessages>[]);
    expect(ok, isTrue);
    expect(fake.startCount, 1);
  });

  test('authenticate returns false when the evaluation fails', () async {
    fake.result = 2;
    final bool ok = await auth.authenticate(
        localizedReason: 'Unlock', authMessages: const <AuthMessages>[]);
    expect(ok, isFalse);
  });

  test('biometricOnly option is forwarded to native', () async {
    await auth.authenticate(
      localizedReason: 'Unlock',
      authMessages: const <AuthMessages>[],
      options: const AuthenticationOptions(biometricOnly: true),
    );
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
