// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `shared_preferences`, implemented over dart:ffi.
//
// Method-channel plugins are not supported on watchOS, so
// this package follows the FFI plugin model: `watchos/Classes/
// shared_preferences_watchos_ffi.m` persists the store as a JSON blob in
// NSUserDefaults, and the Dart side (see src/watchos_prefs_store.dart) does
// all typing and filtering.
//
// Like shared_preferences_foundation on iOS, this registers BOTH the legacy
// SharedPreferencesStorePlatform and the async SharedPreferencesAsyncPlatform
// against the same underlying store.

import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'src/watchos_prefs_store.dart';

/// Legacy watchOS implementation of [SharedPreferencesStorePlatform].
class SharedPreferencesWatchos extends SharedPreferencesStorePlatform {
  WatchosPrefsStore get _store => WatchosPrefsStore.instance;

  /// Registers this class (and its async sibling) as the default
  /// shared_preferences platform implementations on watchOS.
  static void registerWith() {
    SharedPreferencesStorePlatform.instance = SharedPreferencesWatchos();
    SharedPreferencesAsyncWatchos.registerWith();
  }

  @override
  Future<bool> remove(String key) async {
    _store.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    _store.write(key, value);
    return true;
  }

  @override
  Future<bool> clear() => clearWithParameters(
        ClearParameters(filter: PreferencesFilter(prefix: 'flutter.')),
      );

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async {
    final PreferencesFilter filter = parameters.filter;
    final Map<String, Object> data = _store.readAll();
    data.removeWhere((String key, Object _) => _matches(key, filter.prefix, filter.allowList));
    _store.writeAll(data);
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() => getAllWithParameters(
        GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')),
      );

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    final PreferencesFilter filter = parameters.filter;
    final Map<String, Object> data = _store.readAll();
    data.removeWhere((String key, Object _) => !_matches(key, filter.prefix, filter.allowList));
    return data;
  }

  static bool _matches(String key, String prefix, Set<String>? allowList) {
    if (!key.startsWith(prefix)) {
      return false;
    }
    if (allowList != null && !allowList.contains(key)) {
      return false;
    }
    return true;
  }
}

/// Async watchOS implementation of [SharedPreferencesAsyncPlatform].
base class SharedPreferencesAsyncWatchos extends SharedPreferencesAsyncPlatform {
  WatchosPrefsStore get _store => WatchosPrefsStore.instance;

  /// Registers this class as the default async shared_preferences platform
  /// implementation on watchOS.
  static void registerWith() {
    SharedPreferencesAsyncPlatform.instance = SharedPreferencesAsyncWatchos();
  }

  // A hard cast (not `value is T ? value : null`) so that reading a key with
  // the wrong-typed getter throws a `TypeError`, matching every other
  // shared_preferences platform implementation. An absent key stays null.
  T? _typed<T>(String key) {
    final Object? value = _store.read(key);
    if (value == null) {
      return null;
    }
    return value as T;
  }

  @override
  Future<void> setString(String key, String value, SharedPreferencesOptions options) async =>
      _store.write(key, value);

  @override
  Future<void> setBool(String key, bool value, SharedPreferencesOptions options) async =>
      _store.write(key, value);

  @override
  Future<void> setDouble(String key, double value, SharedPreferencesOptions options) async =>
      _store.write(key, value);

  @override
  Future<void> setInt(String key, int value, SharedPreferencesOptions options) async =>
      _store.write(key, value);

  @override
  Future<void> setStringList(
    String key,
    List<String> value,
    SharedPreferencesOptions options,
  ) async =>
      _store.write(key, value);

  @override
  Future<String?> getString(String key, SharedPreferencesOptions options) async =>
      _typed<String>(key);

  @override
  Future<bool?> getBool(String key, SharedPreferencesOptions options) async =>
      _typed<bool>(key);

  @override
  Future<double?> getDouble(String key, SharedPreferencesOptions options) async =>
      _typed<double>(key);

  @override
  Future<int?> getInt(String key, SharedPreferencesOptions options) async =>
      _typed<int>(key);

  @override
  Future<List<String>?> getStringList(String key, SharedPreferencesOptions options) async {
    final Object? value = _store.read(key);
    if (value == null) {
      return null;
    }
    // A hard cast so a wrong-typed read throws `TypeError`; JSON restores a
    // stored list as `List<dynamic>`, so re-type it to `List<String>`.
    return (value as List).cast<String>();
  }

  @override
  Future<void> clear(ClearPreferencesParameters parameters, SharedPreferencesOptions options) async {
    final Set<String>? allowList = parameters.filter.allowList;
    final Map<String, Object> data = _store.readAll();
    if (allowList == null) {
      _store.writeAll(<String, Object>{});
    } else {
      data.removeWhere((String key, Object _) => allowList.contains(key));
      _store.writeAll(data);
    }
  }

  @override
  Future<Map<String, Object>> getPreferences(
    GetPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async {
    final Set<String>? allowList = parameters.filter.allowList;
    final Map<String, Object> data = _store.readAll();
    if (allowList != null) {
      data.removeWhere((String key, Object _) => !allowList.contains(key));
    }
    return _restoreLists(data);
  }

  @override
  Future<Set<String>> getKeys(
    GetPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async {
    final Set<String>? allowList = parameters.filter.allowList;
    final Set<String> keys = _store.readAll().keys.toSet();
    if (allowList != null) {
      keys.retainWhere(allowList.contains);
    }
    return keys;
  }

  /// JSON decodes string-lists as `List<dynamic>`; re-type them so callers
  /// receive `List<String>`.
  static Map<String, Object> _restoreLists(Map<String, Object> data) {
    return data.map((String key, Object value) => MapEntry<String, Object>(
          key,
          value is List ? value.cast<String>() : value,
        ));
  }
}
