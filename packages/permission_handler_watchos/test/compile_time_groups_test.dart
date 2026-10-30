// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by the MIT license that can be found
// in the LICENSE file.
//
// The compile-time groups: the pubspec's `defines` and the native sources'
// guards pair the same macros with the same keys. Each Info.plist key the
// native code reads must be declared under a macro that the guard around
// that code tests, and each declared key must be read in code its macro
// compiles in. A macro or a key spelled differently, or a key filed under
// the wrong macro, would put the wrong groups into every app that a
// flutter-watchos with `defines` builds, and no compile would show it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// A guard of the marker form: `#if !defined(FLUTTER_WATCHOS_PLUGIN_DEFINES)`
/// followed by `|| MACRO` for each macro it tests.
final RegExp _markerGuard = RegExp(
  r'^#if !defined\(FLUTTER_WATCHOS_PLUGIN_DEFINES\)((?:\s*\|\|\s*\w+)+)\s*$',
);

/// An Info.plist key, as an Objective-C string literal: a usage description
/// or this package's own Siri opt-in.
final RegExp _keyLiteral = RegExp(
  r'@"(NS\w+UsageDescription|PermissionHandlerWatchos\w*)"',
);

/// One Info.plist key literal in the native sources, with the macros of the
/// innermost marker guard around it: empty outside any marker guard, and in
/// the `#else` side of one.
class _KeyRead {
  _KeyRead(this.key, this.macros, this.where);

  final String key;
  final Set<String> macros;
  final String where;
}

/// The native sources, sorted by path.
List<File> _sources() {
  return Directory('watchos')
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.m') || f.path.endsWith('.h'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));
}

/// The lines of [file], with each continued line joined to the next.
List<String> _lines(File file) =>
    file.readAsStringSync().replaceAll('\\\n', ' ').split('\n');

/// The macros that the marker guards in the native sources test.
Set<String> _guardedMacros() {
  return <String>{
    for (final File file in _sources())
      for (final String line in _lines(file))
        if (_markerGuard.firstMatch(line.trim()) case final RegExpMatch guard)
          for (final RegExpMatch macro in RegExp(r'\w+').allMatches(guard[1]!))
            macro[0]!,
  };
}

/// Every Info.plist key literal in the native sources, with its guard.
List<_KeyRead> _keyReads() {
  final List<_KeyRead> reads = <_KeyRead>[];
  for (final File file in _sources()) {
    // Each open #if: the macros of a marker guard on its `#if` side, an empty
    // set on its `#else` side, and null for any other #if.
    final List<Set<String>?> open = <Set<String>?>[];
    final List<String> lines = _lines(file);
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (line.startsWith('#if')) {
        final RegExpMatch? guard = _markerGuard.firstMatch(line);
        open.add(guard == null
            ? null
            : RegExp(r'\w+')
                .allMatches(guard[1]!)
                .map((RegExpMatch m) => m[0]!)
                .toSet());
      } else if (line.startsWith('#el')) {
        if (open.last != null) {
          open.last = <String>{};
        }
      } else if (line.startsWith('#endif')) {
        open.removeLast();
      } else {
        final Set<String> macros = open.lastWhere(
              (Set<String>? guard) => guard != null,
              orElse: () => <String>{},
            ) ??
            <String>{};
        for (final RegExpMatch key in _keyLiteral.allMatches(line)) {
          reads.add(_KeyRead(key[1]!, macros, '${file.path}:${i + 1}'));
        }
      }
    }
    expect(open, isEmpty, reason: 'unbalanced #if in ${file.path}');
  }
  return reads;
}

/// The pubspec's `defines`: each macro with its Info.plist keys.
Map<String, List<String>> _declared() {
  Object? node = loadYaml(File('pubspec.yaml').readAsStringSync());
  for (final String key in <String>[
    'flutter',
    'plugin',
    'platforms',
    'watchos',
    'defines'
  ]) {
    node = (node as YamlMap)[key];
  }
  return <String, List<String>>{
    for (final MapEntry<dynamic, dynamic> entry in (node as YamlMap).entries)
      entry.key as String: entry.value is String
          ? <String>[entry.value as String]
          : (entry.value as YamlList).cast<String>().toList(),
  };
}

/// The macro each declared key is filed under.
Map<String, String> _macroOfKey() {
  return <String, String>{
    for (final MapEntry<String, List<String>> define in _declared().entries)
      for (final String key in define.value) key: define.key,
  };
}

void main() {
  test('the guards test exactly the macros the pubspec declares', () {
    expect(_guardedMacros(), _declared().keys.toSet());
  });

  // Siri's usage description is read in Siri's code, but it does not turn
  // that code on: its opt-in does, as the usage description alone does not
  // say that the app has the Siri capability.
  test('each key the native code reads is filed under a macro its guard tests',
      () {
    final Map<String, String> macroOfKey = _macroOfKey();
    for (final _KeyRead read in _keyReads()) {
      if (read.key == 'NSSiriUsageDescription') {
        expect(macroOfKey[read.key], isNull, reason: read.where);
        expect(read.macros, contains('PERMISSION_ASSISTANT'),
            reason: read.where);
        continue;
      }
      expect(read.macros, contains(macroOfKey[read.key]),
          reason: '${read.key} at ${read.where}');
    }
  });

  test('each declared key is read in code that its macro compiles in', () {
    final List<_KeyRead> reads = _keyReads();
    for (final MapEntry<String, List<String>> define in _declared().entries) {
      for (final String key in define.value) {
        expect(
          reads.where((_KeyRead read) =>
              read.key == key && read.macros.contains(define.key)),
          isNotEmpty,
          reason: '${define.key}: $key',
        );
      }
    }
  });

  test('the EventKit keys are among the keys read', () {
    expect(
      <String>{for (final _KeyRead read in _keyReads()) read.key},
      containsAll(<String>[
        'NSCalendarsFullAccessUsageDescription',
        'NSCalendarsWriteOnlyAccessUsageDescription',
        'NSRemindersFullAccessUsageDescription',
      ]),
    );
  });
}
