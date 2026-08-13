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

/// Trampolines handed to native, kept alive for the life of the process.
///
/// They are deliberately never closed. Native can be between reading the
/// pointer and calling it at the moment a listener cancels, and closing under
/// that race is worse than retaining a few words per subscription.
final List<NativeCallable<ConnectivityChangedNative>> _retainedCallables =
    <NativeCallable<ConnectivityChangedNative>>[];

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

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged {
    int? lastCode;
    late final StreamController<List<ConnectivityResult>> controller;

    void emitIfChanged() {
      final int code = _b.current;
      if (code != lastCode) {
        lastCode = code;
        controller.add(_map(code));
      }
    }

    controller = StreamController<List<ConnectivityResult>>.broadcast(
      onListen: () {
        // Emit the current value first: a listener should not have to wait for
        // the network to change before it learns what the network is.
        emitIfChanged();
        final NativeCallable<ConnectivityChangedNative> c =
            NativeCallable<ConnectivityChangedNative>.listener(
                (int _) => emitIfChanged());
        // Connectivity is not a reason to keep the isolate alive.
        c.keepIsolateAlive = false;
        _retainedCallables.add(c);
        _b.setCallback(c.nativeFunction);
      },
      onCancel: () => _b.setCallback(nullptr),
    );
    return controller.stream;
  }
}
