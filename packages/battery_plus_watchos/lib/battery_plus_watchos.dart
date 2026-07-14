// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `battery_plus`, implemented over dart:ffi.
//
// Method-channel plugins are not supported on watchOS, so
// this package follows the FFI plugin model: `watchos/Classes/
// battery_plus_watchos_ffi.m` exports the battery readings from
// `WKInterfaceDevice`, and this class resolves the symbols via
// `DynamicLibrary.process()`.

import 'dart:async';
import 'dart:ffi';

import 'package:battery_plus_platform_interface/battery_plus_platform_interface.dart';

/// FFI bindings to the native battery_plus_watchos C functions.
///
/// Overridable for tests via [BatteryPlusWatchos.bindingsOverride]; the
/// [BatteryPlusWatchosBindings.forTesting] constructor skips FFI so fakes
/// work off-device.
class BatteryPlusWatchosBindings {
  /// Creates bindings that look up native symbols in the current process.
  BatteryPlusWatchosBindings() : _lib = DynamicLibrary.process();

  /// Constructor for fakes/mocks — skips FFI initialization.
  BatteryPlusWatchosBindings.forTesting() : _lib = null;

  final DynamicLibrary? _lib;

  late final int Function() _level = _lib!
      .lookupFunction<Int32 Function(), int Function()>(
          'battery_plus_watchos_level');

  late final int Function() _state = _lib!
      .lookupFunction<Int32 Function(), int Function()>(
          'battery_plus_watchos_state');

  late final int Function() _lowPower = _lib!
      .lookupFunction<Int32 Function(), int Function()>(
          'battery_plus_watchos_is_low_power');

  /// Battery charge 0–100, or -1 when unavailable.
  int get level => _level();

  /// `WKInterfaceDeviceBatteryState` raw value (0 unknown / 1 unplugged /
  /// 2 charging / 3 full).
  int get state => _state();

  /// Whether Low Power Mode is on.
  bool get isLowPower => _lowPower() != 0;
}

/// watchOS implementation of [BatteryPlatform].
class BatteryPlusWatchos extends BatteryPlatform {
  /// Test hook: set before first use to replace the FFI bindings.
  static BatteryPlusWatchosBindings? bindingsOverride;

  static BatteryPlusWatchosBindings? _bindings;

  static BatteryPlusWatchosBindings get _b =>
      bindingsOverride ?? (_bindings ??= BatteryPlusWatchosBindings());

  /// How often [onBatteryStateChanged] polls the native state. watchOS has
  /// no battery-change notification (unlike iOS's UIDevice notifications),
  /// so the stream is poll-based.
  static Duration pollInterval = const Duration(seconds: 2);

  /// Registers this implementation as the default `battery_plus` platform
  /// implementation on watchOS.
  static void registerWith() {
    BatteryPlatform.instance = BatteryPlusWatchos();
  }

  static BatteryState _mapState(int raw) {
    switch (raw) {
      case 1:
        return BatteryState.discharging;
      case 2:
        return BatteryState.charging;
      case 3:
        return BatteryState.full;
      default:
        return BatteryState.unknown;
    }
  }

  @override
  Future<int> get batteryLevel async {
    final int level = _b.level;
    if (level < 0) {
      throw Exception('battery_plus_watchos: battery level unavailable');
    }
    return level;
  }

  @override
  Future<bool> get isInBatterySaveMode async => _b.isLowPower;

  @override
  Future<BatteryState> get batteryState async => _mapState(_b.state);

  @override
  Stream<BatteryState> get onBatteryStateChanged {
    // watchOS exposes no battery-state notification; poll and emit on change.
    BatteryState? last;
    late final StreamController<BatteryState> controller;
    Timer? timer;

    void tick() {
      final BatteryState current = _mapState(_b.state);
      if (current != last) {
        last = current;
        controller.add(current);
      }
    }

    controller = StreamController<BatteryState>.broadcast(
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
