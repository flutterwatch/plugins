// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `in_app_purchase`, over dart:ffi.
// Source plugin: in_app_purchase_storekit. See PORTING_REPORT.md.
//
// First slice: queryProductDetails via StoreKit's SKProductsRequest. StoreKit
// purchasing works on watchOS from 6.2, but the UI surfaces
// (SKStoreProductViewController, the review prompt, code redemption) do not
// exist on the watch — those platform-interface methods are intentionally not
// implemented here.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';

/// The watchOS implementation of [InAppPurchasePlatform].
class InAppPurchaseWatchos extends InAppPurchasePlatform {
  /// Test hook: set before first use to replace the FFI bindings.
  @visibleForTesting
  static InAppPurchaseWatchosBindings? bindingsOverride;

  static InAppPurchaseWatchosBindings? _bindings;

  static InAppPurchaseWatchosBindings get _b =>
      bindingsOverride ?? (_bindings ??= InAppPurchaseWatchosBindings());

  /// Registers this class as the [InAppPurchasePlatform] implementation.
  static void registerWith() {
    InAppPurchasePlatform.instance = InAppPurchaseWatchos();
  }

  /// How often the native query is polled for completion.
  @visibleForTesting
  static Duration pollInterval = const Duration(milliseconds: 50);

  /// How long to wait for StoreKit before giving up with a timeout error.
  @visibleForTesting
  static Duration queryTimeout = const Duration(seconds: 30);

