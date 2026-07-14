// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "package_info_plus_watchos_ffi.h"

#import <Foundation/Foundation.h>

#include <string.h>

// Bundle metadata is constant for the process lifetime, so each getter
// resolves once and caches a heap copy. The `strdup`'d strings are never
// freed by design — one small allocation per key, owned by the plugin.
static const char* _cached_bundle_string(NSString* key, NSString* fallbackKey) {
  @autoreleasepool {
    NSBundle* bundle = [NSBundle mainBundle];
    id value = [bundle objectForInfoDictionaryKey:key];
    if (value == nil && fallbackKey != nil) {
      value = [bundle objectForInfoDictionaryKey:fallbackKey];
    }
    NSString* string = [value isKindOfClass:[NSString class]] ? value : @"";
    return strdup(string.UTF8String);
  }
}

const char* package_info_plus_watchos_app_name(void) {
  static const char* value = NULL;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    value = _cached_bundle_string(@"CFBundleDisplayName", @"CFBundleName");
  });
  return value;
}

const char* package_info_plus_watchos_package_name(void) {
  static const char* value = NULL;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    value = _cached_bundle_string(@"CFBundleIdentifier", nil);
  });
  return value;
}

const char* package_info_plus_watchos_version(void) {
  static const char* value = NULL;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    value = _cached_bundle_string(@"CFBundleShortVersionString", nil);
  });
  return value;
}

const char* package_info_plus_watchos_build_number(void) {
  static const char* value = NULL;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    value = _cached_bundle_string(@"CFBundleVersion", nil);
  });
  return value;
}
