// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `flutter_secure_storage`, implemented over
// dart:ffi against the Keychain.
//
// Method-channel plugins are not supported on watchOS, so this package follows
// the FFI plugin model: `watchos/Classes/flutter_secure_storage_watchos_ffi.m`
// exports the Keychain operations as C symbols, the CLI force-loads the
// compiled archive into the watch binary, and [_FfiBackend] resolves the
// symbols via `DynamicLibrary.process()`.

import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

/// The native operations, factored out behind an interface so unit tests can
/// swap in an in-memory fake off-device (see
/// [FlutterSecureStorageWatchos.backendOverride]).
abstract class FlutterSecureStorageWatchosBackend {
  /// Writes [value] under [key]; returns 0 on success or a Keychain OSStatus.
  int write(String key, String value, String? service, String? accessGroup,
      String? accessibility, bool synchronizable);

  /// Reads [key], or null if absent.
  String? read(String key, String? service, String? accessGroup);

  /// Whether [key] exists.
  bool contains(String key, String? service, String? accessGroup);

  /// Deletes [key]; returns 0 on success (or if already absent).
  int delete(String key, String? service, String? accessGroup);

  /// Every key/value pair for the service.
  Map<String, String> readAll(String? service, String? accessGroup);

  /// Deletes every item for the service; returns 0 on success.
  int deleteAll(String? service, String? accessGroup);
}

/// watchOS implementation of [FlutterSecureStoragePlatform].
base class FlutterSecureStorageWatchos extends FlutterSecureStoragePlatform {
  /// Test hook: set before first use to replace the native backend with a fake.
  static FlutterSecureStorageWatchosBackend? backendOverride;

  static FlutterSecureStorageWatchosBackend? _backend;

  static FlutterSecureStorageWatchosBackend get _b =>
      backendOverride ?? (_backend ??= _FfiBackend());

  /// Registers this implementation as the default `flutter_secure_storage`
  /// platform implementation on watchOS.
  static void registerWith() {
    FlutterSecureStoragePlatform.instance = FlutterSecureStorageWatchos();
  }

  String? _service(Map<String, String> options) => options['accountName'];
  String? _group(Map<String, String> options) => options['groupId'];

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    final int status = _b.write(
      key,
      value,
      _service(options),
      _group(options),
      options['accessibility'],
      options['synchronizable'] == 'true',
    );
    if (status != 0) {
      throw Exception('Keychain write failed (OSStatus $status)');
    }
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async =>
      _b.read(key, _service(options), _group(options));

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      _b.contains(key, _service(options), _group(options));

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    final int status = _b.delete(key, _service(options), _group(options));
    if (status != 0) {
      throw Exception('Keychain delete failed (OSStatus $status)');
    }
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      _b.readAll(_service(options), _group(options));

  @override
  Future<void> deleteAll({
    required Map<String, String> options,
  }) async {
    final int status = _b.deleteAll(_service(options), _group(options));
    if (status != 0) {
      throw Exception('Keychain deleteAll failed (OSStatus $status)');
    }
  }
}

typedef _WriteNative = Int32 Function(Pointer<Utf8>, Pointer<Utf8>,
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Bool);
typedef _WriteDart = int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>,
    Pointer<Utf8>, Pointer<Utf8>, bool);
typedef _Read3Native = Pointer<Utf8> Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _Read3Dart = Pointer<Utf8> Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _Int3Native = Int32 Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _Int3Dart = int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _Read2Native = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _Read2Dart = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _Int2Native = Int32 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _Int2Dart = int Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _FreeDart = void Function(Pointer<Utf8>);

/// Resolves the Keychain C symbols and marshals arguments to/from native.
class _FfiBackend implements FlutterSecureStorageWatchosBackend {
  _FfiBackend() : _lib = DynamicLibrary.process();

  final DynamicLibrary _lib;

  late final _WriteDart _write = _lib.lookupFunction<_WriteNative, _WriteDart>(
      'flutter_secure_storage_watchos_write');
  late final _Read3Dart _read = _lib.lookupFunction<_Read3Native, _Read3Dart>(
      'flutter_secure_storage_watchos_read');
  late final _Int3Dart _contains = _lib.lookupFunction<_Int3Native, _Int3Dart>(
      'flutter_secure_storage_watchos_contains');
  late final _Int3Dart _delete = _lib.lookupFunction<_Int3Native, _Int3Dart>(
      'flutter_secure_storage_watchos_delete');
  late final _Read2Dart _readAll =
      _lib.lookupFunction<_Read2Native, _Read2Dart>(
          'flutter_secure_storage_watchos_read_all');
  late final _Int2Dart _deleteAll =
      _lib.lookupFunction<_Int2Native, _Int2Dart>(
          'flutter_secure_storage_watchos_delete_all');
  late final _FreeDart _free = _lib.lookupFunction<_FreeNative, _FreeDart>(
      'flutter_secure_storage_watchos_free');

  /// Allocates a native UTF-8 copy of [s] (empty string for null, so native
  /// code can treat "" and NULL the same via its `_nonempty` check).
  Pointer<Utf8> _c(String? s) => (s ?? '').toNativeUtf8();

  /// Copies a native string into Dart and releases it with the native free.
  String? _take(Pointer<Utf8> p) {
    if (p == nullptr) {
      return null;
    }
    final String s = p.toDartString();
    _free(p);
    return s;
  }

  @override
  int write(String key, String value, String? service, String? accessGroup,
      String? accessibility, bool synchronizable) {
    final Pointer<Utf8> k = _c(key),
        v = _c(value),
        s = _c(service),
        g = _c(accessGroup),
        a = _c(accessibility);
    try {
      return _write(k, v, s, g, a, synchronizable);
    } finally {
      malloc
        ..free(k)
        ..free(v)
        ..free(s)
        ..free(g)
        ..free(a);
    }
  }

  @override
  String? read(String key, String? service, String? accessGroup) {
    final Pointer<Utf8> k = _c(key), s = _c(service), g = _c(accessGroup);
    try {
      return _take(_read(k, s, g));
    } finally {
      malloc
        ..free(k)
        ..free(s)
        ..free(g);
    }
  }

  @override
  bool contains(String key, String? service, String? accessGroup) {
    final Pointer<Utf8> k = _c(key), s = _c(service), g = _c(accessGroup);
    try {
      return _contains(k, s, g) == 1;
    } finally {
      malloc
        ..free(k)
        ..free(s)
        ..free(g);
    }
  }

  @override
  int delete(String key, String? service, String? accessGroup) {
    final Pointer<Utf8> k = _c(key), s = _c(service), g = _c(accessGroup);
    try {
      return _delete(k, s, g);
    } finally {
      malloc
        ..free(k)
        ..free(s)
        ..free(g);
    }
  }

  @override
  Map<String, String> readAll(String? service, String? accessGroup) {
    final Pointer<Utf8> s = _c(service), g = _c(accessGroup);
    try {
      final String? json = _take(_readAll(s, g));
      if (json == null || json.isEmpty) {
        return <String, String>{};
      }
      final Map<String, dynamic> decoded =
          jsonDecode(json) as Map<String, dynamic>;
      return decoded
          .map((String k, dynamic v) => MapEntry<String, String>(k, '$v'));
    } finally {
      malloc
        ..free(s)
        ..free(g);
    }
  }

  @override
  int deleteAll(String? service, String? accessGroup) {
    final Pointer<Utf8> s = _c(service), g = _c(accessGroup);
    try {
      return _deleteAll(s, g);
    } finally {
      malloc
        ..free(s)
        ..free(g);
    }
  }
}
