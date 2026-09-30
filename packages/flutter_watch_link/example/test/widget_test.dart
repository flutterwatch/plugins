// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Host-side test: the example runs against a fake backend, so this needs no
// device. It is here to catch the example rotting — a renamed API breaks the
// build, and a UI that stops reacting to state breaks this.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_watch_link/flutter_watch_link.dart';
import 'package:flutter_watch_link_example/main.dart';

void main() {
  late FakeLink link;

  setUp(() {
    link = FakeLink();
    WatchLink.backendOverride = link;
  });

  tearDown(() => WatchLink.backendOverride = null);

  testWidgets('renders the session flags and reacts to state changes',
      (WidgetTester tester) async {
    await tester.pumpWidget(const DemoApp(forceCompact: false));
    await tester.pumpAndSettle();

    for (final String flag in <String>[
      'activated',
      'paired',
      'installed',
      'reachable',
    ]) {
      expect(find.text(flag), findsOneWidget);
    }

    link.emitState(const WatchLinkState(
      activated: true,
      reachable: true,
      counterpartInstalled: true,
      counterpartPaired: true,
    ));
    await tester.pumpAndSettle();

    // The flags are colour-coded, so assert the colour rather than the label —
    // the label is present either way.
    final Container chip = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('reachable'),
            matching: find.byType(Container),
          )
          .first,
    );
    expect((chip.decoration! as BoxDecoration).color, Colors.teal);
  });

  // The watch screens this example runs on, in logical pixels: 40 mm,
  // 41 mm, 42 mm (Series 10 and 11), 44 mm, 45 mm, 46 mm and 49 mm.
  const List<Size> watchScreens = <Size>[
    Size(162, 197),
    Size(176, 215),
    Size(187, 223),
    Size(184, 224),
    Size(198, 242),
    Size(208, 248),
    Size(205, 251),
  ];

  for (final Size screen in watchScreens) {
    testWidgets(
        'the watch layout fits a ${screen.width.toInt()}x'
        '${screen.height.toInt()} screen', (WidgetTester tester) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = screen * 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const DemoApp(forceCompact: true));
      await tester.pumpAndSettle();

      // An overflow is reported as a FlutterError, which fails the test on
      // its own; this names the case if it ever does.
      expect(tester.takeException(), isNull);
      expect(find.text('activated'), findsOneWidget);
    });
  }

  testWidgets('a send failure is reported rather than thrown',
      (WidgetTester tester) async {
    // The example's whole error story: sendMessage throws when the counterpart
    // is not reachable, and the UI has to survive that.
    link.failSends = true;
    await tester.pumpWidget(const DemoApp(forceCompact: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('message'));
    await tester.pumpAndSettle();

    expect(find.textContaining('sendMessage failed'), findsOneWidget);
  });

  testWidgets('an inbound message that expects a reply is answered',
      (WidgetTester tester) async {
    await tester.pumpWidget(const DemoApp(forceCompact: false));
    await tester.pumpAndSettle();

    final List<Map<String, Object?>> replies = <Map<String, Object?>>[];
    link.emitMessage(WatchLinkMessage(
      payload: <String, Object?>{'n': 7},
      tier: WatchLinkTier.message,
      replyId: 1,
      responder: (Map<String, Object?> r) async => replies.add(r),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('message: {n: 7}'), findsOneWidget);
    expect(replies.single, <String, Object?>{'ack': 7});
  });
}

/// A [WatchLinkBackend] with no native side, driven by the test.
class FakeLink implements WatchLinkBackend {
  bool failSends = false;

  final StreamController<WatchLinkMessage> _messages =
      StreamController<WatchLinkMessage>.broadcast();
  final StreamController<WatchLinkState> _states =
      StreamController<WatchLinkState>.broadcast();
  final StreamController<String> _errors = StreamController<String>.broadcast();
  final StreamController<WatchLinkFile> _files =
      StreamController<WatchLinkFile>.broadcast();

  void emitState(WatchLinkState s) => _states.add(s);

  void emitMessage(WatchLinkMessage m) => _messages.add(m);

  void _failIfAsked() {
    if (failSends) {
      throw const WatchLinkException('not reachable', code: 'not-reachable');
    }
  }

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<void> activate() async {}

  @override
  Future<WatchLinkState> readState() async => WatchLinkState.unknown;

  @override
  Future<void> sendMessage(Map<String, Object?> payload) async =>
      _failIfAsked();

  @override
  Future<Map<String, Object?>> sendMessageWithReply(
    Map<String, Object?> payload, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    _failIfAsked();
    return <String, Object?>{'pong': true};
  }

  @override
  Future<void> transferFile(String path,
      {Map<String, Object?>? metadata}) async {}

  @override
  Future<int> outstandingFileTransferCount() async => 0;

  @override
  Stream<WatchLinkFile> get files => _files.stream;

  @override
  Future<void> updateApplicationContext(Map<String, Object?> payload) async {}

  @override
  Future<void> transferUserInfo(Map<String, Object?> payload) async {}

  @override
  Future<Map<String, Object?>?> receivedApplicationContext() async => null;

  @override
  Future<Map<String, Object?>?> sentApplicationContext() async => null;

  @override
  Future<int> outstandingTransferCount() async => 0;

  @override
  Stream<WatchLinkMessage> get messages => _messages.stream;

  @override
  Stream<WatchLinkState> get states => _states.stream;

  @override
  Stream<String> get errors => _errors.stream;

  @override
  Future<void> dispose() async {}
}
