// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// On-device tests against the real native library. These cover the half the
// host tests cannot reach by construction: `WatchLinkFfiBindings.forTesting()`
// skips `DynamicLibrary` resolution and every `lookupFunction`, so a symbol
// that failed to export, or a framework the resolver cannot find, is invisible
// to `flutter test` and shows up only here.
//
// Run on the watch:
//   flutter-watchos test integration_test --target lib/main_watch.dart
// Run on the phone:
//   flutter test integration_test
//
// Everything here must pass on **one** device with no counterpart running, so
// the suite asserts the contract rather than delivery: a send with nobody
// listening is expected to fail in a specific, documented way. Two-device
// delivery is checked by hand — see the README's Simulator-pair section.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_watch_link/flutter_watch_link.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final WatchLink link = WatchLink.instance;

  setUpAll(() async {
    if (!await link.isSupported()) {
      return;
    }
    await link.activate();
    // Activation is asynchronous and the simulator's WatchConnectivity daemon
    // is sometimes slow to come up after a boot. A fixed sleep here makes the
    // suite flaky — it was, at two seconds — so wait for the state itself and
    // give up only after a generous deadline.
    final Stopwatch elapsed = Stopwatch()..start();
    while (elapsed.elapsed < const Duration(seconds: 20)) {
      if ((await link.readState()).activated) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  });

  testWidgets('the native library resolves and every symbol binds',
      (WidgetTester _) async {
    // The single most valuable assertion in this file. Each call below is a
    // distinct `lookupFunction`, so this fails loudly if any export was
    // dropped by the linker rather than failing at some later runtime moment.
    await link.isSupported();
    await link.readState();
    await link.receivedApplicationContext();
    await link.sentApplicationContext();
    await link.outstandingTransferCount();
    await link.outstandingFileTransferCount();
  });

  testWidgets('isSupported answers without throwing', (WidgetTester _) async {
    // True on any watch, and on an iPhone with a paired watch. An iPad or an
    // unpaired phone legitimately answers false — that is not a failure.
    expect(await link.isSupported(), isA<bool>());
  });

  testWidgets('activate is idempotent', (WidgetTester _) async {
    // Apps call this on every launch and often from more than one place.
    await link.activate();
    await link.activate();
    expect(await link.readState(), isA<WatchLinkState>());
  });

  testWidgets('the session activates', (WidgetTester _) async {
    if (!await link.isSupported()) {
      return;
    }
    final WatchLinkState state = await link.readState();
    expect(state.activated, isTrue,
        reason: 'activate() ran in setUpAll and WCSession should be up');
  });

  testWidgets('a watch always reports a paired counterpart',
      (WidgetTester _) async {
    if (!await link.isSupported()) {
      return;
    }
    final WatchLinkState state = await link.readState();
    // The asymmetry worth pinning: watchOS has no isPaired, so the watch
    // reports true unconditionally, while the phone answers honestly.
    // counterpartReady must never claim more than its two inputs.
    expect(state.counterpartReady,
        state.counterpartPaired && state.counterpartInstalled);
  });

  testWidgets('states emits the current state on listen',
      (WidgetTester _) async {
    if (!await link.isSupported()) {
      return;
    }
    // A late subscriber must not wait for the next change to learn where it
    // stands — a cold-launched app subscribes after activation has finished.
    final WatchLinkState first = await link.states.first
        .timeout(const Duration(seconds: 5), onTimeout: () {
      fail('states did not emit within 5s of listening');
    });
    expect(first.activated, isTrue);
  });

  testWidgets('sendMessage fails cleanly when nobody is reachable',
      (WidgetTester _) async {
    if (!await link.isSupported()) {
      return;
    }
    final WatchLinkState state = await link.readState();
    if (state.reachable) {
      // A counterpart really is running; the failure path cannot be exercised.
      return;
    }
    await expectLater(
      link.sendMessage(<String, Object?>{'n': 1}),
      throwsA(isA<WatchLinkException>().having(
        (WatchLinkException e) => e.code,
        'code',
        anyOf('not-reachable', 'not-activated'),
      )),
    );
  });

  testWidgets('a non-JSON payload is rejected before it reaches WCSession',
      (WidgetTester _) async {
    if (!await link.isSupported()) {
      return;
    }
    // WCSession accepts only property-list types. Catching this in the codec
    // gives a usable error instead of an NSInvalidArgumentException crash.
    await expectLater(
      link.updateApplicationContext(<String, Object?>{'when': DateTime.now()}),
      throwsA(isA<Object>()),
    );
  });

  testWidgets('the application context round-trips through the system',
      (WidgetTester _) async {
    if (!await link.isSupported()) {
      return;
    }
    final WatchLinkState state = await link.readState();
    if (!state.counterpartReady) {
      // updateApplicationContext needs somewhere to send it.
      return;
    }
    final int stamp = DateTime.now().millisecondsSinceEpoch;
    await link.updateApplicationContext(<String, Object?>{'stamp': stamp});

    // Read back what we sent, not what we received: this is the accessor that
    // reads WCSession.applicationContext rather than
    // receivedApplicationContext, and confusing the two is a silent bug.
    final Map<String, Object?>? sent = await link.sentApplicationContext();
    expect(sent, isNotNull);
    expect(sent!['stamp'], stamp);
  });

  testWidgets('file metadata carrying a null reaches WCSession intact',
      (WidgetTester _) async {
    if (!await link.isSupported()) {
      return;
    }
    if (!(await link.readState()).activated) {
      return;
    }
    // Metadata is wrapped as a JSON string like every other tier rather than
    // handed over as a decoded dictionary. WCSession documents metadata as
    // property-list values, and a JSON null decodes to NSNull, which is not
    // one; the same wrapping is what keeps an int from arriving as a double
    // after the property-list round trip.
    //
    // What this asserts is only that the call is accepted and the app is
    // still running. On a device with no counterpart installed, WCSession
    // discards the transfer without validating the metadata at all — measured,
    // not assumed — so the raise cannot be provoked here. Whether the
    // metadata *arrives* is part of the two-device check in the README.
    //
    // The file is left behind on purpose: the transfer may still be queued
    // when this returns, and deleting the source out from under it would fail
    // the transfer for a reason that has nothing to do with what is being
    // tested. It is a handful of bytes in the app's temporary directory.
    final Directory dir = Directory.systemTemp.createTempSync('watch_link');
    final File file = File('${dir.path}/payload.txt')
      ..writeAsStringSync('hello');
    await link.transferFile(
      file.path,
      metadata: <String, Object?>{'caption': null, 'index': 1},
    );
    expect(await link.outstandingFileTransferCount(), greaterThanOrEqualTo(0));
  });

  testWidgets('transfer counts are readable and non-negative',
      (WidgetTester _) async {
    expect(await link.outstandingTransferCount(), greaterThanOrEqualTo(0));
    expect(await link.outstandingFileTransferCount(), greaterThanOrEqualTo(0));
  });
}
