// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `flutter_secure_storage`, over dart:ffi.
// Backed by the Keychain (`kSecClassGenericPassword`), which is fully
// available on watchOS.

#ifndef FLUTTER_SECURE_STORAGE_WATCHOS_FFI_H
#define FLUTTER_SECURE_STORAGE_WATCHOS_FFI_H

#include <stdbool.h>

// Each exported symbol is marked `used` + default-visibility so it survives
// the linker's `-dead_strip` and lands in the executable's dynamic symbol
// table, where `DynamicLibrary.process()` / dlsym can resolve it.
#define FLUTTER_SECURE_STORAGE_WATCHOS_EXPORT \
  __attribute__((visibility("default"))) __attribute__((used))

// All string arguments are UTF-8 C strings. `service` is the Keychain service
// (`accountName` option, default "flutter_secure_storage_service"). Pass NULL
// or "" for `access_group`/`accessibility` to use defaults; `access_group`
// requires the keychain-access-groups entitlement and is normally unset.

// Returns 0 on success, otherwise the negative Keychain OSStatus.
FLUTTER_SECURE_STORAGE_WATCHOS_EXPORT
int flutter_secure_storage_watchos_write(const char* key, const char* value,
                                         const char* service,
                                         const char* access_group,
                                         const char* accessibility,
                                         bool synchronizable);

// Returns a malloc'd UTF-8 value the caller must release with
// `flutter_secure_storage_watchos_free`, or NULL if the key is absent.
FLUTTER_SECURE_STORAGE_WATCHOS_EXPORT
char* flutter_secure_storage_watchos_read(const char* key, const char* service,
                                          const char* access_group);

// Returns 1 if the key exists, 0 otherwise.
FLUTTER_SECURE_STORAGE_WATCHOS_EXPORT
int flutter_secure_storage_watchos_contains(const char* key,
                                            const char* service,
                                            const char* access_group);

// Deletes one key. Returns 0 on success or if the key was already absent.
FLUTTER_SECURE_STORAGE_WATCHOS_EXPORT
int flutter_secure_storage_watchos_delete(const char* key, const char* service,
                                          const char* access_group);

// Returns a malloc'd JSON object string of every key/value pair for the
// service (the caller frees it), or NULL on error. "{}" when empty.
FLUTTER_SECURE_STORAGE_WATCHOS_EXPORT
char* flutter_secure_storage_watchos_read_all(const char* service,
                                              const char* access_group);

// Deletes every item for the service. Returns 0 on success.
FLUTTER_SECURE_STORAGE_WATCHOS_EXPORT
int flutter_secure_storage_watchos_delete_all(const char* service,
                                              const char* access_group);

// Releases a pointer returned by read / read_all.
FLUTTER_SECURE_STORAGE_WATCHOS_EXPORT
void flutter_secure_storage_watchos_free(char* ptr);

#endif  // FLUTTER_SECURE_STORAGE_WATCHOS_FFI_H