  static const String _errorSource = 'app_store';

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    final InAppPurchaseWatchosBindings b = _b;
    final int handle = b.queryStart(jsonEncode(identifiers.toList()));
    if (handle == 0) {
      return _errorResponse(identifiers, 'start_failed',
          'Could not start the StoreKit product query.');
    }
    try {
      final Stopwatch elapsed = Stopwatch()..start();
      while (!b.queryReady(handle)) {
        if (elapsed.elapsed > queryTimeout) {
          return _errorResponse(
              identifiers, 'timeout', 'StoreKit product query timed out.');
        }
        await Future<void>.delayed(pollInterval);
      }
      return parseProductDetailsResponse(b.queryResult(handle), identifiers);
    } finally {
      b.queryRelease(handle);
    }
  }

  static ProductDetailsResponse _errorResponse(
    Set<String> requested,
    String code,
    String message,
  ) =>
      ProductDetailsResponse(
        productDetails: const <ProductDetails>[],
        notFoundIDs: requested.toList(),
        error: IAPError(source: _errorSource, code: code, message: message),
      );

  /// Parses the native result JSON (see the C header) into a
  /// [ProductDetailsResponse]. Exposed for unit tests.
  @visibleForTesting
  static ProductDetailsResponse parseProductDetailsResponse(
    String? rawJson,
    Set<String> requested,
  ) {
    if (rawJson == null || rawJson.isEmpty) {
      return _errorResponse(
          requested, 'no_result', 'No result from the StoreKit query.');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(rawJson);
    } on FormatException {
      return _errorResponse(
          requested, 'bad_result', 'Malformed StoreKit query result.');
    }
    if (decoded is! Map<String, dynamic>) {
      return _errorResponse(
          requested, 'bad_result', 'Malformed StoreKit query result.');
    }

    final products = <ProductDetails>[
      for (final Object? p in (decoded['products'] as List<dynamic>? ?? const <dynamic>[]))
        if (p is Map<String, dynamic>)
          ProductDetails(
            id: p['id'] as String? ?? '',
            title: p['title'] as String? ?? '',
            description: p['description'] as String? ?? '',
            price: p['price'] as String? ?? '',
            rawPrice: (p['rawPrice'] as num?)?.toDouble() ?? 0.0,
            currencyCode: p['currencyCode'] as String? ?? '',
            currencySymbol: p['currencySymbol'] as String? ?? '',
          ),
    ];
    final notFound = <String>[
      for (final Object? id in (decoded['notFound'] as List<dynamic>? ?? const <dynamic>[]))
        if (id is String) id,
    ];

    IAPError? error;
    final Object? err = decoded['error'];
    if (err is Map<String, dynamic>) {
      error = IAPError(
        source: _errorSource,
        code: err['code'] as String? ?? '',
        message: err['message'] as String? ?? '',
      );
    }

    return ProductDetailsResponse(
      productDetails: products,
      notFoundIDs: notFound,
      error: error,
    );
  }

  // --- Purchase flow ---

  static StreamController<List<PurchaseDetails>>? _purchaseController;
  static Timer? _drainTimer;

  /// How often the native transaction queue is drained into [purchaseStream].
  @visibleForTesting
  static Duration drainInterval = const Duration(milliseconds: 500);

  @override
  Stream<List<PurchaseDetails>> get purchaseStream =>
      (_purchaseController ??= _startPurchaseStream()).stream;

  static StreamController<List<PurchaseDetails>> _startPurchaseStream() {
    final InAppPurchaseWatchosBindings b = _b;
    b.purchasesStart();
    final controller = StreamController<List<PurchaseDetails>>.broadcast();
    _drainTimer = Timer.periodic(drainInterval, (_) {
      if (controller.isClosed) {
        return;
      }
      final List<PurchaseDetails> updates = parsePurchaseUpdates(b.purchasesDrain());
      if (updates.isNotEmpty) {
        controller.add(updates);
      }
    });
    return controller;
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async =>
      _b.buy(purchaseParam.productDetails.id,
          purchaseParam.applicationUserName ?? '', 1);

  @override
  Future<bool> buyConsumable({
    required PurchaseParam purchaseParam,
    bool autoConsume = true,
  }) async =>
      _b.buy(purchaseParam.productDetails.id,
          purchaseParam.applicationUserName ?? '', 1);

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    final String? id = purchase.purchaseID;
    if (id != null && id.isNotEmpty) {
      _b.finish(id);
    }
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async =>
      _b.restore(applicationUserName ?? '');

  /// Cancels the drain timer and tears down the stream. For tests only.
  @visibleForTesting
  static void resetPurchaseStreamForTest() {
    _drainTimer?.cancel();
    _drainTimer = null;
    _purchaseController?.close();
    _purchaseController = null;
  }

  /// Parses a native transaction-update JSON array (see the C header) into
  /// [PurchaseDetails]. Exposed for unit tests.
  @visibleForTesting
  static List<PurchaseDetails> parsePurchaseUpdates(String? rawJson) {
    if (rawJson == null || rawJson.isEmpty) {
      return const <PurchaseDetails>[];
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(rawJson);
    } on FormatException {
      return const <PurchaseDetails>[];
    }
    if (decoded is! List<dynamic>) {
      return const <PurchaseDetails>[];
    }
    final out = <PurchaseDetails>[];
    for (final Object? item in decoded) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final Map<String, dynamic>? err = item['error'] as Map<String, dynamic>?;
      final bool canceled = err != null && (err['canceled'] as bool? ?? false);
      final PurchaseStatus status =
          _statusFrom(item['status'] as String? ?? '', canceled: canceled);
      final String receipt = item['receipt'] as String? ?? '';
      final details = PurchaseDetails(
        purchaseID: item['purchaseID'] as String?,
        productID: item['productID'] as String? ?? '',
        transactionDate: item['transactionDate'] as String?,
        status: status,
        verificationData: PurchaseVerificationData(
          localVerificationData: receipt,
          serverVerificationData: receipt,
          source: _errorSource,
        ),
      )..pendingCompletePurchase = status != PurchaseStatus.pending;
      if (err != null) {
        details.error = IAPError(
          source: _errorSource,
          code: err['code'] as String? ?? '',
          message: err['message'] as String? ?? '',
        );
      }
      out.add(details);
    }
    return out;
  }

  static PurchaseStatus _statusFrom(String name, {required bool canceled}) {
    switch (name) {
      case 'purchased':
        return PurchaseStatus.purchased;
      case 'restored':
        return PurchaseStatus.restored;
      case 'failed':
        return canceled ? PurchaseStatus.canceled : PurchaseStatus.error;
      case 'purchasing':
      case 'deferred':
      default:
        return PurchaseStatus.pending;
    }
  }
}

/// FFI bindings to the native in_app_purchase_watchos C functions.
///
/// Overridable for tests via [InAppPurchaseWatchos.bindingsOverride]; the
/// [InAppPurchaseWatchosBindings.forTesting] constructor skips FFI init so
/// fakes work off-device.
class InAppPurchaseWatchosBindings {
  /// Creates bindings that resolve native symbols in the current process.
  InAppPurchaseWatchosBindings() : _lib = DynamicLibrary.process();

