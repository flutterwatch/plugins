// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// One WCSession, over dart:ffi, for **both** halves of a companion app.
//
// This file is compiled into the iPhone app and the Apple Watch app alike;
// `ios/Classes` and `watchos/Classes` each hold a one-line shim that includes
// it. WatchConnectivity is very nearly the same API on both platforms, so the
// differences are a handful of TARGET_OS_WATCH branches rather than two
// parallel implementations that drift.
//
// Payloads cross as JSON object strings. On the wire each one travels as the
// single value of a reserved WCSession dictionary key, so both halves of the
// session use one encoder and property-list coercion never sees app data.

#ifndef FLUTTER_WATCHOS_CONNECTIVITY_FFI_H
#define FLUTTER_WATCHOS_CONNECTIVITY_FFI_H

#include <stdint.h>

// Each exported symbol is marked `used` + default-visibility so it survives
// the linker's `-dead_strip` and lands in the executable's dynamic symbol
// table, where `DynamicLibrary.process()` / dlsym can resolve it.
#define FWL_EXPORT __attribute__((visibility("default"))) __attribute__((used))

// Result codes. Mirrored in lib/src/codec.dart.
#define FWL_OK 0
#define FWL_NOT_ACTIVATED (-1)
#define FWL_NOT_REACHABLE (-2)
#define FWL_INVALID_PAYLOAD (-3)
#define FWL_NATIVE_ERROR (-4)

// Bit positions in the packed state word returned by `..._state()`.
//
// PAIRED and INSTALLED are deliberately separate. Collapsing them loses the
// difference between "no watch is paired with this phone" and "a watch is
// paired but does not have the app", which are different things to tell the
// user to do about it.
#define FWL_BIT_ACTIVATED (1 << 0)
#define FWL_BIT_REACHABLE (1 << 1)
#define FWL_BIT_COUNTERPART_INSTALLED (1 << 2)
#define FWL_BIT_COUNTERPART_PAIRED (1 << 3)

// What woke Dart up. Mirrored in lib/src/codec.dart.
#define FWL_SIGNAL_INBOUND 1
#define FWL_SIGNAL_STATE 2
#define FWL_SIGNAL_ERROR 3

// Called from whatever thread a WCSession delegate callback arrived on.
//
// It carries a *kind*, never a payload. That is deliberate: the Dart end is a
// `NativeCallable.listener`, which is asynchronous — this function returns
// before Dart runs — so any pointer handed over here could be freed before it
// was read. Dart treats the call purely as "something changed" and pulls the
// data back through `..._poll_inbound` / `..._state` / `..._take_last_error`,
// which are synchronous and safe.
typedef void (*fwl_signal_callback)(int64_t kind);

// Registers the callback Dart wants woken, or NULL to stop signalling.
//
// Safe to call before or after `..._activate`. Anything buffered before
// registration is still delivered, because Dart drains the buffer once on
// registration rather than relying on a signal it may have missed.
FWL_EXPORT
void flutter_watch_link_set_callback(fwl_signal_callback callback);

// Activates `WCSession.default` and installs the delegate. Idempotent; safe to
// call on every app start. Activation is asynchronous — wait for a
// FWL_SIGNAL_STATE signal, or read `..._state()`, rather than assuming this
// returning means it is ready.
FWL_EXPORT
void flutter_watch_link_activate(void);

// Whether this device can run a session at all. On iPhone this is false
// without a paired watch; on the watch it is always true.
FWL_EXPORT
int flutter_watch_link_is_supported(void);

// The packed session state (see the FWL_BIT_* masks). Zero before activation.
FWL_EXPORT
int flutter_watch_link_state(void);

// `json` must be a JSON *object* string; each returns one of the FWL_* codes.
//
// `send_message` reports FWL_NOT_REACHABLE rather than queueing, matching
// WCSession's own semantics. It returns once the message is handed to the
// system: a failure after that point surfaces asynchronously through
// `..._take_last_error`, which is why a companion app also carries a snapshot
// on the application-context tier.
FWL_EXPORT
int flutter_watch_link_send_message(const char* json);
FWL_EXPORT
int flutter_watch_link_update_application_context(const char* json);
FWL_EXPORT
int flutter_watch_link_transfer_user_info(const char* json);

