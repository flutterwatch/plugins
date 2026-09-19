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
