// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `network_info_plus`, implemented over dart:ffi.
//
// Method-channel plugins are not supported on watchOS, so this package follows
// the FFI plugin model: `watchos/Classes/network_info_plus_watchos_ffi.m`
// reads the interface addresses with `getifaddrs` and exports them as C
// symbols, which [_FfiBackend] resolves via `DynamicLibrary.process()`.
//
// Wi-Fi SSID and BSSID are not available on watchOS (no CaptiveNetwork /
// NEHotspotNetwork), so [NetworkInfoPlusWatchos.getWifiName] and
// [NetworkInfoPlusWatchos.getWifiBSSID] return null.

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:network_info_plus_platform_interface/network_info_plus_platform_interface.dart';

/// The native address lookups, behind an interface so unit tests can swap in a
/// fake off-device (see [NetworkInfoPlusWatchos.backendOverride]).
abstract class NetworkInfoPlusWatchosBackend {
  /// The active interface's IPv4 address, or null.
  String? wifiIp();

  /// The active interface's IPv6 address, or null.
  String? wifiIpv6();

  /// The active interface's IPv4 subnet mask, or null.
  String? wifiSubmask();

  /// The active interface's IPv4 broadcast address, or null.
  String? wifiBroadcast();
}

/// watchOS implementation of [NetworkInfoPlatform].
base class NetworkInfoPlusWatchos extends NetworkInfoPlatform {
  /// Test hook: set before first use to replace the native backend with a fake.
  static NetworkInfoPlusWatchosBackend? backendOverride;

  static NetworkInfoPlusWatchosBackend? _backend;

  static NetworkInfoPlusWatchosBackend get _b =>
      backendOverride ?? (_backend ??= _FfiBackend());

  /// Registers this implementation as the default `network_info_plus`
  /// platform implementation on watchOS.
  static void registerWith() {
    NetworkInfoPlatform.instance = NetworkInfoPlusWatchos();
  }

  // watchOS has no CaptiveNetwork/NEHotspotNetwork, so the Wi-Fi identity
  // getters resolve to null rather than throwing UnimplementedError.
  @override
  Future<String?> getWifiName() async => null;

  @override
  Future<String?> getWifiBSSID() async => null;

  @override
  Future<String?> getWifiIP() async => _b.wifiIp();

  @override
  Future<String?> getWifiIPv6() async => _b.wifiIpv6();

  @override
  Future<String?> getWifiSubmask() async => _b.wifiSubmask();

  @override
  Future<String?> getWifiBroadcast() async => _b.wifiBroadcast();

  // getWifiGatewayIP falls through to the base UnimplementedError: reading the
  // default route needs sysctl/PF_ROUTE plumbing with no watchOS story, and
  // the upstream iOS implementation does not provide it either.
}

typedef _StringNative = Pointer<Utf8> Function();
typedef _StringDart = Pointer<Utf8> Function();
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _FreeDart = void Function(Pointer<Utf8>);

/// Resolves the getifaddrs C symbols and copies their results into Dart.
class _FfiBackend implements NetworkInfoPlusWatchosBackend {
  _FfiBackend() : _lib = DynamicLibrary.process();

  final DynamicLibrary _lib;

  late final _StringDart _ip = _lib.lookupFunction<_StringNative, _StringDart>(
      'network_info_plus_watchos_wifi_ip');
  late final _StringDart _ipv6 =
      _lib.lookupFunction<_StringNative, _StringDart>(
          'network_info_plus_watchos_wifi_ipv6');
  late final _StringDart _submask =
      _lib.lookupFunction<_StringNative, _StringDart>(
          'network_info_plus_watchos_wifi_submask');
  late final _StringDart _broadcast =
      _lib.lookupFunction<_StringNative, _StringDart>(
          'network_info_plus_watchos_wifi_broadcast');
  late final _FreeDart _free = _lib.lookupFunction<_FreeNative, _FreeDart>(
      'network_info_plus_watchos_free');

  /// Calls a native getter, copies the string, and releases the native buffer.
  String? _take(_StringDart f) {
    final Pointer<Utf8> p = f();
    if (p == nullptr) {
      return null;
    }
    final String s = p.toDartString();
    _free(p);
    return s;
  }

  @override
  String? wifiIp() => _take(_ip);

  @override
  String? wifiIpv6() => _take(_ipv6);

  @override
  String? wifiSubmask() => _take(_submask);

  @override
  String? wifiBroadcast() => _take(_broadcast);
}
