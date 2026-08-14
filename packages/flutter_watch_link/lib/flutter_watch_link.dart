// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// WatchConnectivity for Flutter companion apps — one Dart API that works
/// unchanged on both the iPhone and the Apple Watch.
///
/// WatchConnectivity is the only transport Apple provides between a phone and
/// its watch. This package puts both halves of a `WCSession` behind a single
/// [WatchLink], over dart:ffi on both platforms — the phone and the watch
/// compile the same native source, so there is one implementation rather than
/// two to keep in step. Inbound payloads are pushed into Dart from the
/// delegate queue; neither side polls.
///
/// ```dart
/// import 'package:flutter_watch_link/flutter_watch_link.dart';
///
/// final WatchLink link = WatchLink.instance;
/// await link.activate();
/// link.messages.listen((WatchLinkMessage m) => merge(m.payload, m.tier));
/// await link.sendMessage(<String, Object?>{'checked': 'milk'});
/// ```
///
/// The three send methods map onto WatchConnectivity's three transports, which
/// differ in latency, ordering, and whether delivery survives the counterpart
/// app closing. [WatchLink] documents how to choose between them.
library flutter_watch_link;

export 'src/backend.dart' show WatchLinkBackend;
// Selected on `dart.library.ffi`, so a platform without dart:ffi (the web)
// gets the stub instead of a compile error. An unconditional `dart:ffi` import
// fails the *build* of any app that targets web, even one that never opens a
// session — see src/ffi_backend_web.dart.
export 'src/ffi_backend_web.dart'
    if (dart.library.ffi) 'src/ffi_backend.dart'
    show
        FlutterWatchLink,
        SignalNative,
        WatchLinkFfiBackend,
        WatchLinkFfiBindings;
export 'src/types.dart'
    show
        WatchLinkException,
        WatchLinkFile,
        WatchLinkMessage,
        WatchLinkResponder,
        WatchLinkState,
        WatchLinkTier;
export 'src/watch_link.dart' show WatchLink;
