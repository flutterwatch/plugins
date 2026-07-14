// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `device_info_plus`, implemented over dart:ffi.
//
// Method-channel plugins are not supported on watchOS, so
// this package follows the FFI plugin model: `watchos/Classes/
// device_info_plus_watchos_ffi.m` exports a single C function returning a
// JSON blob of device fields, the CLI force-loads the compiled archive into
// the watch binary, and this class resolves the symbol via
// `DynamicLibrary.process()`.
//
// device_info_plus reads the watch through its iOS code path (watchOS
// reports `Platform.isIOS == true`), so the JSON is shaped for
// `IosDeviceInfo.fromMap` and returned as a `BaseDeviceInfo`.

import 'dart:convert';
import 'dart:ffi';

import 'package:device_info_plus_platform_interface/device_info_plus_platform_interface.dart';
import 'package:ffi/ffi.dart';

/// FFI bindings to the native device_info_plus_watchos C function.
///
/// Overridable for tests via [DeviceInfoWatchos.bindingsOverride]; the
/// [DeviceInfoWatchosBindings.forTesting] constructor skips FFI
/// initialization so fakes work off-device.
class DeviceInfoWatchosBindings {
  /// Creates bindings that look up native symbols in the current process.
  DeviceInfoWatchosBindings() : _lib = DynamicLibrary.process();

  /// Constructor for fakes/mocks — skips FFI initialization.
  DeviceInfoWatchosBindings.forTesting() : _lib = null;

  final DynamicLibrary? _lib;

  late final Pointer<Utf8> Function() _infoJson = _lib!
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'device_info_plus_watchos_info_json');

  /// The device-info JSON string produced by the native side.
  String get infoJson {
    final Pointer<Utf8> p = _infoJson();
    // Pointer is cached per-process and owned by the plugin.
    return p == nullptr ? '{}' : p.toDartString();
  }
}

/// watchOS implementation of [DeviceInfoPlatform].
class DeviceInfoWatchos extends DeviceInfoPlatform {
  /// Test hook: set before first use to replace the FFI bindings.
  static DeviceInfoWatchosBindings? bindingsOverride;

  static DeviceInfoWatchosBindings? _bindings;

  static DeviceInfoWatchosBindings get _b =>
      bindingsOverride ?? (_bindings ??= DeviceInfoWatchosBindings());

  /// Registers this implementation as the default `device_info_plus`
  /// platform implementation on watchOS.
  static void registerWith() {
    DeviceInfoPlatform.instance = DeviceInfoWatchos();
  }

  @override
  Future<BaseDeviceInfo> deviceInfo() async {
    final Map<String, dynamic> data =
        (jsonDecode(_b.infoJson) as Map<String, dynamic>);
    // `IosDeviceInfo.fromMap` (which device_info_plus applies because the
    // watch reports as iOS) reads this map directly.
    return BaseDeviceInfo(data);
  }
}
