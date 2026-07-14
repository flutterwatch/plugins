// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:battery_plus_platform_interface/battery_plus_platform_interface.dart';
import 'package:battery_plus_watchos/battery_plus_watchos.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mutable fake bindings — no FFI.
class _FakeBindings extends BatteryPlusWatchosBindings {
  _FakeBindings() : super.forTesting();

  int levelValue = 88;
  int stateValue = 2; // charging
  bool lowPowerValue = false;

  @override
  int get level => levelValue;
  @override
  int get state => stateValue;
  @override
  bool get isLowPower => lowPowerValue;
}

void main() {
  late _FakeBindings fake;

  setUp(() {
    fake = _FakeBindings();
    BatteryPlusWatchos.bindingsOverride = fake;
    BatteryPlusWatchos.pollInterval = const Duration(milliseconds: 10);
  });

  test('registerWith installs the watchOS implementation', () {
    BatteryPlusWatchos.registerWith();
    expect(BatteryPlatform.instance, isA<BatteryPlusWatchos>());
  });

  test('batteryLevel returns the native percentage', () async {
    expect(await BatteryPlusWatchos().batteryLevel, 88);
  });

  test('batteryLevel throws when the native reading is unavailable', () async {
    fake.levelValue = -1;
    expect(BatteryPlusWatchos().batteryLevel, throwsA(isA<Exception>()));
  });

  test('batteryState maps WKInterfaceDeviceBatteryState raw values', () async {
    final battery = BatteryPlusWatchos();
    fake.stateValue = 1;
    expect(await battery.batteryState, BatteryState.discharging);
    fake.stateValue = 2;
    expect(await battery.batteryState, BatteryState.charging);
    fake.stateValue = 3;
    expect(await battery.batteryState, BatteryState.full);
    fake.stateValue = 0;
    expect(await battery.batteryState, BatteryState.unknown);
  });

  test('isInBatterySaveMode reflects Low Power Mode', () async {
    fake.lowPowerValue = true;
    expect(await BatteryPlusWatchos().isInBatterySaveMode, isTrue);
  });

  test('onBatteryStateChanged emits the current state, then changes', () async {
    final battery = BatteryPlusWatchos();
    fake.stateValue = 2; // charging
    final Stream<BatteryState> stream = battery.onBatteryStateChanged;
    final Future<List<BatteryState>> firstTwo = stream.take(2).toList();
    // Flip to discharging so a second, distinct event is emitted.
    await Future<void>.delayed(const Duration(milliseconds: 25));
    fake.stateValue = 1;
    expect(await firstTwo, <BatteryState>[BatteryState.charging, BatteryState.discharging]);
  });
}
