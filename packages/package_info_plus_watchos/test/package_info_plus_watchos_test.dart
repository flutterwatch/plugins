// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus_platform_interface/package_info_platform_interface.dart';
import 'package:package_info_plus_watchos/package_info_plus_watchos.dart';

/// Fake bindings — no FFI, fixed Info.plist-shaped values.
class _FakeBindings extends PackageInfoWatchosBindings {
  _FakeBindings() : super.forTesting();

  @override
  String get appName => 'Watch Example';
  @override
  String get packageName => 'com.example.watchExample';
  @override
  String get version => '1.2.3';
  @override
  String get buildNumber => '42';
}

void main() {
  setUp(() {
    PackageInfoWatchos.bindingsOverride = _FakeBindings();
  });

  test('registerWith installs the watchOS implementation', () {
    PackageInfoWatchos.registerWith();
    expect(PackageInfoPlatform.instance, isA<PackageInfoWatchos>());
  });

  test('getAll maps NSBundle fields to PackageInfoData', () async {
    final data = await PackageInfoWatchos().getAll();
    expect(data.appName, 'Watch Example');
    expect(data.packageName, 'com.example.watchExample');
    expect(data.version, '1.2.3');
    expect(data.buildNumber, '42');
    // watchOS exposes no installer source.
    expect(data.installerStore, isNull);
  });
}
