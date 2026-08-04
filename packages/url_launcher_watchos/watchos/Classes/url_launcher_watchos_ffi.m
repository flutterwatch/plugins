// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "url_launcher_watchos_ffi.h"

#import <Foundation/Foundation.h>
#import <WatchKit/WatchKit.h>

// Schemes -[WKApplication openSystemURL:] owns. Keep this list conservative:
// openSystemURL returns void, so an unowned scheme fails silently and we
// would have no way to tell the caller.
static BOOL _is_system_scheme(NSString* scheme) {
  return [scheme isEqualToString:@"tel"] || [scheme isEqualToString:@"sms"];
}

static BOOL _is_web_scheme(NSString* scheme) {
  return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
}

// The activity is held so it can be invalidated later; watchOS keeps a
// published activity current until it is replaced or invalidated.
static NSUserActivity* _handoffActivity = nil;

static NSURL* _url_from_utf8(const char* url) {
  if (url == NULL) {
    return nil;
  }
  NSString* string = [NSString stringWithUTF8String:url];
  if (string.length == 0) {
    return nil;
  }
  NSURL* parsed = [NSURL URLWithString:string];
  return parsed.scheme.length > 0 ? parsed : nil;
}

int url_launcher_watchos_can_launch(const char* url) {
  @autoreleasepool {
    NSURL* parsed = _url_from_utf8(url);
    if (parsed == nil) {
      return 0;
    }
    NSString* scheme = parsed.scheme.lowercaseString;
    return (_is_system_scheme(scheme) || _is_web_scheme(scheme)) ? 1 : 0;
  }
}

int url_launcher_watchos_launch(const char* url) {
  @autoreleasepool {
    NSURL* parsed = _url_from_utf8(url);
    if (parsed == nil) {
      return 0;
    }
    NSString* scheme = parsed.scheme.lowercaseString;

    if (_is_system_scheme(scheme)) {
      // openSystemURL is main-thread-only (NS_SWIFT_UI_ACTOR). FFI calls
      // arrive on the Dart UI thread, which is NOT the platform main thread,
      // so hop explicitly.
      dispatch_async(dispatch_get_main_queue(), ^{
        [[WKApplication sharedApplication] openSystemURL:parsed];
      });
      return 1;
    }

    if (_is_web_scheme(scheme)) {
      dispatch_async(dispatch_get_main_queue(), ^{
        [_handoffActivity invalidate];
        NSUserActivity* activity = [[NSUserActivity alloc]
            initWithActivityType:NSUserActivityTypeBrowsingWeb];
        activity.webpageURL = parsed;
        activity.eligibleForHandoff = YES;
        [activity becomeCurrent];
        _handoffActivity = activity;
      });
      return 1;
    }

    return 0;
  }
}

void url_launcher_watchos_close_handoff(void) {
  @autoreleasepool {
    dispatch_async(dispatch_get_main_queue(), ^{
      [_handoffActivity invalidate];
      _handoffActivity = nil;
    });
  }
}
