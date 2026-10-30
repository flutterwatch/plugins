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
`NSSiriUsageDescription`. Siri also needs its own opt-in, only with the Siri
capability (see `assistant` below), because asking about Siri without the
capability ends the app. When its group is compiled in (see below), a
request whose prompt needs a key the Info.plist lacks fails with a
`PlatformException` whose code is `MISSING_USAGE_DESCRIPTION`, where watchOS
would terminate the app.

### Compile-time groups

As in the iOS implementation, a permission group's code is compiled into the
app only when the app uses the group, which it says by setting one of the
group's keys in the watch app's Info.plist. This takes the first
flutter-watchos release after 0.1.1: on every build, it reads
`watchos/Runner/Info.plist` and defines the group's macro, as the package's
pubspec maps them under `defines`.

| Group | Permissions | Macro | Info.plist keys, any one |
|---|---|---|---|
| Location, when in use | `location`, `locationWhenInUse` | `PERMISSION_LOCATION_WHENINUSE` | `NSLocationWhenInUseUsageDescription` |
| Location, always too | `location`, `locationWhenInUse`, `locationAlways` | `PERMISSION_LOCATION` | `NSLocationAlwaysAndWhenInUseUsageDescription`, `NSLocationAlwaysUsageDescription` |
| Sensors | `sensors` | `PERMISSION_SENSORS` | `NSMotionUsageDescription` |
| Microphone | `microphone` | `PERMISSION_MICROPHONE` | `NSMicrophoneUsageDescription` |
| Contacts | `contacts` | `PERMISSION_CONTACTS` | `NSContactsUsageDescription` |
| Calendar, full access | `calendarFullAccess`, `calendar`, `calendarWriteOnly` | `PERMISSION_EVENTS_FULL_ACCESS` | `NSCalendarsFullAccessUsageDescription` |
| Calendar, write only | `calendarWriteOnly` | `PERMISSION_EVENTS` | `NSCalendarsWriteOnlyAccessUsageDescription` |
| Reminders | `reminders` | `PERMISSION_REMINDERS` | `NSRemindersFullAccessUsageDescription` |
| Bluetooth | `bluetooth` | `PERMISSION_BLUETOOTH` | `NSBluetoothAlwaysUsageDescription` |
| Siri | `assistant` | `PERMISSION_ASSISTANT` | `PermissionHandlerWatchosSiri`, a Boolean set to `YES` |

- A key counts when it holds a non-empty string, `NO` included, or the
  Boolean `YES`. Set `PermissionHandlerWatchosSiri` to the Boolean `YES`, and
  leave it out of an app without the Siri capability: Siri's opt-in counts
  any string as on too.
- `notification`, `criticalAlerts` and `storage` need no key, and are always
  compiled in.
- A group whose keys are all missing answers as a permission watchOS does
  not have, as the iOS implementation answers a group whose macros are all
  off: its status is `denied`, a request answers `permanentlyDenied` without
  a prompt, and its service is `disabled`.
- The calendar and reminders group is compiled in with any one of its three
  keys, as on iOS. All four of its permissions then read their real status
  and answer the service as not applicable. A request whose prompt the keys
  do not allow answers that status without a prompt, as on iOS. The
  full-access key allows the write-only prompt too.
- With `NSLocationWhenInUseUsageDescription` alone, `locationAlways` is left
  out and answers as a permission watchOS does not have, with no "always"
  request and no `NSUserDefaults` flag in the app. The iOS implementation
  keeps its location code for `locationAlways` there, and reads its status.
- If flutter-watchos cannot read `watchos/Runner/Info.plist`, it warns and
  compiles every group in, as an older flutter-watchos does.
- After an Info.plist edit, rebuild with `flutter-watchos build` (or `run`,
  or `test`) before you archive: an Xcode build or archive alone does not
  compile the groups again.

With flutter-watchos 0.1.1 or earlier, every group is compiled into every
app, whatever its Info.plist says. Each permission you ask for still needs
its key, as above, and expect the app to need the usage description of
every group it never asks for too (see App Review).

### App Review

App Store Connect asks for the usage description of each privacy-sensitive
API a binary references (ITMS-90683). With the first flutter-watchos release
after 0.1.1, a group the app's Info.plist leaves out is not in the binary:
none of its framework's class names, selectors or usage-description keys
are. So an app needs only the keys of the groups it uses, as on iOS.

With flutter-watchos 0.1.1 or earlier, every group's code is in every app
that uses this package. The frameworks other than UserNotifications are not
linked and are loaded only when a permission of their group is asked about,
but each group's class names, selectors and delegate metadata are still in
the binary. Whether App Store Connect's check reads those is not documented,
and no upload has checked it yet: until one has, expect such an app to need
the usage description of every group, the ones it never asks for included.

The location strategy keeps one flag in `NSUserDefaults`, whether "always"
was asked for, since watchOS shows that prompt once. `NSUserDefaults` is a
required-reason API, so an app with this code declares
`NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1` in its
privacy manifest (`PrivacyInfo.xcprivacy`). With the first flutter-watchos
release after 0.1.1, that is an app whose Info.plist sets
`NSLocationAlwaysAndWhenInUseUsageDescription` or
`NSLocationAlwaysUsageDescription`, or whose Info.plist the CLI cannot read;
with an older one, every app that uses the package:

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
| `assistant` | Siri, supported for an app that opts in: watchOS ends an app without the Siri capability (`com.apple.developer.siri`) that asks about Siri, so the iOS implementation's build macro is an Info.plist key here, `PermissionHandlerWatchosSiri` set to `YES`, which only an app with the capability sets, with `NSSiriUsageDescription`. Any non-empty string opts in too, as the key turns Siri's code on by the same rule. Without the key Siri is never asked and the status is `denied`. A request answers `permanentlyDenied` with a flutter-watchos that leaves Siri's code out (see Compile-time groups), and `denied` with 0.1.1 or earlier |
| `storage` | granted, as on iOS: the app's own container needs no permission |

`shouldShowRequestPermissionRationale` is false, as on iOS. The statuses and
the error codes are the iOS implementation's.

## Not supported on watchOS

| Member | On watchOS | Why |
|---|---|---|
| `camera`, `photos`, `photosAddOnly`, `mediaLibrary`, `speech`, `appTrackingTransparency`, `backgroundRefresh`, `phone` | `denied`; a request `permanentlyDenied`; service `disabled` | watchOS has none of these; iOS answers the same for a permission it does not know |
| `openAppSettings` | returns false | watchOS has no settings page an app can open; the wearer changes a permission in the watch's Settings or in the Watch app on the iPhone |

## Example deviations

The example is `permission_handler_apple`'s own example app, unchanged
except for this watchOS deviation (and the formatting this repository's CI
checks):

| Where | Change | Why |
|---|---|---|
| `example/pubspec.yaml` | adds `url_launcher_watchos` | the example's `baseflow_plugin_template` opens its links with `url_launcher`, which has no watchOS implementation without it |

`example/integration_test/permission_handler_test.dart` is this package's
own: upstream has no integration test.

## License

MIT, as upstream `permission_handler` is. See `LICENSE` for the full text.
