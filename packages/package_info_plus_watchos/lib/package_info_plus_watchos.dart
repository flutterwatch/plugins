// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `package_info_plus`, implemented over dart:ffi.
//
// Method-channel plugins are not supported on watchOS, so
// this package follows the FFI plugin model: `watchos/Classes/
// package_info_plus_watchos_ffi.m` exports one C symbol per Info.plist
// field, the CLI force-loads the compiled archive into the watch binary,
// and this class resolves the symbols via `DynamicLibrary.process()`.

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:package_info_plus_platform_interface/package_info_data.dart';
import 'package:package_info_plus_platform_interface/package_info_platform_interface.dart';

/// FFI bindings to the native package_info_plus_watchos C functions.
///
/// Overridable for tests via [PackageInfoWatchos.bindingsOverride]; the
/// [PackageInfoWatchosBindings.forTesting] constructor skips FFI
/// initialization so fakes work off-device.
class PackageInfoWatchosBindings {
  /// Creates bindings that look up native symbols in the current process.
  PackageInfoWatchosBindings() : _lib = DynamicLibrary.process();

  /// Constructor for fakes/mocks — skips FFI initialization.
  PackageInfoWatchosBindings.forTesting() : _lib = null;

  final DynamicLibrary? _lib;

  late final Pointer<Utf8> Function() _appName = _lib!
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'package_info_plus_watchos_app_name');

  late final Pointer<Utf8> Function() _packageName = _lib!
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'package_info_plus_watchos_package_name');

  late final Pointer<Utf8> Function() _version = _lib!
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'package_info_plus_watchos_version');

  late final Pointer<Utf8> Function() _buildNumber = _lib!
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'package_info_plus_watchos_build_number');

  late final Pointer<Utf8> Function() _installerStore = _lib!
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'package_info_plus_watchos_installer_store');

  late final Pointer<Utf8> Function() _installTime = _lib!
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'package_info_plus_watchos_install_time');

  late final Pointer<Utf8> Function() _updateTime = _lib!
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'package_info_plus_watchos_update_time');

  String _string(Pointer<Utf8> Function() f) {
    final Pointer<Utf8> p = f();
    // Native pointers are cached per-process and owned by the plugin.
    return p == nullptr ? '' : p.toDartString();
  }

  /// `CFBundleDisplayName` (or `CFBundleName`).
  String get appName => _string(_appName);

  /// `CFBundleIdentifier`.
  String get packageName => _string(_packageName);

  /// `CFBundleShortVersionString`.
  String get version => _string(_version);

  /// `CFBundleVersion`.
  String get buildNumber => _string(_buildNumber);

  /// The installer source (`com.apple.simulator` on the simulator).
  String get installerStore => _string(_installerStore);

  /// Install time in milliseconds since epoch, or `null` if unavailable.
  DateTime? get installTime => _dateFromMillis(_string(_installTime));

  /// Update time in milliseconds since epoch, or `null` if unavailable.
  DateTime? get updateTime => _dateFromMillis(_string(_updateTime));

  static DateTime? _dateFromMillis(String millis) {
    final int? value = int.tryParse(millis);
    return value == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(value);
  }
}

/// watchOS implementation of [PackageInfoPlatform].
class PackageInfoWatchos extends PackageInfoPlatform {
  /// Test hook: set before first use to replace the FFI bindings.
  static PackageInfoWatchosBindings? bindingsOverride;

  static PackageInfoWatchosBindings? _bindings;

  static PackageInfoWatchosBindings get _b =>
      bindingsOverride ?? (_bindings ??= PackageInfoWatchosBindings());

  /// Registers this implementation as the default `package_info_plus`
  /// platform implementation on watchOS.
  static void registerWith() {
    PackageInfoPlatform.instance = PackageInfoWatchos();
  }

  @override
  Future<PackageInfoData> getAll({String? baseUrl}) async {
    return PackageInfoData(
      appName: _b.appName,
      packageName: _b.packageName,
      version: _b.version,
      buildNumber: _b.buildNumber,
      // Code-signing details are not exposed to the app; iOS reports this
      // empty too.
      buildSignature: '',
      installerStore: _b.installerStore,
      installTime: _b.installTime,
      updateTime: _b.updateTime,
    );
  }
}
