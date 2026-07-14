// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: GeolocatorDemo());
  }
}

class GeolocatorDemo extends StatefulWidget {
  const GeolocatorDemo({super.key});

  @override
  State<GeolocatorDemo> createState() => _GeolocatorDemoState();
}

class _GeolocatorDemoState extends State<GeolocatorDemo> {
  String _status = 'tap to locate';

  Future<void> _run() async {
    setState(() => _status = 'locating…');
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _status = 'permission: $permission');
        return;
      }
      final Position pos = await Geolocator.getCurrentPosition();
      setState(() => _status =
          '${pos.latitude.toStringAsFixed(4)}, '
          '${pos.longitude.toStringAsFixed(4)}');
    } catch (e) {
      setState(() => _status = 'error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(_status, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _run, child: const Text('Locate')),
          ],
        ),
      ),
    );
  }
}
