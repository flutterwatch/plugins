// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Runs on the watch simulator against the real getifaddrs-backed FFI
// implementation.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:network_info_plus_platform_interface/network_info_plus_platform_interface.dart';
import 'package:network_info_plus_watchos/network_info_plus_watchos.dart';

/// Loose IPv4 dotted-quad check (0-255 per octet not enforced — enough to
/// confirm the native formatter produced an address rather than garbage).
final RegExp _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final NetworkInfo info = NetworkInfo();

  testWidgets('watchOS implementation is registered', (WidgetTester _) async {
    expect(NetworkInfoPlatform.instance, isA<NetworkInfoPlusWatchos>());
  });

  testWidgets('getWifiIP returns a well-formed address or null',
      (WidgetTester _) async {
    // The simulator shares the host network; an address may or may not be
    // present, but when present it must be a valid dotted quad.
    final String? ip = await info.getWifiIP();
    if (ip != null) {
      expect(_ipv4.hasMatch(ip), isTrue, reason: 'got "$ip"');
    }
  });

  testWidgets('getWifiSubmask returns a well-formed mask or null',
      (WidgetTester _) async {
    final String? mask = await info.getWifiSubmask();
    if (mask != null) {
      expect(_ipv4.hasMatch(mask), isTrue, reason: 'got "$mask"');
    }
  });

  testWidgets('IPv6 getter does not throw', (WidgetTester _) async {
    // Just exercises the native path; the value is environment-dependent.
    await info.getWifiIPv6();
  });

  testWidgets('SSID and BSSID are null on watchOS (not a throw)',
      (WidgetTester _) async {
    expect(await info.getWifiName(), isNull);
    expect(await info.getWifiBSSID(), isNull);
  });
}
