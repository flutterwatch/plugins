// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'types.dart';

/// The native half of a [WatchLink], behind an interface so tests can
/// substitute a fake without a native binary present.
///
/// App code does not use this directly; it uses [WatchLink].
abstract class WatchLinkBackend {
  /// Whether this device can run a WatchConnectivity session at all.
  ///
  /// False on an iPad, and on an iPhone that is not paired with a watch.
  Future<bool> isSupported();

  /// Activates the session. Idempotent — safe to call on every app start.
  Future<void> activate();

  /// Reads the current session state.
  Future<WatchLinkState> readState();

  /// Sends an immediate message. Throws [WatchLinkException] when the
  /// counterpart is not reachable — nothing is queued.
  Future<void> sendMessage(Map<String, Object?> payload);

  /// Sends [payload] and completes with the counterpart's reply.
  Future<Map<String, Object?>> sendMessageWithReply(
    Map<String, Object?> payload, {
    Duration timeout,
  });

  /// Queues [path] for delivery, with optional [metadata].
  Future<void> transferFile(String path, {Map<String, Object?>? metadata});

  /// How many file transfers the system has not yet delivered.
  Future<int> outstandingFileTransferCount();

  /// Files arriving from the counterpart.
  Stream<WatchLinkFile> get files;

  /// Replaces the application context with [payload].
  Future<void> updateApplicationContext(Map<String, Object?> payload);

  /// Queues [payload] for guaranteed FIFO delivery.
  Future<void> transferUserInfo(Map<String, Object?> payload);

  /// The application context most recently *received* from the counterpart,
  /// or null if none has arrived. Survives an app restart, so this is what a
  /// cold-launched app reads to catch up before any stream fires.
  Future<Map<String, Object?>?> receivedApplicationContext();

  /// The application context most recently *sent* from this device, or null
  /// if nothing has been sent. Also survives an app restart.
  Future<Map<String, Object?>?> sentApplicationContext();

  /// How many [transferUserInfo] transfers have not yet been delivered.
  Future<int> outstandingTransferCount();

  /// Payloads arriving from the counterpart, from every tier.
  Stream<WatchLinkMessage> get messages;

  /// Session state changes. Emits the current state on listen.
  Stream<WatchLinkState> get states;

  /// Failures that arrive *after* the call that caused them returned.
  ///
  /// `sendMessage` is the reason this exists: WCSession accepts the message,
  /// returns, and only later reports "Companion app is not installed" to a
  /// callback. Without this stream that failure is invisible and a lost
  /// message looks exactly like a delivered one.
  Stream<String> get errors;

  /// Releases native resources. Rarely needed — a session normally lives as
  /// long as the app.
  Future<void> dispose();
}
