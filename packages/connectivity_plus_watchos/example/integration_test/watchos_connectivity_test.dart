// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Supplementary watchOS test, next to the upstream connectivity_plus_test.dart
// (which it does not replace). Run it with the host Mac online.
//
// The native path monitor delivers its first path a moment after it starts.
// Before 0.2.1 the first checkConnectivity() and the first stream event both
// reported [none], followed a few milliseconds later by the real value. This
// file reads both at start-up, before anything else in the app has started
// the monitor, and checks that neither is [none].

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'the first checkConnectivity() and the first stream event are not none',
      (WidgetTester _) async {
    final Connectivity connectivity = Connectivity();

    // Both are started in the same turn, so both meet the monitor before it
    // has delivered its first path.
    final Future<List<ConnectivityResult>> checked =
        connectivity.checkConnectivity();
    final Future<List<ConnectivityResult>> firstEvent = connectivity
        .onConnectivityChanged.first
        .timeout(const Duration(seconds: 5));

    final List<ConnectivityResult> checkResult = await checked;
    final List<ConnectivityResult> eventResult = await firstEvent;
    // ignore: avoid_print
    print('watchos_connectivity: first check $checkResult, '
        'first event $eventResult');

    expect(checkResult, isNot(<ConnectivityResult>[ConnectivityResult.none]),
        reason: 'the host is online, so the first check must see it');
    expect(eventResult, isNot(<ConnectivityResult>[ConnectivityResult.none]),
        reason: 'the host is online, so the first event must see it');
  });
}
