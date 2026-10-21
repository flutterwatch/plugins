// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// The native half of [PermissionHandlerWatchos], behind an interface so
/// host tests can substitute a fake. Every member maps to one exported C
/// function of `watchos/Classes/permission_handler_watchos_ffi.h`.
library;

import '../permission_handler_watchos.dart';

/// See the library documentation.
abstract class PermissionHandlerWatchosBackend {
  /// Reads the status of the permission numbered [permission]; returns the
  /// request id its answer comes under.
  int check(int permission);

  /// Reads whether the service behind [permission] is on; returns the
  /// request id.
  int service(int permission);

  /// Asks the wearer for [permission] when they have not answered yet;
  /// returns the request id.
  int request(int permission);

  /// The answer to [request] as JSON, or null while there is none yet.
  String? takeResult(int request);

  /// The function native wakes when an answer is ready, or null to stop.
  void setSignalHandler(void Function(int kind)? handler);
}
