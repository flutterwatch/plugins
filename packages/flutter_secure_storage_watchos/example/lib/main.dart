// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: SecureStorageDemo());
  }
}

class SecureStorageDemo extends StatefulWidget {
  const SecureStorageDemo({super.key});

  @override
  State<SecureStorageDemo> createState() => _SecureStorageDemoState();
}

class _SecureStorageDemoState extends State<SecureStorageDemo> {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  String _status = 'tap to run';

  Future<void> _run() async {
    setState(() => _status = 'writing…');
    try {
      await _storage.write(key: 'token', value: 'watch-secret');
      final String? value = await _storage.read(key: 'token');
      final bool has = await _storage.containsKey(key: 'token');
      setState(() => _status = 'read=$value contains=$has');
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
            ElevatedButton(onPressed: _run, child: const Text('Run')),
          ],
        ),
      ),
    );
  }
}
