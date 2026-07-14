// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "device_info_plus_watchos_ffi.h"

#import <Foundation/Foundation.h>
#import <WatchKit/WatchKit.h>

#include <string.h>
#include <sys/utsname.h>

static NSString* _machineIdentifier(void) {
  // On the simulator `uname().machine` reports the host Mac arch, so prefer
  // the model id the simulator advertises, matching the flutter_watchos FFI
  // package's behaviour.
#if TARGET_OS_SIMULATOR
  const char* simModel = getenv("SIMULATOR_MODEL_IDENTIFIER");
  if (simModel && simModel[0] != '\0') {
    return [NSString stringWithUTF8String:simModel];
  }
#endif
  struct utsname systemInfo;
  uname(&systemInfo);
  return [NSString stringWithUTF8String:systemInfo.machine];
}

static NSDictionary* _utsnameMap(void) {
  struct utsname u;
  uname(&u);
  NSString* (^s)(const char*) = ^NSString*(const char* c) {
    return c ? [NSString stringWithUTF8String:c] : @"";
  };
  return @{
    @"sysname" : s(u.sysname),
    @"nodename" : s(u.nodename),
    @"release" : s(u.release),
    @"version" : s(u.version),
    @"machine" : _machineIdentifier(),
  };
}

const char* device_info_plus_watchos_info_json(void) {
  static const char* json = NULL;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    @autoreleasepool {
      WKInterfaceDevice* device = [WKInterfaceDevice currentDevice];

      NSString* vendorId = [[device identifierForVendor] UUIDString] ?: @"";

      NSProcessInfo* processInfo = [NSProcessInfo processInfo];
      unsigned long long physicalRam = processInfo.physicalMemory;

      unsigned long long totalDisk = 0;
      unsigned long long freeDisk = 0;
      NSError* diskError = nil;
      NSDictionary* attrs =
          [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory()
                                                                  error:&diskError];
      if (attrs != nil) {
        totalDisk = [attrs[NSFileSystemSize] unsignedLongLongValue];
        freeDisk = [attrs[NSFileSystemFreeSize] unsignedLongLongValue];
      }

#if TARGET_OS_SIMULATOR
      BOOL isPhysical = NO;
#else
      BOOL isPhysical = YES;
#endif

      NSString* machine = _machineIdentifier();
      NSDictionary* info = @{
        @"name" : device.name ?: @"",
        @"systemName" : device.systemName ?: @"watchOS",
        @"systemVersion" : device.systemVersion ?: @"",
        @"model" : device.model ?: @"Apple Watch",
        // device_info_plus expects a human-facing modelName; watchOS has no
        // marketing-name API, so fall back to the machine identifier.
        @"modelName" : machine,
        @"localizedModel" : device.localizedModel ?: @"Apple Watch",
        @"identifierForVendor" : vendorId,
        @"isPhysicalDevice" : @(isPhysical),
        @"physicalRamSize" : @(physicalRam),
        // No per-app available-RAM API on watchOS; report physical RAM so
        // the non-nullable field is populated.
        @"availableRamSize" : @(physicalRam),
        @"freeDiskSize" : @(freeDisk),
        @"totalDiskSize" : @(totalDisk),
        // These describe iOS-app-on-other-platform contexts that cannot
        // occur on a watch.
        @"isiOSAppOnMac" : @(NO),
        @"isiOSAppOnVision" : @(NO),
        @"utsname" : _utsnameMap(),
      };

      NSData* data = [NSJSONSerialization dataWithJSONObject:info options:0 error:nil];
      NSString* string = data
          ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
          : @"{}";
      json = strdup(string.UTF8String);
    }
  });
  return json;
}
