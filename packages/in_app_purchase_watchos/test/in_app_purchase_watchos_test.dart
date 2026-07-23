// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

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
}

void main() {
  setUp(() {
    InAppPurchaseWatchos.pollInterval = Duration.zero;
    InAppPurchaseWatchos.queryTimeout = const Duration(seconds: 5);
  });

  tearDown(() {
    InAppPurchaseWatchos.bindingsOverride = null;
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
}
