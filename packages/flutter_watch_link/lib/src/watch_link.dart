// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'backend.dart';
// Web gets a stub with the same names; see ffi_backend_web.dart.
import 'ffi_backend_web.dart' if (dart.library.ffi) 'ffi_backend.dart';
import 'types.dart';

/// One WatchConnectivity session, with the same API on both devices.
///
/// A companion app's shared code can call this without knowing which device it
/// is running on — the backend is chosen at first use.
///
/// ```dart
/// final WatchLink link = WatchLink.instance;
/// await link.activate();
/// link.messages.listen((WatchLinkMessage m) => merge(m.payload));
/// await link.sendMessage(<String, Object?>{'tick': itemId});
/// ```
///
/// ## Choosing a tier
///
/// The three send methods are not variations on one idea; pick per situation:
///
/// | Situation | Method | Why |
/// |---|---|---|
/// | Counterpart reachable | [sendMessage] | Immediate. Throws, queueing nothing, if it is not. |
/// | Catching a cold device up | [updateApplicationContext] | Latest-wins, so one delivery replaces any backlog. |
/// | Edit that must not be lost | [transferUserInfo] | FIFO, survives the counterpart being closed. |
///
/// Most apps want all three: the live tier for responsiveness, the context
/// tier as a self-healing snapshot, and the queued tier for durability.
class WatchLink {
  WatchLink._();

  /// The shared instance.
  static final WatchLink instance = WatchLink._();

  static WatchLinkBackend? _backend;

  /// Replaces the platform backend with a fake.
  ///
  /// For tests only. Set it before the first call to any other member; pass
  /// null to restore the real backend.
  static set backendOverride(WatchLinkBackend? backend) => _backend = backend;

  /// The backend in use.
  ///
  /// There is no platform branch: iOS and watchOS compile the same native
  /// source and bind it the same way, so the phone and the watch run
  /// identical code. That is also why `registerWith()` does nothing — nothing
  /// depends on which registrant runs first, the failure that bit
  /// in_app_purchase_watchos.
  static WatchLinkBackend get backend => _backend ??= WatchLinkFfiBackend();

  /// Whether this device can run a session at all.
  ///
  /// False on an iPad, and on an iPhone with no paired watch. Always true on
  /// the watch. Check this before showing companion UI.
  Future<bool> isSupported() => backend.isSupported();

  /// Activates the session. Idempotent — call it once at app start.
  ///
  /// Every send fails until activation completes, so gate the first send on a
  /// [states] event with [WatchLinkState.activated] set rather than assuming
  /// this future resolving is enough.
  Future<void> activate() => backend.activate();

  /// Reads the session state once. Prefer [states] for anything long-lived.
  Future<WatchLinkState> readState() => backend.readState();

  /// Delivers [payload] to the counterpart immediately.
  ///
  /// Throws [WatchLinkException] with code `not-reachable` when the other app
  /// is not running — nothing is queued, so a caller that needs durability
  /// should fall back to [transferUserInfo]. See the class table.
  Future<void> sendMessage(Map<String, Object?> payload) =>
      backend.sendMessage(payload);

  /// Sends [payload] and waits for the counterpart to answer.
  ///
  /// Only possible while the counterpart app is running — a reply needs
  /// somebody there to write it — so this throws `not-reachable` in exactly the
  /// cases [sendMessage] does. The receiving side answers with
  /// [WatchLinkMessage.reply].
  ///
  /// Throws `reply-timeout` if no answer arrives within [timeout]. Prefer a
  /// one-way [sendMessage] plus your own idempotent merge where you can: a
  /// request that must be answered turns a dropped packet into a visible
  /// failure, whereas a one-way edit can simply be re-sent on the next tier.
  Future<Map<String, Object?>> sendMessageWithReply(
    Map<String, Object?> payload, {
    Duration timeout = const Duration(seconds: 30),
  }) =>
      backend.sendMessageWithReply(payload, timeout: timeout);

  /// Queues the file at [path] for delivery, with optional [metadata].
  ///
  /// FIFO and durable like [transferUserInfo], and the only tier that carries
  /// more than the ~65 kB a payload allows. Delivery timing is the system's to
  /// choose; treat it as eventual.
  Future<void> transferFile(String path, {Map<String, Object?>? metadata}) =>
      backend.transferFile(path, metadata: metadata);

  /// How many [transferFile] transfers are still undelivered.
  Future<int> outstandingFileTransferCount() =>
      backend.outstandingFileTransferCount();

  /// Files arriving from the counterpart.
  ///
  /// Each has already been copied somewhere durable — the system deletes its
  /// own copy the moment it hands it over — so the path is safe to read. It is
  /// also **yours to clean up**: nothing deletes it for you.
  Stream<WatchLinkFile> get files => backend.files;

  /// Replaces the shared application context with [payload].
  ///
  /// Latest-wins: each update discards the previous one, so this is a state
  /// snapshot, never an event stream. Its value is that a device which was
  /// off catches up in a single delivery instead of replaying a backlog.
  Future<void> updateApplicationContext(Map<String, Object?> payload) =>
      backend.updateApplicationContext(payload);

  /// Queues [payload] for guaranteed FIFO delivery.
  ///
  /// Survives the counterpart app being closed. Delivery timing is the
  /// system's to choose — treat it as eventual, not immediate.
  Future<void> transferUserInfo(Map<String, Object?> payload) =>
      backend.transferUserInfo(payload);

  /// The application context most recently *received*, or null.
  ///
  /// Persisted by the system across launches, so a cold-launched app should
  /// read this before its first frame to catch up without waiting on
  /// [messages].
  Future<Map<String, Object?>?> receivedApplicationContext() =>
      backend.receivedApplicationContext();

  /// The application context most recently *sent* from this device, or null.
  ///
  /// Also persisted across launches. Useful for skipping a redundant
  /// [updateApplicationContext] — the counterpart already holds this — and for
  /// showing what was last published without keeping a parallel copy.
  Future<Map<String, Object?>?> sentApplicationContext() =>
      backend.sentApplicationContext();

  /// How many [transferUserInfo] payloads are still undelivered.
  Future<int> outstandingTransferCount() => backend.outstandingTransferCount();

  /// Payloads arriving from the counterpart, from all three tiers.
  ///
  /// Each is tagged with the [WatchLinkTier] that carried it. Because the
  /// tiers have different ordering and delivery guarantees, a payload may
  /// arrive twice by different routes — design the receiver to be idempotent
  /// rather than trying to deduplicate here.
  Stream<WatchLinkMessage> get messages => backend.messages;

  /// Session state changes, starting with the current state.
  Stream<WatchLinkState> get states => backend.states;

  /// Failures that arrive after the call that caused them returned.
  ///
  /// Worth surfacing in any app that uses [sendMessage]: WCSession accepts the
  /// message and returns, then reports failure here. Ignoring this stream
  /// means a lost message is indistinguishable from a delivered one.
  Stream<String> get errors => backend.errors;

  /// Releases resources held by the backend. Rarely needed.
  Future<void> dispose() => backend.dispose();
}
