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
`watchos/Runner/Info.plist` and defines the macro of each key the app
sets, as the package's pubspec maps them under `defines`.

| Group | Permissions | Macro | Info.plist keys, any one |
|---|---|---|---|
| Location, when in use | `location`, `locationWhenInUse` | `PERMISSION_LOCATION_WHENINUSE` | `NSLocationWhenInUseUsageDescription` |
| Location, always too | `location`, `locationWhenInUse`, `locationAlways` | `PERMISSION_LOCATION` | `NSLocationAlwaysAndWhenInUseUsageDescription`, `NSLocationAlwaysUsageDescription` |
| Sensors | `sensors` | `PERMISSION_SENSORS` | `NSMotionUsageDescription` |
| Microphone | `microphone` | `PERMISSION_MICROPHONE` | `NSMicrophoneUsageDescription` |
| Contacts | `contacts` | `PERMISSION_CONTACTS` | `NSContactsUsageDescription` |
| Calendar and reminders | `calendar`, `calendarFullAccess`, `calendarWriteOnly`, `reminders` | `PERMISSION_EVENTS_FULL_ACCESS`, `PERMISSION_EVENTS`, `PERMISSION_REMINDERS`, one for each key in turn | `NSCalendarsFullAccessUsageDescription`, `NSCalendarsWriteOnlyAccessUsageDescription`, `NSRemindersFullAccessUsageDescription` |
| Bluetooth | `bluetooth` | `PERMISSION_BLUETOOTH` | `NSBluetoothAlwaysUsageDescription` |
| Siri | `assistant` | `PERMISSION_ASSISTANT` | `PermissionHandlerWatchosSiri`, a Boolean set to `YES` |

- A key counts when it holds a non-empty string, `NO` included, or the
  Boolean `YES`. Set `PermissionHandlerWatchosSiri` to the Boolean `YES`. A
  string compiles Siri's code in too, but only `YES`, `true` or `1`, in any
  case, opts in when the app runs: `<string>NO</string>` compiles the code in
  and leaves Siri off.
- `notification`, `criticalAlerts` and `storage` need no key, and are always
  compiled in.
- When none of a permission's keys counts, it answers as a permission
  watchOS does not have, as the iOS implementation answers a group whose
  macros are all off: its status is `denied`, a request answers
  `permanentlyDenied` without a prompt, and its service is `disabled`.
- Calendar and reminders are one group, as on iOS: any one of its three
  keys compiles it in, and all four of its permissions then read their real
  status and answer the service as not applicable. Each key adds its own
  prompt: the full-access key the one of `calendar` and `calendarFullAccess`,
  the write-only key the one of `calendarWriteOnly`, and the reminders key
  the one of `reminders`. A request whose prompt is left out answers its
  status without a prompt, as on iOS.
- The full-access key compiles the write-only request in too, as on iOS,
  but the write-only prompt still needs its own key,
  `NSCalendarsWriteOnlyAccessUsageDescription`. With only the full-access
  key, `calendarWriteOnly` is granted once full access is, and a request
  while it is not determined fails with `MISSING_USAGE_DESCRIPTION`, where
  iOS sends the write-only request.
- With `NSLocationWhenInUseUsageDescription` alone, `locationAlways` is left
  out and answers as a permission watchOS does not have, with no "always"
  request and no `NSUserDefaults` flag in the app. The iOS implementation
  keeps its location code for `locationAlways` there, and reads its status.
- If flutter-watchos cannot read `watchos/Runner/Info.plist`, it warns and
  compiles every group in, as an older flutter-watchos does.
- After an Info.plist edit, run `flutter-watchos build watchos --release`
  again before you archive. An Xcode build or archive does not compile the
  groups again, `run` and `test` stage a debug build for one SDK, and `test`
  without `-d` compiles no plugin source.

With flutter-watchos 0.1.1 or earlier, every group is compiled into every
app, whatever its Info.plist says. Each permission you ask for still needs
its key, as above, and expect the app to need the usage description of
every group it never asks for too (see App Review).

### App Review

App Store Connect asks for the usage description of each privacy-sensitive
API a binary references (ITMS-90683). With the first flutter-watchos release
after 0.1.1, a group the app's Info.plist leaves out is not in the binary:
none of its framework's class names, selectors or usage-description keys
are. A watch app that only asks for notifications then references the same
privacy API as a native watch app that does only that,
`UNUserNotificationCenter`, and nothing else. So an app needs only the keys
of the groups it uses, as on iOS.

With flutter-watchos 0.1.1 or earlier, every group's code is in every app
that uses this package. The frameworks other than UserNotifications are not
linked and are loaded only when a permission of their group is asked about,
but each group's class names, request selectors and usage-description keys
stay in the binary as strings. Whether App Store Connect's check reads those
is not documented, so expect such an app to need the usage description of
every group, the ones it never asks for included.

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
| `assistant` | Siri, supported for an app that opts in: watchOS ends an app without the Siri capability (`com.apple.developer.siri`) that asks about Siri, so the iOS implementation's build macro is an Info.plist key here, `PermissionHandlerWatchosSiri` set to `YES`, which only an app with the capability sets, with `NSSiriUsageDescription`. Only the Boolean `YES`, or a string `YES`, `true` or `1` in any case, opts in. Without the opt-in Siri is never asked and its status is `denied`. If Siri's code is left out, which a flutter-watchos after 0.1.1 does when the key does not count (see Compile-time groups), a request answers `permanentlyDenied` and the service is `disabled`. If the code is in, as with any other non-empty string (`NO`, say), under flutter-watchos 0.1.1 or earlier, or when flutter-watchos cannot read the Info.plist, a request answers `denied` and the service is not applicable |
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
