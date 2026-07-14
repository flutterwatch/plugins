// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// The persistent key-value store shared by both watchOS shared_preferences
/// implementations (legacy [SharedPreferencesStorePlatform] and async
/// [SharedPreferencesAsyncPlatform]).
///
/// The whole store is a single JSON object persisted in NSUserDefaults under
/// one private key; the native side only loads and saves the blob (see
/// `watchos/Classes/shared_preferences_watchos_ffi.m`). Keeping all typing
/// and filtering in Dart means the five supported value types round-trip
/// through JSON without type tags: `bool`, `int`, `double`, `String`, and
/// `List<String>` each map to a distinct JSON shape.
///
/// Overridable for tests via [WatchosPrefsStore.override]; the
/// [WatchosPrefsStore.forTesting] constructor keeps the store in memory and
/// skips FFI entirely.
class WatchosPrefsStore {
  /// Creates a store backed by the native FFI blob in the current process.
  WatchosPrefsStore() : _lib = DynamicLibrary.process();

  /// In-memory store for tests — no FFI, no persistence.
  WatchosPrefsStore.forTesting([Map<String, Object>? initial])
      : _lib = null,
        _memory = <String, Object>{...?initial};

  final DynamicLibrary? _lib;
  Map<String, Object>? _memory;

  /// Process-wide override installed by tests.
  static WatchosPrefsStore? override;

  static WatchosPrefsStore? _instance;

  /// The shared store instance.
  static WatchosPrefsStore get instance =>
      override ?? (_instance ??= WatchosPrefsStore());

  late final Pointer<Utf8> Function() _loadFn = _lib!
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'shared_preferences_watchos_load');

  late final void Function(Pointer<Utf8>) _saveFn =
      _lib!.lookupFunction<Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>(
          'shared_preferences_watchos_save');

  late final void Function(Pointer<Utf8>) _freeFn =
      _lib!.lookupFunction<Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>(
          'shared_preferences_watchos_free');

  /// Loads the whole store.
  Map<String, Object> readAll() {
    if (_memory != null) {
      return <String, Object>{..._memory!};
    }
    final Pointer<Utf8> p = _loadFn();
    try {
      final String json = p == nullptr ? '{}' : p.toDartString();
      final Object? decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) {
        return decoded.cast<String, Object>();
      }
      return <String, Object>{};
    } finally {
      // Release the buffer the native load() malloc'd for us.
      if (p != nullptr) {
        _freeFn(p);
      }
    }
  }

  /// Persists the whole store.
  void writeAll(Map<String, Object> data) {
    if (_memory != null) {
      _memory = <String, Object>{...data};
      return;
    }
    final Pointer<Utf8> json = jsonEncode(data).toNativeUtf8();
    try {
      _saveFn(json);
    } finally {
      malloc.free(json);
    }
  }

  /// Reads [key], or null if absent.
  Object? read(String key) => readAll()[key];

  /// Sets [key] to [value] and persists.
  void write(String key, Object value) {
    final Map<String, Object> data = readAll();
    data[key] = value;
    writeAll(data);
  }

  /// Removes [key] and persists.
  void remove(String key) {
    final Map<String, Object> data = readAll();
    if (data.remove(key) != null) {
      writeAll(data);
    }
  }
}
