// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Host-side tests. The FFI backend is exercised through a fake bindings
// subclass — `WatchLinkFfiBindings.forTesting()` skips DynamicLibrary setup,
// so none of this needs a watch binary.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
// The FFI names come from src/ rather than the public library on purpose: that
// library selects its backend on `dart.library.ffi`, and the analyzer resolves
// the default (web) branch, where these types are stubs. These tests are
// native-only, so they reach for the native implementation directly.
import 'package:flutter_watch_link/flutter_watch_link.dart'
    hide WatchLinkFfiBackend, WatchLinkFfiBindings, SignalNative;
import 'package:flutter_watch_link/src/codec.dart';
import 'package:flutter_watch_link/src/ffi_backend.dart'
    show SignalNative, WatchLinkFfiBackend, WatchLinkFfiBindings;

/// Scripted native side: a queue of envelopes to hand out, a state word to
/// report, and a record of everything sent.
class FakeBindings extends WatchLinkFfiBindings {
  FakeBindings() : super.forTesting();

  final List<String> inbound = <String>[];
  final List<(String, String)> sent = <(String, String)>[];
  int stateWord = 0;
  int outstanding = 0;
  int dropped = 0;
  String? context;
  String? sentContext;
  int activateCalls = 0;

  /// Latched async failure the native side would report on its next poll.
  String? pendingError;

  /// Result code the next send returns.
  int nextResult = kOk;

  /// Whether the device reports a usable session — false models an iPad, or an
  /// iPhone with no paired watch.
  bool supported = true;

  /// The wake callbacks registered, in order; `null` entries are unregisters.
  ///
  /// Recorded rather than invoked: driving `drainOnce` directly keeps the
  /// tests off the real native→Dart path, which needs a device.
  final List<Pointer<NativeFunction<SignalNative>>> callbacks =
      <Pointer<NativeFunction<SignalNative>>>[];

  @override
  void setCallback(Pointer<NativeFunction<SignalNative>> callback) =>
      callbacks.add(callback);

  @override
  bool isSupported() => supported;

  @override
  void activate() => activateCalls++;

  @override
  int state() => stateWord;

  @override
  int sendMessage(String json) {
    sent.add(('message', json));
    return nextResult;
  }

  @override
  int updateApplicationContext(String json) {
    sent.add(('context', json));
    return nextResult;
  }

  @override
  int transferUserInfo(String json) {
    sent.add(('userInfo', json));
    return nextResult;
  }

  @override
  String? applicationContext() => context;

  @override
  String? sentApplicationContext() => sentContext;

  @override
  String? pollInbound() => inbound.isEmpty ? null : inbound.removeAt(0);

  @override
  int outstandingTransferCount() => outstanding;

  @override
  int droppedInboundCount() => dropped;

  @override
  String? takeLastError() {
    final String? error = pendingError;
    pendingError = null;
    return error;
  }

  /// Reply-expecting sends, as (json, correlationId).
  final List<(String, int)> replySends = <(String, int)>[];

  /// Answers given back to received messages, as (replyId, json).
  final List<(int, String)> responses = <(int, String)>[];

  /// Files queued, as (path, metadataJson).
  final List<(String, String?)> fileSends = <(String, String?)>[];

  int outstandingFiles = 0;

  @override
  int sendMessageWithReply(String json, int correlationId) {
    replySends.add((json, correlationId));
    return nextResult;
  }

  @override
  int respond(int replyId, String json) {
    responses.add((replyId, json));
    return nextResult;
  }

  @override
  int transferFile(String path, String? metadataJson) {
    fileSends.add((path, metadataJson));
    return nextResult;
  }

  @override
  int outstandingFileTransferCount() => outstandingFiles;
}

String envelope(String tier, Map<String, Object?> payload) =>
    jsonEncode(<String, Object?>{'tier': tier, 'payload': payload});

