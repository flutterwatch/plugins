import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: PathList());
  }
}

class PathList extends StatefulWidget {
  const PathList({super.key});

  @override
  State<PathList> createState() => _PathListState();
}

class _PathListState extends State<PathList> {
  final Map<String, String> _paths = <String, String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Future<void> put(String label, Future<Object?> Function() f) async {
      try {
        final Object? dir = await f();
        _paths[label] = dir?.toString() ?? '(null)';
      } catch (e) {
        _paths[label] = 'unsupported';
      }
      if (mounted) {
        setState(() {});
      }
    }

    await put('temp', getTemporaryDirectory);
    await put('support', getApplicationSupportDirectory);
    await put('library', getLibraryDirectory);
    await put('documents', getApplicationDocumentsDirectory);
    await put('cache', getApplicationCacheDirectory);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        children: <Widget>[
          for (final MapEntry<String, String> e in _paths.entries)
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
