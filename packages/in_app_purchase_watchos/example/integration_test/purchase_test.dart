// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// The full purchase round trip against real StoreKit: query → buy → observe the
// transaction on purchaseStream → complete it.
//
// Needs products to exist, which on the Simulator means StoreKit *testing*:
// launch this from Xcode with `watchos/Configuration.storekit` attached to the
// scheme. A CLI launch (`flutter-watchos drive`) does not activate StoreKit
// testing, so the test reports that and skips rather than failing.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:integration_test/integration_test.dart';

const String _kConsumable = 'consumable';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('buy → purchaseStream → completePurchase', (WidgetTester _) async {
    final InAppPurchase iap = InAppPurchase.instance;

    expect(await iap.isAvailable(), isTrue,
        reason: 'StoreKit should allow payments in the test environment');

    final ProductDetailsResponse products =
        await iap.queryProductDetails(<String>{_kConsumable});
    expect(products.error, isNull);

    if (products.productDetails.isEmpty) {
      // ignore: avoid_print
      print('SKIP: no StoreKit products — launch from Xcode with '
          'Configuration.storekit attached. notFound=${products.notFoundIDs}');
      return;
    }
    final ProductDetails product = products.productDetails.single;
    // ignore: avoid_print
    print('DIAG buying ${product.id} at ${product.price}');

    // Collect updates before buying, so nothing is missed.
    final updates = <PurchaseDetails>[];
    final done = Completer<PurchaseDetails>();
    final StreamSubscription<List<PurchaseDetails>> sub =
        iap.purchaseStream.listen((List<PurchaseDetails> batch) {
      for (final PurchaseDetails p in batch) {
        updates.add(p);
        // ignore: avoid_print
        print('DIAG update ${p.productID} status=${p.status} '
            'id=${p.purchaseID} pendingComplete=${p.pendingCompletePurchase} '
            'err=${p.error?.message}');
        if (p.productID == _kConsumable &&
            p.status != PurchaseStatus.pending &&
            !done.isCompleted) {
          done.complete(p);
        }
      }
    });
    addTearDown(sub.cancel);

    final bool started = await iap.buyConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
    // ignore: avoid_print
    print('DIAG buyConsumable started=$started');
    expect(started, isTrue, reason: 'the payment should reach SKPaymentQueue');

    final PurchaseDetails result = await done.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () => throw TimeoutException(
          'no terminal transaction update arrived; saw: '
          '${updates.map((PurchaseDetails p) => "${p.productID}/${p.status}").toList()}'),
    );

    // ignore: avoid_print
    print('DIAG final status=${result.status} receiptLen='
        '${result.verificationData.serverVerificationData.length}');

    expect(result.status, PurchaseStatus.purchased,
        reason: 'error=${result.error?.message}');
    expect(result.productID, _kConsumable);
    expect(result.purchaseID, isNotNull);
    expect(result.pendingCompletePurchase, isTrue);

    // Finishing must not throw, and leaves nothing pending in the queue.
    await iap.completePurchase(result);
    // ignore: avoid_print
    print('DIAG completePurchase OK — round trip verified');
  });
}
