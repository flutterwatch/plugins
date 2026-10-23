// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show FlutterError, FlutterErrorDetails, FlutterExceptionHandler;
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
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

  int drainCalls = 0;

  /// When set, the next [purchasesDrain] throws it instead of returning.
  Object? drainThrows;

  @override
  String purchasesDrain() {
    drainCalls++;
    final Object? error = drainThrows;
    if (error != null) {
      drainThrows = null;
      throw error;
    }
    return drainScript.isNotEmpty ? drainScript.removeAt(0) : '[]';
  }

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

// The error object of a failed update, as native code writes it. 0.1.1 boxed
// `canceled` as a C comparison, an int, which NSJSONSerialization writes as 1
// or 0; native code now writes a JSON boolean.

/// A cancel, as 0.1.1's native code wrote it.
const String _cancelAsNumber =
    '{"code":"2","message":"Cancelled","canceled":1}';

/// Another failure, as 0.1.1's native code wrote it.
const String _failureAsNumber = '{"code":"0","message":"Failed","canceled":0}';

/// A cancel, as native code writes it now.
const String _cancelAsBoolean =
    '{"code":"2","message":"Cancelled","canceled":true}';

/// Another failure, as native code writes it now.
const String _failureAsBoolean =
    '{"code":"0","message":"Failed","canceled":false}';

/// A failed update as the native drain writes it; [error] is the JSON of its
/// error object, verbatim.
String _failedUpdate(String purchaseID, String error) =>
    '{"productID":"coins_100","purchaseID":"$purchaseID","status":"failed",'
    '"receipt":"","error":$error}';

/// A purchased update as the native drain writes it.
String _purchasedUpdate(String purchaseID) =>
    '{"productID":"coins_100","purchaseID":"$purchaseID",'
    '"status":"purchased","receipt":"RECEIPTB64"}';

/// Listens to [stream] from the root zone until the test ends, as a Flutter
/// app does, adding each batch to [batches].
///
/// The drain timer then runs in the root zone too, where a throw out of a
/// periodic timer's callback stops the timer for good. A test's own zone
/// would hide that: it catches the throw, and the timer keeps running. So a
/// throw that escapes the drain fails the whole test file, which is how the
/// test runner reports an error that reached the root zone.
void _listenFromRootZone(
  Stream<List<PurchaseDetails>> stream,
  List<List<PurchaseDetails>> batches,
) {
  final StreamSubscription<List<PurchaseDetails>> subscription =
      Zone.root.run(() => stream.listen(batches.add));
  addTearDown(subscription.cancel);
}

