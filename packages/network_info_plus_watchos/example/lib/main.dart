// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: NetworkInfoDemo());
  }
}

class NetworkInfoDemo extends StatefulWidget {
  const NetworkInfoDemo({super.key});

  @override
  State<NetworkInfoDemo> createState() => _NetworkInfoDemoState();
}

class _NetworkInfoDemoState extends State<NetworkInfoDemo> {
  final NetworkInfo _info = NetworkInfo();
  final Map<String, String> _values = <String, String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Future<void> put(String label, Future<String?> Function() f) async {
      try {
        _values[label] = (await f()) ?? '(null)';
      } catch (_) {
        _values[label] = 'unsupported';
      }
      if (mounted) {
        setState(() {});
      }
    }

    await put('IPv4', _info.getWifiIP);
    await put('IPv6', _info.getWifiIPv6);
    await put('submask', _info.getWifiSubmask);
    await put('broadcast', _info.getWifiBroadcast);
    await put('SSID', _info.getWifiName);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        children: <Widget>[
          for (final MapEntry<String, String> e in _values.entries)
            ListTile(
              dense: true,
              title: Text(e.key, style: const TextStyle(fontSize: 12)),
              subtitle: Text(e.value, style: const TextStyle(fontSize: 9)),
            ),
        ],
      ),
    );
  }
}
