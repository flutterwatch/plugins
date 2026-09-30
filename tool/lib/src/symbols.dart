// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// The FFI symbol check (spec 0006 criterion 14, change plan M177).
///
/// A plugin names the C symbols its Dart code looks up in the pubspec's
/// `flutter.plugin.platforms.watchos.ffiSymbols`, defines them in its native
/// sources, and looks them up by name from `lib/`. The three lists drift
/// apart silently: a symbol Dart looks up that the native side does not
/// define fails only at run time, on a watch. This check compares them, as
/// `specs/research/2026-09-29/plugins-evidence/symcheck.py` did, and fails on
/// a difference that `tool/symcheck_allow.yaml` does not list.
///
/// For a package named `<name>`, only symbols that start with `<name>_`
/// count:
/// - declared: the `ffiSymbols` entries;
/// - looked up: string literals in `lib/**.dart` (a literal with an
///   interpolation is left out and reported);
/// - defined: C function definitions in `watchos/**` and `src/**` (`.m`,
///   `.mm`, `.c`), and `@_cdecl("...")` names in `watchos/**.swift`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The kinds of difference, with the words the report uses.
enum SymbolMismatch {
  /// In `ffiSymbols`, but no native definition.
  declaredNotDefined('declared, not defined'),

  /// Looked up by Dart, but not in `ffiSymbols`.
  lookedUpNotDeclared('looked up by Dart, not declared'),

  /// Defined natively, but not in `ffiSymbols`.
  definedNotDeclared('defined, not declared'),

  /// In `ffiSymbols`, but Dart never looks it up.
  declaredNotLookedUp('declared, not looked up by Dart');

  const SymbolMismatch(this.description);

  /// The words the report and the allow-list use for this kind.
  final String description;
}

/// The symbols of one package.
class PackageSymbols {
  /// Creates the symbol lists of [package].
  PackageSymbols(
    this.package, {
    required this.declared,
    required this.lookedUp,
    required this.defined,
    required this.interpolated,
  });

  /// The package name.
  final String package;

  /// The `ffiSymbols` entries.
  final Set<String> declared;

  /// The names Dart looks up.
  final Set<String> lookedUp;

  /// The names the native sources define.
  final Set<String> defined;

  /// Looked-up literals with an interpolation, which the check cannot read.
  final Set<String> interpolated;

  /// Each kind of difference, with its symbols, sorted.
  Map<SymbolMismatch, List<String>> get mismatches {
    List<String> minus(Set<String> a, Set<String> b) =>
        a.difference(b).toList()..sort();
    return <SymbolMismatch, List<String>>{
      SymbolMismatch.declaredNotDefined: minus(declared, defined),
      SymbolMismatch.lookedUpNotDeclared: minus(lookedUp, declared),
      SymbolMismatch.definedNotDeclared: minus(defined, declared),
      SymbolMismatch.declaredNotLookedUp: minus(declared, lookedUp),
    };
  }
}

List<File> _filesUnder(String directory, Set<String> extensions) {
  final Directory root = Directory(directory);
  if (!root.existsSync()) {
    return <File>[];
  }
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => extensions.contains(p.extension(f.path)))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));
}

/// Reads the symbols of the package in [packageDirectory].
PackageSymbols readPackageSymbols(String packageDirectory) {
  final String package = p.basename(packageDirectory);
  final String prefix = RegExp.escape('${package}_');

  final Object? pubspec = loadYaml(
    File(p.join(packageDirectory, 'pubspec.yaml')).readAsStringSync(),
  );
  Object? node = pubspec;
  for (final String key in <String>[
    'flutter',
    'plugin',
    'platforms',
    'watchos',
    'ffiSymbols',
  ]) {
    node = node is YamlMap ? node[key] : null;
  }
  final Set<String> declared = <String>{
    if (node is YamlList)
      for (final Object? entry in node) '$entry',
  }.where((String name) => name.startsWith('${package}_')).toSet();

  final RegExp literal = RegExp('[\'"]($prefix[A-Za-z0-9_\$]+)[\'"]');
  final Set<String> lookedUp = <String>{};
  final Set<String> interpolated = <String>{};
  for (final File file in _filesUnder(p.join(packageDirectory, 'lib'), <String>{
    '.dart',
  })) {
    for (final Match match in literal.allMatches(file.readAsStringSync())) {
      final String name = match[1]!;
      (name.contains(r'$') ? interpolated : lookedUp).add(name);
    }
  }

  final RegExp definition = RegExp(
    '\\b($prefix[A-Za-z0-9_]+)\\s*\\([^;{]*\\)\\s*\\{',
  );
  final RegExp cdecl = RegExp(r'@_cdecl\("([A-Za-z0-9_]+)"\)');
  final Set<String> defined = <String>{};
  for (final String folder in <String>['watchos', 'src']) {
    for (final File file in _filesUnder(
      p.join(packageDirectory, folder),
      <String>{'.m', '.mm', '.c', '.swift'},
    )) {
      final String source = file.readAsStringSync();
      if (p.extension(file.path) == '.swift') {
        defined.addAll(cdecl.allMatches(source).map((Match m) => m[1]!));
      } else {
        defined.addAll(definition.allMatches(source).map((Match m) => m[1]!));
      }
    }
  }
  return PackageSymbols(
    package,
    declared: declared,
    lookedUp: lookedUp,
    defined: defined,
    interpolated: interpolated,
  );
}

