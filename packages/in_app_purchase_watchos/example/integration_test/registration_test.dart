// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Diagnoses which InAppPurchasePlatform implementation is actually live on the
// watch. The app-facing `in_app_purchase` package selects its implementation
// from `defaultTargetPlatform`, so this records what the watch reports and
// whether that selection displaces the watchOS implementation.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:in_app_purchase_watchos/in_app_purchase_watchos.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the app-facing API uses the watchOS implementation, with no app setup',
      (WidgetTester _) async {
    // watchOS reports as iOS, which is what makes `in_app_purchase` try to
    // install its StoreKit method-channel implementation over ours.
    expect(defaultTargetPlatform, TargetPlatform.iOS);
    // ignore: avoid_print
    print('DIAG preemptError=${InAppPurchaseWatchos.preemptError}');

    // registerWith() pre-empted that selection, so we are live from startup...
    expect(InAppPurchasePlatform.instance, isA<InAppPurchaseWatchos>(),
        reason: 'the registrant should have installed us');

    // ...and reading the app-facing singleton — the thing that used to clobber
    // us — must leave us in place, with no registerWith() call by the app.
    InAppPurchase.instance;
    expect(InAppPurchasePlatform.instance, isA<InAppPurchaseWatchos>(),
        reason: 'app-facing selection must not displace the watchOS platform');
  });

  testWidgets('the standard InAppPurchase API reaches StoreKit through FFI',
      (WidgetTester _) async {
    // The plain, documented API — no workaround anywhere in this test.
    final bool available = await InAppPurchase.instance.isAvailable();
    // ignore: avoid_print
    print('DIAG appFacing isAvailable=$available');

    final ProductDetailsResponse r =
        await InAppPurchase.instance.queryProductDetails(<String>{'consumable'});
    // ignore: avoid_print
    print('DIAG appFacing query error=${r.error?.code} notFound=${r.notFoundIDs}');

    // A channel error would mean StoreKit's method channel answered, not us.
    expect(r.error?.code, isNot('channel-error'));
    expect(r.error, isNull);
  });

  testWidgets('the watchOS implementation itself works when used directly',
      (WidgetTester _) async {
    // Bypass the app-facing selection entirely.
    final InAppPurchaseWatchos watchos = InAppPurchaseWatchos();
    final bool available = await watchos.isAvailable();
    // ignore: avoid_print
    print('DIAG direct isAvailable=$available');

    final ProductDetailsResponse r =
        await watchos.queryProductDetails(<String>{'consumable', 'upgrade'});
    // ignore: avoid_print
    print('DIAG direct query error=${r.error?.code} '
        'found=${r.productDetails.map((ProductDetails p) => p.id).toList()} '
        'notFound=${r.notFoundIDs}');

    // The FFI path must complete without a channel error.
    expect(r.error?.code, isNot('channel-error'));
  });
}
