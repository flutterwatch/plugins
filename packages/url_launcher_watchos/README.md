# url_launcher_watchos

The watchOS implementation of [`url_launcher`][], built for the
[flutter-watchos](https://github.com/flutterwatch/flutter-watchos) toolchain.

A small FFI package — no method channels (watchOS does not support them).

## Usage

Add it alongside the app-facing package; you keep calling `url_launcher`'s
own API.

```yaml
dependencies:
  url_launcher: any
  url_launcher_watchos: ^0.1.0
```

## What watchOS can actually do

watchOS has **no general "open this URL" call** and no WebKit in the SDK, so
this package maps each URL to the one mechanism that fits it:

| URL | `LaunchMode` | Behaviour |
|---|---|---|
| `http:`, `https:` | `platformDefault`, `inAppBrowserView`, `inAppWebView` | Shown **on the watch** in the system browser: a full-screen sheet with an address bar and a close button, whose links navigate. |
| `http:`, `https:` | `externalApplication` | The watch shows the system sheet, which tells the user the link can be viewed on their iPhone, **and** an `NSUserActivity` (`NSUserActivityTypeBrowsingWeb`) is published so the phone or Mac can pick it up via Handoff. |
| `tel:`, `sms:` | any but the in-app modes | Opened on the watch by the system handler, via `-[WKApplication openSystemURL:]` (watchOS 7+). |
| anything else | | `launchUrl` returns `false`. |

`mailto:` is deliberately **not** claimed: `openSystemURL:` does not own it,
and because that method returns `void` an unowned scheme fails silently —
reporting success would be a lie.

`closeInAppWebView()` dismisses the on-watch browser and withdraws a
published Handoff activity.

### `true` means "handed off", not "opened"

watchOS reports no completion for any of these mechanisms, so a `true` result
means the URL was accepted by the system — not that the page loaded or that
the user followed it.

`tel:`, `sms:` and the Handoff path are verified on an Apple Watch Ultra 3
(watchOS 26.5, release build): `tel:` and `sms:` raise the system call and
compose UI, and a web URL shows the sheet on the watch while the Handoff icon
appears on the paired iPhone and opens the page. The on-watch browser is
verified on the watchOS 26.5 Simulator, including opening, following a link,
reopening, and `closeInAppWebView()`.

### How the on-watch browser works

It is an `ASWebAuthenticationSession`, the only public API that puts a web
page on the watch. It presents the system browser (`SafariViewService`); the
SwiftUI `WebView` is unavailable on watchOS, `Link` and `openURL` show the
"view on your iPhone" sheet for web URLs, and WebKit itself is absent from the
SDK. `WKWebView` is reachable only as private API, which App Review rejects.

The session is meant for sign-in, so using it as a browser has consequences:

- **It is ephemeral.** A persistent session first asks "*App* wants to use
  *site* to sign in", which is wrong for a link, so every sheet starts with no
  cookies and keeps none: a user who logs in to a site is logged out when the
  sheet closes.
- **It is a sheet, not a view.** It covers the app and cannot be placed inside
  a Flutter layout, so `webview_flutter` remains impossible. JavaScript runs,
  but `WebViewConfiguration` (JavaScript, DOM storage, headers) is not applied
  and the app cannot talk to the page.
- **No page can close it.** It has no callback scheme; only the user's close
  button or `closeInAppWebView()` ends it.

If watchOS refuses to present the sheet (another one is already up, or the app
is not in front), the URL goes to the iPhone as it would for
`externalApplication`, so the tap is never silently lost.

## Testing

`UrlLauncherWatchos.bindingsOverride` accepts a fake extending
`UrlLauncherWatchosBindings.forTesting()`, so the Dart layer is testable off
device.

[`url_launcher`]: https://pub.dev/packages/url_launcher
