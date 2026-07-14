// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Watch-appropriate integration test against the real FFI implementation,
// using only the app-facing `package_info_plus` API.
//
// The upstream integration test was intentionally not kept: it asserts the
// exact bundle metadata of the upstream iOS example (app name
// "Package Info Plus Example", version "1.2.3", installerStore
// "com.apple.simulator", install/update timestamps) — values tied to that
// app's Info.plist rather than to plugin correctness. Here we assert the
// shape the watch implementation actually guarantees.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('fromPlatform returns this app\'s bundle metadata',
      (WidgetTester _) async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    expect(info.appName, isNotEmpty);
    expect(info.packageName, isNotEmpty);
    expect(info.version, isNotEmpty);
    expect(info.buildNumber, isNotEmpty);
  });
}
