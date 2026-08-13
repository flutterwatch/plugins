# flutter_watch_link

[![pub](https://img.shields.io/pub/v/flutter_watch_link.svg)](https://pub.dev/packages/flutter_watch_link)
[![license](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

**WatchConnectivity for Flutter companion apps — one Dart API that runs
unchanged on both the iPhone and the Apple Watch.**

WatchConnectivity is the only transport Apple provides between a phone and its
watch. This package puts both halves of a `WCSession` behind a single
`WatchLink`, over `dart:ffi` on both platforms.

- **All five transports** — live messages, request/reply, latest-wins
  application context, a guaranteed FIFO queue, and file transfer.
- **Every payload tells you how it arrived**, so you can reason about ordering
  and durability instead of guessing.
- **Nothing polls.** Delegate callbacks push into Dart from the session's own
  queue; there are no timers on either side.
- **One native implementation**, compiled for both platforms, rather than two to
  keep in step.
- **Testable off-device** — swap in a fake session with no native binary.

## Supported platforms

| Platform | Support | Notes |
|---|---|---|
| **watchOS** | ✅ | Requires a Flutter watch app — see [flutter-watchos](https://github.com/flutterwatch/flutter-watchos). |
| **iOS** | ✅ | iPhone only; `isSupported()` returns false on iPad. |
| Web | ⚪️ | **Builds cleanly**; opening a session throws. See below. |
| Android / Wear OS | ❌ | Not yet. The API is named neutrally to leave room for it. |

Depending on this package **does not break a web build**. `dart:ffi` is reached
through a conditional import, so web gets a stub with the same API — an
unconditional import would fail the *compile* of the whole application, not
just the calls it never makes. Platform-neutral types (`WatchLinkState`,
`WatchLinkMessage`, `WatchLinkTier`) are real everywhere, so shared models
still work; only opening a session throws `UnsupportedError`. To run shared
logic in a browser, install a fake with `WatchLink.backendOverride` rather than
branching at every call site.

## Installation

```yaml
dependencies:
  flutter_watch_link: ^0.1.0
```

No entitlement and no Info.plist key is required. Both apps must be halves of
one companion project — see [Setup](#setup).

## Quick start

```dart
import 'package:flutter_watch_link/flutter_watch_link.dart';

final WatchLink link = WatchLink.instance;

// Subscribe before activating: activation is itself a state change.
link.messages.listen((WatchLinkMessage m) => merge(m.payload, m.tier));
link.errors.listen((String e) => log('watch link: $e'));

await link.activate();
await link.sendMessage(<String, Object?>{'checked': 'milk'});
```

The same code compiles and runs on both devices. Nothing branches on platform.

A complete companion app — one `main.dart`, both devices — is in
[`example/`](example).

## Choosing a transport

The send methods are not variations on one idea. They differ in latency,
ordering, and whether delivery survives the counterpart app closing — and a
real companion app uses several:

| Situation | Method | Why |
|---|---|---|
| Counterpart reachable | `sendMessage` | Immediate. Throws, queueing **nothing**, if it is not reachable. |
| You need an answer back | `sendMessageWithReply` | Same reachability rules, but completes with the counterpart's reply. |
| Catching a cold device up | `updateApplicationContext` | Latest-wins: one delivery replaces any backlog. Never use it for a stream of events — intermediate values are dropped by design. |
| An edit that must not be lost | `transferUserInfo` | FIFO, delivered even if the counterpart app is not running. Timing is the system's to choose. |
| Anything over ~65 kB | `transferFile` | FIFO and durable like `transferUserInfo`, and the only tier that carries a file. |

### Replies

```dart
// Asking.
final Map<String, Object?> answer =
    await link.sendMessageWithReply(<String, Object?>{'get': 'status'});

// Answering.
link.messages.listen((WatchLinkMessage m) async {
  if (m.expectsReply) {
    await m.reply(<String, Object?>{'battery': 82});
  }
});
```

Answer promptly. The native side holds the sender's one-shot reply block and
gives up after 30 seconds, answering emptily, so a silent receiver cannot leave
the sender waiting for ever; a late reply is discarded rather than raised.

Prefer a one-way `sendMessage` plus an idempotent merge where you can. A
request that *must* be answered turns a dropped packet into a visible failure,
whereas a one-way edit can simply be re-sent on a durable tier.

### Files

```dart
await link.transferFile('/path/to/photo.png',
    metadata: <String, Object?>{'kind': 'photo'});

link.files.listen((WatchLinkFile f) {
  // f.path — already copied somewhere durable; yours to clean up.
});
```

Received files land in `Documents/fwl_inbox/`, UUID-prefixed so two transfers
of the same filename cannot overwrite each other. They are copied there before
your code hears about them, because the system deletes its own copy the instant
it hands the file over — the URL it supplies is dead by the time Dart could
read it. **Nothing deletes them for you.**

A payload may arrive twice by different routes, so **make your receiver
idempotent** rather than trying to deduplicate. `WatchLinkMessage.tier` tells
you which transport delivered each one, which is what makes that practical to
reason about.

### Reading the context back

Both directions of the application context are readable, and the system
persists both across launches:

```dart
// What the counterpart last published. Read this on a cold launch to catch up
// without waiting for a stream to fire.
final Map<String, Object?>? theirs = await link.receivedApplicationContext();

// What this device last published — useful for skipping a redundant update.
final Map<String, Object?>? ours = await link.sentApplicationContext();
if (ours == null || !mapEquals(ours, snapshot)) {
  await link.updateApplicationContext(snapshot);
}
```

## Session state

```dart
link.states.listen((WatchLinkState s) {
  // s.activated             — session reached WCSessionActivationStateActivated
  // s.reachable             — counterpart app is running, sendMessage will work
  // s.counterpartPaired     — there is a counterpart device at all
  // s.counterpartInstalled  — that device has this app
  // s.counterpartReady      — the two above, for when you just want "can I send"
});
```

The flags are deliberately not collapsed into one `connected` boolean.
`counterpartReady && !reachable` is the ordinary state whenever the other app
is closed — and it is exactly when `transferUserInfo` is the right choice.

`counterpartPaired` and `counterpartInstalled` stay separate because the fix
differs: no watch paired means *pair one*, paired without the app means
*install it*. Collapsing them leaves an app that can only say "not found" to
both.

They are named neutrally because the underlying API is not symmetric. The phone
exposes `isPaired` and `isWatchAppInstalled` separately; the watch has only
`isCompanionAppInstalled`, and reports `counterpartPaired` as always true — a
watch running this code is by definition paired to an iPhone.

## Setup

Both apps must be halves of **one companion project** — the watch app embedded
in the iOS app, with `WKCompanionAppBundleIdentifier` pointing at it.
`flutter-watchos` derives this from the project shape and reconciles the wiring
on every build; `flutter-watchos host` reports the current state. WCSession
will not connect two independently built apps.

## How each side works

**One implementation, both platforms.** `src/` holds the `WCSession` code;
`ios/Classes` and `watchos/Classes` each contain a one-line shim that includes
it. WatchConnectivity is nearly identical on the two platforms, so the real
differences are a few `TARGET_OS_WATCH` branches — `isCompanionAppInstalled` on
the watch versus `isPaired && isWatchAppInstalled` on the phone, plus the
phone-only `sessionDidDeactivate` reactivation.

**Nothing polls.** Delegate callbacks arrive on a background queue and wake
Dart through a `NativeCallable.listener`. The signal carries only a *kind*,
never a payload: `NativeCallable.listener` is asynchronous, so native returns
before Dart runs and a pointer handed across could be freed in between. Dart
pulls the data back with synchronous reads instead, draining a lock-guarded
ring buffer that still sits behind them — a delivery burst can outrun the
isolate, and a bounded buffer with a drop counter beats unbounded growth. Each
drain empties the *whole* buffer, so a burst that accumulated while the app was
backgrounded arrives at once.

**Symbol resolution differs, deliberately.** On watchOS the CLI force-links the
plugin archive into the executable. On iOS the plugin is a *dynamic* framework,
because a static archive's members are only pulled in when something references
them — and nothing does: these symbols exist purely for runtime lookup, so the
linker would drop them. The Dart side probes `DynamicLibrary.process()` first
and falls back to opening the framework, rather than branching on the platform:
`Platform.isIOS` is true on watchOS too, so a branch would be answering a
question the lookup already answers.

Both sides speak one wire format: payloads travel as **JSON strings** under a
single reserved WCSession key. Letting each platform's own codec convert a Dart
map would put two different codecs on the two ends of one session with
WatchConnectivity's property-list coercion in between, where a Dart `int` can
arrive as a `double` and a `null` cannot travel at all. One encoder on each end
removes all three problems. Dictionaries that arrive *without* the reserved key
(from a native watch app, say) are surfaced on a best-effort basis rather than
dropped.

## Limits worth knowing

- **Payload size.** WatchConnectivity caps message and context payloads at
  roughly 65 kB. Send diffs, not whole databases — or use `transferFile`, the
  one tier that is not bound by it.
- **Received files are not cleaned up.** They accumulate in
  `Documents/fwl_inbox/` until you move or delete them.
- **Background delivery.** `transferUserInfo` and `updateApplicationContext`
  are documented to wake the counterpart app. A Flutter watch app's behaviour
  while backgrounded is at the mercy of the engine's `WKApplication` lifecycle
  handling — treat delivery as **guaranteed on next foreground**, not as a
  background wake-up you can build a feature on.
- **`sendMessage` failures after dispatch** do not throw. WCSession accepts the
  message, `sendMessage` returns, and the failure — commonly "Companion app is
  not installed" — arrives on a callback afterwards. It is reported on the
  [`errors`](#diagnostics) stream rather than from the call, so **listen to that
  stream if you use `sendMessage`**; otherwise a lost message is
  indistinguishable from a delivered one. It is also a large part of why a
  companion app should carry a snapshot on the context tier as well.
- **Reply handlers** are acknowledged natively but carry no payload back.
  Model request/response as two one-way messages.
- **iPad** returns false from `isSupported()`. Check it before showing
  companion UI.

## Diagnostics

```dart
link.errors.listen((String e) => log('watch link: $e'));
```

`errors` carries failures that arrive after the call that caused them returned
— see the note on `sendMessage` above. `outstandingTransferCount()` reports
undelivered `transferUserInfo` payloads. On watchOS,
`WatchLinkFfiBackend.droppedInboundCount()` reports payloads the ring buffer had
to drop — non-zero means nothing was draining while payloads arrived.

## Testing

`WatchLink.backendOverride` accepts any `WatchLinkBackend`, so app logic can be
tested off-device with a fake session — no native binary, no simulator:

```dart
WatchLink.backendOverride = MyFakeLink();
addTearDown(() => WatchLink.backendOverride = null);
```

This package's own tests also drive `WatchLinkFfiBackend.forTesting` with
scripted native responses, and [`example/integration_test/`](example/integration_test)
covers the part that only a device can answer: that every C symbol survives the
linker and binds at runtime.

## Example

[`example/`](example) is a companion app for both devices from one
`lib/main.dart`. It shows the session flags live, gives you a button per
transport, and logs everything that arrives tagged with the tier that delivered
it. Press **message** with the counterpart closed to watch `not-reachable`
happen, then **userInfo** to watch the same edit arrive anyway.

## Setting up a Simulator pair

Pairing is not automatic:

```bash
xcrun simctl pair <watch-udid> <phone-udid>
xcrun simctl list pairs        # wait for "(active, connected)"
```

**Launch the iPhone app before the watch app.** The watch reports its
counterpart as installed only once the phone app exists; until then every send
fails with "Companion app is not installed". Reachability on the Simulator also
lags reality by a few seconds — confirm timing-sensitive behaviour on hardware.
