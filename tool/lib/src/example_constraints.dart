// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// The example constraint lint (spec 0006 criterion 14a, change plan M175).
///
/// An example that depends on `any` resolves whatever is newest on the day
/// it is built, so it can break without a change here (the
/// flutter_secure_storage example resolved an upstream major its official
/// test no longer compiles against). No example pubspec may name `any`, or
/// leave a constraint empty, under `dependencies` or `dev_dependencies`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The dependencies of the pubspec [contents] that name `any` or no
/// constraint, as `section: name`.
List<String> unconstrainedDependencies(String contents) {
  final Object? pubspec = loadYaml(contents);
  final List<String> found = <String>[];
  for (final String section in <String>['dependencies', 'dev_dependencies']) {
    final Object? dependencies = pubspec is YamlMap ? pubspec[section] : null;
    if (dependencies is! YamlMap) {
      continue;
    }
    dependencies.forEach((Object? name, Object? value) {
      if (value == null || (value is String && value.trim() == 'any')) {
        found.add('$section: $name');
      }
    });
  }
  return found;
}

/// Checks `packages/*/example/pubspec.yaml` of the repository at [root],
/// writes the report to [out] and returns the exit code.
int runExampleConstraintCheck(String root, StringSink out) {
  final List<String> packages =
      Directory(p.join(root, 'packages'))
          .listSync()
          .whereType<Directory>()
          .map((Directory d) => p.basename(d.path))
          .toList()
        ..sort();
  int failures = 0;
  int examples = 0;
  for (final String package in packages) {
    final File pubspec = File(
      p.join(root, 'packages', package, 'example', 'pubspec.yaml'),
    );
    if (!pubspec.existsSync()) {
      continue;
    }
    examples++;
    final List<String> found = unconstrainedDependencies(
      pubspec.readAsStringSync(),
    );
    if (found.isEmpty) {
      out.writeln('ok   $package/example');
      continue;
    }
    failures++;
    out.writeln('FAIL $package/example');
    for (final String dependency in found) {
      out.writeln('       $dependency has no constraint; use ^x.y.z.');
    }
  }
  if (failures > 0) {
    out.writeln('$failures of $examples examples depend on "any".');
    return 1;
  }
  out.writeln('Example constraints: all $examples examples pass.');
  return 0;
}
