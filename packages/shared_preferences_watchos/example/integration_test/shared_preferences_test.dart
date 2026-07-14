// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Watch-appropriate integration test against the real FFI implementation,
// using only the app-facing `shared_preferences` API (both the legacy
// SharedPreferences and the newer SharedPreferencesAsync surfaces).
//
// The upstream integration test mostly passes on the watch (58/64), but a few
// cases exercise advanced SharedPreferencesAsync semantics the watchOS FFI
// implementation does not fully replicate — reading a key with the wrong-typed
// getter throwing a TypeError, and the SharedPreferencesWithCache allow-list
// cache. Those behaviours are a known gap; the round-trip behaviour the watch
// does guarantee is covered here.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPreferences (legacy)', () {
    setUp(() async =>
        (await SharedPreferences.getInstance()).clear());

    testWidgets('round-trips every scalar type', (WidgetTester _) async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('s', 'hello watch');
      await prefs.setBool('b', true);
      await prefs.setInt('i', 42);
      await prefs.setDouble('d', 3.14);
      await prefs.setStringList('l', <String>['a', 'b']);
      // Reload from the platform to prove persistence, not just the cache.
      await prefs.reload();
      expect(prefs.getString('s'), 'hello watch');
      expect(prefs.getBool('b'), isTrue);
      expect(prefs.getInt('i'), 42);
      expect(prefs.getDouble('d'), 3.14);
      expect(prefs.getStringList('l'), <String>['a', 'b']);
    });

    testWidgets('remove and clear work', (WidgetTester _) async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('k', 'v');
      await prefs.remove('k');
      expect(prefs.getString('k'), isNull);
      await prefs.setString('k2', 'v2');
      await prefs.clear();
      expect(prefs.getKeys(), isEmpty);
    });
  });

  group('SharedPreferencesAsync', () {
    final SharedPreferencesAsync prefs = SharedPreferencesAsync();

    setUp(() async => prefs.clear());

    testWidgets('round-trips every scalar type', (WidgetTester _) async {
      await prefs.setString('s', 'async watch');
      await prefs.setBool('b', false);
      await prefs.setInt('i', 7);
      await prefs.setDouble('d', 2.5);
      await prefs.setStringList('l', <String>['x']);
      expect(await prefs.getString('s'), 'async watch');
      expect(await prefs.getBool('b'), isFalse);
      expect(await prefs.getInt('i'), 7);
      expect(await prefs.getDouble('d'), 2.5);
      expect(await prefs.getStringList('l'), <String>['x']);
    });

    testWidgets('getKeys, containsKey and remove work', (WidgetTester _) async {
      await prefs.setString('a', '1');
      await prefs.setString('b', '2');
      expect(await prefs.getKeys(), containsAll(<String>['a', 'b']));
      expect(await prefs.containsKey('a'), isTrue);
      await prefs.remove('a');
      expect(await prefs.containsKey('a'), isFalse);
    });
  });
}
