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

  testWidgets('KNOWN UPSTREAM LIMITATION: the app-facing singleton displaces us',
      (WidgetTester _) async {
    // `in_app_purchase` selects its implementation from `defaultTargetPlatform`
    // rather than from the plugin registrant. watchOS reports as iOS, so
    // touching `InAppPurchase.instance` registers the StoreKit *method channel*
    // implementation over ours — and method channels do not exist on watchOS,
    // so every call then fails with `channel-error`.
    //
    // This test pins that behaviour. If it ever FAILS, upstream has fixed the
    // selection: delete the registerWith() workaround from the README and the
    // test below.
    expect(defaultTargetPlatform, TargetPlatform.iOS,
        reason: 'watchOS reports as iOS; that is what triggers the override');

    // The registrant does register us correctly first.
    expect(InAppPurchasePlatform.instance, isA<InAppPurchaseWatchos>(),
        reason: 'the watchOS registrant should install us at startup');

    InAppPurchase.instance; // one-time platform selection runs here
    expect(InAppPurchasePlatform.instance, isNot(isA<InAppPurchaseWatchos>()),
        reason: 'if this fails, upstream no longer clobbers us — remove the workaround');
  });

  testWidgets('re-registering after the app-facing singleton takes the platform back',
      (WidgetTester _) async {
    // `InAppPurchase._getOrCreateInstance()` performs its platform selection
    // exactly once, and every InAppPurchase method reads
    // `InAppPurchasePlatform.instance` at call time. So re-registering after
    // the first touch should stick, letting apps keep the standard API.
    InAppPurchase.instance; // one-time selection: registers StoreKit.
    InAppPurchaseWatchos.registerWith(); // take it back.

    expect(InAppPurchasePlatform.instance, isA<InAppPurchaseWatchos>());

    // The standard API must now route through the watchOS FFI implementation.
    final bool available = await InAppPurchase.instance.isAvailable();
    // ignore: avoid_print
    print('DIAG viaAppFacingAfterReregister isAvailable=$available');

    final ProductDetailsResponse r =
        await InAppPurchase.instance.queryProductDetails(<String>{'consumable'});
    // ignore: avoid_print
    print('DIAG viaAppFacing query error=${r.error?.code} '
        'notFound=${r.notFoundIDs}');
    // A channel error would mean StoreKit's method channel answered, not us.
    expect(r.error?.code, isNot('channel-error'));
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
