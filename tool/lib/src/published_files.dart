// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// The files `pub publish` would put in a package's archive, read from a
/// commit or from the working tree.
///
/// pub takes every file under the package folder except the ones git would
/// ignore, reading the repository's `.gitignore` files from the root down,
/// and it ignores hidden files and folders as if a root rule said `.*`. A
/// deeper `.gitignore` can take a hidden file back (the example runners'
/// `watchos/Flutter/.gitignore` says `!.gitignore`, and pub publishes it).
/// Here git decides, with that `.*` rule as its lowest-ranked exclude file.
/// A package with a `.pubignore` is refused: pub reads that file instead of
/// `.gitignore`, which this model does not follow.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'repository.dart';

/// The paths among [paths] that git ignores in the checkout at [root], with
/// pub's hidden-file rule added below every `.gitignore`.
Set<String> _ignored(String root, List<String> paths) {
  if (paths.isEmpty) {
    return <String>{};
  }
  final Directory scratch = Directory.systemTemp.createTempSync(
    'plugins_tool_ignore_',
  );
  try {
    final String exclude = p.join(scratch.path, 'exclude');
    final String input = p.join(scratch.path, 'paths');
    File(exclude).writeAsStringSync('.*\n');
    File(input).writeAsStringSync('${paths.join('\n')}\n');
    final ProcessResult result = Process.runSync('bash', <String>[
      '-c',
      r'git -c core.quotePath=false -c core.excludesFile="$1" '
          r'check-ignore --no-index --stdin < "$2"',
      'check-ignore',
      exclude,
      input,
    ], workingDirectory: root);
    // check-ignore exits 1 when it ignores none of the paths.
    if (result.exitCode > 1) {
      throw ProcessException(
        'git',
        <String>['check-ignore'],
        '${result.stderr}'.trim(),
        result.exitCode,
      );
    }
    return (result.stdout as String)
        .split('\n')
        .where((String line) => line.isNotEmpty)
        .toSet();
  } finally {
    scratch.deleteSync(recursive: true);
  }
}

void _refusePubignore(String package, Iterable<String> paths) {
  final String marker = p.posix.join('packages', package, '');
  for (final String path in paths) {
    if (path.startsWith(marker) && p.posix.basename(path) == '.pubignore') {
      throw StateError(
        '$path: pub reads .pubignore instead of .gitignore, which this check '
        'does not model.',
      );
    }
  }
}

/// The publishable files of `packages/[package]` at [commit] of the
/// repository at [root], as repository-relative paths mapped to git blob
/// ids. The ignore rules are the ones of that commit.
Map<String, String> publishedFilesAt(
  String root,
  String commit,
  String package,
) {
  final String folder = 'packages/$package';
  final Map<String, String> blobs = <String, String>{};
  for (final String line in git(root, <String>[
    'ls-tree',
    '-r',
    '--full-tree',
    commit,
    '--',
    folder,
  ]).split('\n')) {
    // "<mode> <type> <id>\t<path>"
    final int tab = line.indexOf('\t');
    if (tab < 0) {
      continue;
    }
    final List<String> fields = line.substring(0, tab).split(' ');
    if (fields.length == 3 && fields[1] == 'blob') {
      blobs[line.substring(tab + 1)] = fields[2];
    }
  }
  _refusePubignore(package, blobs.keys);

  // The commit's .gitignore files that can apply to the package: the ones
  // in the root, in packages/ and inside the package. Git reads them from a
  // scratch checkout of just those files.
  final List<String> ignoreFiles =
      git(root, <String>[
        'ls-tree',
        '-r',
        '--name-only',
        '--full-tree',
        commit,
      ]).split('\n').where((String path) {
        if (p.posix.basename(path) != '.gitignore') {
          return false;
        }
        final String directory = p.posix.dirname(path);
        return directory == '.' ||
            directory == 'packages' ||
            path.startsWith('$folder/');
      }).toList();
  final Directory scratch = Directory.systemTemp.createTempSync(
    'plugins_tool_rules_',
  );
  try {
    git(scratch.path, <String>['init', '--quiet']);
    for (final String path in ignoreFiles) {
      final File file = File(p.join(scratch.path, path));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(git(root, <String>['show', '$commit:$path']));
    }
    final Set<String> ignored = _ignored(scratch.path, blobs.keys.toList());
    blobs.removeWhere((String path, String blob) => ignored.contains(path));
  } finally {
    scratch.deleteSync(recursive: true);
  }
  return blobs;
}

/// The publishable files of `packages/[package]` in the working tree of the
/// repository at [root], as repository-relative paths mapped to the git blob
/// ids of their current content.
Map<String, String> publishedFilesInWorkingTree(String root, String package) {
  final String folder = 'packages/$package';
  final List<String> paths =
      git(root, <String>[
            'ls-files',
            '--cached',
            '--others',
            '--exclude-per-directory=.gitignore',
            '--',
            folder,
          ])
          .split('\n')
          .where((String path) => path.isNotEmpty)
          .where((String path) => File(p.join(root, path)).existsSync())
          .toSet()
          .toList()
        ..sort();
  _refusePubignore(package, paths);
  final Set<String> ignored = _ignored(root, paths);
  final List<String> published = paths
      .where((String path) => !ignored.contains(path))
      .toList();
  if (published.isEmpty) {
    return <String, String>{};
  }
  final Directory scratch = Directory.systemTemp.createTempSync(
    'plugins_tool_hash_',
  );
  try {
    final String input = p.join(scratch.path, 'paths');
    File(input).writeAsStringSync('${published.join('\n')}\n');
    final ProcessResult result = Process.runSync('bash', <String>[
      '-c',
      r'git hash-object --stdin-paths < "$1"',
      'hash-object',
      input,
    ], workingDirectory: root);
    if (result.exitCode != 0) {
      throw ProcessException(
        'git',
        <String>['hash-object'],
        '${result.stderr}'.trim(),
        result.exitCode,
      );
    }
    final List<String> ids = (result.stdout as String)
        .split('\n')
        .where((String line) => line.isNotEmpty)
        .toList();
    return <String, String>{
      for (int i = 0; i < published.length; i++) published[i]: ids[i],
    };
  } finally {
    scratch.deleteSync(recursive: true);
  }
}

/// The paths whose presence or content differs between [before] and
/// [after], sorted.
List<String> changedPaths(
  Map<String, String> before,
  Map<String, String> after,
) {
  return <String>{
    for (final String path in before.keys)
      if (after[path] != before[path]) path,
    for (final String path in after.keys)
      if (!before.containsKey(path)) path,
  }.toList()..sort();
}