// Sends `json` and asks the counterpart to reply.
//
// The reply cannot come back through this function's return value — it arrives
// on a WCSession callback long afterwards — so it is correlated by
// `correlation_id` and delivered through the inbound buffer as a `reply` or
// `replyError` envelope. Dart holds the pending future against that id.
FWL_EXPORT
int flutter_watch_link_send_message_with_reply(const char* json,
                                                         int64_t correlation_id);

// Answers a received message that carried a `replyId`.
//
// WCSession hands the receiver a one-shot reply block and expects it promptly;
// the block is held natively until this is called. Answering an unknown or
// already-answered id returns FWL_INVALID_PAYLOAD rather than crashing, since
// a late reply after the timeout below is a normal race, not a programming
// error.
FWL_EXPORT
int flutter_watch_link_respond(int64_t reply_id, const char* json);

// Queues a file for delivery, with optional JSON-object `metadata_json`.
//
// Survives the counterpart app being closed, like the user-info tier, and is
// the only tier that carries more than the ~65 kB a payload allows.
FWL_EXPORT
int flutter_watch_link_transfer_file(const char* path,
                                               const char* metadata_json);

// Count of file transfers the system has not yet delivered.
FWL_EXPORT
int flutter_watch_link_outstanding_file_transfer_count(void);

// The application context most recently received, as a JSON object string, or
// NULL if none has arrived. The system persists this across launches.
// Caller owns the result — free it with `..._free`.
FWL_EXPORT
char* flutter_watch_link_application_context(void);

// The application context most recently *sent* from this device, as a JSON
// object string, or NULL if nothing has been sent. Also persisted across
// launches, so a cold-launched app can read back what the counterpart already
// has and skip re-sending it. Caller owns the result — free it with
// `..._free`.
FWL_EXPORT
char* flutter_watch_link_sent_application_context(void);

// How long a received message's reply block is held before it is answered with
// an empty dictionary and discarded. WCSession expects the block promptly, and
// an app that never replies must not leave the *sender* waiting forever.
#define FWL_REPLY_TIMEOUT_SECONDS 30

// Removes and returns the oldest buffered inbound envelope, or NULL when the
// buffer is empty. Caller owns the result — free it with `..._free`.
//
// One of:
//   {"tier":"message"|"applicationContext"|"userInfo","payload":{...},
//    "replyId":N}          — replyId present only when a reply is expected
//   {"tier":"reply","correlationId":N,"payload":{...}}
//   {"tier":"replyError","correlationId":N,"error":"..."}
//   {"tier":"file","path":"...","metadata":{...}}
//
// Replies and files share this one buffer on purpose: it keeps a single drain
// path, so an app that stops reading cannot starve one kind of delivery while
// draining another.
//
// The ring buffer survives the move to push delivery on purpose: a burst of
// deliveries can still outrun the isolate, and a bounded buffer with a drop
// counter is a better failure mode than unbounded growth.
FWL_EXPORT
char* flutter_watch_link_poll_inbound(void);

// Count of `transferUserInfo` transfers the system has not yet delivered.
FWL_EXPORT
int flutter_watch_link_outstanding_transfer_count(void);

// Count of inbound payloads dropped because the ring buffer was full — i.e.
// payloads arrived faster than Dart drained them. Monotonic for the life of
// the process.
FWL_EXPORT
int flutter_watch_link_dropped_inbound_count(void);

// Removes and returns the most recent *asynchronous* failure, or NULL if there
// has been none since the last call. Caller owns the result — free it with
// `..._free`.
//
// This exists because `sendMessage` reports failure to a callback long after
// it has returned: WCSession accepts the send, then fails it with e.g.
// "Companion app is not installed". Without this, that failure is invisible
// to Dart and a lost message looks exactly like a delivered one.
FWL_EXPORT
char* flutter_watch_link_take_last_error(void);

// Frees a string returned by `..._application_context`, `..._poll_inbound` or
// `..._take_last_error`.
FWL_EXPORT
void flutter_watch_link_free(char* value);

#endif  // FLUTTER_WATCHOS_CONNECTIVITY_FFI_H
