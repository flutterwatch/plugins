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
  url_launcher_watchos: ^0.0.1
```

## What watchOS can actually do

watchOS has **no general "open this URL" call** and no WebKit in the SDK, so
this package maps each scheme to the one mechanism that fits it:

| Scheme | Behaviour |
|---|---|
| `tel:`, `sms:` | Opened on the watch by the system handler, via `-[WKApplication openSystemURL:]` (watchOS 7+). |
| `http:`, `https:` | The watch shows the system sheet — which tells the user the link can be viewed on their iPhone — **and** an `NSUserActivity` (`NSUserActivityTypeBrowsingWeb`) is published so the phone or Mac can pick it up via Handoff. |
| anything else | `launchUrl` returns `false`. |

`mailto:` is deliberately **not** claimed: `openSystemURL:` does not own it,
and because that method returns `void` an unowned scheme fails silently —
reporting success would be a lie.

### `true` means "handed off", not "opened"

watchOS reports no completion for either mechanism, so a `true` result means
the URL was accepted by the system — not that the user followed it. For a web
link the user still has to pick up the Handoff on their phone.

All four behaviours above are verified on an Apple Watch Ultra 3
(watchOS 26.5, release build): `tel:` and `sms:` raise the system call and
compose UI, and a web URL shows the sheet on the watch while the Handoff icon
appears on the paired iPhone and opens the page.

### In-app web views do not exist

`PreferredLaunchMode.inAppWebView` and `inAppBrowserView` report unsupported,
and `supportsCloseForMode` is always `false`. `closeWebView()` withdraws the
published Handoff activity, which is the nearest equivalent.

watchOS genuinely has a browser — `WebSheet.framework`, which is what Weather
and Mail present — but it is a private framework, as is the rest of the web
stack (`WebCore`, `MobileSafari`, `SafariSharedUI`). WebKit itself ships in
the OS but is absent from the SDK, and `WKWebView` is a `UIView`, which
watchOS SwiftUI cannot host (there is no `UIViewRepresentable`).

Passing an `https` URL to `openSystemURL:` from a third-party app *does*
raise the system sheet — the documentation's `tel:`/`sms:`-only list is
incomplete — but the sheet then refuses to render and points at the iPhone.
Verified on an Apple Watch Ultra 3 (watchOS 26.5) with `example.com`, so this
is policy rather than a page that happened to fail. That prompt is why this
package makes the call anyway: the user gets told, on the wrist, where their
link went.

## Testing

`UrlLauncherWatchos.bindingsOverride` accepts a fake extending
`UrlLauncherWatchosBindings.forTesting()`, so the Dart layer is testable off
device.

[`url_launcher`]: https://pub.dev/packages/url_launcher