/// One allowed difference.
class AllowedMismatch {
  /// Creates an allowed difference.
  const AllowedMismatch(this.package, this.symbol, this.kind, this.reason);

  /// The package name.
  final String package;

  /// The symbol.
  final String symbol;

  /// The kind of difference.
  final SymbolMismatch kind;

  /// Why it is allowed.
  final String reason;
}

/// Parses `tool/symcheck_allow.yaml`: a list under `allow:` of maps with
/// `package`, `symbol`, `kind` (a [SymbolMismatch] description) and
/// `reason`.
///
/// Throws a [FormatException] for an entry without all four, or with an
/// unknown kind.
List<AllowedMismatch> parseSymbolAllowList(String contents) {
  final Object? document = loadYaml(contents);
  final Object? entries = document is YamlMap ? document['allow'] : null;
  if (entries == null) {
    return <AllowedMismatch>[];
  }
  if (entries is! YamlList) {
    throw const FormatException('"allow" must be a list.');
  }
  return <AllowedMismatch>[
    for (final Object? entry in entries) _allowed(entry),
  ];
}

AllowedMismatch _allowed(Object? entry) {
  String field(String name) {
    final Object? value = entry is YamlMap ? entry[name] : null;
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('An allow-list entry needs "$name": $entry');
    }
    return value;
  }

  final String kind = field('kind');
  return AllowedMismatch(
    field('package'),
    field('symbol'),
    SymbolMismatch.values.firstWhere(
      (SymbolMismatch k) => k.description == kind,
      orElse: () => throw FormatException('Unknown kind "$kind".'),
    ),
    field('reason'),
  );
}

/// Checks every package under `packages/` of the repository at [root],
/// writes the report to [out] and returns the exit code: 1 when a
/// difference is not allowed, or an allowed one no longer exists.
int runSymbolCheck(String root, List<AllowedMismatch> allowed, StringSink out) {
  final List<String> packages =
      Directory(p.join(root, 'packages'))
          .listSync()
          .whereType<Directory>()
          .where(
            (Directory d) => File(p.join(d.path, 'pubspec.yaml')).existsSync(),
          )
          .map((Directory d) => d.path)
          .toList()
        ..sort();
  final Set<AllowedMismatch> used = <AllowedMismatch>{};
  int failures = 0;
  for (final String directory in packages) {
    final PackageSymbols symbols = readPackageSymbols(directory);
    final List<String> problems = <String>[];
    final List<String> notes = <String>[];
    symbols.mismatches.forEach((SymbolMismatch kind, List<String> names) {
      for (final String name in names) {
        final AllowedMismatch? entry = allowed
            .where(
              (AllowedMismatch a) =>
                  a.package == symbols.package &&
                  a.symbol == name &&
                  a.kind == kind,
            )
            .firstOrNull;
        if (entry == null) {
          problems.add('${kind.description}: $name');
        } else {
          used.add(entry);
          notes.add('allowed, ${kind.description}: $name (${entry.reason})');
        }
      }
    });
    for (final String name in symbols.interpolated) {
      notes.add('an interpolated lookup the check cannot read: $name');
    }
    final String counts =
        '${symbols.declared.length} declared, ${symbols.lookedUp.length} '
        'looked up, ${symbols.defined.length} defined';
    if (problems.isEmpty) {
      out.writeln('ok   ${symbols.package}: $counts');
    } else {
      failures++;
      out.writeln('FAIL ${symbols.package}: $counts');
    }
    for (final String problem in problems) {
      out.writeln('       $problem');
    }
    for (final String note in notes) {
      out.writeln('       note: $note');
    }
  }
  for (final AllowedMismatch entry in allowed) {
    if (!used.contains(entry)) {
      failures++;
      out.writeln(
        'FAIL symcheck_allow.yaml: ${entry.package} ${entry.symbol} '
        '(${entry.kind.description}) no longer differs; remove the entry.',
      );
    }
  }
  if (failures > 0) {
    out.writeln('Symbols: $failures problems.');
    return 1;
  }
  out.writeln('Symbols: declared, looked up and defined agree.');
  return 0;
}
