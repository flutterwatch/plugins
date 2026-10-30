// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by the MIT license that can be found
// in the LICENSE file.
//
// The compile-time groups: the pubspec's `defines` and the native sources'
// guards name the same macros, and each key a macro is turned on by is one
// the sources check. A macro or a key spelled differently in the two would
// leave its group out of every app that a flutter-watchos with `defines`
// builds, and no compile would show it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// The marker of a guard: `#if !defined(FLUTTER_WATCHOS_PLUGIN_DEFINES) ||`.
final RegExp _guard = RegExp(
  r'^#if !defined\(FLUTTER_WATCHOS_PLUGIN_DEFINES\)(.*)$',
  multiLine: true,
);

/// The native sources, each with its continued lines joined.
Map<String, String> _sources() {
  return <String, String>{
    for (final File file
        in Directory('watchos').listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.m') || file.path.endsWith('.h'))
        file.path: file.readAsStringSync().replaceAll('\\\n', ' '),
  };
}

/// The macros the guards in the native sources test.
Set<String> _guardedMacros() {
  final Set<String> macros = <String>{};
  for (final String source in _sources().values) {
    for (final RegExpMatch guard in _guard.allMatches(source)) {
      for (final RegExpMatch macro
          in RegExp(r'\|\|\s*([A-Za-z_]\w*)').allMatches(guard[1]!)) {
        macros.add(macro[1]!);
      }
    }
  }
  return macros;
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

/// The usage descriptions the native sources check before a prompt.
Set<String> _checkedKeys() {
  return <String>{
    for (final String source in _sources().values)
      for (final RegExpMatch key
          in RegExp(r'phw_has_key\(@"(\w+)"\)').allMatches(source))
        key[1]!,
  };
}

void main() {
  test('the guards test exactly the macros the pubspec declares', () {
    expect(_guardedMacros(), _declared().keys.toSet());
  });

  test('each declared key is a key the native sources name', () {
    final String sources = _sources().values.join('\n');
    for (final MapEntry<String, List<String>> define in _declared().entries) {
      for (final String key in define.value) {
        expect(sources, contains('@"$key"'), reason: '${define.key}: $key');
      }
    }
  });

  // A request checks its prompt's usage description; that key must turn its
  // group on, or the group would be left out of an app that sets it. Siri is
  // turned on by its opt-in instead, as its usage description alone does not
  // say that the app has the Siri capability.
  test("each usage description a prompt checks turns that prompt's group on",
      () {
    final Set<String> declared = <String>{
      for (final List<String> keys in _declared().values) ...keys
    };
    expect(_checkedKeys().difference(declared),
        <String>{'NSSiriUsageDescription'});
    expect(declared, contains('PermissionHandlerWatchosSiri'));
  });
}
