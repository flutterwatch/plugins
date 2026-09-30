// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// A watchOS supplement to the upstream in_app_purchase_test.dart, which stays
// verbatim. The upstream example calls the StoreKit platform addition behind
// Platform.isIOS, which is true on the watch, where the addition's methods
// fail with an UnsupportedError: the example started with an unhandled
// exception from setDelegate. The example now guards those calls with
// FlutterWatchosPlatform.isIos. This starts the example and checks that it
// gets past its store check without an error.
//
// Run on the watch Simulator:
//   flutter-watchos drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/watchos_example_start_test.dart -d <watch-sim>

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase_example/main.dart' as app;
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the example starts and finishes its store check',
      (WidgetTester tester) async {
    app.main();

    // The store check and the product query go through StoreKit; give them
    // up to 20 s. On a CLI launch StoreKit testing is off, so the query finds
    // no products, which the example shows as "not found".
    final Finder connecting = find.text('Trying to connect...');
    final Stopwatch elapsed = Stopwatch()..start();
    await tester.pump();
    while (connecting.evaluate().isNotEmpty &&
        elapsed.elapsed < const Duration(seconds: 20)) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull);
    expect(connecting, findsNothing,
        reason: 'the example did not finish its store check');
  });
}
