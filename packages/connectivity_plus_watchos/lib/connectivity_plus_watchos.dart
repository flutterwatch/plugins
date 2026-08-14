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

import 'dart:async';
import 'dart:ffi';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';

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

  /// Current native connectivity code (0 none / 1 wifi / 2 mobile /
  /// 3 ethernet / 4 other).
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

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => _map(_b.current);

  /// Connectivity changes, seeded with the current value for *every*
  /// subscriber.
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
          int? lastCode;

          void emitIfChanged() {
            final int code = _b.current;
            if (code != lastCode) {
              lastCode = code;
              out.add(_map(code));
            }
          }

          // The current value first: a listener should not have to wait for
          // the network to change before it learns what the network is.
          emitIfChanged();
          out.onCancel = _Notifier.listen(_b, emitIfChanged);
        },
        isBroadcast: true,
      );
}
