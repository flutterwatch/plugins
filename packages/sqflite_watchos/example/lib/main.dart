// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// sqflite's own example app is built on sqflite_example_common, which is not
// published, so this watch-sized demo stands in for it. The official
// integration test in integration_test/ is upstream's, unchanged.

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

void main() => runApp(const SqfliteExampleApp());

/// Laps saved to a SQLite database on the watch.
class SqfliteExampleApp extends StatelessWidget {
  /// The example app.
  const SqfliteExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: const LapsPage(),
      );
}

/// Add, list and clear laps.
class LapsPage extends StatefulWidget {
  /// The one page.
  const LapsPage({super.key});

  @override
  State<LapsPage> createState() => _LapsPageState();
}

class _LapsPageState extends State<LapsPage> {
  Database? _db;
  List<Map<String, Object?>> _laps = const <Map<String, Object?>>[];
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _db?.close();
    super.dispose();
  }

  Future<void> _open() async {
    try {
      _db = await openDatabase(
        'laps.db',
        version: 1,
        onCreate: (Database db, int version) => db.execute(
            'CREATE TABLE lap (id INTEGER PRIMARY KEY, at INTEGER NOT NULL)'),
      );
      await _reload();
    } on DatabaseException catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _reload() async {
    final List<Map<String, Object?>> laps =
        await _db!.query('lap', orderBy: 'id DESC');
    setState(() => _laps = laps);
  }

  Future<void> _add() async {
    await _db!.insert('lap', <String, Object?>{
      'at': DateTime.now().millisecondsSinceEpoch,
    });
    await _reload();
  }

  Future<void> _clear() async {
    await _db!.delete('lap');
    await _reload();
  }

  String _time(Object? millis) {
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(millis! as int);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 28, 12, 24),
          children: <Widget>[
            Text('${_laps.length} laps',
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
            FilledButton(
              onPressed: _db == null ? null : _add,
              child: const Text('Add lap'),
            ),
            for (final Map<String, Object?> lap in _laps.take(5))
              Text('#${lap['id']}  ${_time(lap['at'])}'),
            if (_laps.isNotEmpty)
              TextButton(onPressed: _clear, child: const Text('Clear')),
          ],
        ),
      );
}
