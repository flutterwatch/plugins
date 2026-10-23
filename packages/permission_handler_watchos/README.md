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
`NSRemindersFullAccessUsageDescription`, `NSBluetoothAlwaysUsageDescription`,
`NSSiriUsageDescription`. A request whose key is missing fails with a
`PlatformException` whose code is `MISSING_USAGE_DESCRIPTION`, where watchOS
would terminate the app.

### App Review

Every permission group's code is in every app that uses this package. The
iOS implementation leaves a group out at compile time unless its build macro
is set, so App Store Connect sees no privacy API an app does not use. A watch
app has no Podfile to set such macros, and the flutter-watchos CLI compiles
plugin sources with fixed flags. Here the frameworks other than
UserNotifications are not linked and are loaded only when a permission of
their group is asked about, but each group's class names, selectors and
delegate metadata are still in the binary. Whether App Store Connect's check
for missing usage descriptions (ITMS-90683) reads those is not documented,
and no upload has checked it yet: until one has, expect an app to need the
usage description of every group, the ones it never asks for included.

The location strategy keeps one flag in `NSUserDefaults`, whether "always"
was asked for, since watchOS shows that prompt once. `NSUserDefaults` is a
required-reason API and this code is in every app that uses the package, so
the app's privacy manifest (`PrivacyInfo.xcprivacy`) declares
`NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`:

```xml
<key>NSPrivacyAccessedAPITypes</key>
<array>
	<dict>
		<key>NSPrivacyAccessedAPIType</key>
		<string>NSPrivacyAccessedAPICategoryUserDefaults</string>
		<key>NSPrivacyAccessedAPITypeReasons</key>
		<array>
			<string>CA92.1</string>
		</array>
	</dict>
</array>
```

## Behaviour on watchOS

| Permission | watchOS |
|---|---|
| `notification` | supported, provisional included |
| `location`, `locationWhenInUse`, `locationAlways` | supported, with the service status; "always" needs "when in use" first, as on iOS |
| `sensors` | supported (Motion & Fitness), with the service status |
| `microphone` | supported |
| `contacts` | supported; watchOS has no limited access |
| `calendarFullAccess`, `calendarWriteOnly`, `reminders` | supported, with the full-access and write-only prompts |
| `bluetooth` | supported, with the service status |
| `criticalAlerts` | supported; needs the Critical Alerts entitlement (`com.apple.developer.usernotifications.critical-alerts`), which Apple grants on request |
| `assistant` | Siri, supported; needs the Siri capability (`com.apple.developer.siri`) and `NSSiriUsageDescription`. watchOS ends an app without the capability that asks about Siri, so the key is the opt-in the iOS implementation's build macro is: without it the status is `denied` and Siri is never asked |
| `storage` | granted, as on iOS: the app's own container needs no permission |

`shouldShowRequestPermissionRationale` is false, as on iOS. The statuses and
the error codes are the iOS implementation's.

## Not supported on watchOS

| Member | On watchOS | Why |
|---|---|---|
| `camera`, `photos`, `photosAddOnly`, `mediaLibrary`, `speech`, `appTrackingTransparency`, `backgroundRefresh`, `phone` | `denied`; a request `permanentlyDenied`; service `disabled` | watchOS has none of these; iOS answers the same for a permission it does not know |
| `openAppSettings` | returns false | watchOS has no settings page an app can open; the wearer changes a permission in the watch's Settings or in the Watch app on the iPhone |

## License

MIT, as upstream `permission_handler` is. See `LICENSE` for the full text.
