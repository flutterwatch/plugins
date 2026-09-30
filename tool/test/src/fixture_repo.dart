// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;

/// Runs git in [directory] and throws when it fails.
String runGit(String directory, List<String> arguments) {
  final ProcessResult result = Process.runSync(
    'git',
    arguments,
    workingDirectory: directory,
  );
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')}: ${result.stderr}');
  }
  return result.stdout as String;
}

/// Copies [from] into [to], creating directories as needed.
void copyTree(String from, String to) {
  for (final FileSystemEntity entity in Directory(
    from,
  ).listSync(recursive: true)) {
    if (entity is! File) {
      continue;
    }
    final String target = p.join(to, p.relative(entity.path, from: from));
    Directory(p.dirname(target)).createSync(recursive: true);
    entity.copySync(target);
  }
}

/// Creates an empty git repository in a new temporary directory.
String createGitRepository() {
  final String root = Directory.systemTemp
      .createTempSync('plugins_tool_')
      .resolveSymbolicLinksSync();
  runGit(root, <String>['init', '--quiet', '--initial-branch=main']);
  runGit(root, <String>['config', 'user.name', 'Fixture']);
  runGit(root, <String>['config', 'user.email', 'fixture@example.com']);
  runGit(root, <String>['config', 'commit.gpgsign', 'false']);
  return root;
}

/// Stages every file in [root] and commits it; returns the commit's sha.
String commitAll(String root, String message) {
  runGit(root, <String>['add', '--all']);
  runGit(root, <String>['commit', '--quiet', '--allow-empty', '-m', message]);
  return runGit(root, <String>['rev-parse', 'HEAD']).trim();
}

/// A checked-in fixture: a directory with `repo/` (committed), optionally
/// `untracked/` (copied in after the commit), entry lists and `expect`.
class Fixture {
  /// Reads the fixture in [directory].
  Fixture(this.directory);

  /// The fixture's directory.
  final String directory;

  /// The fixture's name, its directory's base name.
  String get name => p.basename(directory);

  /// The exit code the check must give.
  int get expectedExitCode => int.parse(_expectLines.first);

  /// Text the check's output must contain.
  List<String> get expectedOutput =>
      _expectLines.skip(1).where((String l) => l.isNotEmpty).toList();

  List<String> get _expectLines =>
      File(p.join(directory, 'expect')).readAsLinesSync();

  /// The fixture's allow-list, or an empty file.
  String get allowList => _listOrEmpty('allow.txt');

  /// The fixture's pending list, or an empty file.
  String get pendingList => _listOrEmpty('pending.txt');

  String _listOrEmpty(String name) {
    final File file = File(p.join(directory, name));
    if (file.existsSync()) {
      return file.path;
    }
    final String empty = p.join(
      Directory.systemTemp.createTempSync('plugins_tool_empty_').path,
      name,
    );
    File(empty).writeAsStringSync('');
    return empty;
  }

  /// Builds the fixture's git repository and returns its root.
  String createRepository() {
    final String root = createGitRepository();
    copyTree(p.join(directory, 'repo'), root);
    commitAll(root, 'fixture');
    final Directory untracked = Directory(p.join(directory, 'untracked'));
    if (untracked.existsSync()) {
      copyTree(untracked.path, root);
    }
    return root;
  }
}

/// The fixtures in [directory], sorted by name.
List<Fixture> fixturesIn(String directory) {
  return Directory(directory).listSync().whereType<Directory>().map((
    Directory d,
  ) {
    return Fixture(d.path);
  }).toList()..sort((Fixture a, Fixture b) => a.name.compareTo(b.name));
}