/// Waits until [batches] holds [count] batches, or two seconds have passed.
Future<void> _waitForBatches(
  List<List<PurchaseDetails>> batches,
  int count,
) async {
  const Duration timeout = Duration(seconds: 2);
  final Stopwatch waited = Stopwatch()..start();
  while (batches.length < count && waited.elapsed < timeout) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

/// The purchase IDs of each batch in [batches].
List<List<String?>> _ids(List<List<PurchaseDetails>> batches) =>
    <List<String?>>[
      for (final List<PurchaseDetails> batch in batches)
        <String?>[for (final PurchaseDetails p in batch) p.purchaseID],
    ];

/// Collects what [FlutterError.reportError] receives until the test ends.
List<FlutterErrorDetails> _collectReports() {
  final List<FlutterErrorDetails> reports = <FlutterErrorDetails>[];
  final FlutterExceptionHandler? previous = FlutterError.onError;
  FlutterError.onError = reports.add;
  addTearDown(() => FlutterError.onError = previous);
  return reports;
}

void main() {
  setUp(() {
    InAppPurchaseWatchos.pollInterval = Duration.zero;
    InAppPurchaseWatchos.queryTimeout = const Duration(seconds: 5);
  });

  tearDown(() {
    InAppPurchaseWatchos.drainInterval = const Duration(milliseconds: 500);
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
      runZonedGuarded(
          InAppPurchaseWatchos.registerWith, (Object _, StackTrace __) {});

      expect(InAppPurchasePlatform.instance, isA<InAppPurchaseWatchos>(),
          reason: 'registerWith must install us even if pre-emption fails');
    });

    test('retries a failing pre-emption, then reports giving up', () async {
      InAppPurchaseWatchos.resetPreemptionForTest();
      // Only the quick retries on the next event-loop turns.
      InAppPurchaseWatchos.preemptRetryWindow = Duration.zero;
      int probeCalls = 0;
      InAppPurchaseWatchos.preemptProbe = () {
        probeCalls++;
        throw StateError('Binding has not yet been initialized.');
      };

      InAppPurchaseWatchos.registerWith();
      // Each retry is a Timer.run, so yield until the chain is exhausted.
      for (int i = 0; i < 40 && !InAppPurchaseWatchos.preemptExhausted; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(probeCalls, greaterThan(1),
          reason: 'it must retry, not give up at once');
      expect(InAppPurchaseWatchos.preemptExhausted, isTrue,
          reason:
              'exhaustion must be observable — it silently breaks the plugin');
      expect(InAppPurchaseWatchos.preemptError, isA<StateError>());
      // Even having lost the race, we must still be the installed platform.
      expect(InAppPurchasePlatform.instance, isA<InAppPurchaseWatchos>());
    });

    // `flutter-watchos test -d` starts a test's main() seconds after the
    // registrant, when the quick retries are long gone.
    test('keeps retrying at an interval for a main() that starts late',
        () async {
      InAppPurchaseWatchos.resetPreemptionForTest();
      InAppPurchaseWatchos.preemptRetryInterval =
          const Duration(milliseconds: 1);
      InAppPurchaseWatchos.preemptRetryWindow = const Duration(seconds: 5);
      int probeCalls = 0;
      // The binding arrives after the twenty quick retries and ten slow ones.
      InAppPurchaseWatchos.preemptProbe = () {
        if (++probeCalls <= 30) {
          throw StateError('Binding has not yet been initialized.');
        }
      };

      InAppPurchaseWatchos.registerWith();
      final Stopwatch waited = Stopwatch()..start();
      while (InAppPurchaseWatchos.preemptError != null &&
          waited.elapsed < const Duration(seconds: 5)) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }

      expect(probeCalls, 31);
      expect(InAppPurchaseWatchos.preemptError, isNull);
      expect(InAppPurchaseWatchos.preemptExhausted, isFalse);
      expect(InAppPurchasePlatform.instance, isA<InAppPurchaseWatchos>());
    });

    test('gives up once the retry window has passed', () async {
      InAppPurchaseWatchos.resetPreemptionForTest();
      InAppPurchaseWatchos.preemptRetryInterval =
          const Duration(milliseconds: 2);
      InAppPurchaseWatchos.preemptRetryWindow =
          const Duration(milliseconds: 40);
      int probeCalls = 0;
      InAppPurchaseWatchos.preemptProbe = () {
        probeCalls++;
        throw StateError('Binding has not yet been initialized.');
      };

      InAppPurchaseWatchos.registerWith();
      final Stopwatch waited = Stopwatch()..start();
      while (!InAppPurchaseWatchos.preemptExhausted &&
          waited.elapsed < const Duration(seconds: 5)) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }

      expect(InAppPurchaseWatchos.preemptExhausted, isTrue);
      expect(probeCalls, greaterThan(21),
          reason: 'the interval retries come after the twenty quick ones');
      expect(InAppPurchasePlatform.instance, isA<InAppPurchaseWatchos>());
    });

    test('stops retrying once the pre-emption succeeds', () async {
      InAppPurchaseWatchos.resetPreemptionForTest();
      int probeCalls = 0;
      InAppPurchaseWatchos.preemptProbe = () => probeCalls++;

      InAppPurchaseWatchos.registerWith();
      InAppPurchaseWatchos.registerWith();
      for (int i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(probeCalls, 1,
          reason: 'the selection must be triggered exactly once');
      expect(InAppPurchaseWatchos.preemptExhausted, isFalse);
      expect(InAppPurchaseWatchos.preemptError, isNull);
    });
  });

  group('platform addition', () {
    setUp(() {
      InAppPurchaseWatchos.resetPreemptionForTest();
      InAppPurchasePlatformAddition.instance = null;
    });

    tearDown(() {
      InAppPurchaseWatchos.resetPreemptionForTest();
      InAppPurchasePlatformAddition.instance = null;
    });

    test('registerWith installs the watchOS addition, a StoreKit addition', () {
      InAppPurchaseWatchos.preemptProbe = () {};

      InAppPurchaseWatchos.registerWith();

      expect(InAppPurchasePlatformAddition.instance,
          isA<InAppPurchaseWatchosPlatformAddition>());
      // Upstream code casts the addition to this type.
      expect(InAppPurchasePlatformAddition.instance,
          isA<InAppPurchaseStoreKitPlatformAddition>());
    });

    test('it replaces the StoreKit addition that a succeeding probe installs',
        () {
      // Upstream's registerPlatform() installs StoreKit's method-channel
      // addition before it installs the platform.
      InAppPurchaseWatchos.preemptProbe = () {
        InAppPurchasePlatformAddition.instance =
            InAppPurchaseStoreKitPlatformAddition();
      };

      InAppPurchaseWatchos.registerWith();

      expect(InAppPurchasePlatformAddition.instance,
          isA<InAppPurchaseWatchosPlatformAddition>());
    });

    test(
        'it is installed on the first attempt and after each retry when the '
        'probe installs StoreKit\'s addition and then throws', () async {
      int probeCalls = 0;
      InAppPurchaseWatchos.preemptProbe = () {
        probeCalls++;
        InAppPurchasePlatformAddition.instance =
            InAppPurchaseStoreKitPlatformAddition();
        if (probeCalls <= 2) {
          throw StateError('Binding has not yet been initialized.');
        }
      };

      InAppPurchaseWatchos.registerWith();
      expect(probeCalls, 1);
      expect(InAppPurchasePlatformAddition.instance,
          isA<InAppPurchaseWatchosPlatformAddition>(),
          reason: 'the first, failed attempt must install it');

      // Each retry is a Timer.run; wait for the first retry, which fails too.
      for (int i = 0; i < 40 && probeCalls < 2; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(probeCalls, 2);
      expect(InAppPurchasePlatformAddition.instance,
          isA<InAppPurchaseWatchosPlatformAddition>(),
          reason: 'a failed retry must install it again');

      // The third attempt succeeds.
      for (int i = 0; i < 40 && probeCalls < 3; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(probeCalls, 3);
      expect(InAppPurchaseWatchos.preemptError, isNull);
      expect(InAppPurchasePlatformAddition.instance,
          isA<InAppPurchaseWatchosPlatformAddition>(),
          reason: 'the succeeding retry must install it too');
    });

    test('each of the five methods fails with a Future, never synchronously',
        () async {
      final InAppPurchaseWatchosPlatformAddition addition =
          InAppPurchaseWatchosPlatformAddition();
      final Map<String, Future<Object?> Function()> calls =
          <String, Future<Object?> Function()>{
        'sync': addition.sync,
        'presentCodeRedemptionSheet': addition.presentCodeRedemptionSheet,
        'refreshPurchaseVerificationData':
            addition.refreshPurchaseVerificationData,
        'setDelegate': () => addition.setDelegate(null),
        'showPriceConsentIfNeeded': addition.showPriceConsentIfNeeded,
      };

      for (final MapEntry<String, Future<Object?> Function()> call
          in calls.entries) {
        late Future<Object?> result;
        expect(() => result = call.value(), returnsNormally, reason: call.key);
        await expectLater(
          result,
          throwsA(isA<UnsupportedError>()
              .having((UnsupportedError e) => e.message, 'message',
                  contains('watchOS'))
              .having((UnsupportedError e) => e.message, 'message',
                  contains(call.key))),
          reason: call.key,
        );
      }
    });
  });

  group('purchase stream lifecycle', () {
    test('polls only while listened to, and never after close', () async {
      final fake = _FakeBindings(result: null);
      InAppPurchaseWatchos.bindingsOverride = fake;
      InAppPurchaseWatchos.drainInterval = const Duration(milliseconds: 5);

      final Stream<List<PurchaseDetails>> stream =
          InAppPurchaseWatchos().purchaseStream;
      // The observer is installed eagerly (StoreKit re-delivers unfinished
      // transactions at launch), but nothing should poll yet.
      expect(fake.startObserverCalls, 1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fake.drainCalls, 0,
          reason: 'polling with no listener just burns watch battery');

      final sub = stream.listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fake.drainCalls, greaterThan(0),
          reason: 'it must poll while listened to');

      await sub.cancel();
      final int afterCancel = fake.drainCalls;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fake.drainCalls, afterCancel,
          reason: 'the last listener leaving must stop the timer');
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
      await expectLater(platform.queryProductDetails(<String>{'a'}), completes);
      await expectLater(platform.restorePurchases(), completes);
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
          InAppPurchaseWatchos.parseProductDetailsResponse(
              null, <String>{'a', 'b'});
      expect(r.error, isNotNull);
      expect(r.error!.code, 'no_result');
      expect(r.notFoundIDs, containsAll(<String>['a', 'b']));
    });

    test('malformed JSON is reported as bad_result', () {
      final ProductDetailsResponse r =
          InAppPurchaseWatchos.parseProductDetailsResponse(
              '{not json', <String>{'a'});
      expect(r.error?.code, 'bad_result');
    });

    test('missing product fields fall back to safe defaults', () {
      final json = jsonEncode(<String, dynamic>{
        'products': <dynamic>[
          <String, dynamic>{'id': 'only_id'},
        ],
      });
      final ProductDetails p = InAppPurchaseWatchos.parseProductDetailsResponse(
          json, <String>{'only_id'}).productDetails.single;
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
          <String, dynamic>{
            'productID': 'a',
            'purchaseID': 'r1',
            'status': 'restored'
          },
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

    test('null / empty / malformed yield no updates, and malformed is reported',
        () {
      final List<FlutterErrorDetails> reports = _collectReports();

      expect(InAppPurchaseWatchos.parsePurchaseUpdates(null), isEmpty);
      expect(InAppPurchaseWatchos.parsePurchaseUpdates(''), isEmpty);
      expect(reports, isEmpty, reason: 'no updates is not an error');

      expect(InAppPurchaseWatchos.parsePurchaseUpdates('{not json'), isEmpty);
      expect(InAppPurchaseWatchos.parsePurchaseUpdates('{}'), isEmpty);
      expect(reports, hasLength(2),
          reason: 'a drain that is not a JSON array must not vanish silently');
      for (final FlutterErrorDetails report in reports) {
        expect(report.library, 'in_app_purchase_watchos');
      }
    });

    test('reads canceled as a JSON boolean, and as the 1 or 0 that 0.1.1 sent',
        () {
      final List<FlutterErrorDetails> reports = _collectReports();
      final String json = '[${_failedUpdate('f1', _cancelAsBoolean)},'
          '${_failedUpdate('f2', _failureAsBoolean)},'
          '${_failedUpdate('f3', _cancelAsNumber)},'
          '${_failedUpdate('f4', _failureAsNumber)},'
          // Neither a missing flag nor one of another type is a cancel.
          '${_failedUpdate('f5', '{"code":"2","message":"Cancelled"}')},'
          '${_failedUpdate('f6', '{"code":"2","canceled":"true"}')}]';

      final List<PurchaseDetails> d =
          InAppPurchaseWatchos.parsePurchaseUpdates(json);

      expect(d.map((PurchaseDetails p) => p.purchaseID).toList(),
          <String>['f1', 'f2', 'f3', 'f4', 'f5', 'f6']);
      expect(d.map((PurchaseDetails p) => p.status).toList(), <PurchaseStatus>[
        PurchaseStatus.canceled,
        PurchaseStatus.error,
        PurchaseStatus.canceled,
        PurchaseStatus.error,
        PurchaseStatus.error,
        PurchaseStatus.error,
      ]);
      for (final PurchaseDetails p in d) {
        expect(p.error?.code, isNotEmpty, reason: p.purchaseID);
        // StoreKit keeps a failed transaction until it is finished.
        expect(p.pendingCompletePurchase, isTrue, reason: p.purchaseID);
      }
      expect(reports, isEmpty, reason: 'every update here is readable');
    });

    test('leaves out and reports an update it cannot read, keeps the rest', () {
      final List<FlutterErrorDetails> reports = _collectReports();
      final String json = '[${_purchasedUpdate('p1')},'
          '{"productID":"a","purchaseID":"x1","status":7},'
          '"not an update",'
          '${_failedUpdate('x2', '"not an error object"')},'
          '${_purchasedUpdate('p2')}]';

      final List<PurchaseDetails> d =
          InAppPurchaseWatchos.parsePurchaseUpdates(json);

      expect(d.map((PurchaseDetails p) => p.purchaseID).toList(),
          <String>['p1', 'p2']);
      expect(reports, hasLength(3));
      for (final FlutterErrorDetails report in reports) {
        expect(report.library, 'in_app_purchase_watchos');
      }
      // Each report says which update of the batch it left out.
      expect(
          reports.map((FlutterErrorDetails r) => r.context.toString()),
          <Matcher>[
            contains('2 of 5'),
            contains('3 of 5'),
            contains('4 of 5')
          ]);
    });
  });

  group('purchase actions', () {
    late _FakeBindings fake;
    setUp(() {
      fake = _FakeBindings(result: null);
      InAppPurchaseWatchos.bindingsOverride = fake;
    });

    test('buyNonConsumable forwards the product id and returns the result',
        () async {
      fake.buyResult = true;
      final bool ok = await InAppPurchaseWatchos().buyNonConsumable(
        purchaseParam: PurchaseParam(
            productDetails: _product('premium'), applicationUserName: 'u42'),
      );
      expect(ok, isTrue);
      expect(fake.lastBuy, <Object?>['premium', 'u42', 1]);
    });

    test('buyConsumable forwards and returns false when the queue rejects',
        () async {
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
              localVerificationData: '',
              serverVerificationData: '',
              source: 'app_store'),
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
              localVerificationData: '',
              serverVerificationData: '',
              source: 'app_store'),
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
        <String, dynamic>{
          'productID': 'coins_100',
          'purchaseID': 't1',
          'status': 'purchased'
        },
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

    // 0.1.1 lost every failed update this way, and the stream with it: the
    // `as bool?` cast threw in the drain timer, which then never ran again.
    test(
        'a failed update with canceled as 1 or true reaches an app, and later '
        'batches still arrive', () async {
      final List<FlutterErrorDetails> reports = _collectReports();
      final fake = _FakeBindings(result: null);
      fake.drainScript.addAll(<String>[
        '[${_failedUpdate('f1', _cancelAsNumber)}]',
        '[${_failedUpdate('f2', _cancelAsBoolean)}]',
        '[${_purchasedUpdate('p1')}]',
      ]);
      InAppPurchaseWatchos.bindingsOverride = fake;
      InAppPurchaseWatchos.drainInterval = const Duration(milliseconds: 1);

      final List<List<PurchaseDetails>> batches = <List<PurchaseDetails>>[];
      _listenFromRootZone(InAppPurchaseWatchos().purchaseStream, batches);
      await _waitForBatches(batches, 3);

      expect(reports, isEmpty, reason: 'every update here is readable');
      expect(_ids(batches), <List<String>>[
        <String>['f1'],
        <String>['f2'],
        <String>['p1'],
      ]);
      expect(
          batches.map((List<PurchaseDetails> b) => b.single.status).toList(),
          <PurchaseStatus>[
            PurchaseStatus.canceled,
            PurchaseStatus.canceled,
            PurchaseStatus.purchased,
          ]);
    });

    test(
        'an update it cannot read is reported, and the rest of its batch and '
        'later batches still arrive', () async {
      final List<FlutterErrorDetails> reports = _collectReports();
      final fake = _FakeBindings(result: null);
      fake.drainScript.addAll(<String>[
        '[{"productID":"a","purchaseID":"x1","status":7},'
            '${_purchasedUpdate('p1')}]',
        '[${_purchasedUpdate('p2')}]',
      ]);
      InAppPurchaseWatchos.bindingsOverride = fake;
      InAppPurchaseWatchos.drainInterval = const Duration(milliseconds: 1);

      final List<List<PurchaseDetails>> batches = <List<PurchaseDetails>>[];
      _listenFromRootZone(InAppPurchaseWatchos().purchaseStream, batches);
      await _waitForBatches(batches, 2);

      expect(_ids(batches), <List<String>>[
        <String>['p1'],
        <String>['p2'],
      ]);
      expect(reports, hasLength(1));
      expect(reports.single.library, 'in_app_purchase_watchos');
    });

    test('a drain that throws is reported, and the next drain still runs',
        () async {
      final List<FlutterErrorDetails> reports = _collectReports();
      final fake = _FakeBindings(result: null)
        ..drainThrows = StateError('the native drain failed');
      fake.drainScript.add('[${_purchasedUpdate('p1')}]');
      InAppPurchaseWatchos.bindingsOverride = fake;
      InAppPurchaseWatchos.drainInterval = const Duration(milliseconds: 1);

      final List<List<PurchaseDetails>> batches = <List<PurchaseDetails>>[];
      _listenFromRootZone(InAppPurchaseWatchos().purchaseStream, batches);
      await _waitForBatches(batches, 1);

      expect(_ids(batches), <List<String>>[
        <String>['p1'],
      ]);
      expect(reports, hasLength(1));
      expect(reports.single.exception, isA<StateError>());
      expect(reports.single.library, 'in_app_purchase_watchos');
    });
  });
}
