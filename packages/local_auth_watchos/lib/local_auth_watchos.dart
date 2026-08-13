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

  /// Registers the function native calls when an evaluation resolves, or
  /// `nullptr` to stop.
  void setCallback(Pointer<NativeFunction<LocalAuthResolvedNative>> callback);

  /// Cancels any in-progress evaluation.
  void stop();
}

/// Signature of the native→Dart completion signal.
typedef LocalAuthResolvedNative = Void Function(Int64);

/// Trampolines handed to native, kept for the life of the process.
///
/// Never closed: native can be between reading the pointer and calling it when
/// an evaluation ends, and closing under that race is worse than retaining a
/// few words per authentication.
final List<NativeCallable<LocalAuthResolvedNative>> _retainedCallables =
    <NativeCallable<LocalAuthResolvedNative>>[];

/// watchOS implementation of [LocalAuthPlatform].
base class LocalAuthWatchos extends LocalAuthPlatform {
  /// Test hook: set before first use to replace the native backend with a fake.
  static LocalAuthWatchosBackend? backendOverride;

  /// How long to wait for the system's authentication UI before giving up.
  ///
  /// The UI has no timeout of its own — a prompt left on screen stays there —
  /// so this bounds the future rather than the prompt.
  static Duration timeout = const Duration(minutes: 2);

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
    final Completer<bool> completer = Completer<bool>();

    void settle() {
      final int state = _b.poll();
      if (state != 0 && !completer.isCompleted) {
        completer.complete(state == 1);
      }
    }

    final NativeCallable<LocalAuthResolvedNative> callable =
        NativeCallable<LocalAuthResolvedNative>.listener((int _) => settle());
    // A prompt awaiting a human is not a reason to hold the isolate open.
    callable.keepIsolateAlive = false;
    _retainedCallables.add(callable);
    _b.setCallback(callable.nativeFunction);

    _b.startAuthenticate(localizedReason, options.biometricOnly);
    // An evaluation can resolve before the callback is even registered — a
    // policy the device cannot evaluate fails immediately — so check once
    // rather than waiting for a signal that has already been and gone.
    settle();

    try {
      return await completer.future.timeout(timeout, onTimeout: () {
        _b.stop();
        return false;
      });
    } finally {
      _b.setCallback(nullptr);
    }
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

  late final void Function(Pointer<NativeFunction<LocalAuthResolvedNative>>)
      _setCallback = _lib.lookupFunction<
              Void Function(Pointer<NativeFunction<LocalAuthResolvedNative>>),
              void Function(Pointer<NativeFunction<LocalAuthResolvedNative>>)>(
          'local_auth_watchos_set_callback');

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
  void setCallback(Pointer<NativeFunction<LocalAuthResolvedNative>> callback) =>
      _setCallback(callback);

  @override
  void stop() => _stop();
}
