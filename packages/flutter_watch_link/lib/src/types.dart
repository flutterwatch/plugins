// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Which WatchConnectivity transport delivered a payload.
///
/// The three tiers are not interchangeable — they differ in latency, ordering,
/// and whether delivery survives the counterpart app being closed. A companion
/// app normally uses all three, picking per situation rather than settling on
/// one. See the package README for the decision table.
enum WatchLinkTier {
  /// `sendMessage` — immediate, and only possible while the counterpart app is
  /// running and reachable. Fails outright otherwise; nothing is queued.
  message,

  /// `updateApplicationContext` — a single latest-wins dictionary. Each update
  /// replaces the previous one, so a device that was off catches up in one
  /// delivery instead of replaying history. Never use it for a stream of
  /// events: intermediate values are dropped by design.
  applicationContext,

  /// `transferUserInfo` — FIFO queue, delivered even if the counterpart app is
  /// not running. The right tier for edits that must not be lost.
  userInfo,

  /// `transferFile` — FIFO like [userInfo], and the only tier that carries
  /// more than the ~65 kB a payload allows. Arrives on
  /// [WatchLink.files] rather than [WatchLink.messages], because a file is a
  /// path plus metadata, not a payload.
  file,
}

/// Answers a message whose sender is waiting for a reply.
typedef WatchLinkResponder = Future<void> Function(Map<String, Object?> reply);

/// A payload that arrived from the counterpart device, tagged with the
/// transport that carried it.
class WatchLinkMessage {
  /// Creates a message. Exposed for tests and fake backends.
  const WatchLinkMessage({
    required this.payload,
    required this.tier,
    this.replyId,
    WatchLinkResponder? responder,
  }) : _responder = responder;

  /// The decoded payload, exactly as the sender passed it.
  final Map<String, Object?> payload;

  /// The transport that delivered [payload].
  final WatchLinkTier tier;

  /// Correlates this message with the sender's waiting reply handler, or null
  /// when the sender is not expecting one.
  final int? replyId;

  final WatchLinkResponder? _responder;

  /// Whether the sender is waiting for [reply].
  bool get expectsReply => replyId != null;

  /// Answers the sender.
  ///
  /// Only meaningful when [expectsReply]; a no-op otherwise. Answer promptly —
  /// the native side holds the sender's one-shot reply block, and gives up
  /// after 30 seconds so a silent receiver cannot leave the sender waiting for
  /// ever. A late reply is discarded, not an error.
  Future<void> reply(Map<String, Object?> payload) async {
    final WatchLinkResponder? responder = _responder;
    if (responder == null || replyId == null) {
      return;
    }
    await responder(payload);
  }

  @override
  String toString() => 'WatchLinkMessage(${tier.name}, $payload'
      '${expectsReply ? ', expects reply' : ''})';
}

/// A file that arrived from the counterpart device.
class WatchLinkFile {
  /// Creates a received file. Exposed for tests and fake backends.
  const WatchLinkFile({required this.path, required this.metadata});

  /// Where the file now lives, inside this app's documents directory.
  ///
  /// The system hands the file over in a temporary location it deletes
  /// immediately, so the plugin copies it somewhere durable before telling
  /// Dart about it. **Nothing cleans this up for you** — move or delete it once
  /// you have consumed it, or the directory grows without bound.
  final String path;

  /// Whatever the sender attached; empty when it sent none.
  final Map<String, Object?> metadata;

  @override
  String toString() => 'WatchLinkFile($path, $metadata)';
}

/// A snapshot of the session's connection state.
///
/// The flags answer different questions and are deliberately not collapsed
/// into one "connected" boolean: an app can be installed on the counterpart
/// but not running ([counterpartInstalled] without [reachable]), which is
/// precisely when [WatchLinkTier.userInfo] is the right choice — and a phone
/// can have no watch at all ([counterpartPaired] false), which is a different
/// thing to tell the user about than a watch missing the app.
class WatchLinkState {
  /// Creates a state snapshot. Exposed for tests and fake backends.
  const WatchLinkState({
    required this.activated,
    required this.reachable,
    required this.counterpartInstalled,
    required this.counterpartPaired,
  });

  /// Nothing known yet — the session has not finished activating.
  static const WatchLinkState unknown = WatchLinkState(
    activated: false,
    reachable: false,
    counterpartInstalled: false,
    counterpartPaired: false,
  );

  /// Whether the session reached `WCSessionActivationStateActivated`.
  ///
  /// Until this is true every send throws; call [WatchLink.activate] once at
  /// startup and wait for it.
  final bool activated;

  /// Whether the counterpart app is running and can receive a
  /// [WatchLinkTier.message] right now.
  final bool reachable;

  /// Whether this package's app is installed on the counterpart device.
  ///
  /// Named neutrally on purpose. The underlying API is not symmetric: the
  /// phone side exposes `isPaired` plus `isWatchAppInstalled`, while the watch
  /// side has only `isCompanionAppInstalled`. Rather than pretend the phone
  /// API exists on the watch, both sides report the one question that has a
  /// meaningful answer on each — "is there an app over there to talk to".
  final bool counterpartInstalled;

  /// Whether a counterpart device is paired at all.
  ///
  /// On the phone this is `WCSession.isPaired` — false when the user owns no
  /// Apple Watch. On the watch it is always true, because a watch running this
  /// code is by definition paired to an iPhone.
  ///
  /// Kept separate from [counterpartInstalled] because the remedies differ:
  /// unpaired means "pair a watch", paired-but-not-installed means "install
  /// the app on it". Use [counterpartReady] when all you need is whether a
  /// send has somewhere to land.
  final bool counterpartPaired;

  /// Whether there is a counterpart app for a send to reach at all.
  ///
  /// Does **not** imply [reachable] — the app may be installed but not
  /// running, which is what the queueing tiers are for.
  bool get counterpartReady => counterpartPaired && counterpartInstalled;

  @override
  bool operator ==(Object other) =>
      other is WatchLinkState &&
      other.activated == activated &&
      other.reachable == reachable &&
      other.counterpartInstalled == counterpartInstalled &&
      other.counterpartPaired == counterpartPaired;

  @override
  int get hashCode => Object.hash(
        activated,
        reachable,
        counterpartInstalled,
        counterpartPaired,
      );

  @override
  String toString() => 'WatchLinkState(activated: $activated, '
      'reachable: $reachable, counterpartInstalled: $counterpartInstalled, '
      'counterpartPaired: $counterpartPaired)';
}

/// Thrown when the underlying `WCSession` refuses an operation.
class WatchLinkException implements Exception {
  /// Creates an exception describing a failed session operation.
  const WatchLinkException(this.message, {this.code});

  /// A human-readable explanation.
  final String message;

  /// The native error code, when the platform supplied one.
  final String? code;

  @override
  String toString() =>
      'WatchLinkException(${code == null ? '' : '$code: '}$message)';
}
