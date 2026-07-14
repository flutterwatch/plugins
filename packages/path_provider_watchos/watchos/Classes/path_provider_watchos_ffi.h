// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef PATH_PROVIDER_WATCHOS_FFI_H
#define PATH_PROVIDER_WATCHOS_FFI_H

// Each exported symbol is marked `used` + default-visibility so it survives
// the linker's `-dead_strip` and lands in the executable's dynamic symbol
// table, where `DynamicLibrary.process()` / dlsym can resolve it. The watch
// app links this archive statically, so without `used` the linker would drop
// these (FFI has no compile-time caller). The flutter-watchos CLI
// additionally emits a forced reference for each symbol listed under
// `flutter.plugin.platforms.watchos.ffiSymbols` in pubspec.yaml.
#define PATH_PROVIDER_WATCHOS_EXPORT \
  __attribute__((visibility("default"))) __attribute__((used))

// Every function returns an absolute directory path as a UTF-8 C string, or
// NULL when the directory cannot be resolved. Returned pointers are owned by
// the plugin (cached for the lifetime of the process — the sandbox paths
// never change after launch); callers must NOT free them.

/// `NSTemporaryDirectory()`, trailing slash stripped.
PATH_PROVIDER_WATCHOS_EXPORT const char* path_provider_watchos_temporary_path(void);

/// `NSApplicationSupportDirectory` in the user domain. Created on first call
/// (it does not exist by default in the sandbox), matching the iOS
/// path_provider behaviour.
PATH_PROVIDER_WATCHOS_EXPORT const char* path_provider_watchos_application_support_path(void);

/// `NSLibraryDirectory` in the user domain.
PATH_PROVIDER_WATCHOS_EXPORT const char* path_provider_watchos_library_path(void);

/// `NSDocumentDirectory` in the user domain.
PATH_PROVIDER_WATCHOS_EXPORT const char* path_provider_watchos_documents_path(void);

/// `NSCachesDirectory` in the user domain.
PATH_PROVIDER_WATCHOS_EXPORT const char* path_provider_watchos_cache_path(void);

#endif  // PATH_PROVIDER_WATCHOS_FFI_H
