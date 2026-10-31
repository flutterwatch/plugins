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
//
// The pubspec files each key under one macro, and the guards decide which.
// A key read in code that several macros compile in, such as the
// when-in-use key under PERMISSION_LOCATION || PERMISSION_LOCATION_WHENINUSE,
// belongs to the one that no other key turns on. Filed under the other one
// too, it would turn that one on as well, and put its code into apps that
// do not use it.

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

/// Siri's usage description is read in Siri's code, but it does not turn
/// that code on: its opt-in does, as the usage description alone does not
/// say that the app has the Siri capability.
const String _siriUsageDescription = 'NSSiriUsageDescription';

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

/// The pubspec's `defines`: each macro with its Info.plist keys, none for an
/// entry that lists none.
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
      entry.key as String: switch (entry.value) {
        final String key => <String>[key],
        final YamlList keys => keys.cast<String>().toList(),
        _ => <String>[],
      },
  };
}

/// The macros the pubspec files each declared key under.
Map<String, Set<String>> _macrosOfKey() {
  final Map<String, Set<String>> macros = <String, Set<String>>{};
  for (final MapEntry<String, List<String>> define in _declared().entries) {
    for (final String key in define.value) {
      (macros[key] ??= <String>{}).add(define.key);
    }
  }
  return macros;
}

/// The macros the guards leave each key the native code reads, from the
/// sources alone: those that compile in every read of the key. Where that
/// is several, a macro that no other key is left takes the key, since each
/// macro needs a key and a key turns one macro on. A key still left several
/// is one the guards do not decide.
Map<String, Set<String>> _macrosTheGuardsLeave() {
  final Map<String, Set<String>> left = <String, Set<String>>{};
  for (final _KeyRead read in _keyReads()) {
    if (read.key != _siriUsageDescription) {
      left[read.key] =
          left[read.key]?.intersection(read.macros) ?? read.macros.toSet();
    }
  }
  final Set<String> macros = _guardedMacros();
  bool narrowed = true;
  while (narrowed) {
    narrowed = false;
    for (final String macro in macros) {
      final List<String> keys = <String>[
        for (final MapEntry<String, Set<String>> entry in left.entries)
          if (entry.value.contains(macro)) entry.key,
      ];
      if (keys.length == 1 && left[keys.single]!.length > 1) {
        left[keys.single] = <String>{macro};
        narrowed = true;
      }
    }
  }
  return left;
}

/// [macrosOfKey] as sorted `key: MACRO` lines, for a readable failure.
List<String> _pairs(Map<String, Set<String>> macrosOfKey) {
  return <String>[
    for (final MapEntry<String, Set<String>> entry in macrosOfKey.entries)
      '${entry.key}: ${(entry.value.toList()..sort()).join(', ')}',
  ]..sort();
}

void main() {
  test('the guards test exactly the macros the pubspec declares', () {
    expect(_guardedMacros(), _declared().keys.toSet());
  });

  test('each macro lists a key, and each key is listed once', () {
    final Map<String, List<String>> declared = _declared();
    expect(
      <String>[
        for (final MapEntry<String, List<String>> define in declared.entries)
          if (define.value.isEmpty) define.key,
      ],
      isEmpty,
      reason: 'macros that list no key',
    );
    final List<String> keys = <String>[
      for (final List<String> listed in declared.values) ...listed,
    ];
    expect(
      <String>{
        for (final String key in keys)
          if (keys.where((String other) => other == key).length > 1) key,
      },
      isEmpty,
      reason: 'keys listed more than once',
    );
  });

  test('each key the native code reads is filed under a macro its guard tests',
      () {
    final Map<String, Set<String>> macrosOfKey = _macrosOfKey();
    for (final _KeyRead read in _keyReads()) {
      if (read.key == _siriUsageDescription) {
        expect(macrosOfKey[read.key], isNull, reason: read.where);
        expect(read.macros, contains('PERMISSION_ASSISTANT'),
            reason: read.where);
        continue;
      }
      expect(macrosOfKey[read.key], isNotNull,
          reason: '${read.key} at ${read.where} is filed under no macro');
      expect(read.macros, containsAll(macrosOfKey[read.key]!),
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

  test('each key is filed under exactly the macro the guards leave it', () {
    expect(_pairs(_macrosOfKey()), _pairs(_macrosTheGuardsLeave()));
  });

  // The iOS implementation compiles the write-only request in with
  // PERMISSION_EVENTS or PERMISSION_EVENTS_FULL_ACCESS, and so does this
  // package. A guard that tests PERMISSION_EVENTS alone leaves the key to the
  // same macro, so the test above cannot tell the two apart.
  test('the write-only request is compiled in with either calendar macro', () {
    expect(
      <List<String>>[
        for (final _KeyRead read in _keyReads())
          if (read.key == 'NSCalendarsWriteOnlyAccessUsageDescription')
            read.macros.toList()..sort(),
      ],
      <List<String>>[
        <String>['PERMISSION_EVENTS', 'PERMISSION_EVENTS_FULL_ACCESS'],
      ],
    );
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
