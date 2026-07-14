// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef PACKAGE_INFO_PLUS_WATCHOS_FFI_H
#define PACKAGE_INFO_PLUS_WATCHOS_FFI_H

// See path_provider_watchos_ffi.h for why every symbol is `used` +
// default-visibility: the watch app links this archive statically, so
// without the attributes the linker would drop these (FFI has no
// compile-time caller). The CLI additionally emits a forced reference for
// each symbol listed under `flutter.plugin.platforms.watchos.ffiSymbols`.
#define PACKAGE_INFO_PLUS_WATCHOS_EXPORT \
  __attribute__((visibility("default"))) __attribute__((used))

// Each getter returns a UTF-8 C string owned by the plugin (cached for the
// process lifetime — bundle metadata never changes after launch). Callers
// must NOT free the returned pointer. A missing Info.plist key yields an
// empty string, matching the iOS package_info_plus behaviour.

/// `CFBundleDisplayName`, falling back to `CFBundleName`.
PACKAGE_INFO_PLUS_WATCHOS_EXPORT const char* package_info_plus_watchos_app_name(void);

/// `CFBundleIdentifier`.
PACKAGE_INFO_PLUS_WATCHOS_EXPORT const char* package_info_plus_watchos_package_name(void);

/// `CFBundleShortVersionString` (the marketing version).
PACKAGE_INFO_PLUS_WATCHOS_EXPORT const char* package_info_plus_watchos_version(void);

/// `CFBundleVersion` (the build number).
PACKAGE_INFO_PLUS_WATCHOS_EXPORT const char* package_info_plus_watchos_build_number(void);

#endif  // PACKAGE_INFO_PLUS_WATCHOS_FFI_H
