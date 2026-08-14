// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "connectivity_plus_watchos_ffi.h"

#import <Foundation/Foundation.h>
#import <Network/Network.h>

#include <stdatomic.h>

// SystemConfiguration's SCNetworkReachability is unavailable on watchOS, so
// connectivity comes from the Network framework (watchOS 6+). A single
// long-lived NWPathMonitor runs on a background queue and caches the latest
// connectivity code; the FFI getter just reads that cache, and Dart polls it
// for the change stream.
static _Atomic int32_t s_current = kConnectivityWatchosNone;
static nw_path_monitor_t s_monitor = NULL;
static _Atomic(connectivity_plus_watchos_cb) s_callback = NULL;

static int32_t _code_for_path(nw_path_t path) {
  if (nw_path_get_status(path) != nw_path_status_satisfied) {
    return kConnectivityWatchosNone;
  }
  if (nw_path_uses_interface_type(path, nw_interface_type_wifi)) {
    return kConnectivityWatchosWifi;
  }
  if (nw_path_uses_interface_type(path, nw_interface_type_cellular)) {
    return kConnectivityWatchosMobile;
  }
  if (nw_path_uses_interface_type(path, nw_interface_type_wired)) {
    return kConnectivityWatchosEthernet;
  }
  return kConnectivityWatchosOther;
}

static void _ensure_monitor(void) {
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    s_monitor = nw_path_monitor_create();
    dispatch_queue_t queue = dispatch_queue_create(
        "dev.flutterwatch.connectivity_plus_watchos", DISPATCH_QUEUE_SERIAL);
    nw_path_monitor_set_queue(s_monitor, queue);
    nw_path_monitor_set_update_handler(s_monitor, ^(nw_path_t _Nonnull path) {
      int32_t code = _code_for_path(path);
      int32_t previous = atomic_exchange(&s_current, code);
      // Only wake Dart when the answer actually changed. NWPathMonitor fires
      // on path details Dart cannot observe through this API, and every
      // spurious signal is an isolate wake-up on a watch.
      if (code != previous) {
        connectivity_plus_watchos_cb callback = atomic_load(&s_callback);
        if (callback != NULL) {
          callback(0);
        }
      }
    });
    nw_path_monitor_start(s_monitor);
  });
}

void connectivity_plus_watchos_set_callback(
    connectivity_plus_watchos_cb callback) {
  atomic_store(&s_callback, callback);
  // Registering is also what starts the monitor for a listener that subscribes
  // before anything has read the current value.
  _ensure_monitor();
}

int32_t connectivity_plus_watchos_current(void) {
  _ensure_monitor();
  return atomic_load(&s_current);
}
