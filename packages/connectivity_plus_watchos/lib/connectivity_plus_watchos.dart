// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `connectivity_plus`, implemented over dart:ffi.
//
// Method-channel plugins are not supported on watchOS, so
// this package follows the FFI plugin model: `watchos/Classes/
// connectivity_plus_watchos_ffi.m` runs a persistent `NWPathMonitor`
// (SystemConfiguration reachability does not exist on watchOS) and caches
// the current connectivity, and this class resolves the symbols via
// `DynamicLibrary.process()`.
//
// Changes are **pushed**: the path monitor wakes Dart through a
// `NativeCallable.listener` and Dart re-reads the cached value. It does not
// poll. A connectivity state that changes a handful of times a day does not
// justify a timer running for the life of the app on a watch.
//
// The native cache starts as "unknown" (-1): the monitor delivers its first
// path a moment after it starts. Both `checkConnectivity()` and the stream
// register for changes before they read, and while the value is unknown they
// wait for the first update, for at most
// `ConnectivityPlusWatchos.firstValueTimeout` (one second), and then report
// none. So an app that asks at start-up gets the real value, not a `none`
// that turns into `wifi` a few milliseconds later.

import 'dart:async';
import 'dart:ffi';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// FFI bindings to the native connectivity_plus_watchos C function.
///
/// Overridable for tests via [ConnectivityPlusWatchos.bindingsOverride]; the
/// [ConnectivityPlusWatchosBindings.forTesting] constructor skips FFI so
/// fakes work off-device.
class ConnectivityPlusWatchosBindings {
  /// Creates bindings that look up native symbols in the current process.
  ConnectivityPlusWatchosBindings() : _lib = DynamicLibrary.process();

  /// Constructor for fakes/mocks — skips FFI initialization.
  ConnectivityPlusWatchosBindings.forTesting() : _lib = null;

  final DynamicLibrary? _lib;

  late final int Function() _current = _lib!
      .lookupFunction<Int32 Function(), int Function()>(
          'connectivity_plus_watchos_current');

  late final void Function(Pointer<NativeFunction<ConnectivityChangedNative>>)
      _setCallback = _lib!.lookupFunction<
              Void Function(Pointer<NativeFunction<ConnectivityChangedNative>>),
              void Function(Pointer<NativeFunction<ConnectivityChangedNative>>)>(
          'connectivity_plus_watchos_set_callback');

  /// Current native connectivity code (-1 unknown / 0 none / 1 wifi /
  /// 2 mobile / 3 ethernet / 4 other).
  ///
  /// The code is -1 until the path monitor has delivered its first path.
  int get current => _current();

  /// Registers the function the path monitor calls on a change, or `nullptr`
  /// to stop.
  void setCallback(Pointer<NativeFunction<ConnectivityChangedNative>> cb) =>
      _setCallback(cb);
}

/// Signature of the native→Dart connectivity-change signal.
typedef ConnectivityChangedNative = Void Function(Int64);

/// Fan-out for the single native callback slot.
///
/// Native holds **one** callback pointer, so registering per subscription
/// would let the newest subscriber silence every older one, and let the first
/// cancel unregister the callback out from under the rest. They share one
/// trampoline instead, and native is unregistered only once nobody is left.
class _Notifier {
  static final Set<void Function()> _listeners = <void Function()>{};
  static NativeCallable<ConnectivityChangedNative>? _callable;

  /// Which bindings the trampoline is currently registered with, or null when
  /// it is not registered at all.
  ///
  /// Tracked because the bindings are swappable (`bindingsOverride`):
  /// registering once and never again would leave replaced bindings silent.
  static ConnectivityPlusWatchosBindings? _registeredWith;

  /// Calls [listener] on every path change, and returns a function that stops
  /// it.
  static void Function() listen(
      ConnectivityPlusWatchosBindings bindings, void Function() listener) {
    _listeners.add(listener);
    if (!identical(_registeredWith, bindings)) {
      final NativeCallable<ConnectivityChangedNative> c = _callable ??= () {
        final NativeCallable<ConnectivityChangedNative> created =
            NativeCallable<ConnectivityChangedNative>.listener((int _) {
          // Copied: a listener may remove itself while being notified.
          for (final void Function() l in _listeners.toList()) {
            l();
          }
        });
        // Connectivity is not a reason to keep the isolate alive.
        created.keepIsolateAlive = false;
        return created;
      }();
      _registeredWith = bindings;
      bindings.setCallback(c.nativeFunction);
    }
    return () {
      _listeners.remove(listener);
      if (_listeners.isEmpty) {
        bindings.setCallback(nullptr);
        // The trampoline itself is kept and reused on the next listen: native
        // may be between reading the pointer and calling it, an empty listener
        // set already makes a late signal a no-op, and a NativeCallable is
        // only reclaimed by close() — so discarding it would leak one per
        // listen/cancel cycle.
        _registeredWith = null;
      }
    };
  }
}

