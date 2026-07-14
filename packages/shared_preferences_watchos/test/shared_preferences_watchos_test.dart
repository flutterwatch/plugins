// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:shared_preferences_watchos/shared_preferences_watchos.dart';
import 'package:shared_preferences_watchos/src/watchos_prefs_store.dart';

const SharedPreferencesOptions _options = SharedPreferencesOptions();

void main() {
  setUp(() {
    // In-memory store — no FFI, no persistence between tests.
    WatchosPrefsStore.override = WatchosPrefsStore.forTesting();
  });

  test('registerWith installs both legacy and async implementations', () {
    SharedPreferencesWatchos.registerWith();
    expect(SharedPreferencesStorePlatform.instance, isA<SharedPreferencesWatchos>());
    expect(SharedPreferencesAsyncPlatform.instance, isA<SharedPreferencesAsyncWatchos>());
  });

  group('async', () {
    final SharedPreferencesAsyncWatchos prefs = SharedPreferencesAsyncWatchos();

    test('round-trips every value type with its exact Dart type', () async {
      await prefs.setBool('b', true, _options);
      await prefs.setInt('i', 7, _options);
      await prefs.setDouble('d', 3.5, _options);
      await prefs.setString('s', 'hi', _options);
      await prefs.setStringList('l', <String>['a', 'b'], _options);

      expect(await prefs.getBool('b', _options), true);
      expect(await prefs.getInt('i', _options), 7);
      expect(await prefs.getDouble('d', _options), 3.5);
      expect(await prefs.getString('s', _options), 'hi');
      expect(await prefs.getStringList('l', _options), <String>['a', 'b']);
    });

    test('type-mismatched reads throw a TypeError, matching other platforms',
        () async {
      await prefs.setInt('i', 7, _options);
      expect(() => prefs.getString('i', _options), throwsA(isA<TypeError>()));
      expect(() => prefs.getBool('i', _options), throwsA(isA<TypeError>()));
    });

    test('reads of an absent key return null', () async {
      expect(await prefs.getString('missing', _options), isNull);
      expect(await prefs.getBool('missing', _options), isNull);
      expect(await prefs.getStringList('missing', _options), isNull);
    });

    test('getKeys / getPreferences honour the allowList filter', () async {
      await prefs.setInt('keep', 1, _options);
      await prefs.setInt('drop', 2, _options);
      const params = GetPreferencesParameters(
        filter: PreferencesFilters(allowList: <String>{'keep'}),
      );
      expect(await prefs.getKeys(params, _options), <String>{'keep'});
      expect(await prefs.getPreferences(params, _options), <String, Object>{'keep': 1});
    });

    test('clear with a null allowList wipes everything', () async {
      await prefs.setInt('a', 1, _options);
      await prefs.setInt('b', 2, _options);
      await prefs.clear(
        const ClearPreferencesParameters(filter: PreferencesFilters()),
        _options,
      );
      expect(await prefs.getKeys(
        const GetPreferencesParameters(filter: PreferencesFilters()),
        _options,
      ), isEmpty);
    });
  });

  group('legacy store', () {
    final SharedPreferencesWatchos store = SharedPreferencesWatchos();

    test('getAll filters to the flutter. prefix', () async {
      await store.setValue('Int', 'flutter.count', 3);
      await store.setValue('String', 'other', 'x');
      final all = await store.getAll();
      expect(all, <String, Object>{'flutter.count': 3});
    });

    test('remove deletes a key', () async {
      await store.setValue('String', 'flutter.k', 'v');
      expect(await store.remove('flutter.k'), isTrue);
      expect(await store.getAll(), isEmpty);
    });

    test('clear only removes prefixed keys', () async {
      await store.setValue('Int', 'flutter.a', 1);
      await store.setValue('Int', 'unprefixed', 2);
      await store.clear();
      // The unprefixed key survives (clear defaults to the flutter. prefix).
      expect(WatchosPrefsStore.instance.readAll().containsKey('unprefixed'), isTrue);
      expect(WatchosPrefsStore.instance.readAll().containsKey('flutter.a'), isFalse);
    });
  });
}
