// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// pana verifies a package's `repository` by cloning it and reading every file
// named pubspec.yaml. When more than one of them carries the package's name,
// "Provide a valid pubspec.yaml" scores 0/10. Fixtures that borrowed real
// package names cost six packages those points, so a fixture's package must
// never be named like a package in packages/.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  final String repo = p.normalize(p.join(Directory.current.path, '..'));

  test('each package name is in exactly one pubspec.yaml, its own', () {
    final List<String> packages =
        Directory(p.join(repo, 'packages'))
            .listSync()
            .whereType<Directory>()
            .map((Directory d) => p.basename(d.path))
            .toList()
          ..sort();
    expect(packages, isNotEmpty);

    // The files pana sees: everything git tracks, plus new files not ignored.
    final ProcessResult listed = Process.runSync('git', <String>[
      'ls-files',
      '--cached',
      '--others',
      '--exclude-standard',
    ], workingDirectory: repo);
    expect(listed.exitCode, 0, reason: '${listed.stderr}');
    final Map<String, List<String>> byName = <String, List<String>>{};
    for (final String path in (listed.stdout as String).split('\n')) {
      final File file = File(p.join(repo, path));
      if (p.basename(path) != 'pubspec.yaml' || !file.existsSync()) {
        continue;
      }
      final Object? doc = loadYaml(file.readAsStringSync());
      final Object? name = doc is YamlMap ? doc['name'] : null;
      if (name is String) {
        (byName[name] ??= <String>[]).add(path);
      }
    }

    for (final String package in packages) {
      expect(byName[package], <String>[
        'packages/$package/pubspec.yaml',
      ], reason: 'pubspec.yaml files named $package');
    }
  });
}
