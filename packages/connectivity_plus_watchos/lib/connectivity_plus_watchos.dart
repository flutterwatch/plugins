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
// the current connectivity, and this class resolves the symbol via
// `DynamicLibrary.process()`.

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

  /// Current native connectivity code (0 none / 1 wifi / 2 mobile /
  /// 3 ethernet / 4 other).
  int get current => _current();
}

/// watchOS implementation of [ConnectivityPlatform].
class ConnectivityPlusWatchos extends ConnectivityPlatform {
  /// Test hook: set before first use to replace the FFI bindings.
  static ConnectivityPlusWatchosBindings? bindingsOverride;

  static ConnectivityPlusWatchosBindings? _bindings;

  static ConnectivityPlusWatchosBindings get _b =>
      bindingsOverride ?? (_bindings ??= ConnectivityPlusWatchosBindings());

  /// How often [onConnectivityChanged] polls the native monitor. The native
  /// `NWPathMonitor` updates its cache asynchronously; Dart samples it,
  /// since watchOS offers no cross-FFI push channel.
  static Duration pollInterval = const Duration(seconds: 2);

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
    Timer? timer;

    void tick() {
      final int code = _b.current;
      if (code != lastCode) {
        lastCode = code;
        controller.add(_map(code));
      }
    }

    controller = StreamController<List<ConnectivityResult>>.broadcast(
      onListen: () {
        tick();
        timer = Timer.periodic(pollInterval, (_) => tick());
      },
      onCancel: () {
        timer?.cancel();
        timer = null;
      },
    );
    return controller.stream;
  }
}
