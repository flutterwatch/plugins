# url_launcher_watchos — porting report

## Verification status

| Aspect | Result |
|---|---|
| Implementation | ✅ Working (FFI) |
| watchOS capability | ◐ Partial — see the scheme table below |
| Host unit tests (`flutter-watchos test`) | ✅ pass (10) |
| Native compile (`arm64-apple-watchos7.0-simulator`, `-Wall -Wextra`) | ✅ clean, all 3 symbols exported |
| CLI integration | ✅ `url_launcher` drops off the "no watchOS implementation" warning in a real app |
| Upstream integration test | ✗ not reused — upstream asserts an in-app `SFSafariViewController`/webview surface that cannot exist on watchOS |
| Own integration test (Simulator, real FFI) | ✅ pass (5) — symbols resolve via `DynamicLibrary.process()` and `url_launcher` federates to this implementation |
| On-device (Apple Watch Ultra 3, watchOS 26.5, release AOT) | ✅ web path verified by hand — the system sheet appears and reports the link can be viewed on the iPhone |
| On-device Handoff pickup on the phone | ◐ **Not yet confirmed** — the activity is published, but that the Handoff icon appears on the paired iPhone has not been observed |

Marking: ✅ full / passes · ◐ partial — reason given · ○ not applicable (no upstream test) · ✗ unsupported on watchOS.

Hand-authored rather than scaffolded: the upstream iOS implementation is
built entirely on `UIApplication.open` and `SFSafariViewController`, neither
of which exists on watchOS, so there was nothing to port mechanically.

`flutter-watchos plugin port --from-pub url_launcher_ios` was run afterwards
as a cross-check. It flags exactly three unavailable APIs in the source —
`SafariServices`, `UIApplication`, `UIKitViews` — and its `UIApplication`
note independently prescribes the mechanism used here: "watchOS only supports
`WKExtension.shared().openSystemURL(_:)` for tel: and sms: schemes". Its
scaffold's shape (package name, `dartPluginClass: UrlLauncherWatchos`,
`ffiPlugin: true`, `implements: url_launcher`) matches this package; the
exported symbols and every method body are the human half it leaves behind.

## Status

✅ WORKING FFI implementation:

- `watchos/Classes/url_launcher_watchos_ffi.m` exports three C symbols
  (`used` + default-visibility, plus the `ffiSymbols` forced references, so
  the statically linked symbols survive `-dead_strip`).
- `lib/url_launcher_watchos.dart` extends `UrlLauncherPlatform` and resolves
  the symbols via `DynamicLibrary.process()`.

## Why this is not a straight port

watchOS has **no general URL-opening API**. `UIApplication` does not exist,
and WebKit — while it does ship inside the OS — is absent from the SDK, with
`WKWebView` being a `UIView` that watchOS SwiftUI cannot host (there is no
`UIViewRepresentable`). Only two mechanisms remain, and each covers a
different set of schemes.

### The watch does have a browser; we just cannot drive it

`WebSheet.framework` is the mini browser Weather and Mail present, and the
rest of the stack (`WebCore`, `MobileSafari`, `SafariSharedUI`, `WebUI`) sits
beside it — all in `PrivateFrameworks`.

`openSystemURL:` reaches it, and contrary to the documentation it is not
limited to `tel:`/`sms:` — an `https:` URL raises the system sheet. But for a
third-party app that sheet refuses to render, showing "URL failed to load —
this url can be viewed on your iPhone". Confirmed on an Apple Watch Ultra 3
(watchOS 26.5, release AOT) with `https://example.com`, a page with no
JavaScript, redirects or TLS quirks — so this is policy, not a page that
failed.

That refusal is worth triggering anyway: it is the only on-wrist feedback the
user gets. Publishing the Handoff activity alone would look like nothing
happened.

## API coverage

| Method | watchOS backing | Status |
|---|---|---|
| `canLaunch` | scheme whitelist | ✅ |
| `launchUrl` / `launch` | `openSystemURL:` or Handoff, by scheme | ◐ see below |
| `closeWebView` | invalidates the published `NSUserActivity` | ◐ nearest equivalent |
| `supportsMode` | `platformDefault`, `externalApplication` only | ◐ |
| `supportsCloseForMode` | always `false` | ✗ nothing is closable |
| `linkDelegate` | `null` (framework default) | ✅ |

### Scheme behaviour

| Scheme | Mechanism | Status |
|---|---|---|
| `tel:`, `sms:` | `-[WKApplication openSystemURL:]` (watchOS 7+) | ✅ opens on the watch |
| `http:`, `https:` | `openSystemURL:` **and** `NSUserActivity` + `becomeCurrent` | ◐ the watch shows "can be viewed on your iPhone"; Handoff carries it to the phone |
| `mailto:` | — | ✗ refused deliberately |
| everything else | — | ✗ `launchUrl` returns `false` |

`mailto:` is refused rather than passed to `openSystemURL:`: that method does
not own the scheme and returns `void`, so an unowned scheme fails silently.
Returning `true` would report a success that never happened.

### `true` does not mean "opened"

Neither mechanism reports completion, so a `true` result means the URL was
accepted by the system — not that the user followed it. For a web link the
user still has to pick the Handoff up on their phone.

## Threading

`openSystemURL:` is `NS_SWIFT_UI_ACTOR` (main-thread only) and
`becomeCurrent` is main-thread affine, but FFI calls arrive on the Dart UI
thread, which is not the platform main thread. Both paths therefore
`dispatch_async` to the main queue. This is why the native functions return
"accepted" rather than a real result — the work has not run yet when they
return.

## Follow-ups

- ✅ Done: the `https:` path on hardware — the system sheet appears and
  defers to the iPhone.
- Still open: confirm the Handoff offer actually reaches the paired iPhone
  (the icon in the app switcher), and that `tel:`/`sms:` raise the call and
  compose UI. There is no API to observe the peer device from the watch, so
  these last steps are necessarily manual.
