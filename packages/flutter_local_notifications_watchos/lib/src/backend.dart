// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// The C symbols of `watchos/Classes/flutter_local_notifications_watchos_ffi.h`,
// behind an interface so host tests can substitute a fake.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// What woke Dart up. Mirrored in the native header.
abstract final class NotificationsSignal {
  /// A request finished.
  static const int request = 1;

  /// Taps are queued.
  static const int responses = 2;
}

/// The native half of `FlutterLocalNotificationsWatchos`. Every member maps
/// to one exported C function; JSON shapes are the native header's.
abstract class NotificationsWatchosBackend {
  /// Starts `initialize` and returns its request id.
  int initialize(String settingsJson);

  /// Starts a permission request and returns its id.
  int requestPermissions(String optionsJson);

  /// Starts a permission check and returns its id.
  int checkPermissions();

  /// Starts adding a notification and returns the request id.
  int add(String notificationJson);

  /// Removes notification [id], pending and delivered.
  void cancel(int id);

  /// Removes every notification, or only pending ones.
  void cancelAll({required bool pendingOnly});

  /// Starts listing pending notifications and returns the request id.
  int pending();

  /// Starts listing delivered notifications and returns the request id.
  int active();

  /// The launch tap as JSON.
  String launchDetails();

  /// The queued taps as a JSON array, or null when none are.
  String? pollResponses();

  /// The result of request [id] as JSON, or null while it runs.
  String? takeRequestResult(int id);

  /// The function native wakes, or null to stop.
  void setSignalHandler(void Function(int kind)? handler);
}

typedef _SignalNative = Void Function(Int64);

/// [NotificationsWatchosBackend] over the exported C functions.
class FfiNotificationsWatchosBackend implements NotificationsWatchosBackend {
  /// Resolves the symbols from the process lazily, on first use.
  FfiNotificationsWatchosBackend() : _lib = DynamicLibrary.process();

  final DynamicLibrary _lib;
  NativeCallable<_SignalNative>? _callable;
  void Function(int kind)? _handler;

  late final void Function(Pointer<NativeFunction<_SignalNative>>)
      _setCallback = _lib.lookupFunction<
              Void Function(Pointer<NativeFunction<_SignalNative>>),
              void Function(Pointer<NativeFunction<_SignalNative>>)>(
          'flutter_local_notifications_watchos_set_callback');
  late final int Function(Pointer<Utf8>) _initialize = _lib.lookupFunction<
      Int64 Function(Pointer<Utf8>),
      int Function(
          Pointer<Utf8>)>('flutter_local_notifications_watchos_initialize');
  late final int Function(Pointer<Utf8>) _requestPermissions =
      _lib.lookupFunction<Int64 Function(Pointer<Utf8>),
              int Function(Pointer<Utf8>)>(
          'flutter_local_notifications_watchos_request_permissions');
  late final int Function() _checkPermissions =
      _lib.lookupFunction<Int64 Function(), int Function()>(
          'flutter_local_notifications_watchos_check_permissions');
  late final int Function(Pointer<Utf8>) _add = _lib.lookupFunction<
      Int64 Function(Pointer<Utf8>),
      int Function(Pointer<Utf8>)>('flutter_local_notifications_watchos_add');
  late final void Function(int) _cancel =
      _lib.lookupFunction<Void Function(Int64), void Function(int)>(
          'flutter_local_notifications_watchos_cancel');
  late final void Function(int) _cancelAll =
      _lib.lookupFunction<Void Function(Int32), void Function(int)>(
          'flutter_local_notifications_watchos_cancel_all');
  late final int Function() _pending =
      _lib.lookupFunction<Int64 Function(), int Function()>(
          'flutter_local_notifications_watchos_pending');
  late final int Function() _active =
      _lib.lookupFunction<Int64 Function(), int Function()>(
          'flutter_local_notifications_watchos_active');
  late final Pointer<Utf8> Function() _launchDetails =
      _lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'flutter_local_notifications_watchos_launch_details');
  late final Pointer<Utf8> Function() _pollResponses =
      _lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'flutter_local_notifications_watchos_poll_responses');
  late final Pointer<Utf8> Function(int) _takeRequestResult =
      _lib.lookupFunction<
          Pointer<Utf8> Function(Int64),
          Pointer<Utf8> Function(
              int)>('flutter_local_notifications_watchos_take_request_result');
  late final void Function(Pointer<Utf8>) _release = _lib.lookupFunction<
      Void Function(Pointer<Utf8>),
      void Function(
          Pointer<Utf8>)>('flutter_local_notifications_watchos_release');

  String? _take(Pointer<Utf8> p) {
    if (p == nullptr) {
      return null;
    }
    try {
      return p.toDartString();
    } finally {
      _release(p);
    }
  }

  int _withString(String s, int Function(Pointer<Utf8>) call) =>
      using((Arena arena) => call(s.toNativeUtf8(allocator: arena)));

  @override
  int initialize(String settingsJson) => _withString(settingsJson, _initialize);
  @override
  int requestPermissions(String optionsJson) =>
      _withString(optionsJson, _requestPermissions);
  @override
  int checkPermissions() => _checkPermissions();
  @override
  int add(String notificationJson) => _withString(notificationJson, _add);
  @override
  void cancel(int id) => _cancel(id);
  @override
  void cancelAll({required bool pendingOnly}) =>
      _cancelAll(pendingOnly ? 1 : 0);
  @override
  int pending() => _pending();
  @override
  int active() => _active();
  @override
  String launchDetails() =>
      _take(_launchDetails()) ?? '{"launched": false, "response": null}';
  @override
  String? pollResponses() => _take(_pollResponses());
  @override
  String? takeRequestResult(int id) => _take(_takeRequestResult(id));

  @override
  void setSignalHandler(void Function(int kind)? handler) {
    _handler = handler;
    if (handler == null) {
      _setCallback(nullptr);
      return;
    }
    final NativeCallable<_SignalNative> callable = _callable ??= () {
      final NativeCallable<_SignalNative> created =
          NativeCallable<_SignalNative>.listener(
              (int kind) => _handler?.call(kind));
      created.keepIsolateAlive = false;
      return created;
    }();
    _setCallback(callable.nativeFunction);
  }
}
