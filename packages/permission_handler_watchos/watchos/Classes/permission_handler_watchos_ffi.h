// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by the MIT license that can be found
// in the LICENSE file.
//
// watchOS implementation of `permission_handler`, over dart:ffi.
//
// A permission is permission_handler's own number for it (the index of the
// Permission in permission_handler_platform_interface), and a status is its
// PermissionStatus or ServiceStatus number, the same numbers the iOS
// implementation answers with. Each call returns a request id at once; the
// answer is kept as JSON until Dart takes it, and native wakes Dart through
// one callback that carries a kind, never a payload.
//
// The answer is {"status": <PermissionStatus>}, {"service": <ServiceStatus>}
// or {"error": {"code", "message"}}. An error's code is the iOS
// implementation's: MISSING_USAGE_DESCRIPTION when the Info.plist lacks the
// key the system prompt needs (the call fails instead of the app being
// terminated), and MISSING_WHENINUSE_PERMISSION for an "always" location
// request made before "when in use" was granted.

#ifndef PERMISSION_HANDLER_WATCHOS_FFI_H
#define PERMISSION_HANDLER_WATCHOS_FFI_H

#include <stdint.h>

// Each exported symbol is marked `used` + default-visibility so it survives
// the linker's `-dead_strip` and lands in the executable's dynamic symbol
// table, where `DynamicLibrary.process()` / dlsym can resolve it.
#define PHW_EXPORT __attribute__((visibility("default"))) __attribute__((used))

// What woke Dart up. Mirrored in lib/src/ffi_backend.dart.
#define PHW_SIGNAL_RESULT 1

typedef void (*phw_signal_callback)(int64_t kind);

// Registers the callback Dart wants woken, or NULL to stop signalling.
PHW_EXPORT
void permission_handler_watchos_set_callback(phw_signal_callback callback);

// Reads the status of `permission`, without asking the wearer.
PHW_EXPORT
int64_t permission_handler_watchos_check(int32_t permission);

// Reads whether the service behind `permission` is on: location services,
// motion activity, Bluetooth; not applicable for the others.
PHW_EXPORT
int64_t permission_handler_watchos_service(int32_t permission);

// Asks the wearer for `permission` when they have not answered yet, and
// answers with its status afterwards.
PHW_EXPORT
int64_t permission_handler_watchos_request(int32_t permission);

// The answer to `request` as JSON, which the caller releases with
// permission_handler_watchos_release; NULL while there is none yet.
PHW_EXPORT
char* permission_handler_watchos_take_result(int64_t request);

// Releases a string this file returned.
PHW_EXPORT
void permission_handler_watchos_release(char* string);

#endif  // PERMISSION_HANDLER_WATCHOS_FFI_H
