// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Prints the macros each package declares under
/// `flutter.plugin.platforms.watchos.defines`, one line per package that
/// declares any: `defines <package directory> <MACRO>…`, in the order
/// declared. Fails, naming the package and each problem, on a declaration
/// the CLI would refuse. `check_native_sources.sh` runs it.
///
/// Usage, from `tool/`: `dart run bin/plugin_defines.dart
/// [--root <repository>]`.
library;

import 'dart:io';

import 'package:plugins_tool/src/plugin_defines.dart';
import 'package:plugins_tool/src/repository.dart';

void main(List<String> arguments) {
  final Map<String, String> options = parseOptions(arguments, <String>{'root'});
  exitCode = runPluginDefines(
    options['root'] ?? repositoryRootOf(toolDirectory()),
    stdout,
  );
}
