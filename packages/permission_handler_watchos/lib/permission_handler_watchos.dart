// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `permission_handler`, over dart:ffi.
//
// Method-channel plugins are not supported on watchOS, so the answers come
// from `watchos/Classes/` over dart:ffi: each call returns a request id,
// native wakes Dart through one `NativeCallable.listener` when an answer is
// ready, and Dart takes it as JSON. The permissions, statuses and error
// codes are the iOS implementation's.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';

import 'src/backend.dart';
import 'src/ffi_backend.dart';

export 'src/backend.dart' show PermissionHandlerWatchosBackend;

/// What woke Dart up. Mirrored in
/// `watchos/Classes/permission_handler_watchos_ffi.h`.
abstract final class PermissionHandlerWatchosSignal {
  /// An answer is ready.
  static const int result = 1;
}

/// watchOS implementation of [PermissionHandlerPlatform].
///
/// Answers for location (when in use and always), notifications, sensors
/// (Motion & Fitness), the microphone, contacts, the calendar (full access
/// and write only), reminders and Bluetooth. The permissions watchOS does not
/// have answer as the iOS implementation answers for one it does not know:
/// [PermissionStatus.denied], a request [PermissionStatus.permanentlyDenied],
/// their service [ServiceStatus.disabled].
class PermissionHandlerWatchos extends PermissionHandlerPlatform {
  /// Test hook: set before first use to replace the native backend.
  static PermissionHandlerWatchosBackend? backendOverride;

  static PermissionHandlerWatchosBackend? _backend;

  PermissionHandlerWatchosBackend get _b =>
      backendOverride ?? (_backend ??= FfiPermissionHandlerWatchosBackend());

  /// Registers this class as the `permission_handler` implementation on
  /// watchOS.
  static void registerWith() {
    PermissionHandlerPlatform.instance = PermissionHandlerWatchos();
  }

  final Map<int, Completer<Map<String, Object?>>> _pending =
      <int, Completer<Map<String, Object?>>>{};
  bool _registered = false;

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async =>
      PermissionStatusValue.statusByValue(
        _number(await _await(_b.check(permission.value)), 'status'),
      );

  /// Whether the service behind [permission] is on: location services for
  /// the location permissions, motion activity for [Permission.sensors],
  /// Bluetooth for [Permission.bluetooth]; [ServiceStatus.notApplicable] for
  /// the others watchOS has.
  @override
  Future<ServiceStatus> checkServiceStatus(Permission permission) async =>
      ServiceStatusValue.statusByValue(
        _number(await _await(_b.service(permission.value)), 'service'),
      );

  /// Asks for each of [permissions] in turn, as the watch shows one prompt
  /// at a time, and answers with each one's status afterwards.
  ///
  /// Fails with a [PlatformException] whose code is
  /// `MISSING_USAGE_DESCRIPTION` when the app's Info.plist lacks the key a
  /// prompt needs, where watchOS would terminate the app, and
  /// `MISSING_WHENINUSE_PERMISSION` for [Permission.locationAlways] asked
  /// for before "when in use" was granted.
  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async {
    final Map<Permission, PermissionStatus> statuses =
        <Permission, PermissionStatus>{};
    for (final Permission permission in permissions) {
      statuses[permission] = PermissionStatusValue.statusByValue(
        _number(await _await(_b.request(permission.value)), 'status'),
      );
    }
    return statuses;
  }

  /// Always false: watchOS, like iOS, has no rationale to show.
  @override
  Future<bool> shouldShowRequestPermissionRationale(
    Permission permission,
  ) async =>
      false;

  /// Always false: watchOS has no settings page an app can open. The wearer
  /// changes a permission in the watch's Settings, or in the Watch app on
  /// the iPhone.
  @override
  Future<bool> openAppSettings() async => false;

  static int _number(Map<String, Object?> answer, String key) =>
      (answer[key]! as num).toInt();

  void _update() {
    final bool wanted = _pending.isNotEmpty;
    if (wanted == _registered) {
      return;
    }
    _registered = wanted;
    _b.setSignalHandler(wanted
        ? (int kind) {
            if (kind == PermissionHandlerWatchosSignal.result) {
              _drain();
            }
          }
        : null);
  }

  Future<Map<String, Object?>> _await(int request) {
    final Completer<Map<String, Object?>> completer =
        Completer<Map<String, Object?>>();
    _pending[request] = completer;
    _update();
    // The answer may have landed before the handler was registered.
    _drain();
    return completer.future;
  }

  void _drain() {
    for (final int request in _pending.keys.toList()) {
      final String? json = _b.takeResult(request);
      if (json == null) {
        continue;
      }
      final Completer<Map<String, Object?>> completer =
          _pending.remove(request)!;
      final Map<String, Object?> answer =
          (jsonDecode(json) as Map<Object?, Object?>).cast<String, Object?>();
      final Object? error = answer['error'];
      if (error is Map<Object?, Object?>) {
        completer.completeError(PlatformException(
          code: error['code'] as String? ?? 'ERROR',
          message: error['message'] as String?,
        ));
      } else {
        completer.complete(answer);
      }
    }
    _update();
  }
}
