// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Helpers to read a git repository and this tool's own files.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Runs `git` with [arguments] in [root] and returns its standard output.
/// Paths in the output are not quoted, even when they hold non-ASCII
/// characters.
///
/// Throws a [ProcessException] when git fails.
String git(String root, List<String> arguments) {
  final ProcessResult result = Process.runSync('git', <String>[
    '-c',
    'core.quotePath=false',
    ...arguments,
  ], workingDirectory: root);
  if (result.exitCode != 0) {
    throw ProcessException(
      'git',
      arguments,
      '${result.stderr}'.trim(),
      result.exitCode,
    );
  }
  return result.stdout as String;
}

/// The files git shows in [root], relative to it: tracked files, and
/// untracked files that are not ignored. Only files that exist are listed.
List<String> repositoryFiles(String root, [List<String> pathspecs = const []]) {
  return git(root, <String>[
        'ls-files',
        '--cached',
        '--others',
        '--exclude-standard',
        '--',
        ...pathspecs,
      ])
      .split('\n')
      .where((String path) => path.isNotEmpty)
      .where((String path) => File(p.join(root, path)).existsSync())
      .toSet()
      .toList()
    ..sort();
}

/// The root of the git repository that holds [directory].
String repositoryRootOf(String directory) {
  return git(directory, <String>['rev-parse', '--show-toplevel']).trim();
}

/// The directory of this tool package (the one holding its `pubspec.yaml`),
/// found from the running script, which is in its `bin/` or `test/`.
String toolDirectory() {
  String directory = p.dirname(p.fromUri(Platform.script));
  while (!File(p.join(directory, 'pubspec.yaml')).existsSync()) {
    final String parent = p.dirname(directory);
    if (parent == directory) {
      return Directory.current.path;
    }
    directory = parent;
  }
  return directory;
}

/// Parses `--name value` pairs from [arguments] into a map.
///
/// Throws a [FormatException] for an unknown option, or for one without a
/// value.
Map<String, String> parseOptions(List<String> arguments, Set<String> known) {
  final Map<String, String> options = <String, String>{};
  for (int i = 0; i < arguments.length; i++) {
    final String argument = arguments[i];
    if (!argument.startsWith('--') || !known.contains(argument.substring(2))) {
      throw FormatException('Unknown argument: $argument');
    }
    if (i + 1 >= arguments.length) {
      throw FormatException('$argument needs a value');
    }
    options[argument.substring(2)] = arguments[++i];
  }
  return options;
}
