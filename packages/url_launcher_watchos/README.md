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
| `http:`, `https:` | Published as an `NSUserActivity` (`NSUserActivityTypeBrowsingWeb`) so the page can be opened on the **paired iPhone or Mac** through Handoff. The watch cannot render it. |
| anything else | `launchUrl` returns `false`. |

`mailto:` is deliberately **not** claimed: `openSystemURL:` does not own it,
and because that method returns `void` an unowned scheme fails silently —
reporting success would be a lie.

### `true` means "handed off", not "opened"

watchOS reports no completion for either mechanism, so a `true` result means
the URL was accepted by the system — not that the user followed it. For a web
link the user still has to pick up the Handoff on their phone.

### In-app web views do not exist

`PreferredLaunchMode.inAppWebView` and `inAppBrowserView` report unsupported,
and `supportsCloseForMode` is always `false`. `closeWebView()` withdraws the
published Handoff activity, which is the nearest equivalent.

WebKit ships inside watchOS (system apps like Mail use it), but it is absent
from the SDK — no headers, no linkable stub — and `WKWebView` is a `UIView`,
which watchOS SwiftUI cannot host (there is no `UIViewRepresentable`). There
is therefore no supported way for a third-party app to render a page on the
watch.

## Testing

`UrlLauncherWatchos.bindingsOverride` accepts a fake extending
`UrlLauncherWatchosBindings.forTesting()`, so the Dart layer is testable off
device.

[`url_launcher`]: https://pub.dev/packages/url_launcher
