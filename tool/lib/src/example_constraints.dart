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
///
/// A git dependency moves the same way unless its `ref` names one commit:
/// a branch, a tag or no `ref` at all can resolve to new code tomorrow. So a
/// git dependency must pin a full commit hash (sqflite's example takes
/// `sqflite_example_common`, which is not on pub.dev, from its repository).
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// A full git commit hash, as `ref` must name it.
final RegExp _commitHash = RegExp(r'^[0-9a-f]{40}$');

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

/// The git dependencies of the pubspec [contents] whose `ref` is not a full
/// commit hash, as `section: name`. A `git:` given as a plain URL has no
/// `ref`, so it is one of them.
List<String> unpinnedGitDependencies(String contents) {
  final Object? pubspec = loadYaml(contents);
  final List<String> found = <String>[];
  for (final String section in <String>['dependencies', 'dev_dependencies']) {
    final Object? dependencies = pubspec is YamlMap ? pubspec[section] : null;
    if (dependencies is! YamlMap) {
      continue;
    }
    dependencies.forEach((Object? name, Object? value) {
      if (value is! YamlMap || !value.containsKey('git')) {
        return;
      }
      final Object? git = value['git'];
      final Object? ref = git is YamlMap ? git['ref'] : null;
      if (ref is! String || !_commitHash.hasMatch(ref)) {
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
    final String contents = pubspec.readAsStringSync();
    final List<String> unconstrained = unconstrainedDependencies(contents);
    final List<String> unpinned = unpinnedGitDependencies(contents);
    if (unconstrained.isEmpty && unpinned.isEmpty) {
      out.writeln('ok   $package/example');
      continue;
    }
    failures++;
    out.writeln('FAIL $package/example');
    for (final String dependency in unconstrained) {
      out.writeln('       $dependency has no constraint; use ^x.y.z.');
    }
    for (final String dependency in unpinned) {
      out.writeln(
        '       $dependency is a git dependency without a pinned commit; '
        'set its ref to a full commit hash.',
      );
    }
  }
  if (failures > 0) {
    out.writeln(
      '$failures of $examples examples have a dependency that can move.',
    );
    return 1;
  }
  out.writeln('Example constraints: all $examples examples pass.');
  return 0;
}
