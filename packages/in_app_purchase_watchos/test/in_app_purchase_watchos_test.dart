// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:in_app_purchase_watchos/in_app_purchase_watchos.dart';

/// Drives [InAppPurchaseWatchos] without touching FFI: [queryReady] reports
/// not-ready [readyAfter] times before completing, then [queryResult] returns
/// [result].
class _FakeBindings extends InAppPurchaseWatchosBindings {
  _FakeBindings({
    required this.result,
    this.startHandle = 1,
    this.readyAfter = 0,
  }) : super.forTesting();

  final String? result;
  final int startHandle;
  final int readyAfter;

  int polls = 0;
  int releaseCount = 0;
  String? lastStartJson;

  @override
  int queryStart(String idsJson) {
    lastStartJson = idsJson;
    return startHandle;
  }

  @override
  bool queryReady(int handle) => polls++ >= readyAfter;

  @override
  String? queryResult(int handle) => result;

  @override
  void queryRelease(int handle) => releaseCount++;

  // --- purchase flow ---
  bool canPay = true;
  bool buyResult = true;

  @override
  bool canMakePayments() => canPay;
  int startObserverCalls = 0;
  List<Object?>? lastBuy;
  String? lastFinish;
  String? lastRestore;
  final List<String> drainScript = <String>[];

  @override
  void purchasesStart() => startObserverCalls++;

  @override
  bool buy(String productId, String applicationUsername, int quantity) {
    lastBuy = <Object?>[productId, applicationUsername, quantity];
    return buyResult;
  }

  @override
  String purchasesDrain() =>
      drainScript.isNotEmpty ? drainScript.removeAt(0) : '[]';

  @override
  void finish(String purchaseId) => lastFinish = purchaseId;

  @override
  void restore(String applicationUsername) => lastRestore = applicationUsername;
}

/// A stand-in for whatever implementation the app-facing package would install.
class _OtherPlatform extends InAppPurchasePlatform {}

/// A minimal [ProductDetails] for building [PurchaseParam]s in tests.
ProductDetails _product(String id) => ProductDetails(
      id: id,
      title: id,
      description: id,
      price: r'$0.99',
      rawPrice: 0.99,
      currencyCode: 'USD',
    );

