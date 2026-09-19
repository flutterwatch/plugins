// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef URL_LAUNCHER_WATCHOS_FFI_H
#define URL_LAUNCHER_WATCHOS_FFI_H

// See path_provider_watchos_ffi.h for why every symbol is `used` +
// default-visibility: the watch app links this archive statically, so without
// the attributes the linker would drop these (FFI has no compile-time
// caller). The CLI additionally emits a forced reference for each symbol
// listed under `flutter.plugin.platforms.watchos.ffiSymbols`.
#define URL_LAUNCHER_WATCHOS_EXPORT \
  __attribute__((visibility("default"))) __attribute__((used))

// watchOS has no general "open this URL" call. Three narrow mechanisms exist,
// and this plugin maps each URL to the one that fits:
//
//   * tel: / sms:      -> -[WKApplication openSystemURL:], which hands the
//                         URL to the system phone/messages handler.
//   * http: / https:,  -> an ephemeral ASWebAuthenticationSession, which
//     on the watch        shows the page in the system browser on the watch
//                         (`url_launcher_watchos_open_in_app`).
//   * http: / https:,  -> openSystemURL: AND an NSUserActivity of type
//     on the iPhone       NSUserActivityTypeBrowsingWeb published via
//                         -becomeCurrent. openSystemURL: shows the system
//                         sheet, which for a third-party app says the link
//                         can be viewed on the iPhone; the activity is what
//                         makes the phone able to pick it up. See the .m for
//                         the hardware-verified detail.
//
// Any other scheme is refused rather than silently dropped: openSystemURL
// returns void and does nothing for schemes it does not own, so reporting
// success would be a lie.

/// Whether [url] is a scheme this plugin can act on. Returns 1 or 0.
URL_LAUNCHER_WATCHOS_EXPORT int url_launcher_watchos_can_launch(const char* url);

/// Acts on [url]: opens it via the system handler (tel:/sms:) or publishes it
/// for Handoff (http:/https:). Returns 1 when the URL was accepted and acted
/// on, 0 when the scheme is unsupported or the string is not a valid URL.
///
/// A 1 means "handed to the system", not "the user completed it" — watchOS
/// gives no completion callback for either mechanism.
URL_LAUNCHER_WATCHOS_EXPORT int url_launcher_watchos_launch(const char* url);

/// Withdraws any Handoff activity this plugin published (see
/// `url_launcher_watchos_launch`). Safe to call when none is active.
URL_LAUNCHER_WATCHOS_EXPORT void url_launcher_watchos_close_handoff(void);

/// Shows an http:/https: [url] in the system browser on the watch. Returns 1
/// when the URL was accepted, 0 for any other scheme or an invalid string.
///
/// The browser is presented asynchronously on the main thread. If watchOS
/// refuses to present it, the URL goes to the iPhone as
/// `url_launcher_watchos_launch` would send it, so a 1 still means the user
/// saw something happen.
URL_LAUNCHER_WATCHOS_EXPORT int url_launcher_watchos_open_in_app(const char* url);

/// Dismisses the browser opened by `url_launcher_watchos_open_in_app`. Safe
/// to call when none is showing.
URL_LAUNCHER_WATCHOS_EXPORT void url_launcher_watchos_close_in_app(void);

#endif  // URL_LAUNCHER_WATCHOS_FFI_H
