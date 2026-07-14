// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: LocalAuthDemo());
  }
}

class LocalAuthDemo extends StatefulWidget {
  const LocalAuthDemo({super.key});

  @override
  State<LocalAuthDemo> createState() => _LocalAuthDemoState();
}

class _LocalAuthDemoState extends State<LocalAuthDemo> {
  final LocalAuthentication _auth = LocalAuthentication();
  String _status = 'tap to authenticate';

  Future<void> _run() async {
    setState(() => _status = 'authenticating…');
    try {
      final bool supported = await _auth.isDeviceSupported();
      if (!supported) {
        setState(() => _status = 'device not supported (no passcode set)');
        return;
      }
      final bool ok = await _auth.authenticate(
        localizedReason: 'Confirm it is you',
      );
      setState(() => _status = ok ? 'authenticated ✅' : 'failed / cancelled');
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
            ElevatedButton(onPressed: _run, child: const Text('Unlock')),
          ],
        ),
      ),
    );
  }
}
