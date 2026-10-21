// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `wakelock_plus`, over dart:ffi.
//
// watchOS has no idle timer an app can turn off, so the wakelock is an
// extended runtime session (`watchos/Classes/wakelock_plus_watchos_ffi.m`):
// while it runs, the app keeps running and returns to the front with the
// wrist down. Its type comes from the Info.plist's WKBackgroundModes. The
// session starts asynchronously; native wakes Dart through a
// `NativeCallable.listener` and Dart re-reads the state.

import 'dart:async';
import 'dart:ffi';

import 'package:flutter/services.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

/// The native session operations, behind an interface so unit tests can
/// drive the state off-device (see [WakelockPlusWatchos.backendOverride]).
abstract class WakelockPlusWatchosBackend {
  /// Whether the Info.plist's WKBackgroundModes names a session type:
  /// self-care, mindfulness, physical-therapy or alarm.
  bool hasSessionMode();

  /// Starts a session unless one is starting or running.
  void start();

  /// Ends the session.
  void stop();

  /// 0 off, 1 starting, 2 on.
  int state();

  /// The `WKExtendedRuntimeSessionErrorCode` of the last session that ended
  /// with an error, or 0.
  int lastError();

  /// Registers the function native calls when the session starts or ends,
  /// or `nullptr` to stop.
  void setCallback(Pointer<NativeFunction<Void Function(Int64)>> callback);
}

/// watchOS implementation of [WakelockPlusPlatformInterface].
class WakelockPlusWatchos extends WakelockPlusPlatformInterface {
  /// Test hook: set before first use to replace the native backend with a fake.
  static WakelockPlusWatchosBackend? backendOverride;

  /// How long [toggle] waits for the session to start or fail.
  static Duration startTimeout = const Duration(seconds: 5);

  static WakelockPlusWatchosBackend? _backend;

  static WakelockPlusWatchosBackend get _b =>
      backendOverride ?? (_backend ??= _FfiBackend());

  /// One trampoline for the life of the app, registered only while a
  /// [toggle] waits; a `NativeCallable` is reclaimed only by `close()`.
  static NativeCallable<Void Function(Int64)>? _callable;

  /// What each waiting [toggle] checks when the session changes. Every one
  /// is woken, so a second `enable()` before the first completes does not
  /// leave the first waiting out the timeout.
  static final Set<void Function()> _waiters = <void Function()>{};

  /// Registers this implementation as the default `wakelock_plus` platform
  /// implementation on watchOS.
  static void registerWith() {
    WakelockPlusPlatformInterface.instance = WakelockPlusWatchos();
  }

  /// Turns the wakelock on or off.
  ///
  /// On starts an extended runtime session and completes once it runs. It
  /// needs a session type in the Info.plist's WKBackgroundModes; without one
  /// there is nothing to start, so this completes and [enabled] stays false.
  /// A session the system refuses fails this with a [PlatformException]
  /// whose `details` is the `WKExtendedRuntimeSessionErrorCode`. A session
  /// ends on its own when its type's time is up (10 minutes for self-care,
  /// an hour for mindfulness and physical therapy), and [enabled] then
  /// reads false.
  @override
  Future<void> toggle({required bool enable}) async {
    final WakelockPlusWatchosBackend b = _b;
    if (!enable) {
      b.stop();
      return;
    }
    if (!b.hasSessionMode() || b.state() == 2) {
      return;
    }
    final Completer<void> settled = Completer<void>();
    void check() {
      if (b.state() != 1 && !settled.isCompleted) {
        settled.complete();
      }
    }

    _waiters.add(check);
    final NativeCallable<Void Function(Int64)> callable = _callable ??= () {
      final NativeCallable<Void Function(Int64)> created =
          NativeCallable<Void Function(Int64)>.listener((int _) {
        for (final void Function() waiter in _waiters.toList()) {
          waiter();
        }
      });
      created.keepIsolateAlive = false;
      return created;
    }();
    b.setCallback(callable.nativeFunction);
    try {
      b.start();
      // The session may settle before the callback could have fired.
      check();
      await settled.future.timeout(startTimeout, onTimeout: () {});
    } finally {
      _waiters.remove(check);
      if (_waiters.isEmpty) {
        b.setCallback(nullptr);
      }
    }
    if (b.state() == 0 && b.lastError() != 0) {
      throw PlatformException(
        code: 'session_invalidated',
        message: 'watchOS ended the extended runtime session with error '
            '${b.lastError()}.',
        details: b.lastError(),
      );
    }
  }

  /// Whether the extended runtime session is running.
  @override
  Future<bool> get enabled async => _b.state() == 2;
}

/// Resolves the native session functions.
class _FfiBackend implements WakelockPlusWatchosBackend {
  _FfiBackend() : _lib = DynamicLibrary.process();

  final DynamicLibrary _lib;

  late final int Function() _hasSessionMode =
      _lib.lookupFunction<Int32 Function(), int Function()>(
          'wakelock_plus_watchos_has_session_mode');
  late final void Function() _start =
      _lib.lookupFunction<Void Function(), void Function()>(
          'wakelock_plus_watchos_start');
  late final void Function() _stop =
      _lib.lookupFunction<Void Function(), void Function()>(
          'wakelock_plus_watchos_stop');
  late final int Function() _state =
      _lib.lookupFunction<Int32 Function(), int Function()>(
          'wakelock_plus_watchos_state');
  late final int Function() _lastError =
      _lib.lookupFunction<Int64 Function(), int Function()>(
          'wakelock_plus_watchos_last_error');
  late final void Function(Pointer<NativeFunction<Void Function(Int64)>>)
      _setCallback = _lib.lookupFunction<
              Void Function(Pointer<NativeFunction<Void Function(Int64)>>),
              void Function(Pointer<NativeFunction<Void Function(Int64)>>)>(
          'wakelock_plus_watchos_set_callback');

  @override
  bool hasSessionMode() => _hasSessionMode() == 1;
  @override
  void start() => _start();
  @override
  void stop() => _stop();
  @override
  int state() => _state();
  @override
  int lastError() => _lastError();
  @override
  void setCallback(Pointer<NativeFunction<Void Function(Int64)>> callback) =>
      _setCallback(callback);
}
