// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `path_provider`, implemented over dart:ffi.
//
// Method-channel plugins are not supported on watchOS, so
// this package follows the FFI plugin model: `watchos/Classes/
// path_provider_watchos_ffi.m` exports one C symbol per directory getter,
// the CLI force-loads the compiled archive into the watch binary, and this
// class resolves the symbols via `DynamicLibrary.process()`.

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// FFI bindings to the native path_provider_watchos C functions.
///
/// Overridable for tests via [PathProviderWatchos.bindingsOverride]: the
/// [PathProviderWatchosBindings.forTesting] constructor skips FFI
/// initialization so fakes work off-device.
class PathProviderWatchosBindings {
  /// Creates bindings that look up native symbols in the current process.
  PathProviderWatchosBindings() : _lib = DynamicLibrary.process();

  /// Constructor for fakes/mocks — skips FFI initialization.
  PathProviderWatchosBindings.forTesting() : _lib = null;

  final DynamicLibrary? _lib;

  late final Pointer<Utf8> Function() _temporaryPath = _lib!
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'path_provider_watchos_temporary_path');

  late final Pointer<Utf8> Function() _applicationSupportPath = _lib!
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'path_provider_watchos_application_support_path');

  late final Pointer<Utf8> Function() _libraryPath = _lib!
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'path_provider_watchos_library_path');

  late final Pointer<Utf8> Function() _documentsPath = _lib!
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'path_provider_watchos_documents_path');

  late final Pointer<Utf8> Function() _cachePath = _lib!
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'path_provider_watchos_cache_path');

  String? _string(Pointer<Utf8> Function() f) {
    final Pointer<Utf8> p = f();
    // Native pointers are cached per-process and owned by the plugin — never
    // freed here.
    return p == nullptr ? null : p.toDartString();
  }

  /// `NSTemporaryDirectory()`, trailing slash stripped.
  String? get temporaryPath => _string(_temporaryPath);

  /// `NSApplicationSupportDirectory`, created on first access.
  String? get applicationSupportPath => _string(_applicationSupportPath);

  /// `NSLibraryDirectory`.
  String? get libraryPath => _string(_libraryPath);

  /// `NSDocumentDirectory`.
  String? get documentsPath => _string(_documentsPath);

  /// `NSCachesDirectory`.
  String? get cachePath => _string(_cachePath);
}

/// watchOS implementation of [PathProviderPlatform].
base class PathProviderWatchos extends PathProviderPlatform {
  /// Test hook: set before first use to replace the FFI bindings.
  static PathProviderWatchosBindings? bindingsOverride;

  static PathProviderWatchosBindings? _bindings;

  static PathProviderWatchosBindings get _b =>
      bindingsOverride ?? (_bindings ??= PathProviderWatchosBindings());

  /// Registers this implementation as the default `path_provider`
  /// platform implementation on watchOS.
  static void registerWith() {
    PathProviderPlatform.instance = PathProviderWatchos();
  }

  @override
  Future<String?> getTemporaryPath() async => _b.temporaryPath;

  @override
  Future<String?> getApplicationSupportPath() async =>
      _b.applicationSupportPath;

  @override
  Future<String?> getLibraryPath() async => _b.libraryPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => _b.documentsPath;

  @override
  Future<String?> getApplicationCachePath() async => _b.cachePath;

  // The remaining interface methods (external storage, downloads) describe
  // directories that do not exist on watchOS; the base class's
  // UnimplementedError defaults are the correct behaviour.
}
