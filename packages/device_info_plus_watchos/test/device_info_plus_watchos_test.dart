// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:device_info_plus_platform_interface/device_info_plus_platform_interface.dart';
import 'package:device_info_plus_watchos/device_info_plus_watchos.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake bindings — no FFI, a fixed watch-shaped JSON blob.
class _FakeBindings extends DeviceInfoWatchosBindings {
  _FakeBindings() : super.forTesting();

  @override
  String get infoJson => jsonEncode(<String, dynamic>{
        'name': 'Apple Watch',
        'systemName': 'Watch OS',
        'systemVersion': '11.0',
        'model': 'Apple Watch',
        'modelName': 'Watch7,1',
        'localizedModel': 'Apple Watch',
        'identifierForVendor': 'A1B2C3D4-0000-0000-0000-000000000000',
        'isPhysicalDevice': true,
        'physicalRamSize': 1024,
        'availableRamSize': 1024,
        'freeDiskSize': 2048,
        'totalDiskSize': 4096,
        'isiOSAppOnMac': false,
        'isiOSAppOnVision': false,
        'utsname': <String, dynamic>{
          'sysname': 'Darwin',
          'nodename': 'Apple-Watch',
          'release': '24.0.0',
          'version': 'Darwin Kernel',
          'machine': 'Watch7,1',
        },
      });
}

void main() {
  setUp(() {
    DeviceInfoWatchos.bindingsOverride = _FakeBindings();
  });

  test('registerWith installs the watchOS implementation', () {
    DeviceInfoWatchos.registerWith();
    expect(DeviceInfoPlatform.instance, isA<DeviceInfoWatchos>());
  });

  test('deviceInfo returns a map shaped for IosDeviceInfo.fromMap', () async {
    final data = (await DeviceInfoWatchos().deviceInfo()).data;
    expect(data['model'], 'Apple Watch');
    expect(data['systemVersion'], '11.0');
    expect(data['isPhysicalDevice'], isTrue);
    // Scalars must be the right Dart types (fromMap assigns to non-nullable
    // int/bool fields).
    expect(data['physicalRamSize'], isA<int>());
    expect(data['totalDiskSize'], isA<int>());
    expect((data['utsname'] as Map)['machine'], 'Watch7,1');
  });
}
