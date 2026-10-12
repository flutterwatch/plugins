// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Host-side: the example against fake GameKit bindings and a fake clock band,
// so it needs no watch. It lays the example out on three watch screens in
// both safe areas, and checks what the example shows when a call fails, as
// every call does on a Simulator with no Game Center account, and when the
// player signs in.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_watchos/flutter_watchos.dart';
import 'package:games_services_example/main.dart';
import 'package:games_services_watchos/games_services_watchos.dart';

/// A watch screen in points, with the insets watchOS reports for it while the
/// clock is shown, and the corner inset the host reports instead in the
/// default safe area, as measured on the watchOS Simulator (the values
/// flutter_watchos's own example test uses).
class _Watch {
  const _Watch(
    this.name,
    this.size, {
    required this.top,
    required this.bottom,
    required this.corner,
  });

  final String name;
  final Size size;

  /// The top inset watchOS reports: the clock's band.
  final double top;

  /// The bottom inset watchOS reports.
  final double bottom;

  /// The inset on all four sides in the default `corners` safe area.
  final double corner;
}

/// The left and right insets watchOS reports, the same on every watch.
const double _sides = 2;

const List<_Watch> _watches = <_Watch>[
  _Watch('40mm', Size(162, 197), top: 40, bottom: 19, corner: 9),
  _Watch('42mm', Size(187, 223), top: 48, bottom: 31, corner: 13),
  _Watch('Ultra 3', Size(211, 257), top: 56.5, bottom: 40, corner: 17),
];

/// The safe area the host reports, selected by the app's
/// `FlutterWatchOSSafeArea` key.
enum _Mode {
  /// The default: the corner inset on all four sides, clock left out.
  corners,

  /// `platform`: the insets watchOS reports, clock included.
  platform,

  /// `platform` under a host that does not report the clock band.
  platformUnreported,
}

/// Stands in for the clock band the watch host reports.
class _ClockBand extends WatchOSNativeBindings {
  _ClockBand(this.band) : super.forTesting();

  final double band;

  @override
  double get clockBandHeight => band;
}

/// GameKit with or without a signed-in account. Without one, as on a
/// Simulator, every call fails.
class _GameKit extends GamesServicesWatchosBindings {
  _GameKit({this.hasAccount = false}) : super.forTesting();

  final bool hasAccount;
  GcAuthState _state = GcAuthState.idle;

  @override
  GcAuthState get authState => _state;

  @override
  String? get lastError => 'The player is not signed in.';

  @override
  String? get playerAlias => _state == GcAuthState.signedIn ? 'Gardener' : null;

  @override
  Future<bool> signIn({Duration timeout = const Duration(seconds: 20)}) async {
    // GameKit answers a launch's sign-in once.
    if (_state == GcAuthState.idle) {
      _state = hasAccount ? GcAuthState.signedIn : GcAuthState.failed;
    }
    return _state == GcAuthState.signedIn;
  }

  @override
  Future<bool> submitScore(
    int score,
    String leaderboardId, {
    Duration timeout = const Duration(seconds: 15),
  }) async =>
      _state == GcAuthState.signedIn;

  @override
  Future<List<GcEntry>?> topScores(
    String leaderboardId, {
    int count = 10,
    Duration timeout = const Duration(seconds: 20),
  }) async =>
      _state == GcAuthState.signedIn ? const <GcEntry>[] : null;
}

