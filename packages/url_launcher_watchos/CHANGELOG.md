## 0.1.1

* README: the install snippet names `url_launcher: ^6.3.2` instead of `any`,
  and this version.
* `pubspec.yaml`: `repository` points at this package's folder in the plugins
  repo.
* Comments now say what keeps the FFI exports in the app: the CLI force-loads
  the plugin archive, each export is `used` with default visibility, and the
  CLI keeps global symbols through the App Store strip. `ffiSymbols` lists the
  exports.
* README: a "Not supported on watchOS" table; PORTING_REPORT: an "Interface
  coverage" list of every member of `url_launcher_platform_interface` 2.3.2,
  audited by hand.
* `pubspec.yaml`: the description is 172 characters (pub.dev allows 180).
* PORTING_REPORT: the interface list and the scheme table describe the browser
  on the watch, and `supportsMode` and `supportsCloseForMode` as they are.

## 0.1.0

* **Web pages open on the watch.** `http:` and `https:` URLs launched with
  `LaunchMode.platformDefault`, `inAppBrowserView` or `inAppWebView` are shown
  in the system browser on the watch, through an ephemeral
  `ASWebAuthenticationSession`. `closeInAppWebView()` dismisses it.
* **Behaviour change:** the default mode used to send web URLs to the paired
  iPhone. Pass `mode: LaunchMode.externalApplication` to keep doing that.
* `supportsMode` now reports `inAppWebView` and `inAppBrowserView`, and
  `supportsCloseForMode` reports both as closable.
* The legacy `launch()` shows a web URL on the watch when `useSafariVC` or
  `useWebView` is set, which is url_launcher's default for web URLs.
* Links `AuthenticationServices`.

## 0.0.1

* Initial release: watchOS implementation of `url_launcher` over dart:ffi.
* `tel:` and `sms:` open through `-[WKApplication openSystemURL:]`.
* `http:` and `https:` are published as an `NSUserActivity` for Handoff to the
  paired iPhone or Mac; the watch has no WebKit to render them itself.
* Other schemes (including `mailto:`) report unsupported rather than failing
  silently.
