## 0.1.0

Initial release. One `WatchLink` API over `WCSession` that compiles unchanged
for the iPhone and the Apple Watch.

* **One implementation, both devices.** Each platform is an FFI plugin
  compiling the same source from `src/`, so there is a single native
  implementation rather than two to keep in step. Nothing branches on platform.
* **All four transports.** `sendMessage`, `updateApplicationContext`,
  `transferUserInfo`, and `transferFile`, with the delivering tier tagged on
  every inbound payload so a receiver can tell how something arrived.
* **Pushed, not polled.** Inbound payloads reach Dart from the `WCSession`
  delegate queue through a `NativeCallable.listener`; neither side runs a
  timer. The signal carries only a kind — Dart pulls the data back with
  synchronous reads from a bounded native buffer, which also keeps a
  dropped-payload count.
* **Reply handlers, both directions.** `sendMessageWithReply` returns a future
  that completes with the counterpart's answer; a received `WatchLinkMessage`
  that `expectsReply` is answered with `message.reply(...)`. A receiver that
  never answers cannot hang the sender: the native side answers emptily and
  drops the block after 30 s, and the waiting future has its own timeout in
  case a signal is lost.
* **File transfer.** `transferFile(path, metadata:)`,
  `outstandingFileTransferCount()`, and a `files` stream — the one tier that
  carries more than the ~65 kB a payload allows. Received files are copied into
  `Documents/fwl_inbox/` before Dart is told about them, because the system
  deletes its own copy the instant the delegate returns. They are **yours to
  clean up**.
* **Session state** (`activated` / `reachable` / `counterpartPaired` /
  `counterpartInstalled`, plus a derived `counterpartReady`) as a stream and a
  one-shot read, with outstanding-transfer and dropped-payload counters for
  diagnostics UI. Paired and installed stay separate because the remedy
  differs — pair a watch, or install the app on the one you have.
* **Both directions of the application context** are readable and survive a
  restart: `receivedApplicationContext()` for what the counterpart published,
  `sentApplicationContext()` for what this device did.
* **CocoaPods and Swift Package Manager.** On iOS the plugin builds as a
  **dynamic** framework by necessity: its symbols exist only for runtime
  lookup, so nothing references them, and a static archive's members are
  dropped at link time — producing a clean build that fails on first use.
* **Web-safe to depend on.** `dart:ffi` is behind a conditional import, so an
  app that also targets web still builds; the session throws
  `UnsupportedError` there while the platform-neutral types keep working.
* **Every `states` subscriber is seeded**, not just the first. A broadcast
  stream's `onListen` fires only when the listener count goes zero-to-one, so a
  second concurrent subscriber would otherwise wait for the next change to
  learn where it stands. Each subscriber gets the current state on subscribe
  and its own de-duplication, and the native callback is unregistered only once
  the last one cancels.
* **File metadata survives the trip.** `transferFile`'s metadata is carried as
  JSON like every other tier rather than handed to `WCSession` as a decoded
  dictionary. `WCSession` documents metadata as property-list values, and a
  JSON null decodes to `NSNull`, which is not one; the same wrapping is what
  keeps an int from arriving as a double after a property-list round trip.
* **`dispose()` is terminal and idempotent.** Calling it twice is fine. Any
  other call afterwards throws `WatchLinkException(code: 'disposed')` rather
  than a `StateError` from a closed controller.
* Requires Dart 3.1.0, where `NativeCallable.listener` landed.
