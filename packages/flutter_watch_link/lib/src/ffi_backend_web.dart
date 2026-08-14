// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// The web stand-in for `ffi_backend.dart`.
//
// WatchConnectivity is an Apple API and there is nothing to bind to in a
// browser, but that is no reason to break the build of an app that merely
// *contains* a watch companion. `dart:ffi` does not exist on web, and an
// unconditional import of it is a **compile** error for the whole application
// — not a runtime one — so a Flutter app targeting iOS, watchOS and web could
// not depend on this package at all.
//
// Every conditional import in this package selects on `dart.library.ffi`, so
// this file is what any platform *without* dart:ffi gets: the same names, no
// native code, and a clear error if something actually tries to use a session.

import 'backend.dart';

/// Signature of the native→Dart wake signal.
///
/// Declared so the public library exports the same names everywhere. There is
/// no native side on web, so nothing ever calls it.
typedef SignalNative = void Function(int);

/// Registers the watchOS implementation.
///
/// Present on web only so the export list matches; the CLI's generated
/// registrant never runs here.
class FlutterWatchLink {
  /// Registrant hook. Does nothing, on every platform.
  static void registerWith() {}
}

/// Raw FFI bindings — unavailable on web.
class WatchLinkFfiBindings {
  /// Always throws: there is no native library to bind to.
  WatchLinkFfiBindings() {
    throw UnsupportedError(_message);
  }
}

/// The session backend — unavailable on web.
///
/// Constructing it throws rather than returning something that fails later, so
/// the error names the real problem at the point of use. App code that runs on
/// both web and a watch should branch before touching [WatchLink], or install
/// its own [WatchLinkBackend] with `WatchLink.backendOverride`.
class WatchLinkFfiBackend implements WatchLinkBackend {
  /// Always throws.
  WatchLinkFfiBackend() {
    throw UnsupportedError(_message);
  }

  // Declaring noSuchMethod lets this satisfy WatchLinkBackend without
  // restating sixteen members that can never run — the constructor has already
  // thrown before any of them could be reached.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(_message);
}

const String _message =
    'flutter_watch_link needs WatchConnectivity, which exists only on iOS and '
    'watchOS. This platform has no session to open. Guard the call, or set '
    'WatchLink.backendOverride to your own WatchLinkBackend.';
