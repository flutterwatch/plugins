// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "battery_plus_watchos_ffi.h"

#import <Foundation/Foundation.h>
#import <WatchKit/WatchKit.h>

// WKInterfaceDevice's battery properties are UI-adjacent; read them on the
// main thread. The Dart UI isolate runs on its own thread, so a dispatch to
// main is safe (the platform main thread is not blocked on us).
static void _run_on_main(void (^block)(void)) {
  if ([NSThread isMainThread]) {
    block();
  } else {
    dispatch_sync(dispatch_get_main_queue(), block);
  }
}

// Battery monitoring must be enabled before WKInterfaceDevice returns a
// level/state; enable it once, on the main thread.
static void _ensure_monitoring(void) {
  _run_on_main(^{
    WKInterfaceDevice* device = [WKInterfaceDevice currentDevice];
    if (!device.batteryMonitoringEnabled) {
      device.batteryMonitoringEnabled = YES;
    }
  });
}

int32_t battery_plus_watchos_level(void) {
  _ensure_monitoring();
  __block float level = -1.0f;
  _run_on_main(^{
    level = [WKInterfaceDevice currentDevice].batteryLevel;
  });
  if (level < 0.0f) {
    return -1;
  }
  return (int32_t)(level * 100.0f + 0.5f);
}

int32_t battery_plus_watchos_state(void) {
  _ensure_monitoring();
  __block WKInterfaceDeviceBatteryState state = WKInterfaceDeviceBatteryStateUnknown;
  _run_on_main(^{
    state = [WKInterfaceDevice currentDevice].batteryState;
  });
  return (int32_t)state;
}

int32_t battery_plus_watchos_is_low_power(void) {
  if (@available(watchOS 9.0, *)) {
    return [NSProcessInfo processInfo].isLowPowerModeEnabled ? 1 : 0;
  }
  return 0;
}
