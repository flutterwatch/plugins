// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `url_launcher`, implemented over dart:ffi.
//
// Method-channel plugins are not supported on watchOS, so this package
// follows the FFI plugin model: `watchos/Classes/url_launcher_watchos_ffi.m`
// exports the C entry points, the CLI force-loads the compiled archive into
// the watch binary, and this class resolves the symbols via
// `DynamicLibrary.process()`.

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// FFI bindings to the native url_launcher_watchos C functions.
///
/// Overridable for tests via [UrlLauncherWatchos.bindingsOverride]; the
/// [UrlLauncherWatchosBindings.forTesting] constructor skips FFI
/// initialization so fakes work off-device.
class UrlLauncherWatchosBindings {
  /// Creates bindings that look up native symbols in the current process.
  UrlLauncherWatchosBindings() : _lib = DynamicLibrary.process();

  /// Constructor for fakes/mocks — skips FFI initialization.
  UrlLauncherWatchosBindings.forTesting() : _lib = null;

  final DynamicLibrary? _lib;

  late final int Function(Pointer<Utf8>) _canLaunch = _lib!.lookupFunction<
      Int32 Function(Pointer<Utf8>),
      int Function(Pointer<Utf8>)>('url_launcher_watchos_can_launch');

  late final int Function(Pointer<Utf8>) _launch = _lib!.lookupFunction<
      Int32 Function(Pointer<Utf8>),
      int Function(Pointer<Utf8>)>('url_launcher_watchos_launch');

  late final void Function() _closeHandoff = _lib!
      .lookupFunction<Void Function(), void Function()>(
          'url_launcher_watchos_close_handoff');

  T _withUrl<T>(String url, T Function(Pointer<Utf8>) body) {
    final Pointer<Utf8> p = url.toNativeUtf8();
    try {
      return body(p);
    } finally {
      calloc.free(p);
    }
  }

  /// Whether the native side recognises [url]'s scheme.
  bool canLaunch(String url) => _withUrl(url, (p) => _canLaunch(p) != 0);

  /// Hands [url] to the system (tel:/sms:) or to Handoff (http:/https:).
  bool launch(String url) => _withUrl(url, (p) => _launch(p) != 0);

  /// Withdraws a published Handoff activity.
  void closeHandoff() => _closeHandoff();
}

/// watchOS implementation of [UrlLauncherPlatform].
///
/// watchOS has no general URL-opening API and no WebKit, so the two
/// mechanisms it does have are mapped by scheme:
///
/// | Scheme | Behaviour |
/// |---|---|
/// | `tel:`, `sms:` | Opened by the system handler on the watch. |
/// | `http:`, `https:` | Published as a Handoff activity for the paired iPhone/Mac — the watch cannot render a page itself. |
/// | anything else | [launchUrl] returns `false`. |
///
/// A `true` result means the URL was handed to the system, not that the user
/// followed it: watchOS reports no completion for either mechanism.
class UrlLauncherWatchos extends UrlLauncherPlatform {
  /// Test hook: set before first use to replace the FFI bindings.
  static UrlLauncherWatchosBindings? bindingsOverride;

  static UrlLauncherWatchosBindings? _bindings;

  static UrlLauncherWatchosBindings get _b =>
      bindingsOverride ?? (_bindings ??= UrlLauncherWatchosBindings());

  /// Registers this implementation as the default `url_launcher` platform
  /// implementation on watchOS.
  static void registerWith() {
    UrlLauncherPlatform.instance = UrlLauncherWatchos();
  }

  @override
  final LinkDelegate? linkDelegate = null;

  @override
  Future<bool> canLaunch(String url) async => _b.canLaunch(url);

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async {
    // Every in-app-webview flag is meaningless here: there is no WebKit in
    // the watchOS SDK, so a web URL can only ever leave the watch.
    return _b.launch(url);
  }

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async =>
      _b.launch(url);

  @override
  Future<void> closeWebView() async {
    // No in-app web view exists; the nearest equivalent is withdrawing the
    // Handoff offer published for a web URL.
    _b.closeHandoff();
  }

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async {
    // Only the platform default is meaningful: in-app web views cannot exist
    // on watchOS, and there is no external-app-vs-browser distinction.
    return mode == PreferredLaunchMode.platformDefault ||
        mode == PreferredLaunchMode.externalApplication;
  }

  @override
  Future<bool> supportsCloseForMode(PreferredLaunchMode mode) async => false;
}
