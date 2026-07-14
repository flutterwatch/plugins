// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Runs on the watch simulator against the real LocalAuthentication-backed FFI
// implementation.
//
// The Simulator has no passcode enrolled by default, so device support is
// typically false and an evaluation fails gracefully. These assertions verify
// the symbols resolve and each method returns a well-formed result without
// throwing — the interactive success path is exercised on a real watch.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';
import 'package:local_auth_watchos/local_auth_watchos.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final LocalAuthentication auth = LocalAuthentication();

  testWidgets('watchOS implementation is registered', (WidgetTester _) async {
    expect(LocalAuthPlatform.instance, isA<LocalAuthWatchos>());
  });

  testWidgets('isDeviceSupported resolves the native canEvaluatePolicy check',
      (WidgetTester _) async {
    expect(await auth.isDeviceSupported(), isA<bool>());
  });

  testWidgets('biometrics are unavailable on watchOS', (WidgetTester _) async {
    expect(await auth.getAvailableBiometrics(), isEmpty);
    expect(await auth.isDeviceSupported(), isA<bool>());
  });

  testWidgets('stopAuthentication returns true', (WidgetTester _) async {
    expect(await LocalAuthPlatform.instance.stopAuthentication(), isTrue);
  });

  testWidgets('a biometrics-only request fails fast (no biometry on watchOS)',
      (WidgetTester _) async {
    // biometricOnly never presents interactive UI on the watch — it is
    // rejected immediately — so it is safe to drive on the Simulator.
    final bool result = await LocalAuthPlatform.instance.authenticate(
      localizedReason: 'test',
      authMessages: const <AuthMessages>[],
      options: const AuthenticationOptions(biometricOnly: true),
    );
    expect(result, isFalse);
  }, timeout: const Timeout(Duration(seconds: 15)));

  // Note: the interactive device-owner (passcode) authenticate flow presents
  // system UI and cannot be driven headlessly on the Simulator; it is verified
  // manually on a physical Apple Watch. The poll/return logic is covered by the
  // package unit tests.
}
