// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Exercises the plugin against real StoreKit on the device/simulator.
//
// Requires products to exist: either the `watchos/Configuration.storekit`
// test configuration (StoreKit testing) or an App Store Connect sandbox.
// Without either, StoreKit legitimately reports every id as not-found and the
// product test is skipped rather than failed — the availability and
// no-throw assertions still run, since those must hold regardless.

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:integration_test/integration_test.dart';

const Set<String> _kProductIds = <String>{
  'consumable',
  'upgrade',
  'subscription_silver',
  'subscription_gold',
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('isAvailable() answers without throwing', (WidgetTester _) async {
    // The first call every app makes; it must never throw.
    final bool available = await InAppPurchase.instance.isAvailable();
    expect(available, isA<bool>());
  });

  testWidgets('queryProductDetails reaches StoreKit and returns a response',
      (WidgetTester _) async {
    final ProductDetailsResponse response =
        await InAppPurchase.instance.queryProductDetails(_kProductIds);

    // Whatever StoreKit says, the round trip must complete without error and
    // account for every id exactly once.
    expect(response.error, isNull,
        reason: 'StoreKit returned an error: ${response.error?.message}');
    final Set<String> seen = <String>{
      ...response.productDetails.map((ProductDetails p) => p.id),
      ...response.notFoundIDs,
    };
    expect(seen, equals(_kProductIds));

    if (response.productDetails.isEmpty) {
      // No StoreKit configuration is active — nothing more to assert.
      // ignore: avoid_print
      print('SKIP: no products configured; notFound=${response.notFoundIDs}');
      return;
    }

    // ignore: avoid_print
    print('FOUND ${response.productDetails.length} products: '
        '${response.productDetails.map((ProductDetails p) => "${p.id}@${p.price}").join(", ")}');
    for (final ProductDetails p in response.productDetails) {
      expect(p.id, isNotEmpty);
      expect(p.title, isNotEmpty);
      expect(p.price, isNotEmpty, reason: '${p.id} has no formatted price');
      expect(p.rawPrice, greaterThan(0), reason: '${p.id} has no raw price');
      expect(p.currencyCode, isNotEmpty);
    }
  });
}