/// watchOS implementation of [ConnectivityPlatform].
class ConnectivityPlusWatchos extends ConnectivityPlatform {
  /// Test hook: set before first use to replace the FFI bindings.
  static ConnectivityPlusWatchosBindings? bindingsOverride;

  static ConnectivityPlusWatchosBindings? _bindings;

  static ConnectivityPlusWatchosBindings get _b =>
      bindingsOverride ?? (_bindings ??= ConnectivityPlusWatchosBindings());

  /// How long [checkConnectivity] and the first event of
  /// [onConnectivityChanged] wait for the path monitor's first update while
  /// the native value is still unknown. After it they report
  /// [ConnectivityResult.none].
  ///
  /// One second; tests shorten it.
  @visibleForTesting
  static Duration firstValueTimeout = const Duration(seconds: 1);

  /// The native code before the path monitor has delivered its first path.
  static const int _unknown = -1;

  /// The native code for no connectivity.
  static const int _none = 0;

  /// Registers this implementation as the default `connectivity_plus`
  /// platform implementation on watchOS.
  static void registerWith() {
    ConnectivityPlatform.instance = ConnectivityPlusWatchos();
  }

  static List<ConnectivityResult> _map(int code) {
    switch (code) {
      case 1:
        return <ConnectivityResult>[ConnectivityResult.wifi];
      case 2:
        return <ConnectivityResult>[ConnectivityResult.mobile];
      case 3:
        return <ConnectivityResult>[ConnectivityResult.ethernet];
      case 4:
        return <ConnectivityResult>[ConnectivityResult.other];
      default:
        return <ConnectivityResult>[ConnectivityResult.none];
    }
  }

  /// The current connectivity.
  ///
  /// Registers for changes before it reads, so the path monitor's first
  /// update cannot slip in between. While the native value is unknown it
  /// waits for that update, for at most [firstValueTimeout], and then reports
  /// [ConnectivityResult.none].
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    final ConnectivityPlusWatchosBindings bindings = _b;
    final Completer<int> known = Completer<int>();
    final void Function() stop = _Notifier.listen(bindings, () {
      final int code = bindings.current;
      if (code != _unknown && !known.isCompleted) {
        known.complete(code);
      }
    });
    try {
      final int code = bindings.current;
      if (code != _unknown) {
        return _map(code);
      }
      return _map(await known.future
          .timeout(firstValueTimeout, onTimeout: () => _none));
    } finally {
      stop();
    }
  }

  /// Connectivity changes, seeded with the current value for *every*
  /// subscriber.
  ///
  /// Each subscriber registers for changes before it reads. Its first event
  /// is the first known value: while the native value is unknown it waits for
  /// the path monitor's first update, and after [firstValueTimeout] without
  /// one it gets [ConnectivityResult.none] (followed by the real value when
  /// that update arrives).
  ///
  /// [Stream.multi] rather than a broadcast controller: a broadcast
  /// `onListen` fires only when the listener count goes from zero to one, so a
  /// second concurrent subscriber would never learn what the network is until
  /// it happened to change. Each subscriber gets its own dedupe state and its
  /// own entry in [_Notifier], and native is only unregistered once the last
  /// one cancels.
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      Stream<List<ConnectivityResult>>.multi(
        (MultiStreamController<List<ConnectivityResult>> out) {
          final ConnectivityPlusWatchosBindings bindings = _b;
          int? lastCode;
          Timer? firstValueTimer;

          void emit(int code) {
            if (code != lastCode) {
              lastCode = code;
              out.add(_map(code));
            }
          }

          void emitIfKnown() {
            final int code = bindings.current;
            if (code == _unknown) {
              return;
            }
            firstValueTimer?.cancel();
            firstValueTimer = null;
            emit(code);
          }

          // Register before reading, so the path monitor's first update cannot
          // slip in between.
          final void Function() stop = _Notifier.listen(bindings, emitIfKnown);
          out.onCancel = () {
            firstValueTimer?.cancel();
            firstValueTimer = null;
            stop();
          };
          // The current value first: a listener should not have to wait for
          // the network to change before it learns what the network is. While
          // it is unknown, the first update brings it, or the bound runs out.
          final int code = bindings.current;
          if (code != _unknown) {
            emit(code);
          } else {
            firstValueTimer = Timer(firstValueTimeout, () {
              firstValueTimer = null;
              emit(_none);
            });
          }
        },
        isBroadcast: true,
      );
}
