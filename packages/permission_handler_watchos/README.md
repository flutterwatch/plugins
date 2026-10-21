# permission_handler_watchos

The watchOS implementation of [`permission_handler`](https://pub.dev/packages/permission_handler).

Scaffolded with [`flutter-watchos plugin port`](https://github.com/flutterwatch/flutter-watchos)
from `permission_handler_apple` and finished by hand as an **FFI**
implementation — see `PORTING_REPORT.md`.

## Usage

`permission_handler` does not include a watchOS implementation, so add this
package alongside it:

```yaml
dependencies:
  permission_handler: ^13.0.2
  permission_handler_watchos: ^0.0.1
```

Use permission_handler as usual:

```dart
final PermissionStatus status = await Permission.locationWhenInUse.request();
if (status.isGranted) {
  // ...
}
```

Add the usage description of each permission you ask for to the watch app's
`watchos/Runner/Info.plist`, as on iOS: `NSLocationWhenInUseUsageDescription`,
`NSLocationAlwaysAndWhenInUseUsageDescription`, `NSMotionUsageDescription`,
`NSMicrophoneUsageDescription`, `NSContactsUsageDescription`,
`NSCalendarsFullAccessUsageDescription`,
`NSCalendarsWriteOnlyAccessUsageDescription`,
`NSRemindersFullAccessUsageDescription`, `NSBluetoothAlwaysUsageDescription`.
A request whose key is missing fails with a `PlatformException` whose code is
`MISSING_USAGE_DESCRIPTION`, where watchOS would terminate the app.

There are no build macros to set. The iOS implementation needs one per
permission so that an app does not reference an API it never asks for; this
package loads each framework at runtime, the first time a permission of its
group is asked about, so an app carries no reference to the others.

## Behaviour on watchOS

| Permission | watchOS |
|---|---|
| `notification` | supported, provisional included |
| `location`, `locationWhenInUse`, `locationAlways` | supported, with the service status; "always" needs "when in use" first, as on iOS |
| `sensors` | supported (Motion & Fitness), with the service status |
| `microphone` | supported, watchOS 10 and later |
| `contacts` | supported, `limited` from watchOS 11 |
| `calendarFullAccess`, `calendarWriteOnly`, `reminders` | supported, watchOS 10 and later for the full-access and write-only prompts |
| `bluetooth` | supported, with the service status |

`shouldShowRequestPermissionRationale` is false, as on iOS. The statuses and
the error codes are the iOS implementation's.

## Not supported on watchOS

| Member | On watchOS | Why |
|---|---|---|
| `camera`, `photos`, `photosAddOnly`, `mediaLibrary`, `speech`, `appTrackingTransparency`, `backgroundRefresh`, `phone` | `denied`; a request `permanentlyDenied`; service `disabled` | watchOS has none of these; iOS answers the same for a permission it does not know |
| `criticalAlerts`, `assistant` | as above | not implemented yet: each needs an entitlement |
| `openAppSettings` | returns false | watchOS has no settings page an app can open; the wearer changes a permission in the watch's Settings or in the Watch app on the iPhone |

## License

MIT, as upstream `permission_handler` is. See `LICENSE` for the full text.
