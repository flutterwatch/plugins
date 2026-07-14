// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "shared_preferences_watchos_ffi.h"

#import <Foundation/Foundation.h>

#include <stdlib.h>
#include <string.h>

// One NSUserDefaults key holds the whole store as a JSON string. Keeping the
// plugin's data in a single private key (rather than scattering typed keys
// across the shared NSUserDefaults namespace) means get-all never has to
// distinguish our keys from the system's.
static NSString* const kStoreKey = @"flutterwatch.shared_preferences.store";

const char* shared_preferences_watchos_load(void) {
  @autoreleasepool {
    NSString* json = [[NSUserDefaults standardUserDefaults] stringForKey:kStoreKey];
    if (json == nil || json.length == 0) {
      json = @"{}";
    }
    // Fresh copy every call (the store mutates between calls); Dart frees it
    // via shared_preferences_watchos_free.
    return strdup(json.UTF8String);
  }
}

void shared_preferences_watchos_save(const char* json) {
  @autoreleasepool {
    if (json == NULL) {
      return;
    }
    NSString* value = [NSString stringWithUTF8String:json];
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if (value == nil) {
      return;
    }
    [defaults setObject:value forKey:kStoreKey];
  }
}

void shared_preferences_watchos_free(char* ptr) {
  if (ptr != NULL) {
    free(ptr);
  }
}
