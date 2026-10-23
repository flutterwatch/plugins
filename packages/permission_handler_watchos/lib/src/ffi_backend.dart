// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by the MIT license that can be found
// in the LICENSE file.
//
// The C symbols of `watchos/Classes/permission_handler_watchos_ffi.h`,
// resolved from the process.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'backend.dart';

typedef _SignalNative = Void Function(Int64);

/// [PermissionHandlerWatchosBackend] over the exported C functions.
class FfiPermissionHandlerWatchosBackend
    implements PermissionHandlerWatchosBackend {
  /// Resolves the symbols from the process lazily, on first use.
  FfiPermissionHandlerWatchosBackend() : _lib = DynamicLibrary.process();

  final DynamicLibrary _lib;

  /// One trampoline for the life of the backend; only its pointer is
  /// unregistered, since a [NativeCallable] is reclaimed only by `close()`.
  NativeCallable<_SignalNative>? _callable;
  void Function(int kind)? _handler;

  late final void Function(Pointer<NativeFunction<_SignalNative>>)
      _setCallback = _lib.lookupFunction<
              Void Function(Pointer<NativeFunction<_SignalNative>>),
              void Function(Pointer<NativeFunction<_SignalNative>>)>(
          'permission_handler_watchos_set_callback');
  late final int Function(int) _check =
      _lib.lookupFunction<Int64 Function(Int32), int Function(int)>(
          'permission_handler_watchos_check');
  late final int Function(int) _service =
      _lib.lookupFunction<Int64 Function(Int32), int Function(int)>(
          'permission_handler_watchos_service');
  late final int Function(int) _request =
      _lib.lookupFunction<Int64 Function(Int32), int Function(int)>(
          'permission_handler_watchos_request');
  late final Pointer<Utf8> Function(int) _takeResult = _lib.lookupFunction<
      Pointer<Utf8> Function(Int64),
      Pointer<Utf8> Function(int)>('permission_handler_watchos_take_result');
  late final void Function(Pointer<Utf8>) _release = _lib.lookupFunction<
      Void Function(Pointer<Utf8>),
      void Function(Pointer<Utf8>)>('permission_handler_watchos_release');

  @override
  int check(int permission) => _check(permission);

  @override
  int service(int permission) => _service(permission);

  @override
  int request(int permission) => _request(permission);

  @override
  String? takeResult(int request) {
    final Pointer<Utf8> json = _takeResult(request);
    if (json == nullptr) {
      return null;
    }
    try {
      return json.toDartString();
    } finally {
      _release(json);
    }
  }

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
