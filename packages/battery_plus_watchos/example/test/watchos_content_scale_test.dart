// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// A watchOS supplement, not an upstream test. The example is battery_plus's
// own phone app, kept verbatim; it fits a watch only through the
// FlutterWatchOSContentScale in watchos/Runner/Info.plist. This lays the app
// out in the logical space that scale gives each watch screen, with room for
// the system insets, and fails on any overflow.

import 'dart:io';

import 'package:battery_plus_example/main.dart';
import 'package:battery_plus_platform_interface/battery_plus_platform_interface.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers every call at once, so the page settles without a platform.
class _FakeBattery extends BatteryPlatform {
  @override
  Future<int> get batteryLevel async => 80;

  @override
  Future<BatteryState> get batteryState async => BatteryState.full;

  @override
  Future<bool> get isInBatterySaveMode async => false;

  @override
  Stream<BatteryState> get onBatteryStateChanged =>
      const Stream<BatteryState>.empty();
}

/// The FlutterWatchOSContentScale the example's runner sets.
double _contentScale() {
  final String plist = File('watchos/Runner/Info.plist').readAsStringSync();
  final RegExpMatch? match = RegExp(
    r'<key>FlutterWatchOSContentScale</key>\s*<real>([0-9.]+)</real>',
  ).firstMatch(plist);
  expect(match, isNotNull, reason: 'Info.plist sets no content scale');
  return double.parse(match!.group(1)!);
}

void main() {
  // The watch screens, in points: 40 mm, 41 mm, 42 mm (Series 10 and 11),
  // 44 mm, 45 mm, 46 mm and 49 mm.
  const List<Size> watchScreens = <Size>[
    Size(162, 197),
    Size(176, 215),
    Size(187, 223),
    Size(184, 224),
    Size(198, 242),
    Size(208, 248),
    Size(205, 251),
  ];

  setUp(() => BatteryPlatform.instance = _FakeBattery());

  for (final Size screen in watchScreens) {
    testWidgets(
        'the example fits a ${screen.width.toInt()}x'
        '${screen.height.toInt()} watch at its content scale',
        (WidgetTester tester) async {
      final double scale = _contentScale();
      // One logical pixel is `scale` points, so the app lays out in a space
      // 1/scale the screen's size; the insets, 40 points at the top and 20 at
      // the bottom, grow the same way.
      const double dpr = 2;
      tester.view.devicePixelRatio = dpr;
      tester.view.physicalSize = screen / scale * dpr;
      tester.view.padding = FakeViewPadding(
        top: 40 / scale * dpr,
        bottom: 20 / scale * dpr,
      );
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      // An overflow is reported as a FlutterError, which fails the test on
      // its own; this names the case if it ever does.
      expect(tester.takeException(), isNull);
      expect(find.text('full'), findsOneWidget);
    });
  }
}
