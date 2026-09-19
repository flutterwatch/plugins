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

  late final int Function(Pointer<Utf8>) _openInApp = _lib!.lookupFunction<
      Int32 Function(Pointer<Utf8>),
      int Function(Pointer<Utf8>)>('url_launcher_watchos_open_in_app');

  late final void Function() _closeInApp = _lib!
      .lookupFunction<Void Function(), void Function()>(
          'url_launcher_watchos_close_in_app');

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

  /// Shows an http:/https: [url] in the system browser on the watch.
  bool openInApp(String url) => _withUrl(url, (p) => _openInApp(p) != 0);

  /// Dismisses the browser opened by [openInApp].
  void closeInApp() => _closeInApp();
}

/// watchOS implementation of [UrlLauncherPlatform].
///
/// watchOS has no general URL-opening API and no WebKit in its SDK, so each
/// URL goes to the one mechanism that fits it:
///
/// | URL and mode | Behaviour |
/// |---|---|
/// | `http:`/`https:`, [PreferredLaunchMode.platformDefault], `inAppBrowserView` or `inAppWebView` | Shown in the system browser on the watch, a full-screen sheet with an address bar and a close button. |
/// | `http:`/`https:`, [PreferredLaunchMode.externalApplication] | The system sheet tells the user the link can be viewed on their iPhone, and a Handoff activity is published so the phone can pick it up. |
/// | `tel:`, `sms:` | Opened by the system handler on the watch. |
/// | anything else | [launchUrl] returns `false`. |
///
/// A `true` result means the URL was handed to the system, not that the user
/// followed it: watchOS reports no completion for any of these mechanisms.
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
    // The legacy API's useSafariVC is what url_launcher sets for web URLs by
    // default, so it maps to the on-watch browser as it does to
    // SFSafariViewController on iOS. The JavaScript, DOM storage and header
    // options have nothing to act on: the system browser is not configurable.
    if ((useSafariVC || useWebView) && _isWebUrl(url)) {
      return _b.openInApp(url);
    }
    return _b.launch(url);
  }

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    switch (options.mode) {
      case PreferredLaunchMode.inAppWebView:
      case PreferredLaunchMode.inAppBrowserView:
        // url_launcher itself rejects a non-web URL for these modes before it
        // gets here; refuse rather than guess if one arrives anyway.
        return _isWebUrl(url) && _b.openInApp(url);
      case PreferredLaunchMode.externalApplication:
      case PreferredLaunchMode.externalNonBrowserApplication:
        return _b.launch(url);
      case PreferredLaunchMode.platformDefault:
      // The enum lives in another package; a mode added there must fall back
      // to the default rather than stop this switch compiling.
      // ignore: unreachable_switch_default
      default:
        // Web URLs open on the watch, as they open in-app on iOS.
        return _isWebUrl(url) ? _b.openInApp(url) : _b.launch(url);
    }
  }

  @override
  Future<void> closeWebView() async {
    _b.closeInApp();
    // Also withdraw a Handoff offer published for an externalApplication
    // launch; there is no other way to take it back.
    _b.closeHandoff();
  }

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async {
    // externalNonBrowserApplication is not claimed: the watch cannot tell
    // whether the iPhone will open a web URL in an app or in Safari. It still
    // launches, falling back to externalApplication as the interface asks.
    return mode == PreferredLaunchMode.platformDefault ||
        mode == PreferredLaunchMode.inAppWebView ||
        mode == PreferredLaunchMode.inAppBrowserView ||
        mode == PreferredLaunchMode.externalApplication;
  }

  @override
  Future<bool> supportsCloseForMode(PreferredLaunchMode mode) async =>
      mode == PreferredLaunchMode.inAppWebView ||
      mode == PreferredLaunchMode.inAppBrowserView;

  static bool _isWebUrl(String url) {
    final String scheme = Uri.tryParse(url)?.scheme.toLowerCase() ?? '';
    return scheme == 'http' || scheme == 'https';
  }
}
