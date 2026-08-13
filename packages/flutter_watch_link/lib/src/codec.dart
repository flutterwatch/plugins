// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// The wire format, shared by both backends so iOS and watchOS cannot drift.
//
// Payloads cross the boundary as **JSON strings**, not as native maps. The
// obvious alternative — letting each platform's message codec convert a Dart
// map — would put two different codecs on the two ends of one session
// (Flutter's StandardMessageCodec on the phone, hand-written conversion on the
// watch) and leave WatchConnectivity's property-list coercion in the middle,
// where a Dart int can arrive as a double and a null cannot travel at all.
// One JSON encoder on each end removes all three problems, and makes the
// format inspectable in logs.
//
// The native side wraps the JSON string in a single-entry dictionary under
// [reservedPayloadKey] before handing it to WCSession, and unwraps it on
// arrival. A dictionary that arrives *without* that key came from something
// other than this package (a native watch app, say); the native side makes a
// best-effort JSON encoding of it instead of dropping it.

import 'types.dart';

/// The single WCSession dictionary key this package occupies. Kept versioned
/// so a future wire change can be detected rather than silently misparsed.
const String reservedPayloadKey = '_fwl_v1';

/// Result codes returned by the native send functions. Mirrored in
/// `src/flutter_watch_link_ffi.h`, which both platforms compile.
const int kOk = 0;

/// The session has not reached `WCSessionActivationStateActivated`.
const int kNotActivated = -1;

/// `sendMessage` was attempted while the counterpart was unreachable.
const int kNotReachable = -2;

/// The payload was not a JSON object.
const int kInvalidPayload = -3;

/// `WCSession` reported an error of its own.
const int kNativeError = -4;

/// Bit positions in the packed session-state word.
const int kBitActivated = 1 << 0;

/// See [WatchLinkState.reachable].
const int kBitReachable = 1 << 1;

/// See [WatchLinkState.counterpartInstalled].
const int kBitCounterpartInstalled = 1 << 2;

/// See [WatchLinkState.counterpartPaired].
const int kBitCounterpartPaired = 1 << 3;

/// Wake-signal kinds passed to the native→Dart callback. Mirrored in
/// src/flutter_watch_link_ffi.h.
///
/// Advisory only: the backend drains every source on any signal, so a
/// coalesced or misattributed kind cannot strand a payload.
const int kSignalInbound = 1;

/// A session-state change (activation, reachability, counterpart install).
const int kSignalState = 2;

/// An asynchronous failure was latched.
const int kSignalError = 3;

/// Unpacks the state word both platforms report.
WatchLinkState decodeState(int word) => WatchLinkState(
      activated: word & kBitActivated != 0,
      reachable: word & kBitReachable != 0,
      counterpartInstalled: word & kBitCounterpartInstalled != 0,
      counterpartPaired: word & kBitCounterpartPaired != 0,
    );

/// Decodes an inbound envelope, `{"tier": "...", "payload": {...}}`.
///
/// [responderFor] supplies the callback that answers a message carrying a
/// `replyId`; the codec knows the id is there but not how to send anything, so
/// the backend passes that in.
///
/// Returns null for anything malformed. Dropping beats throwing here: the
/// receiver cannot fix a bad payload, and this runs inside the drain loop,
/// where an exception would stall every later message behind it.
WatchLinkMessage? decodeEnvelope(
  Object? decoded, {
  WatchLinkResponder Function(int replyId)? responderFor,
}) {
  if (decoded is! Map<String, Object?>) {
    return null;
  }
  final Object? payload = decoded['payload'];
  if (payload is! Map<String, Object?>) {
    return null;
  }
  final Object? rawReplyId = decoded['replyId'];
  final int? replyId = rawReplyId is int ? rawReplyId : null;
  return WatchLinkMessage(
    payload: payload,
    tier: decodeTier(decoded['tier']),
    replyId: replyId,
    responder: replyId == null ? null : responderFor?.call(replyId),
  );
}

/// Decodes a `{"tier":"file","path":...,"metadata":{...}}` envelope.
WatchLinkFile? decodeFile(Object? decoded) {
  if (decoded is! Map<String, Object?>) {
    return null;
  }
  final Object? path = decoded['path'];
  if (path is! String || path.isEmpty) {
    return null;
  }
  final Object? metadata = decoded['metadata'];
  return WatchLinkFile(
    path: path,
    metadata: metadata is Map<String, Object?> ? metadata : const <String, Object?>{},
  );
}

/// Maps the envelope's tier name onto [WatchLinkTier].
WatchLinkTier decodeTier(Object? name) => switch (name) {
      'applicationContext' => WatchLinkTier.applicationContext,
      'userInfo' => WatchLinkTier.userInfo,
      'file' => WatchLinkTier.file,
      _ => WatchLinkTier.message,
    };

/// Builds the [WatchLinkException] a native result code stands for.
WatchLinkException exceptionFor(int code, String operation) => switch (code) {
      kNotActivated => WatchLinkException(
          '$operation before the session finished activating. Call '
          'WatchLink.instance.activate() and await a state with '
          'activated == true.',
          code: 'not-activated',
        ),
      kNotReachable => const WatchLinkException(
          'The counterpart app is not reachable, and sendMessage queues '
          'nothing. Use transferUserInfo for delivery that survives the other '
          'app being closed.',
          code: 'not-reachable',
        ),
      kInvalidPayload => WatchLinkException(
          '$operation received a payload that is not a JSON object.',
          code: 'invalid-payload',
        ),
      _ => WatchLinkException('$operation failed in WCSession.',
          code: 'native-error-$code'),
    };