void main() {
  group('codec', () {
    test('unpacks every combination of the state word', () {
      expect(decodeState(0), WatchLinkState.unknown);
      expect(
        decodeState(kBitActivated | kBitReachable),
        const WatchLinkState(
          activated: true,
          reachable: true,
          counterpartInstalled: false,
          counterpartPaired: false,
        ),
      );
      expect(
        decodeState(kBitActivated | kBitCounterpartInstalled),
        const WatchLinkState(
          activated: true,
          reachable: false,
          counterpartInstalled: true,
          counterpartPaired: false,
        ),
      );
      expect(
        decodeState(kBitActivated | kBitCounterpartPaired),
        const WatchLinkState(
          activated: true,
          reachable: false,
          counterpartInstalled: false,
          counterpartPaired: true,
        ),
      );
    });

    test('keeps paired and installed distinguishable', () {
      // The three states a phone can be in, and the reason the bits are not
      // collapsed: each wants a different message in the UI.
      const WatchLinkState noWatch = WatchLinkState(
        activated: true,
        reachable: false,
        counterpartInstalled: false,
        counterpartPaired: false,
      );
      const WatchLinkState watchWithoutApp = WatchLinkState(
        activated: true,
        reachable: false,
        counterpartInstalled: false,
        counterpartPaired: true,
      );
      const WatchLinkState ready = WatchLinkState(
        activated: true,
        reachable: false,
        counterpartInstalled: true,
        counterpartPaired: true,
      );

      expect(noWatch, isNot(watchWithoutApp));
      expect(noWatch.counterpartReady, isFalse);
      expect(watchWithoutApp.counterpartReady, isFalse);
      expect(ready.counterpartReady, isTrue);
      // Installed but unpaired is contradictory and must not read as ready.
      expect(
        decodeState(kBitCounterpartInstalled).counterpartReady,
        isFalse,
      );
    });

    test('maps tier names, defaulting unknown names to message', () {
      expect(decodeTier('applicationContext'),
          WatchLinkTier.applicationContext);
      expect(decodeTier('userInfo'), WatchLinkTier.userInfo);
      expect(decodeTier('message'), WatchLinkTier.message);
      expect(decodeTier('something-newer'), WatchLinkTier.message);
      expect(decodeTier(null), WatchLinkTier.message);
    });

    test('returns null for envelopes it cannot use', () {
      expect(decodeEnvelope('not a map'), isNull);
      expect(decodeEnvelope(<String, Object?>{'tier': 'message'}), isNull);
      expect(
        decodeEnvelope(<String, Object?>{'tier': 'message', 'payload': 7}),
        isNull,
      );
    });
  });

  group('WatchLinkFfiBackend', () {
    late FakeBindings bindings;
    late WatchLinkFfiBackend backend;

    setUp(() {
      bindings = FakeBindings();
      backend = WatchLinkFfiBackend.forTesting(bindings);
    });

    tearDown(() => backend.dispose());

    test('drains the whole buffer in one tick, preserving order and tier',
        () async {
      final List<WatchLinkMessage> seen = <WatchLinkMessage>[];
      backend.messages.listen(seen.add);
      await Future<void>.delayed(Duration.zero);

      bindings.inbound.addAll(<String>[
        envelope('message', <String, Object?>{'n': 1}),
        envelope('userInfo', <String, Object?>{'n': 2}),
        envelope('applicationContext', <String, Object?>{'n': 3}),
      ]);
      backend.drainOnce();
      await Future<void>.delayed(Duration.zero);

      // One tick, not three: a burst that piled up while the app was
      // backgrounded must not trickle out one item per poll interval.
      expect(seen.map((WatchLinkMessage m) => m.payload['n']), <int>[1, 2, 3]);
      expect(
        seen.map((WatchLinkMessage m) => m.tier),
        <WatchLinkTier>[
          WatchLinkTier.message,
          WatchLinkTier.userInfo,
          WatchLinkTier.applicationContext,
        ],
      );
      expect(bindings.inbound, isEmpty);
    });

    test('skips a malformed envelope without stalling the ones behind it',
        () async {
      final List<WatchLinkMessage> seen = <WatchLinkMessage>[];
      backend.messages.listen(seen.add);
      await Future<void>.delayed(Duration.zero);

      bindings.inbound.addAll(<String>[
        jsonEncode(<String, Object?>{'tier': 'message'}), // no payload
        envelope('message', <String, Object?>{'n': 2}),
      ]);
      backend.drainOnce();
      await Future<void>.delayed(Duration.zero);

      expect(seen.single.payload['n'], 2);
    });

    test('emits state only when it changes', () async {
      final List<WatchLinkState> seen = <WatchLinkState>[];
      backend.states.listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      expect(seen.single, WatchLinkState.unknown, reason: 'initial state');

      bindings.stateWord = kBitActivated | kBitReachable;
      backend.drainOnce();
      backend.drainOnce(); // Unchanged — must not emit twice.
      await Future<void>.delayed(Duration.zero);

      expect(seen, hasLength(2));
      expect(seen.last.activated, isTrue);
      expect(seen.last.reachable, isTrue);
    });

    test('sends JSON on the tier the caller asked for', () async {
      await backend.sendMessage(<String, Object?>{'a': 1});
      await backend.updateApplicationContext(<String, Object?>{'b': 2});
      await backend.transferUserInfo(<String, Object?>{'c': 3});

      expect(bindings.sent, <(String, String)>[
        ('message', '{"a":1}'),
        ('context', '{"b":2}'),
        ('userInfo', '{"c":3}'),
      ]);
    });

    test('turns an unreachable counterpart into a typed, actionable error',
        () async {
      bindings.nextResult = kNotReachable;
      await expectLater(
        backend.sendMessage(<String, Object?>{'a': 1}),
        throwsA(
          isA<WatchLinkException>()
              .having((WatchLinkException e) => e.code, 'code', 'not-reachable')
              // The message has to point at the fix, because "not reachable"
              // is the normal case whenever the other app is closed.
              .having((WatchLinkException e) => e.message, 'message',
                  contains('transferUserInfo')),
        ),
      );
    });

    test('reports a send before activation distinctly from unreachable',
        () async {
      bindings.nextResult = kNotActivated;
      await expectLater(
        backend.transferUserInfo(<String, Object?>{'a': 1}),
        throwsA(isA<WatchLinkException>()
            .having((WatchLinkException e) => e.code, 'code', 'not-activated')),
      );
    });

    test('reads the received application context, or null when none', () async {
      expect(await backend.receivedApplicationContext(), isNull);
      bindings.context = '{"items":["milk"]}';
      expect(await backend.receivedApplicationContext(),
          <String, Object?>{'items': <String>['milk']});
    });

    test('reads the sent application context, or null when none', () async {
      expect(await backend.sentApplicationContext(), isNull);
      bindings.sentContext = '{"items":["bread"]}';
      expect(await backend.sentApplicationContext(),
          <String, Object?>{'items': <String>['bread']});
    });

    test('does not confuse the sent context with the received one', () async {
      // They come from different WCSession properties and routinely differ —
      // reading one where the other was meant is a silent, plausible-looking
      // bug, so pin the direction.
      bindings.context = '{"from":"counterpart"}';
      bindings.sentContext = '{"from":"us"}';
      expect(await backend.receivedApplicationContext(),
          <String, Object?>{'from': 'counterpart'});
      expect(await backend.sentApplicationContext(),
          <String, Object?>{'from': 'us'});
    });

    test('surfaces a send failure that landed after the call returned',
        () async {
      // The case that motivates the whole errors stream: WCSession accepts the
      // message, sendMessage returns OK, and the failure arrives later on a
      // native callback. Without this the caller believes it was delivered.
      final List<String> seen = <String>[];
      backend.errors.listen(seen.add);
      await Future<void>.delayed(Duration.zero);

      await backend.sendMessage(<String, Object?>{'a': 1});
      expect(seen, isEmpty, reason: 'the send itself reported success');

      bindings.pendingError = 'sendMessage: Companion app is not installed.';
      backend.drainOnce();
      await Future<void>.delayed(Duration.zero);

      expect(seen.single, contains('Companion app is not installed'));

      // Taking it clears it — a stale error must not repeat every poll.
      backend.drainOnce();
      await Future<void>.delayed(Duration.zero);
      expect(seen, hasLength(1));
    });

    test('surfaces diagnostics counters', () async {
      bindings.outstanding = 3;
      bindings.dropped = 7;
      expect(await backend.outstandingTransferCount(), 3);
      expect(await backend.droppedInboundCount(), 7);
    });

    test('activate is forwarded and safe to repeat', () async {
      await backend.activate();
      await backend.activate();
      expect(bindings.activateCalls, 2);
    });

    test('forwards whether the device supports a session at all', () async {
      expect(await backend.isSupported(), isTrue);
      bindings.supported = false;
      expect(await backend.isSupported(), isFalse,
          reason: 'an iPad, or an iPhone with no paired watch');
    });
  });

  group('push signalling', () {
    late FakeBindings bindings;
    late WatchLinkFfiBackend backend;

    setUp(() {
      bindings = FakeBindings();
      backend = WatchLinkFfiBackend.forTesting(bindings);
    });

    tearDown(() => backend.dispose());

    test('registers a wake callback before activating', () async {
      // Order matters: WCSession's activation callback is itself a signal, so
      // registering afterwards would race with the thing it reports.
      await backend.activate();
      expect(bindings.callbacks, isNotEmpty);
      expect(bindings.callbacks.first, isNot(nullptr));
    });

    test('registers once however many streams are listened to', () async {
      backend.messages.listen((_) {});
      backend.states.listen((_) {});
      backend.errors.listen((_) {});
      await Future<void>.delayed(Duration.zero);

      expect(bindings.callbacks.where((Pointer<void> p) => p != nullptr),
          hasLength(1),
          reason: 'one native callback backs every stream');
    });

    test('drains what arrived before anything listened', () async {
      // The gap this closes: payloads start arriving the moment the session
      // activates, which can be long before the app subscribes. Without the
      // drain on registration they would sit in the ring buffer until the
      // *next* delivery happened to signal.
      bindings.inbound.add(envelope('userInfo', <String, Object?>{'early': 1}));

      final List<WatchLinkMessage> seen = <WatchLinkMessage>[];
      backend.messages.listen(seen.add);
      await Future<void>.delayed(Duration.zero);

      expect(seen.single.payload['early'], 1);
    });

    test('unregisters when the last listener goes away', () async {
      final StreamSubscription<WatchLinkMessage> sub =
          backend.messages.listen((_) {});
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(bindings.callbacks.last, nullptr,
          reason: 'native must stop signalling into a Dart end nobody reads');
    });

    test('keeps signalling while any other stream is still listened to',
        () async {
      final StreamSubscription<WatchLinkMessage> messages =
          backend.messages.listen((_) {});
      final StreamSubscription<WatchLinkState> states =
          backend.states.listen((_) {});
      await Future<void>.delayed(Duration.zero);

      await messages.cancel();

      expect(bindings.callbacks.last, isNot(nullptr),
          reason: 'states is still listening');
      await states.cancel();
    });

    test('reuses one trampoline across listen/cancel cycles', () async {
      // A NativeCallable is only reclaimed by close(), which cannot be called
      // while native might be mid-signal — so allocating a fresh one per cycle
      // would leak one per subscription for the life of the app.
      for (int i = 0; i < 3; i++) {
        final StreamSubscription<WatchLinkMessage> sub =
            backend.messages.listen((_) {});
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
      }

      final List<Pointer<NativeFunction<SignalNative>>> registered = bindings
          .callbacks
          .where((Pointer<NativeFunction<SignalNative>> p) => p != nullptr)
          .toList();
      expect(registered, hasLength(3), reason: 'three listen cycles');
      expect(registered.toSet(), hasLength(1),
          reason: 'the same trampoline, re-registered');
    });
  });

  group('states seeding', () {
    late FakeBindings bindings;
    late WatchLinkFfiBackend backend;

    setUp(() {
      bindings = FakeBindings();
      backend = WatchLinkFfiBackend.forTesting(bindings);
      bindings.stateWord = kBitActivated | kBitReachable;
    });

    tearDown(() => backend.dispose());

    test('seeds every subscriber, not just the first', () async {
      final List<WatchLinkState> first = <WatchLinkState>[];
      final StreamSubscription<WatchLinkState> a =
          backend.states.listen(first.add);
      await Future<void>.delayed(Duration.zero);
      expect(first.single.activated, isTrue);

      // A second listener while the first is still subscribed. A broadcast
      // controller's onListen does not fire again, so seeding there would
      // leave this one on WatchLinkState.unknown until the state moved.
      final List<WatchLinkState> second = <WatchLinkState>[];
      final StreamSubscription<WatchLinkState> b =
          backend.states.listen(second.add);
      await Future<void>.delayed(Duration.zero);

      expect(second, hasLength(1));
      expect(second.single.activated, isTrue);
      expect(second.single.reachable, isTrue);
      expect(first, hasLength(1), reason: 'the seed goes only to the newcomer');

      await a.cancel();
      await b.cancel();
    });

    test('a late subscriber does not suppress a change for the others',
        () async {
      final List<WatchLinkState> first = <WatchLinkState>[];
      final StreamSubscription<WatchLinkState> a =
          backend.states.listen(first.add);
      await Future<void>.delayed(Duration.zero);

      // The state moves, then a second listener arrives before the drain that
      // reports it. Recording the newcomer's seed as the last known state
      // would make that drain a no-op and the change would never reach `a`.
      bindings.stateWord = kBitActivated;
      final StreamSubscription<WatchLinkState> b =
          backend.states.listen((_) {});
      await Future<void>.delayed(Duration.zero);
      backend.drainOnce();
      await Future<void>.delayed(Duration.zero);

      expect(first, hasLength(2));
      expect(first.last.reachable, isFalse);

      await a.cancel();
      await b.cancel();
    });

    test('both subscribers see subsequent changes', () async {
      final List<WatchLinkState> first = <WatchLinkState>[];
      final List<WatchLinkState> second = <WatchLinkState>[];
      final StreamSubscription<WatchLinkState> a =
          backend.states.listen(first.add);
      final StreamSubscription<WatchLinkState> b =
          backend.states.listen(second.add);
      await Future<void>.delayed(Duration.zero);

      bindings.stateWord = 0;
      backend.drainOnce();
      await Future<void>.delayed(Duration.zero);

      expect(first.last.activated, isFalse);
      expect(second.last.activated, isFalse);

      await a.cancel();
      await b.cancel();
    });

    test('cancelling one subscriber leaves the other listening', () async {
      final List<WatchLinkState> kept = <WatchLinkState>[];
      final StreamSubscription<WatchLinkState> a =
          backend.states.listen((_) {});
      final StreamSubscription<WatchLinkState> b =
          backend.states.listen(kept.add);
      await Future<void>.delayed(Duration.zero);
      await a.cancel();

      expect(bindings.callbacks.last, isNot(nullptr),
          reason: 'one subscriber is left, so native must keep signalling');

      bindings.stateWord = 0;
      backend.drainOnce();
      await Future<void>.delayed(Duration.zero);
      expect(kept.last.activated, isFalse);

      await b.cancel();
      expect(bindings.callbacks.last, nullptr);
    });
  });

  group('dispose', () {
    late FakeBindings bindings;
    late WatchLinkFfiBackend backend;

    setUp(() {
      bindings = FakeBindings();
      backend = WatchLinkFfiBackend.forTesting(bindings);
    });

    test('reports use-after-dispose instead of failing on a closed stream',
        () async {
      // WatchLink.instance is a singleton, so a stray dispose() used to
      // poison it: the next call reached a closed controller and threw
      // `StateError: Cannot add new events after calling close`, which says
      // nothing about what actually went wrong.
      await backend.dispose();

      Matcher disposed() => throwsA(isA<WatchLinkException>()
          .having((WatchLinkException e) => e.code, 'code', 'disposed'));

      expect(backend.activate(), disposed());
      expect(backend.readState(), disposed());
      expect(backend.isSupported(), disposed());
      expect(backend.sendMessage(<String, Object?>{}), disposed());
      expect(backend.sendMessageWithReply(<String, Object?>{}), disposed());
      expect(backend.updateApplicationContext(<String, Object?>{}), disposed());
      expect(backend.transferUserInfo(<String, Object?>{}), disposed());
      expect(backend.transferFile('/tmp/x'), disposed());
      expect(backend.receivedApplicationContext(), disposed());
      expect(backend.sentApplicationContext(), disposed());
      expect(backend.outstandingTransferCount(), disposed());
      expect(backend.outstandingFileTransferCount(), disposed());
      expect(() => backend.messages, disposed());
      expect(() => backend.states, disposed());
      expect(() => backend.errors, disposed());
      expect(() => backend.files, disposed());
    });

    test('a native signal that lands after dispose is harmless', () async {
      backend.messages.listen((_) {});
      await Future<void>.delayed(Duration.zero);
      await backend.dispose();

      // Native can be between reading the callback pointer and calling it
      // when dispose runs; the drain it triggers must not reach the closed
      // controllers.
      bindings.inbound.add(envelope('message', <String, Object?>{'late': 1}));
      expect(backend.drainOnce, returnsNormally);
    });

    test('is idempotent', () async {
      await backend.dispose();
      await expectLater(backend.dispose(), completes);
    });
  });

  group('reply handlers', () {
    late FakeBindings bindings;
    late WatchLinkFfiBackend backend;

    setUp(() {
      bindings = FakeBindings();
      backend = WatchLinkFfiBackend.forTesting(bindings);
    });

    tearDown(() => backend.dispose());

    /// The envelope native sends back when the counterpart answers.
    String reply(int correlationId, Map<String, Object?> payload) =>
        jsonEncode(<String, Object?>{
          'tier': 'reply',
          'correlationId': correlationId,
          'payload': payload,
        });

    test('completes the future with the counterpart\'s answer', () async {
      final Future<Map<String, Object?>> pending =
          backend.sendMessageWithReply(<String, Object?>{'ask': 1});

      // The reply arrives long after the send returned, correlated by id.
      final int id = bindings.replySends.single.$2;
      bindings.inbound.add(reply(id, <String, Object?>{'answer': 2}));
      backend.drainOnce();

      expect(await pending, <String, Object?>{'answer': 2});
    });

    test('routes each reply to its own waiting future', () async {
      // The reason correlation ids exist: two in-flight requests must not be
      // able to take each other's answers.
      final Future<Map<String, Object?>> first =
          backend.sendMessageWithReply(<String, Object?>{'n': 1});
      final Future<Map<String, Object?>> second =
          backend.sendMessageWithReply(<String, Object?>{'n': 2});

      final int firstId = bindings.replySends[0].$2;
      final int secondId = bindings.replySends[1].$2;
      expect(firstId, isNot(secondId));

      // Answered out of order, deliberately.
      bindings.inbound.add(reply(secondId, <String, Object?>{'for': 2}));
      bindings.inbound.add(reply(firstId, <String, Object?>{'for': 1}));
      backend.drainOnce();

      expect(await first, <String, Object?>{'for': 1});
      expect(await second, <String, Object?>{'for': 2});
    });

    test('surfaces a failed reply as an error, not a hang', () async {
      final Future<Map<String, Object?>> pending =
          backend.sendMessageWithReply(<String, Object?>{'ask': 1});
      final int id = bindings.replySends.single.$2;

      bindings.inbound.add(jsonEncode(<String, Object?>{
        'tier': 'replyError',
        'correlationId': id,
        'error': 'counterpart is not installed',
      }));
      backend.drainOnce();

      await expectLater(
        pending,
        throwsA(isA<WatchLinkException>()
            .having((WatchLinkException e) => e.code, 'code', 'reply-failed')),
      );
    });

    test('times out rather than waiting for ever on a lost reply', () async {
      // Native has its own timeout, but a dropped signal would otherwise leave
      // this future pending for the life of the app.
      await expectLater(
        backend.sendMessageWithReply(
          <String, Object?>{'ask': 1},
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<WatchLinkException>()
            .having((WatchLinkException e) => e.code, 'code', 'reply-timeout')),
      );
    });

    test('does not register a pending reply when the send is refused',
        () async {
      bindings.nextResult = kNotReachable;
      await expectLater(
        backend.sendMessageWithReply(<String, Object?>{'ask': 1}),
        throwsA(isA<WatchLinkException>()),
      );
      // A leaked completer here would keep the native signal registered for
      // ever, since _stopSignalsIfIdle refuses to unregister while one waits.
      bindings.nextResult = kOk;
      await backend.dispose();
    });

    test('a received message carrying a replyId can be answered', () async {
      final List<WatchLinkMessage> seen = <WatchLinkMessage>[];
      backend.messages.listen(seen.add);
      await Future<void>.delayed(Duration.zero);

      bindings.inbound.add(jsonEncode(<String, Object?>{
        'tier': 'message',
        'payload': <String, Object?>{'ping': true},
        'replyId': 7,
      }));
      backend.drainOnce();
      await Future<void>.delayed(Duration.zero);

      expect(seen.single.expectsReply, isTrue);
      await seen.single.reply(<String, Object?>{'pong': true});
      expect(bindings.responses.single, (7, '{"pong":true}'));
    });

    test('replying to a message nobody asked about is a no-op', () async {
      final List<WatchLinkMessage> seen = <WatchLinkMessage>[];
      backend.messages.listen(seen.add);
      await Future<void>.delayed(Duration.zero);

      bindings.inbound.add(envelope('message', <String, Object?>{'ping': true}));
      backend.drainOnce();
      await Future<void>.delayed(Duration.zero);

      expect(seen.single.expectsReply, isFalse);
      await seen.single.reply(<String, Object?>{'pong': true});
      expect(bindings.responses, isEmpty,
          reason: 'no sender is waiting, so there is nothing to answer');
    });
  });

  group('file transfer', () {
    late FakeBindings bindings;
    late WatchLinkFfiBackend backend;

    setUp(() {
      bindings = FakeBindings();
      backend = WatchLinkFfiBackend.forTesting(bindings);
    });

    tearDown(() => backend.dispose());

    test('queues a path, with metadata only when given', () async {
      await backend.transferFile('/tmp/a.png');
      await backend.transferFile('/tmp/b.png',
          metadata: <String, Object?>{'kind': 'photo'});

      expect(bindings.fileSends, <(String, String?)>[
        ('/tmp/a.png', null),
        ('/tmp/b.png', '{"kind":"photo"}'),
      ]);
    });

    test('surfaces received files on their own stream, not as messages',
        () async {
      // A file is a path plus metadata, not a payload — putting it on
      // `messages` would force every listener to type-check what it got.
      final List<WatchLinkFile> files = <WatchLinkFile>[];
      final List<WatchLinkMessage> messages = <WatchLinkMessage>[];
      backend.files.listen(files.add);
      backend.messages.listen(messages.add);
      await Future<void>.delayed(Duration.zero);

      bindings.inbound.add(jsonEncode(<String, Object?>{
        'tier': 'file',
        'path': '/var/mobile/.../fwl_inbox/uuid-photo.png',
        'metadata': <String, Object?>{'kind': 'photo'},
      }));
      backend.drainOnce();
      await Future<void>.delayed(Duration.zero);

      expect(files.single.path, endsWith('photo.png'));
      expect(files.single.metadata, <String, Object?>{'kind': 'photo'});
      expect(messages, isEmpty);
    });

    test('a file envelope with no usable path is dropped', () async {
      final List<WatchLinkFile> files = <WatchLinkFile>[];
      backend.files.listen(files.add);
      await Future<void>.delayed(Duration.zero);

      bindings.inbound.addAll(<String>[
        jsonEncode(<String, Object?>{'tier': 'file', 'metadata': <String, Object?>{}}),
        jsonEncode(<String, Object?>{'tier': 'file', 'path': ''}),
      ]);
      backend.drainOnce();
      await Future<void>.delayed(Duration.zero);

      expect(files, isEmpty);
    });

    test('reports undelivered transfers', () async {
      bindings.outstandingFiles = 4;
      expect(await backend.outstandingFileTransferCount(), 4);
    });
  });

  group('WatchLink', () {
    tearDown(() => WatchLink.backendOverride = null);

    test('routes through an injected backend', () async {
      final FakeBindings bindings = FakeBindings();
      WatchLink.backendOverride = WatchLinkFfiBackend.forTesting(bindings);

      await WatchLink.instance.sendMessage(<String, Object?>{'x': 1});

      expect(bindings.sent.single.$2, '{"x":1}');
    });

    group('delegation', () {
      // WatchLink is a thin pass-through, which is exactly why it needs
      // covering: every member is a one-line forward, and a forward to the
      // wrong backend method — transferUserInfo where updateApplicationContext
      // was meant — type-checks, runs, and silently picks the wrong transport.
      late RecordingBackend backend;

      setUp(() {
        backend = RecordingBackend();
        WatchLink.backendOverride = backend;
      });

      tearDown(() => WatchLink.backendOverride = null);

      test('each send method reaches its own backend method', () async {
        final WatchLink link = WatchLink.instance;
        await link.sendMessage(<String, Object?>{'a': 1});
        await link.updateApplicationContext(<String, Object?>{'b': 2});
        await link.transferUserInfo(<String, Object?>{'c': 3});
        await link.transferFile('/tmp/x', metadata: <String, Object?>{'d': 4});

        expect(backend.calls, <String>[
          'sendMessage',
          'updateApplicationContext',
          'transferUserInfo',
          'transferFile',
        ]);
        expect(backend.payloads.take(3), <Object?>[
          <String, Object?>{'a': 1},
          <String, Object?>{'b': 2},
          <String, Object?>{'c': 3},
        ]);
        // Records compare their fields with ==, and Map's == is identity, so
        // the file tuple has to be unpacked rather than matched whole.
        final (String, Map<String, Object?>?) file =
            backend.payloads.last! as (String, Map<String, Object?>?);
        expect(file.$1, '/tmp/x');
        expect(file.$2, <String, Object?>{'d': 4});
      });

      test('each reader reaches its own backend method', () async {
        final WatchLink link = WatchLink.instance;
        expect(await link.isSupported(), isTrue);
        expect(await link.readState(), RecordingBackend.state);
        expect(await link.receivedApplicationContext(),
            <String, Object?>{'from': 'them'});
        expect(await link.sentApplicationContext(),
            <String, Object?>{'from': 'us'});
        expect(await link.outstandingTransferCount(), 7);
        expect(await link.outstandingFileTransferCount(), 9);

        expect(backend.calls, <String>[
          'isSupported',
          'readState',
          'receivedApplicationContext',
          'sentApplicationContext',
          'outstandingTransferCount',
          'outstandingFileTransferCount',
        ]);
      });

      test('sendMessageWithReply forwards the timeout and returns the reply',
          () async {
        final Map<String, Object?> reply = await WatchLink.instance
            .sendMessageWithReply(<String, Object?>{'ping': true},
                timeout: const Duration(seconds: 3));

        expect(reply, <String, Object?>{'pong': true});
        expect(backend.calls, <String>['sendMessageWithReply']);
        expect(backend.lastTimeout, const Duration(seconds: 3));
      });

      test('each stream carries the backend events for that stream', () async {
        // Identity is the wrong assertion — `.stream` hands back a fresh
        // wrapper each access — so this checks that events actually flow, and
        // that no two getters are wired to the same source.
        final WatchLink link = WatchLink.instance;
        final List<WatchLinkMessage> messages = <WatchLinkMessage>[];
        final List<WatchLinkState> states = <WatchLinkState>[];
        final List<String> errors = <String>[];
        final List<WatchLinkFile> files = <WatchLinkFile>[];
        link.messages.listen(messages.add);
        link.states.listen(states.add);
        link.errors.listen(errors.add);
        link.files.listen(files.add);
        await pumpEventQueue();

        backend.emitMessage(const WatchLinkMessage(
            payload: <String, Object?>{'m': 1}, tier: WatchLinkTier.message));
        backend.emitState(RecordingBackend.state);
        backend.emitError('boom');
        backend.emitFile(const WatchLinkFile(
            path: '/f', metadata: <String, Object?>{}));
        await pumpEventQueue();

        expect(messages.single.payload, <String, Object?>{'m': 1});
        expect(states.single, RecordingBackend.state);
        expect(errors.single, 'boom');
        expect(files.single.path, '/f');
      });

      test('activate and dispose reach the backend', () async {
        await WatchLink.instance.activate();
        await WatchLink.instance.dispose();
        expect(backend.calls, <String>['activate', 'dispose']);
      });
    });
  });

  group('types', () {
    test('a message without a replyId expects no reply and reply is a no-op',
        () async {
      const WatchLinkMessage m = WatchLinkMessage(
        payload: <String, Object?>{'a': 1},
        tier: WatchLinkTier.userInfo,
      );
      expect(m.expectsReply, isFalse);
      // Must not throw: receivers call reply() defensively without checking.
      await m.reply(<String, Object?>{'ignored': true});
      expect(m.toString(), contains('userInfo'));
      expect(m.toString(), isNot(contains('expects reply')));
    });

    test('a message with a responder forwards the reply payload', () async {
      final List<Map<String, Object?>> answered = <Map<String, Object?>>[];
      final WatchLinkMessage m = WatchLinkMessage(
        payload: <String, Object?>{'q': 'name'},
        tier: WatchLinkTier.message,
        replyId: 42,
        responder: (Map<String, Object?> r) async => answered.add(r),
      );

      expect(m.expectsReply, isTrue);
      expect(m.toString(), contains('expects reply'));
      await m.reply(<String, Object?>{'a': 'watch'});
      expect(answered.single, <String, Object?>{'a': 'watch'});
    });

    test('a replyId with no responder still does not throw', () async {
      // The combination a fake backend produces most easily; a receiver that
      // answers it should be a no-op rather than a crash.
      const WatchLinkMessage m = WatchLinkMessage(
        payload: <String, Object?>{},
        tier: WatchLinkTier.message,
        replyId: 1,
      );
      await m.reply(<String, Object?>{'a': 1});
    });

    test('state equality covers every flag', () {
      const WatchLinkState base = WatchLinkState(
        activated: true,
        reachable: true,
        counterpartInstalled: true,
        counterpartPaired: true,
      );
      expect(base, base);
      expect(base.hashCode, base.hashCode);

      for (final WatchLinkState other in <WatchLinkState>[
        const WatchLinkState(
            activated: false,
            reachable: true,
            counterpartInstalled: true,
            counterpartPaired: true),
        const WatchLinkState(
            activated: true,
            reachable: false,
            counterpartInstalled: true,
            counterpartPaired: true),
        const WatchLinkState(
            activated: true,
            reachable: true,
            counterpartInstalled: false,
            counterpartPaired: true),
        const WatchLinkState(
            activated: true,
            reachable: true,
            counterpartInstalled: true,
            counterpartPaired: false),
      ]) {
        expect(base, isNot(other),
            reason: 'flipping one flag must not compare equal: $other');
      }

      expect(base, isNot('not a state'));
      expect(base.toString(), contains('counterpartPaired: true'));
    });

    test('a file carries its path and metadata', () {
      const WatchLinkFile f = WatchLinkFile(
        path: '/docs/fwl_inbox/x-photo.png',
        metadata: <String, Object?>{'kind': 'photo'},
      );
      expect(f.toString(), contains('x-photo.png'));
      expect(f.toString(), contains('kind'));
    });

    test('every native error code maps to a distinct, actionable message', () {
      // A caller has to be able to tell an unreachable watch from a malformed
      // payload, so each code gets its own code string and its own advice.
      final Map<int, String> codes = <int, String>{
        kNotActivated: 'not-activated',
        kNotReachable: 'not-reachable',
        kInvalidPayload: 'invalid-payload',
        kNativeError: 'native-error-$kNativeError',
      };

      for (final MapEntry<int, String> e in codes.entries) {
        final WatchLinkException x = exceptionFor(e.key, 'sendMessage');
        expect(x.code, e.value);
        expect(x.toString(), contains(e.value));
        expect(x.message, isNotEmpty);
      }

      // The two that name the failed operation should say which it was.
      expect(exceptionFor(kNotActivated, 'transferFile').message,
          contains('transferFile'));
      // not-reachable is the one that points at the alternative tier.
      expect(exceptionFor(kNotReachable, 'sendMessage').message,
          contains('transferUserInfo'));
    });
  });
}

