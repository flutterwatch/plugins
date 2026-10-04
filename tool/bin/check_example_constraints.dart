// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Fails when an example pubspec names `any`, or no constraint, under
/// `dependencies` or `dev_dependencies`.
///
/// Usage, from `tool/`: `dart run bin/check_example_constraints.dart
/// [--root <repository>]`.
library;

import 'dart:io';

import 'package:plugins_tool/src/example_constraints.dart';
import 'package:plugins_tool/src/repository.dart';

void main(List<String> arguments) {
  final Map<String, String> options = parseOptions(arguments, <String>{'root'});
  exitCode = runExampleConstraintCheck(
    options['root'] ?? repositoryRootOf(toolDirectory()),
    stdout,
  );
}
