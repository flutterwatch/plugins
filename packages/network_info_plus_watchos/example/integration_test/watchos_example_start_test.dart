// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// A watchOS supplement to the upstream network_info_plus_test.dart, which
// stays verbatim. The upstream example asks permission_handler for location
// access at start, behind Platform.isIOS, which is true on the watch;
// permission_handler_watchos answers it there. This starts the example,
// checks that it starts without an error, and then that it reaches its
// network info.
//
// The network info waits for the answer to the location prompt. A run where
// location was answered before (the Simulator keeps the answer across
// installs) checks it at once. On a fresh install the prompt stays up with
// no one to answer it, so that check is skipped unless the run passes
// --dart-define=NIP_PROMPT=true, where someone answers the prompt within a
// minute. Answering it in advance also works:
//   xcrun simctl privacy <watch-sim> grant location \
//     com.example.networkInfoPlusExample.watchkitapp
//
// Run on the watch Simulator:
//   flutter-watchos drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/watchos_example_start_test.dart -d <watch-sim>

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_info_plus_example/main.dart' as app;
import 'package:permission_handler/permission_handler.dart';

/// Whether someone answers the location prompt on this run
/// (`--dart-define=NIP_PROMPT=true`).
const bool _prompt = bool.fromEnvironment('NIP_PROMPT');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the example starts and shows its network info',
      (WidgetTester tester) async {
    // "denied" is a location prompt not answered yet: the example's request
    // at start shows it, and the network info waits for it.
    final bool answered =
        await Permission.locationWhenInUse.status != PermissionStatus.denied;

    app.main();
    final Stopwatch elapsed = Stopwatch()..start();
    while (elapsed.elapsed < const Duration(seconds: 3)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);

    if (!answered && !_prompt) {
      markTestSkipped('the location prompt is up with no one to answer it: '
          'run with --dart-define=NIP_PROMPT=true and answer it, or grant '
          'location first');
      return;
    }

    // The info arrives after the answer and seven native reads.
    final Duration limit =
        answered ? const Duration(seconds: 10) : const Duration(seconds: 60);
    final Finder info = find.textContaining('Wifi IPv4:');
    while (info.evaluate().isEmpty && elapsed.elapsed < limit) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull);
    expect(info, findsOneWidget,
        reason: 'the example did not finish reading the network info');
    expect(find.textContaining('Failed to get'), findsNothing);
  });
}
