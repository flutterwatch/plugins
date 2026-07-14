// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `network_info_plus`, over dart:ffi.
//
// Only the IP-address family of getters is supported: watchOS has no
// CaptiveNetwork / NEHotspotNetwork, so Wi-Fi SSID and BSSID are unavailable
// (the Dart side returns null for those). The addresses come from
// `getifaddrs`, preferring the primary "en0" interface.

#ifndef NETWORK_INFO_PLUS_WATCHOS_FFI_H
#define NETWORK_INFO_PLUS_WATCHOS_FFI_H

// Each exported symbol is marked `used` + default-visibility so it survives
// the linker's `-dead_strip` and lands in the executable's dynamic symbol
// table, where `DynamicLibrary.process()` / dlsym can resolve it.
#define NETWORK_INFO_PLUS_WATCHOS_EXPORT \
  __attribute__((visibility("default"))) __attribute__((used))

// Each getter returns a malloc'd UTF-8 string the caller must release with
// `network_info_plus_watchos_free`, or NULL when unavailable.

// The IPv4 address of the active interface (dotted quad).
NETWORK_INFO_PLUS_WATCHOS_EXPORT
char* network_info_plus_watchos_wifi_ip(void);

// The IPv6 address of the active interface.
NETWORK_INFO_PLUS_WATCHOS_EXPORT
char* network_info_plus_watchos_wifi_ipv6(void);

// The IPv4 subnet mask of the active interface.
NETWORK_INFO_PLUS_WATCHOS_EXPORT
char* network_info_plus_watchos_wifi_submask(void);

// The IPv4 broadcast address of the active interface.
NETWORK_INFO_PLUS_WATCHOS_EXPORT
char* network_info_plus_watchos_wifi_broadcast(void);

// Releases a pointer returned by any getter above.
NETWORK_INFO_PLUS_WATCHOS_EXPORT
void network_info_plus_watchos_free(char* ptr);

#endif  // NETWORK_INFO_PLUS_WATCHOS_FFI_H