  /// Constructor for fakes/mocks — skips FFI initialization.
  InAppPurchaseWatchosBindings.forTesting() : _lib = null;

  final DynamicLibrary? _lib;

  late final int Function(Pointer<Utf8>) _queryStart = _lib!.lookupFunction<
      Int64 Function(Pointer<Utf8>),
      int Function(Pointer<Utf8>)>('in_app_purchase_watchos_query_start');

  late final bool Function(int) _queryReady = _lib!.lookupFunction<
      Bool Function(Int64),
      bool Function(int)>('in_app_purchase_watchos_query_ready');

  late final Pointer<Utf8> Function(int) _queryResult = _lib!.lookupFunction<
      Pointer<Utf8> Function(Int64),
      Pointer<Utf8> Function(int)>('in_app_purchase_watchos_query_result');

  late final void Function(int) _queryRelease = _lib!.lookupFunction<
      Void Function(Int64),
      void Function(int)>('in_app_purchase_watchos_query_release');

  /// Starts a StoreKit product query for [idsJson] (a JSON array of ids).
  /// Returns a handle, or 0 if the query could not be started.
  int queryStart(String idsJson) {
    final Pointer<Utf8> p = idsJson.toNativeUtf8();
    try {
      return _queryStart(p);
    } finally {
      malloc.free(p);
    }
  }

  /// Whether the query for [handle] has completed (success or failure).
  bool queryReady(int handle) => _queryReady(handle);

  /// The result JSON for [handle], or null if none is available yet.
  String? queryResult(int handle) {
    final Pointer<Utf8> p = _queryResult(handle);
    return p == nullptr ? null : p.toDartString();
  }

  /// Frees the result and handle. Must be called once per [queryStart].
  void queryRelease(int handle) => _queryRelease(handle);

  late final void Function() _purchasesStart = _lib!.lookupFunction<
      Void Function(),
      void Function()>('in_app_purchase_watchos_purchases_start');

  late final bool Function(Pointer<Utf8>, Pointer<Utf8>, int) _buy =
      _lib!.lookupFunction<Bool Function(Pointer<Utf8>, Pointer<Utf8>, Int32),
              bool Function(Pointer<Utf8>, Pointer<Utf8>, int)>(
          'in_app_purchase_watchos_buy');

  late final Pointer<Utf8> Function() _purchasesDrain = _lib!.lookupFunction<
      Pointer<Utf8> Function(),
      Pointer<Utf8> Function()>('in_app_purchase_watchos_purchases_drain');

  late final void Function(Pointer<Utf8>) _finish = _lib!.lookupFunction<
      Void Function(Pointer<Utf8>),
      void Function(Pointer<Utf8>)>('in_app_purchase_watchos_finish');

  late final void Function(Pointer<Utf8>) _restore = _lib!.lookupFunction<
      Void Function(Pointer<Utf8>),
      void Function(Pointer<Utf8>)>('in_app_purchase_watchos_restore');

  /// Installs the StoreKit payment-transaction observer (idempotent).
  void purchasesStart() => _purchasesStart();

  /// Enqueues a payment for a previously-queried product. Returns false if the
  /// product was not cached (i.e. not queried first).
  bool buy(String productId, String applicationUsername, int quantity) {
    final Pointer<Utf8> pid = productId.toNativeUtf8();
    final Pointer<Utf8> user = applicationUsername.toNativeUtf8();
    try {
      return _buy(pid, user, quantity);
    } finally {
      malloc.free(pid);
      malloc.free(user);
    }
  }

  /// Drains pending transaction updates as a JSON array string.
  String purchasesDrain() {
    final Pointer<Utf8> p = _purchasesDrain();
    return p == nullptr ? '[]' : p.toDartString();
  }

  /// Finishes the transaction identified by [purchaseId].
  void finish(String purchaseId) {
    final Pointer<Utf8> p = purchaseId.toNativeUtf8();
    try {
      _finish(p);
    } finally {
      malloc.free(p);
    }
  }

  /// Restores completed purchases; updates arrive via [purchasesDrain].
  void restore(String applicationUsername) {
    final Pointer<Utf8> p = applicationUsername.toNativeUtf8();
    try {
      _restore(p);
    } finally {
      malloc.free(p);
    }
  }
}
