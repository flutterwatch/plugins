// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `local_auth`, implemented over dart:ffi.
//
// Method-channel plugins are not supported on watchOS, so this package follows
// the FFI plugin model: `watchos/Classes/local_auth_watchos_ffi.m` wraps
// LocalAuthentication (LAContext), and this class resolves the symbols via
// `DynamicLibrary.process()`. `evaluatePolicy` is asynchronous, so the native
// side caches the result and the Dart side polls it.
//
// The watch has no Face ID / Touch ID, so only device-owner (passcode / wrist
// unlock) authentication is offered: `deviceSupportsBiometrics` is false,
// `getEnrolledBiometrics` is empty, and a biometrics-only request fails.

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';

/// Native LocalAuthentication operations, behind an interface so unit tests can
/// swap in a fake off-device (see [LocalAuthWatchos.backendOverride]).
abstract class LocalAuthWatchosBackend {
  /// Whether device-owner authentication (passcode) can be evaluated.
  bool isDeviceSupported();

  /// Whether biometric authentication is available (always false on watchOS).
  bool supportsBiometrics();

  /// Begins an asynchronous evaluation, resetting the poll state to pending.
  void startAuthenticate(String reason, bool biometricOnly);

  /// Poll state: 0 = pending, 1 = success, 2 = failure.
  int poll();

  /// Cancels any in-progress evaluation.
  void stop();
}

/// watchOS implementation of [LocalAuthPlatform].
base class LocalAuthWatchos extends LocalAuthPlatform {
  /// Test hook: set before first use to replace the native backend with a fake.
  static LocalAuthWatchosBackend? backendOverride;

  /// How often the Dart side polls the native evaluation result.
  static Duration pollInterval = const Duration(milliseconds: 120);

  static LocalAuthWatchosBackend? _backend;

  static LocalAuthWatchosBackend get _b =>
      backendOverride ?? (_backend ??= _FfiBackend());

  /// Registers this implementation as the default `local_auth` platform
  /// implementation on watchOS.
  static void registerWith() {
    LocalAuthPlatform.instance = LocalAuthWatchos();
  }

  @override
  Future<bool> authenticate({
    required String localizedReason,
    required Iterable<AuthMessages> authMessages,
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async {
    _b.startAuthenticate(localizedReason, options.biometricOnly);
    // Poll until the native completion handler resolves, or give up after a
    // generous window (the system UI has no fixed timeout of its own).
    const int maxPolls = 1000;
    for (int i = 0; i < maxPolls; i++) {
      final int state = _b.poll();
      if (state != 0) {
        return state == 1;
      }
      await Future<void>.delayed(pollInterval);
    }
    _b.stop();
    return false;
  }

  @override
  Future<bool> deviceSupportsBiometrics() async => _b.supportsBiometrics();

  @override
  Future<List<BiometricType>> getEnrolledBiometrics() async =>
      const <BiometricType>[];

  @override
  Future<bool> isDeviceSupported() async => _b.isDeviceSupported();

  @override
  Future<bool> stopAuthentication() async {
    _b.stop();
    return true;
  }
}

typedef _IntNative = Int32 Function();
typedef _IntDart = int Function();
typedef _AuthNative = Void Function(Pointer<Utf8>, Int32);
typedef _AuthDart = void Function(Pointer<Utf8>, int);

/// Resolves the LocalAuthentication C symbols.
class _FfiBackend implements LocalAuthWatchosBackend {
  _FfiBackend() : _lib = DynamicLibrary.process();

  final DynamicLibrary _lib;

  late final _IntDart _isSupported = _lib.lookupFunction<_IntNative, _IntDart>(
      'local_auth_watchos_is_device_supported');
  late final _IntDart _supportsBiometrics =
      _lib.lookupFunction<_IntNative, _IntDart>(
          'local_auth_watchos_supports_biometrics');
  late final _AuthDart _authenticate =
      _lib.lookupFunction<_AuthNative, _AuthDart>(
          'local_auth_watchos_authenticate');
  late final _IntDart _poll =
      _lib.lookupFunction<_IntNative, _IntDart>('local_auth_watchos_poll');
  late final _IntDart _stop =
      _lib.lookupFunction<_IntNative, _IntDart>('local_auth_watchos_stop');

  @override
  bool isDeviceSupported() => _isSupported() == 1;

  @override
  bool supportsBiometrics() => _supportsBiometrics() == 1;

  @override
  void startAuthenticate(String reason, bool biometricOnly) {
    final Pointer<Utf8> r = reason.toNativeUtf8();
    try {
      _authenticate(r, biometricOnly ? 1 : 0);
    } finally {
      malloc.free(r);
    }
  }

  @override
  int poll() => _poll();

  @override
  void stop() => _stop();
}
