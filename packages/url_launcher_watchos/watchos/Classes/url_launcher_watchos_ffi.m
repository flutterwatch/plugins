// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "url_launcher_watchos_ffi.h"

#import <AuthenticationServices/AuthenticationServices.h>
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

// The on-watch browser session. ASWebAuthenticationSession must be kept alive
// by the caller for as long as its sheet is up, and this is the only owner.
static ASWebAuthenticationSession* _browserSession = nil;

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

// Sends a web URL to the paired iPhone. Main thread only.
static void _hand_off(NSURL* url) {
  // Both calls, deliberately.
  //
  // openSystemURL: DOES accept http/https (the docs only mention tel:
  // and sms:) and presents the system web sheet. Verified on a physical
  // Apple Watch Ultra 3, watchOS 26.5: for a third-party app that sheet
  // declines to render and shows "URL failed to load — this url can be
  // viewed on your iPhone", for `example.com` as much as for anything
  // else. watchOS DOES have a browser (WebSheet.framework, which Weather
  // and Mail use) but does not vend it to us.
  //
  // That refusal is still the best thing to show: it tells the user, on
  // the wrist, that the link is going to their phone. Publishing the
  // Handoff activity silently would leave them staring at nothing.
  // So: openSystemURL for the visible prompt, NSUserActivity so the
  // phone actually has something to pick up.
  [[WKApplication sharedApplication] openSystemURL:url];
  [_handoffActivity invalidate];
  NSUserActivity* activity = [[NSUserActivity alloc]
      initWithActivityType:NSUserActivityTypeBrowsingWeb];
  activity.webpageURL = url;
  activity.eligibleForHandoff = YES;
  [activity becomeCurrent];
  _handoffActivity = activity;
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
        _hand_off(parsed);
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

int url_launcher_watchos_open_in_app(const char* url) {
  @autoreleasepool {
    NSURL* parsed = _url_from_utf8(url);
    if (parsed == nil || !_is_web_scheme(parsed.scheme.lowercaseString)) {
      return 0;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      // ASWebAuthenticationSession is the one public API that shows a web page
      // on the watch: it presents the system browser (SafariViewService), with
      // an address bar, a close button, and links that navigate.
      //
      // It exists for sign-in, so two choices here are about using it as a
      // browser. There is no callback scheme, so no page can end the session;
      // only the user's close button does. And the session is ephemeral: a
      // persistent one first asks "<App> wants to use <site> to sign in",
      // which is wrong for a link, and the ephemeral one shows no prompt.
      // The price is that cookies and logins do not outlive the sheet.
      //
      // Verified on the watchOS 26.5 Simulator: example.com renders and its
      // "Learn more" link loads iana.org.
      [_browserSession cancel];
      // Weak, so the session's own completion block does not keep it alive.
      __block __weak ASWebAuthenticationSession* weakSession = nil;
      ASWebAuthenticationSession* session = [[ASWebAuthenticationSession alloc]
                initWithURL:parsed
          callbackURLScheme:nil
          completionHandler:^(NSURL* callbackURL, NSError* error) {
            // Fires when the user closes the sheet (CanceledLogin).
            if (_browserSession == weakSession) {
              _browserSession = nil;
            }
          }];
      weakSession = session;
      session.prefersEphemeralWebBrowserSession = YES;
      if ([session start]) {
        _browserSession = session;
      } else {
        // Refused (another sheet is up, or the app is not in front). Do not
        // leave the tap with no visible effect; fall back to the iPhone.
        _hand_off(parsed);
      }
    });
    return 1;
  }
}

void url_launcher_watchos_close_in_app(void) {
  @autoreleasepool {
    dispatch_async(dispatch_get_main_queue(), ^{
      [_browserSession cancel];
      _browserSession = nil;
    });
  }
}
