# local_auth_watchos

The watchOS implementation of [`local_auth`](https://pub.dev/packages/local_auth).

Backed by **LocalAuthentication** (`LAContext`, available on watchOS 9+) over
dart:ffi. `evaluatePolicy` is asynchronous, so its reply block **pushes** the
result into Dart through a `NativeCallable.listener`; `authenticate` resolves
the moment the system answers rather than on a poll interval.

> Scaffolded by [`flutter-watchos plugin port`](https://github.com/flutterwatch/flutter-watchos)
> from `local_auth_darwin`, then implemented and verified by hand.

## Usage

This is a federated plugin implementation. Apps that already depend on
`local_auth` and target watchOS only need to add this package alongside it:

```yaml
dependencies:
  local_auth: ^<latest>
  local_auth_watchos: ^0.0.1
```

The plugin registers automatically via Flutter's federated registry — no
explicit imports required from app code.

## Behaviour on watchOS

The watch has **no Face ID / Touch ID**, so only device-owner authentication
(passcode / wrist unlock) is offered:

| Method | watchOS |
|---|---|
| `authenticate` (device-owner) | supported (watchOS 9+) |
| `authenticate` with `biometricOnly: true` | fails (no biometry) |
| `deviceSupportsBiometrics` | always false |
| `getEnrolledBiometrics` | always empty |
| `isDeviceSupported` | true when a passcode is set |
| `stopAuthentication` | supported |

## Status

| Platform | Implemented |
|----------|-------------|
| Apple Watch (`watchos`) | yes (device-owner auth, watchOS 9+) |
| Watch simulator (`watchsimulator`) | query methods verified; interactive auth needs a device |

The query methods are verified on the simulator (`example/integration_test`);
the interactive passcode prompt is verified on a physical Apple Watch.

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the full text.