/// A [WatchLinkBackend] that records which member was called.
///
/// Deliberately not a subclass of the FFI backend: this is here to prove the
/// facade forwards to the member it claims to, so it has to sit at the
/// interface boundary rather than below it.
class RecordingBackend implements WatchLinkBackend {
  static const WatchLinkState state = WatchLinkState(
    activated: true,
    reachable: true,
    counterpartInstalled: true,
    counterpartPaired: true,
  );

  final List<String> calls = <String>[];
  final List<Object?> payloads = <Object?>[];
  Duration? lastTimeout;

  final StreamController<WatchLinkMessage> _messages =
      StreamController<WatchLinkMessage>.broadcast();
  final StreamController<WatchLinkState> _states =
      StreamController<WatchLinkState>.broadcast();
  final StreamController<String> _errors = StreamController<String>.broadcast();
  final StreamController<WatchLinkFile> _files =
      StreamController<WatchLinkFile>.broadcast();

  @override
  Future<bool> isSupported() async {
    calls.add('isSupported');
    return true;
  }

  @override
  Future<void> activate() async => calls.add('activate');

  @override
  Future<WatchLinkState> readState() async {
    calls.add('readState');
    return state;
  }

  @override
  Future<void> sendMessage(Map<String, Object?> payload) async {
    calls.add('sendMessage');
    payloads.add(payload);
  }

