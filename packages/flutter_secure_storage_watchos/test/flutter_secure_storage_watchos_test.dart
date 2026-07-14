// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Host-side unit tests. The native Keychain backend is replaced with an
// in-memory fake so the platform-interface mapping is verified off-device;
// the real Keychain path is exercised by the example's integration_test.

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_secure_storage_watchos/flutter_secure_storage_watchos.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory stand-in for the native Keychain, keyed by (service, key).
class _FakeBackend implements FlutterSecureStorageWatchosBackend {
  final Map<String, Map<String, String>> _store =
      <String, Map<String, String>>{};

  String _svc(String? service) => service ?? 'default';
  Map<String, String> _bucket(String? service) =>
      _store.putIfAbsent(_svc(service), () => <String, String>{});

  @override
  int write(String key, String value, String? service, String? accessGroup,
      String? accessibility, bool synchronizable) {
    _bucket(service)[key] = value;
    return 0;
  }

  @override
  String? read(String key, String? service, String? accessGroup) =>
      _bucket(service)[key];

  @override
  bool contains(String key, String? service, String? accessGroup) =>
      _bucket(service).containsKey(key);

  @override
  int delete(String key, String? service, String? accessGroup) {
    _bucket(service).remove(key);
    return 0;
  }

  @override
  Map<String, String> readAll(String? service, String? accessGroup) =>
      Map<String, String>.from(_bucket(service));

  @override
  int deleteAll(String? service, String? accessGroup) {
    _bucket(service).clear();
    return 0;
  }
}

void main() {
  const Map<String, String> options = <String, String>{
    'accountName': 'flutter_secure_storage_service',
  };

  late _FakeBackend fake;
  late FlutterSecureStorageWatchos storage;

  setUp(() {
    fake = _FakeBackend();
    FlutterSecureStorageWatchos.backendOverride = fake;
    storage = FlutterSecureStorageWatchos();
  });

  tearDown(() => FlutterSecureStorageWatchos.backendOverride = null);

  test('registerWith installs the watchOS implementation', () {
    FlutterSecureStorageWatchos.registerWith();
    expect(FlutterSecureStoragePlatform.instance,
        isA<FlutterSecureStorageWatchos>());
  });

  test('write then read round-trips a value', () async {
    await storage.write(key: 'token', value: 'abc123', options: options);
    expect(await storage.read(key: 'token', options: options), 'abc123');
  });

  test('read returns null for a missing key', () async {
    expect(await storage.read(key: 'nope', options: options), isNull);
  });

  test('containsKey reflects presence', () async {
    expect(await storage.containsKey(key: 'k', options: options), isFalse);
    await storage.write(key: 'k', value: 'v', options: options);
    expect(await storage.containsKey(key: 'k', options: options), isTrue);
  });

  test('delete removes a single key', () async {
    await storage.write(key: 'k', value: 'v', options: options);
    await storage.delete(key: 'k', options: options);
    expect(await storage.containsKey(key: 'k', options: options), isFalse);
  });

  test('readAll returns every pair; deleteAll clears them', () async {
    await storage.write(key: 'a', value: '1', options: options);
    await storage.write(key: 'b', value: '2', options: options);
    expect(await storage.readAll(options: options),
        <String, String>{'a': '1', 'b': '2'});
    await storage.deleteAll(options: options);
    expect(await storage.readAll(options: options), isEmpty);
  });

  test('write surfaces a non-zero Keychain status as an exception', () async {
    FlutterSecureStorageWatchos.backendOverride = _FailingBackend();
    expect(
      FlutterSecureStorageWatchos().write(
          key: 'k', value: 'v', options: options),
      throwsA(isA<Exception>()),
    );
  });
}

class _FailingBackend extends _FakeBackend {
  @override
  int write(String key, String value, String? service, String? accessGroup,
          String? accessibility, bool synchronizable) =>
      -25299; // errSecDuplicateItem, arbitrary non-zero OSStatus.
}
