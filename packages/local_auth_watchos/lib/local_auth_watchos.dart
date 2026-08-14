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

/// Fan-out for the single native callback slot.
///
/// Native holds **one** callback pointer, so a second [LocalAuthWatchos
/// .authenticate] would otherwise overwrite the first's callback — leaving
/// the first future to hang until its timeout and report failure for an
/// authentication that succeeded — and then clear the callback the first was
/// still waiting on. Overlapping calls share one trampoline, and all of them
/// settle when the evaluation resolves.
class _Notifier {
  static final Set<void Function()> _listeners = <void Function()>{};
  static NativeCallable<LocalAuthResolvedNative>? _callable;

  /// Which backend the trampoline is currently registered with, or null when
  /// it is not registered at all.
  ///
  /// Tracked because the backend is swappable (`backendOverride`): registering
  /// once and never again would leave a replaced backend silent.
  static LocalAuthWatchosBackend? _registeredWith;

  /// Calls [listener] whenever an evaluation resolves, and returns a function
  /// that stops it.
  static void Function() listen(
      LocalAuthWatchosBackend backend, void Function() listener) {
    _listeners.add(listener);
    if (!identical(_registeredWith, backend)) {
      final NativeCallable<LocalAuthResolvedNative> c = _callable ??= () {
        final NativeCallable<LocalAuthResolvedNative> created =
            NativeCallable<LocalAuthResolvedNative>.listener((int _) {
          // Copied: a listener removes itself as it settles.
          for (final void Function() l in _listeners.toList()) {
            l();
          }
        });
        // A prompt awaiting a human is not a reason to hold the isolate open.
        created.keepIsolateAlive = false;
        return created;
      }();
      _registeredWith = backend;
      backend.setCallback(c.nativeFunction);
    }
    return () {
      _listeners.remove(listener);
      if (_listeners.isEmpty) {
        backend.setCallback(nullptr);
        // The trampoline itself is kept and reused by the next call: native
        // may be between reading the pointer and calling it, an empty listener
        // set already makes a late signal a no-op, and a NativeCallable is
        // only reclaimed by close() — so discarding it would leak one per
        // authentication.
        _registeredWith = null;
      }
    };
  }
}

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

  /// Prompts for device-owner authentication.
  ///
  /// Native runs one `LAContext` at a time, so overlapping calls share a
  /// single evaluation: the later prompt supersedes the earlier one and every
  /// outstanding future completes with that shared outcome. None of them
  /// hangs, which is the part that matters — a caller that needs the two
  /// treated separately has to serialise them itself.
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

    final void Function() stopListening = _Notifier.listen(_b, settle);

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
      // Only unregisters native once no other call is still waiting.
      stopListening();
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
