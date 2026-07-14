// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef DEVICE_INFO_PLUS_WATCHOS_FFI_H
#define DEVICE_INFO_PLUS_WATCHOS_FFI_H

// See path_provider_watchos_ffi.h for why the export is `used` +
// default-visibility. The CLI also emits a forced reference for the symbol
// listed under `flutter.plugin.platforms.watchos.ffiSymbols`.
#define DEVICE_INFO_PLUS_WATCHOS_EXPORT \
  __attribute__((visibility("default"))) __attribute__((used))

/// Returns a JSON object (UTF-8 C string) describing the watch, shaped for
/// `IosDeviceInfo.fromMap` — the map device_info_plus reads on an
/// iOS-family platform (watchOS reports `Platform.isIOS == true`). Keys:
/// name, systemName, systemVersion, model, modelName, localizedModel,
/// identifierForVendor, isPhysicalDevice, physicalRamSize, availableRamSize,
/// freeDiskSize, totalDiskSize, isiOSAppOnMac, isiOSAppOnVision, and a
/// nested `utsname` object (sysname/nodename/release/version/machine).
///
/// The returned pointer is owned by the plugin (resolved once, cached for
/// the process lifetime); callers must NOT free it.
DEVICE_INFO_PLUS_WATCHOS_EXPORT const char* device_info_plus_watchos_info_json(void);

#endif  // DEVICE_INFO_PLUS_WATCHOS_FFI_H
