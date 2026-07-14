// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_watchos/path_provider_watchos.dart';

/// Fake bindings — no FFI, fixed sandbox-shaped paths.
class _FakeBindings extends PathProviderWatchosBindings {
  _FakeBindings() : super.forTesting();

  @override
  String? get temporaryPath => '/sandbox/tmp';
  @override
  String? get applicationSupportPath => '/sandbox/Library/Application Support';
  @override
  String? get libraryPath => '/sandbox/Library';
  @override
  String? get documentsPath => '/sandbox/Documents';
  @override
  String? get cachePath => '/sandbox/Library/Caches';
}

void main() {
  setUp(() {
    PathProviderWatchos.bindingsOverride = _FakeBindings();
  });

  test('registerWith installs the watchOS implementation', () {
    PathProviderWatchos.registerWith();
    expect(PathProviderPlatform.instance, isA<PathProviderWatchos>());
  });

  test('directory getters forward to the native bindings', () async {
    final PathProviderWatchos provider = PathProviderWatchos();
    expect(await provider.getTemporaryPath(), '/sandbox/tmp');
    expect(await provider.getApplicationSupportPath(),
        '/sandbox/Library/Application Support');
    expect(await provider.getLibraryPath(), '/sandbox/Library');
    expect(await provider.getApplicationDocumentsPath(), '/sandbox/Documents');
    expect(
        await provider.getApplicationCachePath(), '/sandbox/Library/Caches');
  });

  test('watchOS-inapplicable directories keep throwing defaults', () {
    final PathProviderWatchos provider = PathProviderWatchos();
    expect(provider.getDownloadsPath, throwsUnimplementedError);
    expect(provider.getExternalStoragePath, throwsUnimplementedError);
  });
}
