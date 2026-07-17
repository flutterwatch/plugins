// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Host-side unit tests. The native FirebaseCore backend is replaced with a
// fake serving scripted JSON snapshots, so the Dart <-> native marshalling,
// app-registry bookkeeping, and error mapping are verified off-device; the
// real FirebaseCore SDK is exercised by the example app on the watch
// simulator.

import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:firebase_core_watchos/firebase_core_watchos.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake bindings recording every call and serving scripted results.
class _FakeBindings extends FirebaseCoreWatchosBindings {
  _FakeBindings() : super.forTesting();

  final List<String> calls = <String>[];

  // Dart app name -> app-info snapshot the native layer would return.
  final Map<String, Map<String, Object?>> configured = <String, Map<String, Object?>>{};

  Map<String, Object?>? configureError;

  @override
  Map<String, Object?> configure(String name, String optionsJson) {
    calls.add('configure($name)');
    if (configureError != null) {
      return configureError!;
    }
    final String dartName = name.isEmpty ? '[DEFAULT]' : name;
    final Map<String, Object?> info = <String, Object?>{
      'name': dartName,
      'options': <String, Object?>{
        'apiKey': 'k',
        'appId': 'a',
        'messagingSenderId': 's',
        'projectId': 'p',
      },
      'isAutomaticDataCollectionEnabled': true,
    };
    configured[dartName] = info;
    return info;
  }

  @override
  Map<String, Object?> options(String name) {
    calls.add('options($name)');
    final String dartName = name.isEmpty ? '[DEFAULT]' : name;
    return configured[dartName] ??
        <String, Object?>{'error': 'No app', 'code': 'no-app'};
  }

  @override
  List<Object?> apps() {
    calls.add('apps()');
    return configured.values.toList();
  }

  @override
  Map<String, Object?> delete(String name) {
    calls.add('delete($name)');
    configured.remove(name);
    return <String, Object?>{'deleted': true};
  }

  @override
  Map<String, Object?> setAutoDataCollection(String name, bool enabled) {
    calls.add('setAutoDataCollection($name, $enabled)');
    return <String, Object?>{'ok': true};
  }
}

const FirebaseOptions _options = FirebaseOptions(
  apiKey: 'k',
  appId: 'a',
  messagingSenderId: 's',
  projectId: 'p',
);

void main() {
  late _FakeBindings fake;
  late FirebaseCoreWatchos platform;

  setUp(() {
    fake = _FakeBindings();
    FirebaseCoreWatchos.bindingsOverride = fake;
    platform = FirebaseCoreWatchos();
  });

  tearDown(() {
    FirebaseCoreWatchos.bindingsOverride = null;
  });

  test('registerWith installs the instance', () {
    FirebaseCoreWatchos.registerWith();
    expect(FirebasePlatform.instance, isA<FirebaseCoreWatchos>());
  });

  test('initializeApp with no name configures the default app', () async {
    final FirebaseAppPlatform app =
        await platform.initializeApp(options: _options);
    expect(app.name, defaultFirebaseAppName);
    expect(app.options.apiKey, 'k');
    // The default app is configured with an empty native name.
    expect(fake.calls, contains('configure()'));
  });

  test('initializeApp with a name configures a secondary app', () async {
    final FirebaseAppPlatform app =
        await platform.initializeApp(name: 'foo', options: _options);
    expect(app.name, 'foo');
    expect(fake.calls, contains('configure(foo)'));
    expect(platform.apps.map((FirebaseAppPlatform a) => a.name), contains('foo'));
  });

  test('initializeApp surfaces a native error as a FirebaseException', () async {
    fake.configureError = <String, Object?>{
      'error': 'boom',
      'code': 'configuration-failed'
    };
    await expectLater(
      platform.initializeApp(options: _options),
      throwsA(isA<FirebaseException>()
          .having((FirebaseException e) => e.code, 'code', 'configuration-failed')),
    );
  });

  test('app() throws when the named app was never created', () {
    expect(
      () => platform.app('missing'),
      throwsA(isA<FirebaseException>()
          .having((FirebaseException e) => e.code, 'code', 'no-app')),
    );
  });

  test('app() returns a previously initialized app', () async {
    await platform.initializeApp(name: 'foo', options: _options);
    expect(platform.app('foo').name, 'foo');
  });

  test('setAutomaticDataCollectionEnabled forwards to native', () async {
    final FirebaseAppPlatform app =
        await platform.initializeApp(options: _options);
    await app.setAutomaticDataCollectionEnabled(false);
    expect(fake.calls, contains('setAutoDataCollection([DEFAULT], false)'));
    expect(app.isAutomaticDataCollectionEnabled, isFalse);
  });

  test('delete removes the app from the registry', () async {
    await platform.initializeApp(name: 'foo', options: _options);
    await platform.app('foo').delete();
    expect(fake.calls, contains('delete(foo)'));
    expect(platform.apps.map((FirebaseAppPlatform a) => a.name), isNot(contains('foo')));
  });
}