  @override
  Future<Map<String, Object?>> sendMessageWithReply(
    Map<String, Object?> payload, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    calls.add('sendMessageWithReply');
    payloads.add(payload);
    lastTimeout = timeout;
    return <String, Object?>{'pong': true};
  }

  @override
  Future<void> transferFile(String path,
      {Map<String, Object?>? metadata}) async {
    calls.add('transferFile');
    payloads.add((path, metadata));
  }

  @override
  Future<int> outstandingFileTransferCount() async {
    calls.add('outstandingFileTransferCount');
    return 9;
  }

  @override
  Stream<WatchLinkFile> get files => _files.stream;

  @override
  Future<void> updateApplicationContext(Map<String, Object?> payload) async {
    calls.add('updateApplicationContext');
    payloads.add(payload);
  }

  @override
  Future<void> transferUserInfo(Map<String, Object?> payload) async {
    calls.add('transferUserInfo');
    payloads.add(payload);
  }

  @override
  Future<Map<String, Object?>?> receivedApplicationContext() async {
    calls.add('receivedApplicationContext');
    return <String, Object?>{'from': 'them'};
  }

  @override
  Future<Map<String, Object?>?> sentApplicationContext() async {
    calls.add('sentApplicationContext');
    return <String, Object?>{'from': 'us'};
  }

  @override
  Future<int> outstandingTransferCount() async {
    calls.add('outstandingTransferCount');
    return 7;
  }

  @override
  Stream<WatchLinkMessage> get messages => _messages.stream;

  @override
  Stream<WatchLinkState> get states => _states.stream;

  @override
  Stream<String> get errors => _errors.stream;

  void emitMessage(WatchLinkMessage m) => _messages.add(m);

  void emitState(WatchLinkState s) => _states.add(s);

  void emitError(String e) => _errors.add(e);

  void emitFile(WatchLinkFile f) => _files.add(f);

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await _messages.close();
    await _states.close();
    await _errors.close();
    await _files.close();
  }
}
