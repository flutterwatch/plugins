# flutter_watch_link example

An iPhone app and an Apple Watch app that share one `WCSession` — and one
[`lib/main.dart`](lib/main.dart). The same Dart and the same native source run
on both devices; the only thing that differs is sizing.

The screen shows the four session flags (`activated`, `paired`, `installed`,
`reachable`), one button per transport, and a log of everything that arrives,
tagged with the tier that delivered it. Inbound messages that expect a reply are
answered automatically.

## Running both halves

Build and install the watch app, then the phone app, from this directory:

```bash
flutter-watchos run
```

```bash
flutter run
```

Press **message** on one device and watch the log on the other. With the
counterpart app closed, **message** fails with `not-reachable` — that is the
point of the tier, not a bug — while **userInfo** queues and arrives when the
other app next opens.

## Tests

Host-side widget tests run against a fake backend and need no device:

```bash
flutter test
```

Integration tests drive the real native library, so they need a device or
simulator. They assert the contract on a single device — symbol binding,
activation, and the documented failure modes — rather than two-device delivery:

```bash
flutter-watchos test integration_test -d <watch-simulator>
```
