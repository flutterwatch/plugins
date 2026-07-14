// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Runs on the watch simulator against the real FFI implementation
// (path_provider_watchos). Adapted from the upstream path_provider example's
// integration_test, trimmed to the directories that exist on watchOS.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_watchos/path_provider_watchos.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('watchOS implementation is registered', (WidgetTester _) async {
    expect(PathProviderPlatform.instance, isA<PathProviderWatchos>());
  });

  testWidgets('getTemporaryDirectory returns a usable directory',
      (WidgetTester _) async {
    final Directory dir = await getTemporaryDirectory();
    expect(dir.path, isNotEmpty);
    expect(dir.existsSync(), isTrue);
  });

  testWidgets('getApplicationSupportDirectory is created on demand',
      (WidgetTester _) async {
    final Directory dir = await getApplicationSupportDirectory();
    expect(dir.path, isNotEmpty);
    expect(dir.existsSync(), isTrue);
  });

  testWidgets('getApplicationDocumentsDirectory returns a path',
      (WidgetTester _) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    expect(dir.path, isNotEmpty);
  });

  testWidgets('getApplicationCacheDirectory returns a path',
      (WidgetTester _) async {
    final Directory dir = await getApplicationCacheDirectory();
    expect(dir.path, isNotEmpty);
  });

  testWidgets('temp directory round-trips a file', (WidgetTester _) async {
    final Directory dir = await getTemporaryDirectory();
    final File f = File('${dir.path}/probe.txt');
    await f.writeAsString('hello watch');
    expect(await f.readAsString(), 'hello watch');
    await f.delete();
  });
}
