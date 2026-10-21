// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `flutter_local_notifications`, over dart:ffi.
//
// Local notifications through UNUserNotificationCenter. The flutter-watchos
// host owns the notification-center delegate and rebroadcasts its callbacks
// as NSNotifications; this file observes them from the moment the binary
// loads, so the tap that launched the app is not missed, answers
// "will present" from the flags stored in each notification, and queues
// taps for Dart.
//
// The asynchronous UserNotifications calls return a request id at once; a
// FLNW_SIGNAL_REQUEST signal says one finished and
// `..._take_request_result` hands its JSON over. Taps queue as events
// behind FLNW_SIGNAL_RESPONSES. Strings are JSON that native allocates and
// `..._release` releases.

#ifndef FLUTTER_LOCAL_NOTIFICATIONS_WATCHOS_FFI_H
#define FLUTTER_LOCAL_NOTIFICATIONS_WATCHOS_FFI_H

#include <stdint.h>

// Each exported symbol is marked `used` + default-visibility so it survives
// the linker's `-dead_strip` and lands in the executable's dynamic symbol
// table, where `DynamicLibrary.process()` / dlsym can resolve it.
#define FLNW_EXPORT __attribute__((visibility("default"))) __attribute__((used))

// What woke Dart up. Mirrored in lib/src/backend.dart.
#define FLNW_SIGNAL_REQUEST 1
#define FLNW_SIGNAL_RESPONSES 2

typedef void (*flnw_signal_callback)(int64_t kind);

FLNW_EXPORT
void flutter_local_notifications_watchos_set_callback(flnw_signal_callback callback);

// Sets the categories and the default presentation flags, starts handing
// taps to Dart instead of keeping them as the launch tap, and asks for the
// permissions the settings request. `json` is {"categories": [{"identifier",
// "actions": [{"identifier", "title", "options"}], "options"}],
// "defaults": {"presentAlert", "presentSound", "presentBadge",
// "presentBanner", "presentList"}, "request": {"alert", "sound", "badge",
// "provisional", "critical"}}. Result: {"granted": <bool>}.
FLNW_EXPORT
int64_t flutter_local_notifications_watchos_initialize(const char* json);

// `json` is {"alert", "sound", "badge", "provisional", "critical"}.
// Result: {"granted": <bool>}.
FLNW_EXPORT
int64_t flutter_local_notifications_watchos_request_permissions(const char* json);

// Result: {"isEnabled", "isAlertEnabled", "isSoundEnabled",
// "isBadgeEnabled", "isProvisionalEnabled", "isCriticalEnabled"}.
FLNW_EXPORT
int64_t flutter_local_notifications_watchos_check_permissions(void);

// Adds a notification request. `json` is {"id", "title", "body", "payload",
// "details": {...DarwinNotificationDetails...}, "trigger": {"type": "now"} |
// {"type": "calendar", "epochMs", "timeZone", "match"} | {"type":
// "interval", "seconds", "repeats"}}. Result: {}.
FLNW_EXPORT
int64_t flutter_local_notifications_watchos_add(const char* json);

// Removes `notification` (its id), pending and delivered.
FLNW_EXPORT
void flutter_local_notifications_watchos_cancel(int64_t notification);

// Removes every notification this app scheduled or delivered; with
// `pending_only` nonzero, only those not yet delivered.
FLNW_EXPORT
void flutter_local_notifications_watchos_cancel_all(int pending_only);

// Result: a JSON array of {"id", "title", "body", "payload"}.
FLNW_EXPORT
int64_t flutter_local_notifications_watchos_pending(void);

// Result: a JSON array of {"id", "title", "body", "payload",
// "threadIdentifier"}.
FLNW_EXPORT
int64_t flutter_local_notifications_watchos_active(void);

// {"launched": <bool>, "response": {"id", "actionId", "payload", "type"} or
// null}: the tap that launched the app, if it arrived before this was first
// asked and before `initialize`. A tap after that queues for the response
// callback instead, so it is never lost.
FLNW_EXPORT
char* flutter_local_notifications_watchos_launch_details(void);

// Drains the queued taps (all but the launch tap), as a JSON array of {"id",
// "actionId", "payload", "type"}; NULL when none are queued.
FLNW_EXPORT
char* flutter_local_notifications_watchos_poll_responses(void);

// The result of `request` as JSON, or NULL while it runs. A failed
// request is {"error": {"code", "message"}}.
FLNW_EXPORT
char* flutter_local_notifications_watchos_take_request_result(int64_t request);

// Releases a string this file returned.
FLNW_EXPORT
void flutter_local_notifications_watchos_release(char* string);

#endif  // FLUTTER_LOCAL_NOTIFICATIONS_WATCHOS_FFI_H
