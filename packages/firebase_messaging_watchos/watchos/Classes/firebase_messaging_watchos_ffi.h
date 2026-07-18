// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// C symbols exported to Dart over dart:ffi. Every function that returns a
// `const char *` returns a freshly heap-allocated UTF-8 JSON string; ownership
// transfers to the caller, which must release it with
// `firebase_messaging_watchos_free`. Errors are reported in-band as
// `{"error": message, "code": code}`.
//
// The APNs device token reaches the process through the app-level
// WKApplicationDelegate; the flutter-watchos runner's
// FlutterWatchOSAppDelegate rebroadcasts those callbacks as NSNotifications,
// which this plugin observes to hand the token to FirebaseMessaging.

#ifndef FIREBASE_MESSAGING_WATCHOS_FFI_H
#define FIREBASE_MESSAGING_WATCHOS_FFI_H

#include <stdint.h>

// Each exported symbol is marked `used` + default-visibility so it survives
// the linker's `-dead_strip` and lands in the executable's dynamic symbol
// table, where `DynamicLibrary.process()` / dlsym can resolve it. The watch
// app links this archive statically, so without the attributes the linker
// would drop these (FFI has no compile-time caller). The CLI additionally
// emits a forced reference for each symbol listed under
// `flutter.plugin.platforms.watchos.ffiSymbols`.
#define FIREBASE_MESSAGING_WATCHOS_EXPORT \
  __attribute__((visibility("default"))) __attribute__((used))

// Starts an asynchronous operation. `request_json` is a JSON object with at
// least {"op": name}; op-specific arguments ride along. Supported ops:
// requestPermission, getNotificationSettings, getToken, deleteToken,
// subscribeToTopic, unsubscribeFromTopic. Returns {"token": N} or an error.
FIREBASE_MESSAGING_WATCHOS_EXPORT const char* firebase_messaging_watchos_begin(
    const char* request_json);

// Polls an operation started by `firebase_messaging_watchos_begin`. Returns
// {"pending": true} until the operation completes, then the result exactly
// once.
FIREBASE_MESSAGING_WATCHOS_EXPORT const char* firebase_messaging_watchos_poll(
    int64_t token);

// Reads the plugin's current state:
// {"tokenGeneration": n, "fcmToken": ... | null, "apnsToken": hex | null,
//  "apnsError": ... | null}. tokenGeneration increments whenever the FCM
// token changes, letting the Dart side drive onTokenRefresh by polling.
FIREBASE_MESSAGING_WATCHOS_EXPORT const char* firebase_messaging_watchos_state(void);

// Drains queued messages. `kind` is "foreground" (messages received while
// the app was frontmost -> onMessage), "opened" (notification taps ->
// onMessageOpenedApp), or "initial" (the tap that launched the app;
// returned once as {"message": {...} | null}). Queue kinds return
// {"messages": [...]}.
FIREBASE_MESSAGING_WATCHOS_EXPORT const char* firebase_messaging_watchos_take_messages(
    const char* kind);

// Synchronous configuration:
// {"op": "registerForRemoteNotifications"} |
// {"op": "setAutoInit", "enabled": bool} | {"op": "getAutoInit"} |
// {"op": "setForegroundPresentation", "alert": bool, "badge": bool,
//  "sound": bool}.
// Returns {"ok": true} (getAutoInit: {"enabled": bool}) or an error.
FIREBASE_MESSAGING_WATCHOS_EXPORT const char* firebase_messaging_watchos_configure(
    const char* request_json);

// Releases a string previously returned by any of the functions above.
FIREBASE_MESSAGING_WATCHOS_EXPORT void firebase_messaging_watchos_free(
    const char* ptr);

#endif  // FIREBASE_MESSAGING_WATCHOS_FFI_H
