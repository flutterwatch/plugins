// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Runs in a browser: `flutter test --platform chrome test/web_test.dart`.
//
// The point is not that WatchConnectivity works on web — it cannot. It is that
// depending on this package does not break a web build, and that an app which
// reaches for a session anyway gets an error that says why. The compile half
// of that is proven by this file existing at all: if the public library pulled
// in `dart:ffi` unconditionally, this suite would not compile.
@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_watch_link/flutter_watch_link.dart';

void main() {
  tearDown(() => WatchLink.backendOverride = null);

  test('the package compiles for web and its types are usable', () {
    // Platform-neutral types must be real classes here, not stubs — app code
    // shares models across platforms and only branches at the session.
    const WatchLinkState s = WatchLinkState(
      activated: false,
      reachable: false,
      counterpartInstalled: false,
      counterpartPaired: false,
    );
    expect(s, WatchLinkState.unknown);
    expect(WatchLinkTier.values, hasLength(4));
    expect(
      const WatchLinkMessage(
        payload: <String, Object?>{'a': 1},
        tier: WatchLinkTier.userInfo,
      ).expectsReply,
      isFalse,
    );
  });

  test('opening a session fails with an explanation, not a crash', () {
    Object? thrown;
    try {
      WatchLink.instance.isSupported();
    } on Object catch (e) {
      thrown = e;
    }
    expect(thrown, isA<UnsupportedError>());
    // The message has to name the cause and the way out; "Unsupported
    // operation: null" would leave a caller with nothing to act on.
    final String message = thrown.toString();
    expect(message, contains('WatchConnectivity'));
    expect(message, contains('backendOverride'));
  });

  test('registerWith is a harmless no-op', () {
    // The CLI's generated registrant never runs on web, but the symbol is
    // exported everywhere so the export list does not vary by platform.
    expect(FlutterWatchLink.registerWith, returnsNormally);
  });

  test('an injected backend works normally on web', () {
    // The supported way to run shared app logic in a browser: supply a fake
    // session rather than branching every call site.
    WatchLink.backendOverride = _StubBackend();
    expect(WatchLink.backend, isA<_StubBackend>());
  });
}

class _StubBackend implements WatchLinkBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
