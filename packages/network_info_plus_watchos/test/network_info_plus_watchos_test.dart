// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Host-side unit tests. The native getifaddrs backend is replaced with a fake
// so the platform-interface mapping is verified off-device; the real lookups
// are exercised by the example's integration_test.

import 'package:flutter_test/flutter_test.dart';
import 'package:network_info_plus_platform_interface/network_info_plus_platform_interface.dart';
import 'package:network_info_plus_watchos/network_info_plus_watchos.dart';

class _FakeBackend implements NetworkInfoPlusWatchosBackend {
  @override
  String? wifiIp() => '192.168.1.42';
  @override
  String? wifiIpv6() => 'fd00::42';
  @override
  String? wifiSubmask() => '255.255.255.0';
  @override
  String? wifiBroadcast() => '192.168.1.255';
}

void main() {
  late NetworkInfoPlusWatchos info;

  setUp(() {
    NetworkInfoPlusWatchos.backendOverride = _FakeBackend();
    info = NetworkInfoPlusWatchos();
  });

  tearDown(() => NetworkInfoPlusWatchos.backendOverride = null);

  test('registerWith installs the watchOS implementation', () {
    NetworkInfoPlusWatchos.registerWith();
    expect(NetworkInfoPlatform.instance, isA<NetworkInfoPlusWatchos>());
  });

  test('IP getters forward the native values', () async {
    expect(await info.getWifiIP(), '192.168.1.42');
    expect(await info.getWifiIPv6(), 'fd00::42');
    expect(await info.getWifiSubmask(), '255.255.255.0');
    expect(await info.getWifiBroadcast(), '192.168.1.255');
  });

  test('SSID and BSSID are unavailable on watchOS (null, not a throw)',
      () async {
    expect(await info.getWifiName(), isNull);
    expect(await info.getWifiBSSID(), isNull);
  });

  test('getWifiGatewayIP is unimplemented on watchOS', () {
    expect(() => info.getWifiGatewayIP(), throwsA(isA<UnimplementedError>()));
  });
}
