# wakelock_plus_example

A watchOS-only example app. Run it on an Apple Watch simulator with:

```sh
flutter-watchos run
```

The runner's `Info.plist` names a `self-care` extended runtime session in
`WKBackgroundModes`, which the wakelock needs on watchOS.
