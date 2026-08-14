# sensors_plus_watchos

The watchOS implementation of [`sensors_plus`](https://pub.dev/packages/sensors_plus).

Motion samples come from **CoreMotion** (`CMMotionManager`) over dart:ffi.
Each CoreMotion update is **pushed** into Dart through a
`NativeCallable.listener`; nothing polls. That means one stream event per
native sample, rather than one per timer tick on a clock independent of
CoreMotion's.

> Scaffolded by [`flutter-watchos plugin port`](https://github.com/flutterwatch/flutter-watchos)
> from `sensors_plus`, then implemented and verified by hand.

## Usage

This is a federated plugin implementation. Apps that already depend on
`sensors_plus` and target watchOS only need to add this package alongside it:

```yaml
dependencies:
  sensors_plus: ^<latest>
  sensors_plus_watchos: ^0.0.1
```

The plugin registers automatically via Flutter's federated registry — no
explicit imports required from app code.

## Behaviour on watchOS

| Stream | watchOS |
|---|---|
| `accelerometerEventStream` | supported (raw acceleration, m/s²) |
| `userAccelerometerEventStream` | supported (gravity removed, via device motion) |
| `gyroscopeEventStream` | supported (rad/s) |
| `magnetometerEventStream` | supported (µT) |
| `barometerEventStream` | not implemented (separate altimeter API) |

Units and axis signs match the `sensors_plus` iOS implementation.

> **Simulator note:** the watchOS Simulator has no motion hardware, so the
> streams emit nothing there. On a physical Apple Watch they stream normally.

## Status

| Platform | Implemented |
|----------|-------------|
| Apple Watch (`watchos`) | yes (accelerometer, gyroscope, magnetometer, user-accel) |
| Watch simulator (`watchsimulator`) | builds/links; no samples (no hardware) |

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the full text.
