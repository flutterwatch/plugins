// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// A watchOS supplement to the upstream network_info_plus_test.dart, which
// stays verbatim. The upstream example asks permission_handler for location
// access behind Platform.isIOS, which is true on the watch, and
// permission_handler has no watchOS implementation: the example started with
// a MissingPluginException. The example now guards that call with
// FlutterWatchosPlatform.isIos. This starts the example and checks that it
// reaches its network info without an error.
//
// Run on the watch Simulator:
//   flutter-watchos drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/watchos_example_start_test.dart -d <watch-sim>

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_info_plus_example/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the example starts and shows its network info',
      (WidgetTester tester) async {
    app.main();

    // The info arrives after seven native reads; give it up to 10 s.
    final Finder info = find.textContaining('Wifi IPv4:');
    final Stopwatch elapsed = Stopwatch()..start();
    while (info.evaluate().isEmpty &&
        elapsed.elapsed < const Duration(seconds: 10)) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull);
    expect(info, findsOneWidget,
        reason: 'the example did not finish reading the network info');
    expect(find.textContaining('Failed to get'), findsNothing);
  });
}
