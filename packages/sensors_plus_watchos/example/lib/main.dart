// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: SensorsDemo());
  }
}

class SensorsDemo extends StatefulWidget {
  const SensorsDemo({super.key});

  @override
  State<SensorsDemo> createState() => _SensorsDemoState();
}

class _SensorsDemoState extends State<SensorsDemo> {
  AccelerometerEvent? _accel;
  GyroscopeEvent? _gyro;
  final List<StreamSubscription<dynamic>> _subs = <StreamSubscription<dynamic>>[];

  @override
  void initState() {
    super.initState();
    _subs.add(accelerometerEventStream().listen(
        (AccelerometerEvent e) => setState(() => _accel = e)));
    _subs.add(gyroscopeEventStream().listen(
        (GyroscopeEvent e) => setState(() => _gyro = e)));
  }

  @override
  void dispose() {
    for (final StreamSubscription<dynamic> s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  String _fmt(double? x, double? y, double? z) => x == null
      ? '(waiting…)'
      : '${x.toStringAsFixed(2)}, ${y!.toStringAsFixed(2)}, '
          '${z!.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('accelerometer', style: TextStyle(fontSize: 11)),
            Text(_fmt(_accel?.x, _accel?.y, _accel?.z),
                style: const TextStyle(fontSize: 10)),
            const SizedBox(height: 8),
            const Text('gyroscope', style: TextStyle(fontSize: 11)),
            Text(_fmt(_gyro?.x, _gyro?.y, _gyro?.z),
                style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
