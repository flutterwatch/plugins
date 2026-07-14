// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Watch-appropriate integration test against the real Keychain-backed FFI
// implementation. Like a real client, it depends only on the app-facing
// `flutter_secure_storage` package — the watchOS implementation registers
// itself federatedly with no imports or code changes here.
//
// The upstream `app_test.dart` was intentionally not kept: it drives the
// mobile example UI (off-screen on the watch) and exercises Secure Enclave /
// biometric features that do not exist on watchOS. Its baseline
// write/read/delete assertions — the part that applies to the watch — are
// reproduced here.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const FlutterSecureStorage storage = FlutterSecureStorage();

  setUp(() async => storage.deleteAll());
  tearDown(() async => storage.deleteAll());

  testWidgets('write then read round-trips a value through the Keychain',
      (WidgetTester _) async {
    await storage.write(key: 'token', value: 'watch-secret');
    expect(await storage.read(key: 'token'), 'watch-secret');
  });

  testWidgets('overwriting a key updates the stored value',
      (WidgetTester _) async {
    await storage.write(key: 'k', value: 'v1');
    await storage.write(key: 'k', value: 'v2');
    expect(await storage.read(key: 'k'), 'v2');
  });

  testWidgets('containsKey and delete behave correctly',
      (WidgetTester _) async {
    expect(await storage.containsKey(key: 'k'), isFalse);
    await storage.write(key: 'k', value: 'v');
    expect(await storage.containsKey(key: 'k'), isTrue);
    await storage.delete(key: 'k');
    expect(await storage.containsKey(key: 'k'), isFalse);
  });

  testWidgets('readAll and deleteAll cover every key', (WidgetTester _) async {
    await storage.write(key: 'a', value: '1');
    await storage.write(key: 'b', value: '2');
    final Map<String, String> all = await storage.readAll();
    expect(all['a'], '1');
    expect(all['b'], '2');
    await storage.deleteAll();
    expect(await storage.readAll(), isEmpty);
  });

  testWidgets('unicode values survive a round-trip', (WidgetTester _) async {
    await storage.write(key: 'emoji', value: '⌚️→🔐 café');
    expect(await storage.read(key: 'emoji'), '⌚️→🔐 café');
  });
}
