// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// lib/src/plugin_defines.dart: the `defines` a pubspec declares, read as the
// CLI reads them, which tool/check_native_sources.sh compiles each plugin
// with. tool/test/check_native_sources_test.dart runs it through the script.

import 'package:plugins_tool/src/plugin_defines.dart';
import 'package:test/test.dart';

/// A plugin pubspec whose `watchos:` block ends with [lines].
String _pubspec(String lines) {
  return 'name: gadget_watchos\n'
      'flutter:\n'
      '  plugin:\n'
      '    platforms:\n'
      '      watchos:\n'
      '        ffiPlugin: true\n'
      '$lines';
}

void main() {
  test('reads a key or a list of keys, in the order declared', () {
    final PluginDefines defines = readPluginDefines(
      _pubspec(
        '        defines:\n'
        '          GADGET_LOCATION:\n'
        '            - NSLocationWhenInUseUsageDescription\n'
        '            - NSLocationAlwaysAndWhenInUseUsageDescription\n'
        '          GADGET_CAMERA: NSCameraUsageDescription\n',
      ),
    );
    expect(defines.macros, <String>['GADGET_LOCATION', 'GADGET_CAMERA']);
    expect(defines.problems, isEmpty);
  });

  test('a pubspec without defines, or with an empty value, declares none', () {
    for (final String pubspec in <String>[
      _pubspec(''),
      _pubspec('        defines:\n'),
      _pubspec('        defines: {}\n'),
      'name: not_a_plugin\n',
    ]) {
      final PluginDefines defines = readPluginDefines(pubspec);
      expect(defines.macros, isEmpty, reason: pubspec);
      expect(defines.problems, isEmpty, reason: pubspec);
    }
  });

  // The CLI's own words, so the check and a build refuse the same pubspec.
  for (final (String label, String lines, String problem)
      in <(String, String, String)>[
        (
          'a list instead of a map',
          '        defines:\n          - GADGET_CAMERA\n',
          '`defines` is a list, not a map.',
        ),
        (
          'a macro that is not a C identifier',
          '        defines:\n          GADGET-CAMERA: NSCameraUsageDescription\n',
          '`GADGET-CAMERA` is not a C identifier.',
        ),
        (
          'a key that is a number',
          '        defines:\n          GADGET_CAMERA: 7\n',
          '`GADGET_CAMERA` maps to 7, not an Info.plist key or a list of keys.',
        ),
        (
          'no key',
          '        defines:\n          GADGET_CAMERA:\n',
          '`GADGET_CAMERA` names no Info.plist key.',
        ),
        (
          'an empty key',
          "        defines:\n          GADGET_CAMERA: ''\n",
          '`GADGET_CAMERA` names an empty Info.plist key.',
        ),
        (
          'an empty list',
          '        defines:\n          GADGET_CAMERA: []\n',
          '`GADGET_CAMERA` lists no Info.plist key.',
        ),
        (
          'a list with a number',
          '        defines:\n          GADGET_CAMERA: [NSCameraUsageDescription, 7]\n',
          '`GADGET_CAMERA` lists 7, which is not an Info.plist key.',
        ),
      ]) {
    test('refuses $label', () {
      final PluginDefines defines = readPluginDefines(_pubspec(lines));
      expect(defines.problems, <String>[problem]);
    });
  }

  test('a pubspec that does not parse is refused', () {
    final PluginDefines defines = readPluginDefines('name: [unclosed\n');
    expect(defines.problems.single, startsWith('pubspec.yaml does not parse'));
  });
}
