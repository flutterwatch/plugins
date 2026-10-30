// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// The per-app defines each plugin declares, for `check_native_sources.sh`.
///
/// A plugin maps preprocessor macros to app Info.plist keys under
/// `flutter.plugin.platforms.watchos.defines` in its pubspec. From the first
/// flutter-watchos release after 0.1.1, the CLI compiles the plugin's native
/// sources with `FLUTTER_WATCHOS_PLUGIN_DEFINES` and each macro whose key the
/// app's Info.plist sets; an older CLI passes neither. So the check compiles
/// such a plugin three ways: with no `-D`, with the marker and every macro,
/// and with the marker alone.
///
/// The pubspec is read with package:yaml, the parser the CLI reads it with,
/// so a declaration means the same to both, and a declaration the CLI would
/// refuse fails here with the CLI's words: `defines` must be a map, each
/// macro a C identifier, and each value an Info.plist key (a non-empty
/// string) or a non-empty list of keys.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'repository.dart';

/// A C identifier, which a macro name must be.
final RegExp _cIdentifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// A package's pubspec, one level under `packages/`.
final RegExp _packagePubspec = RegExp(r'^packages/[^/]+/pubspec\.yaml$');

/// What a pubspec declares under `flutter.plugin.platforms.watchos.defines`.
class PluginDefines {
  /// Creates the declaration of [macros], with the [problems] that make the
  /// CLI refuse it.
  const PluginDefines(this.macros, this.problems);

  /// The macro names, in the order the pubspec declares them.
  final List<String> macros;

  /// What is wrong with the declaration, as the CLI words it. Empty when the
  /// CLI accepts it.
  final List<String> problems;
}

/// Reads the `defines` of the pubspec text [pubspec].
///
/// A pubspec without `defines`, or with an empty one, declares none.
PluginDefines readPluginDefines(String pubspec) {
  Object? node;
  try {
    node = loadYaml(pubspec);
  } on YamlException catch (error) {
    return PluginDefines(const <String>[], <String>[
      'pubspec.yaml does not parse: ${error.message}',
    ]);
  }
  for (final String key in <String>[
    'flutter',
    'plugin',
    'platforms',
    'watchos',
    'defines',
  ]) {
    node = node is YamlMap ? node[key] : null;
  }
  if (node == null) {
    return const PluginDefines(<String>[], <String>[]);
  }
  if (node is! YamlMap) {
    return PluginDefines(const <String>[], <String>[
      '`defines` is ${_describe(node)}, not a map.',
    ]);
  }
  final List<String> macros = <String>[];
  final List<String> problems = <String>[];
  for (final MapEntry<dynamic, dynamic> entry in node.entries) {
    final Object? macro = entry.key;
    if (macro is! String || !_cIdentifier.hasMatch(macro)) {
      problems.add('`$macro` is not a C identifier.');
      continue;
    }
    final List<String> keyProblems = _keysProblems(macro, entry.value);
    if (keyProblems.isEmpty) {
      macros.add(macro);
    } else {
      problems.addAll(keyProblems);
    }
  }
  return PluginDefines(macros, problems);
}

/// What is wrong with [value] as the Info.plist keys of [macro]: empty for
/// a key or a non-empty list of keys.
List<String> _keysProblems(String macro, Object? value) {
  if (value == null) {
    return <String>['`$macro` names no Info.plist key.'];
  }
  if (value is String) {
    return value.isEmpty
        ? <String>['`$macro` names an empty Info.plist key.']
        : const <String>[];
  }
  if (value is! YamlList) {
    return <String>[
      '`$macro` maps to ${_describe(value)}, not an Info.plist key or a list '
          'of keys.',
    ];
  }
  if (value.isEmpty) {
    return <String>['`$macro` lists no Info.plist key.'];
  }
  return <String>[
    for (final Object? key in value)
      if (key is! String || key.isEmpty)
        '`$macro` lists ${_describe(key)}, which is not an Info.plist key.',
  ];
}

/// [value] as a message shows it.
String _describe(Object? value) {
  return switch (value) {
    null => 'an empty entry',
    String() when value.isEmpty => 'an empty string',
    String() => '"$value"',
    YamlMap() => 'a map',
    YamlList() => 'a list',
    _ => '$value',
  };
}

/// Writes to [out] a line `defines <package directory> <MACRO>…` for each
/// package of the repository at [root] whose tracked pubspec declares
/// `defines`, and the problems of each declaration the CLI would refuse.
///
/// Returns 0, or 1 when a declaration is refused.
int runPluginDefines(String root, StringSink out) {
  final List<String> pubspecs = git(root, <String>[
    'ls-files',
    '--',
    'packages/*/pubspec.yaml',
  ]).split('\n').where(_packagePubspec.hasMatch).toList()..sort();
  int status = 0;
  for (final String pubspec in pubspecs) {
    final String package = p.dirname(pubspec);
    final PluginDefines defines = readPluginDefines(
      File(p.join(root, pubspec)).readAsStringSync(),
    );
    if (defines.problems.isNotEmpty) {
      out.writeln(
        'The watchOS plugin ${p.basename(package)} has an invalid `defines` '
        'in $pubspec:',
      );
      for (final String problem in defines.problems) {
        out.writeln('  - $problem');
      }
      status = 1;
    } else if (defines.macros.isNotEmpty) {
      out.writeln('defines $package ${defines.macros.join(' ')}');
    }
  }
  return status;
}