void main() {
  setUp(() {
    InAppPurchaseWatchos.pollInterval = Duration.zero;
    InAppPurchaseWatchos.queryTimeout = const Duration(seconds: 5);
  });

  tearDown(() {
    InAppPurchaseWatchos.resetPurchaseStreamForTest();
    InAppPurchaseWatchos.bindingsOverride = null;
  });

  group('registerWith', () {
    // The end-to-end behaviour (pre-empting the app-facing selection so the
    // plain InAppPurchase API routes here) is verified on a real watch by
    // example/integration_test/registration_test.dart — it needs the watchOS
    // defaultTargetPlatform and a live binding. Here we only pin the invariant
    // that must hold however that attempt goes.
    test('always leaves this implementation as the live platform', () {
      InAppPurchaseWatchos.resetPreemptionForTest();
      InAppPurchasePlatform.instance = _OtherPlatform();

      // Under `flutter test` the host reports as Android, so the pre-emption
      // drives in_app_purchase_android, whose billing client fails
      // asynchronously off-device. That noise is irrelevant here — the watch
      // takes the StoreKit path, which fails synchronously and is caught.
      runZonedGuarded(InAppPurchaseWatchos.registerWith, (Object _, StackTrace __) {});

      expect(InAppPurchasePlatform.instance, isA<InAppPurchaseWatchos>(),
          reason: 'registerWith must install us even if pre-emption fails');
    });
  });

  group('isAvailable', () {
    // Every app calls isAvailable() first; an unimplemented override throws
    // UnimplementedError and the plugin is dead on arrival.
    test('reflects canMakePayments and never throws', () async {
      final fake = _FakeBindings(result: null);
      InAppPurchaseWatchos.bindingsOverride = fake;

      fake.canPay = true;
      expect(await InAppPurchaseWatchos().isAvailable(), isTrue);

      fake.canPay = false;
      expect(await InAppPurchaseWatchos().isAvailable(), isFalse);
    });

    test('every method the example app calls is actually overridden', () async {
      // Regression guard: the base class throws UnimplementedError for anything
      // left unimplemented, which is how isAvailable() slipped through.
      final fake = _FakeBindings(result: '{"products":[],"notFound":[]}');
      InAppPurchaseWatchos.bindingsOverride = fake;
      final platform = InAppPurchaseWatchos();

      await expectLater(platform.isAvailable(), completes);
      await expectLater(
          platform.queryProductDetails(<String>{'a'}), completes);
      await expectLater(
          platform.restorePurchases(), completes);
      await expectLater(
          platform.buyConsumable(
              purchaseParam: PurchaseParam(productDetails: _product('a'))),
          completes);
      await expectLater(
          platform.buyNonConsumable(
              purchaseParam: PurchaseParam(productDetails: _product('a'))),
          completes);
      expect(() => platform.purchaseStream, returnsNormally);
    });
  });

  group('parseProductDetailsResponse', () {
    test('maps products and unknown ids, no error', () {
      final json = jsonEncode(<String, dynamic>{
        'products': <dynamic>[
          <String, dynamic>{
            'id': 'coins_100',
            'title': '100 Coins',
            'description': 'A pile of coins',
            'price': r'$0.99',
            'rawPrice': 0.99,
            'currencyCode': 'USD',
            'currencySymbol': r'$',
          },
        ],
        'notFound': <dynamic>['ghost_product'],
      });

      final ProductDetailsResponse r =
          InAppPurchaseWatchos.parseProductDetailsResponse(
              json, <String>{'coins_100', 'ghost_product'});

      expect(r.error, isNull);
      expect(r.notFoundIDs, <String>['ghost_product']);
      expect(r.productDetails, hasLength(1));
      final ProductDetails p = r.productDetails.single;
      expect(p.id, 'coins_100');
      expect(p.title, '100 Coins');
      expect(p.price, r'$0.99');
      expect(p.rawPrice, 0.99);
      expect(p.currencyCode, 'USD');
      expect(p.currencySymbol, r'$');
    });

    test('surfaces a StoreKit error object as an IAPError', () {
      final json = jsonEncode(<String, dynamic>{
        'products': <dynamic>[],
        'notFound': <dynamic>[],
        'error': <String, dynamic>{'code': '0', 'message': 'Network down'},
      });

      final ProductDetailsResponse r =
          InAppPurchaseWatchos.parseProductDetailsResponse(json, <String>{'x'});

      expect(r.productDetails, isEmpty);
      expect(r.error, isNotNull);
      expect(r.error!.source, 'app_store');
      expect(r.error!.code, '0');
      expect(r.error!.message, 'Network down');
    });

    test('null result is an error, not an empty success', () {
      final ProductDetailsResponse r =
          InAppPurchaseWatchos.parseProductDetailsResponse(null, <String>{'a', 'b'});
      expect(r.error, isNotNull);
      expect(r.error!.code, 'no_result');
      expect(r.notFoundIDs, containsAll(<String>['a', 'b']));
    });

    test('malformed JSON is reported as bad_result', () {
      final ProductDetailsResponse r =
          InAppPurchaseWatchos.parseProductDetailsResponse('{not json', <String>{'a'});
      expect(r.error?.code, 'bad_result');
    });

    test('missing rawPrice / fields fall back to safe defaults', () {
      final json = jsonEncode(<String, dynamic>{
        'products': <dynamic>[
          <String, dynamic>{'id': 'only_id'},
        ],
      });
      final ProductDetails p =
          InAppPurchaseWatchos.parseProductDetailsResponse(json, <String>{'only_id'})
              .productDetails
              .single;
      expect(p.id, 'only_id');
      expect(p.rawPrice, 0.0);
      expect(p.title, '');
      expect(p.currencyCode, '');
    });
  });

  group('queryProductDetails', () {
    test('polls until ready, then parses and releases', () async {
      final fake = _FakeBindings(
        readyAfter: 3,
        result: jsonEncode(<String, dynamic>{
          'products': <dynamic>[
            <String, dynamic>{
              'id': 'sub_monthly',
              'title': 'Monthly',
              'description': 'Monthly sub',
              'price': '€4,99',
              'rawPrice': 4.99,
              'currencyCode': 'EUR',
              'currencySymbol': '€',
            },
          ],
          'notFound': <dynamic>[],
        }),
      );
      InAppPurchaseWatchos.bindingsOverride = fake;

      final ProductDetailsResponse r = await InAppPurchaseWatchos()
          .queryProductDetails(<String>{'sub_monthly'});

      expect(r.error, isNull);
      expect(r.productDetails.single.id, 'sub_monthly');
      expect(r.productDetails.single.rawPrice, 4.99);
      // Started with a JSON array of the requested ids.
      expect(jsonDecode(fake.lastStartJson!), <String>['sub_monthly']);
      // Polled more than once (readyAfter: 3) and released exactly once.
      expect(fake.polls, greaterThan(1));
      expect(fake.releaseCount, 1);
    });

    test('a zero handle is an immediate start_failed error', () async {
      InAppPurchaseWatchos.bindingsOverride =
          _FakeBindings(startHandle: 0, result: null);

      final ProductDetailsResponse r =
          await InAppPurchaseWatchos().queryProductDetails(<String>{'a'});

      expect(r.error?.code, 'start_failed');
      expect(r.notFoundIDs, <String>['a']);
    });

    test('times out when the native query never becomes ready', () async {
      InAppPurchaseWatchos.queryTimeout = const Duration(milliseconds: 20);
      // readyAfter huge => queryReady never returns true within the timeout.
      InAppPurchaseWatchos.bindingsOverride =
          _FakeBindings(readyAfter: 1 << 30, result: null);

      final ProductDetailsResponse r =
          await InAppPurchaseWatchos().queryProductDetails(<String>{'a'});

      expect(r.error?.code, 'timeout');
    });
  });

  group('parsePurchaseUpdates', () {
    test('maps a purchased transaction, marked pending-complete', () {
      final json = jsonEncode(<dynamic>[
        <String, dynamic>{
          'productID': 'coins_100',
          'purchaseID': 't1',
          'transactionDate': '1700000000000',
          'status': 'purchased',
          'receipt': 'RECEIPTB64',
        },
      ]);
      final PurchaseDetails d =
          InAppPurchaseWatchos.parsePurchaseUpdates(json).single;
      expect(d.status, PurchaseStatus.purchased);
      expect(d.productID, 'coins_100');
      expect(d.purchaseID, 't1');
      expect(d.transactionDate, '1700000000000');
      expect(d.verificationData.serverVerificationData, 'RECEIPTB64');
      expect(d.verificationData.source, 'app_store');
      expect(d.pendingCompletePurchase, isTrue);
      expect(d.error, isNull);
    });

    test('failed maps to error; failed+canceled maps to canceled', () {
      final json = jsonEncode(<dynamic>[
        <String, dynamic>{
          'productID': 'a',
          'purchaseID': 'f1',
          'status': 'failed',
          'error': <String, dynamic>{
            'code': '2',
            'message': 'boom',
            'canceled': false,
          },
        },
        <String, dynamic>{
          'productID': 'b',
          'purchaseID': 'f2',
          'status': 'failed',
          'error': <String, dynamic>{
            'code': '2',
            'message': 'user bailed',
            'canceled': true,
          },
        },
      ]);
      final List<PurchaseDetails> d =
          InAppPurchaseWatchos.parsePurchaseUpdates(json);
      expect(d[0].status, PurchaseStatus.error);
      expect(d[0].error!.message, 'boom');
      expect(d[1].status, PurchaseStatus.canceled);
    });

    test('purchasing and deferred are pending, not pending-complete', () {
      for (final String s in <String>['purchasing', 'deferred']) {
        final PurchaseDetails d = InAppPurchaseWatchos.parsePurchaseUpdates(
          jsonEncode(<dynamic>[
            <String, dynamic>{'productID': 'a', 'status': s},
          ]),
        ).single;
        expect(d.status, PurchaseStatus.pending, reason: s);
        expect(d.pendingCompletePurchase, isFalse, reason: s);
      }
    });

    test('restored maps to restored', () {
      final PurchaseDetails d = InAppPurchaseWatchos.parsePurchaseUpdates(
        jsonEncode(<dynamic>[
          <String, dynamic>{'productID': 'a', 'purchaseID': 'r1', 'status': 'restored'},
        ]),
      ).single;
      expect(d.status, PurchaseStatus.restored);
      expect(d.pendingCompletePurchase, isTrue);
    });

    test('a restore failure surfaces as an error with nothing to complete', () {
      // What the native restoreCompletedTransactionsFailedWithError: emits:
      // no productID and no purchaseID, since no transaction exists.
      final PurchaseDetails d = InAppPurchaseWatchos.parsePurchaseUpdates(
        jsonEncode(<dynamic>[
          <String, dynamic>{
            'productID': '',
            'purchaseID': '',
            'status': 'failed',
            'error': <String, dynamic>{
              'code': '16',
              'message': 'Restore failed',
              'canceled': false,
            },
          },
        ]),
      ).single;
      expect(d.status, PurchaseStatus.error);
      expect(d.error!.message, 'Restore failed');
      // Nothing to finish — must not ask the app to complete it.
      expect(d.pendingCompletePurchase, isFalse);
    });

    test('null / empty / malformed yield no updates', () {
      expect(InAppPurchaseWatchos.parsePurchaseUpdates(null), isEmpty);
      expect(InAppPurchaseWatchos.parsePurchaseUpdates(''), isEmpty);
      expect(InAppPurchaseWatchos.parsePurchaseUpdates('{not json'), isEmpty);
      expect(InAppPurchaseWatchos.parsePurchaseUpdates('{}'), isEmpty);
    });
  });

  group('purchase actions', () {
    late _FakeBindings fake;
    setUp(() {
      fake = _FakeBindings(result: null);
      InAppPurchaseWatchos.bindingsOverride = fake;
    });

    test('buyNonConsumable forwards the product id and returns the result', () async {
      fake.buyResult = true;
      final bool ok = await InAppPurchaseWatchos().buyNonConsumable(
        purchaseParam: PurchaseParam(
            productDetails: _product('premium'), applicationUserName: 'u42'),
      );
      expect(ok, isTrue);
      expect(fake.lastBuy, <Object?>['premium', 'u42', 1]);
    });

    test('buyConsumable forwards and returns false when the queue rejects', () async {
      fake.buyResult = false;
      final bool ok = await InAppPurchaseWatchos().buyConsumable(
        purchaseParam: PurchaseParam(productDetails: _product('coins_100')),
      );
      expect(ok, isFalse);
      expect(fake.lastBuy, <Object?>['coins_100', '', 1]);
    });

    test('completePurchase finishes by purchaseID', () async {
      await InAppPurchaseWatchos().completePurchase(
        PurchaseDetails(
          purchaseID: 't9',
          productID: 'coins_100',
          status: PurchaseStatus.purchased,
          transactionDate: '1',
          verificationData: PurchaseVerificationData(
              localVerificationData: '', serverVerificationData: '', source: 'app_store'),
        ),
      );
      expect(fake.lastFinish, 't9');
    });

    test('completePurchase with no id is a no-op', () async {
      await InAppPurchaseWatchos().completePurchase(
        PurchaseDetails(
          productID: 'x',
          status: PurchaseStatus.error,
          transactionDate: null,
          verificationData: PurchaseVerificationData(
              localVerificationData: '', serverVerificationData: '', source: 'app_store'),
        ),
      );
      expect(fake.lastFinish, isNull);
    });

    test('restorePurchases forwards the username', () async {
      await InAppPurchaseWatchos().restorePurchases(applicationUserName: 'u7');
      expect(fake.lastRestore, 'u7');
    });
  });

  group('purchaseStream', () {
    test('installs the observer and drains updates into the stream', () async {
      final fake = _FakeBindings(result: null);
      fake.drainScript.add(jsonEncode(<dynamic>[
        <String, dynamic>{'productID': 'coins_100', 'purchaseID': 't1', 'status': 'purchased'},
      ]));
      InAppPurchaseWatchos.bindingsOverride = fake;
      InAppPurchaseWatchos.drainInterval = const Duration(milliseconds: 1);

      final List<List<PurchaseDetails>> events = <List<PurchaseDetails>>[];
      final sub = InAppPurchaseWatchos().purchaseStream.listen(events.add);

      // Let the periodic drain fire.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await sub.cancel();

      expect(fake.startObserverCalls, 1);
      expect(events, isNotEmpty);
      expect(events.first.single.productID, 'coins_100');
      expect(events.first.single.status, PurchaseStatus.purchased);
    });
  });
}