void main() {
  setUp(() {
    GamesServicesWatchos.bindingsOverride = _GameKit();
    GamesServicesWatchos.registerWith();
  });

  tearDown(() {
    GamesServicesWatchos.bindingsOverride = null;
    WatchStatusBar.bindingsOverride = null;
  });

  for (final _Watch watch in _watches) {
    for (final _Mode mode in _Mode.values) {
      testWidgets(
          '${watch.name}, ${mode.name}: the list fills the screen, starts '
          'below the clock and insets its rows', (WidgetTester tester) async {
        final double side = mode == _Mode.corners ? watch.corner : _sides;
        final double top = mode == _Mode.corners ? watch.corner : watch.top;
        final double bottom =
            mode == _Mode.corners ? watch.corner : watch.bottom;
        // The host reports the clock's band in both safe areas; a host that
        // does not report it leaves heightOf the view's top padding, which in
        // `platform` is the band too.
        if (mode != _Mode.platformUnreported) {
          WatchStatusBar.bindingsOverride = _ClockBand(watch.top);
        }

        const double pixelRatio = 2;
        tester.view.devicePixelRatio = pixelRatio;
        tester.view.physicalSize = watch.size * pixelRatio;
        final FakeViewPadding insets = FakeViewPadding(
          left: side * pixelRatio,
          top: top * pixelRatio,
          right: side * pixelRatio,
          bottom: bottom * pixelRatio,
        );
        tester.view.padding = insets;
        tester.view.viewPadding = insets;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(const ExampleApp());
        await tester.pumpAndSettle();

        // No SafeArea shrinks the list: it covers the whole screen, so its
        // rows can scroll under the clock and down to the bottom edge.
        expect(tester.getRect(find.byType(ListView)), Offset.zero & watch.size);

        // The first row starts 6 below the clock's band in both safe areas,
        // and 10 inside the side insets.
        final Rect status = tester.getRect(find.text('signed out'));
        expect(status.top, watch.top + 6);
        expect(status.left, side + 10);
        expect(status.right, watch.size.width - side - 10);

        // At rest, no button is in the clock's band.
        for (final Element button in find.byType(TextButton).evaluate()) {
          expect(
            tester.getRect(find.byWidget(button.widget)).top,
            greaterThanOrEqualTo(watch.top),
          );
        }

        // Enough lines in the log to scroll on every screen, then scroll to
        // the end. One jump is not enough: the list builds its rows lazily
        // and learns its full length only once the last ones are built.
        for (int i = 0; i < 6; i++) {
          await tester.tap(find.text('Sign in'));
          await tester.pumpAndSettle();
        }
        final ScrollPosition position =
            tester.state<ScrollableState>(find.byType(Scrollable)).position;
        double extent = -1;
        for (int jumps = 0;
            jumps < 10 && position.maxScrollExtent != extent;
            jumps++) {
          extent = position.maxScrollExtent;
          position.jumpTo(extent);
          await tester.pump();
        }
        expect(position.maxScrollExtent, greaterThan(0));
        expect(position.pixels, position.maxScrollExtent);

        // The last row, the oldest line of the log, ends 6 above the bottom
        // inset.
        final Rect last = tester.getRect(
          find.textContaining('sign-in failed').last,
        );
        expect(last.bottom, watch.size.height - bottom - 6);
      });
    }
  }

  testWidgets('a failed sign-in, submission and read show in the log',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();
    expect(find.text('signed out'), findsOneWidget);

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(
      find.text('sign-in failed: The player is not signed in.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Submit 10'));
    await tester.pumpAndSettle();
    expect(
      find.text('submit failed: Not signed in to Game Center'),
      findsOneWidget,
    );

    await tester.tap(find.text('Load scores'));
    await tester.pumpAndSettle();
    expect(find.text('load failed'), findsOneWidget);
    expect(find.text('signed out'), findsOneWidget);
  });

  testWidgets('a sign-in shows the player', (WidgetTester tester) async {
    GamesServicesWatchos.bindingsOverride = _GameKit(hasAccount: true);
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();
    expect(find.text('signed out'), findsOneWidget);

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Player authenticated successfully'), findsOneWidget);
    expect(find.text('signed in as Gardener'), findsOneWidget);

    await tester.tap(find.text('Load scores'));
    await tester.pumpAndSettle();
    expect(find.text('no scores'), findsOneWidget);
  });
}
