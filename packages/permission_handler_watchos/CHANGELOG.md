## 0.0.1

First version, staged: checked on the watchOS 27.0 Simulator, not yet on a
physical watch.

* `PermissionHandlerWatchos` answers `permission_handler` on watchOS over
  dart:ffi: status, service status and requests for location (when in use
  and always), notifications, critical alerts, sensors, the microphone,
  contacts, the calendar (full access and write only), reminders, Bluetooth
  and Siri (`assistant`, for an app that sets `PermissionHandlerWatchosSiri`
  in its Info.plist), with the iOS implementation's statuses and error
  codes. `storage` is granted, as on iOS.
* Each group is compiled into the app only when the watch app's Info.plist
  sets one of its keys, as the iOS implementation's `PERMISSION_*` macros
  do: the pubspec maps the same macros to the keys under `defines`, which
  the first flutter-watchos release after 0.1.1 applies. A group left out
  answers as an unknown permission does, and none of its class names,
  selectors or keys are in the binary. Calendar and reminders behave as on
  iOS with only some of their keys: each status is still read, and a
  request whose prompt is left out answers its status. With only the
  when-in-use key, `locationAlways` is left out too. Siri opts in only when
  `PermissionHandlerWatchosSiri` is the Boolean YES or a string YES, true or
  1: any non-empty string compiles Siri's code in, but `NO` leaves Siri off.
  Under flutter-watchos 0.1.1 or earlier, or when the CLI cannot read the
  Info.plist, every group is compiled in, and whether App Store Connect's
  usage-description check reads the groups an app does not use is not yet
  known (see the README).
* Each framework but UserNotifications is loaded at runtime instead of
  linked.
* The location strategy keeps one flag in `NSUserDefaults`, for "always",
  so an app that compiles "always" in declares
  `NSPrivacyAccessedAPICategoryUserDefaults` (`CA92.1`) in its privacy
  manifest.
* A request whose usage description is missing fails with
  `MISSING_USAGE_DESCRIPTION` instead of the app being terminated. A request
  while another waits fails with `ERROR_ALREADY_REQUESTING_PERMISSIONS`, as
  on iOS. A location prompt closed without an answer answers denied, as on
  iOS; watchOS sends no delegate call then, so the app becoming active
  again is the answer.
* The example's `lib/` is permission_handler_apple's own example,
  unchanged, with `url_launcher_watchos` for its template's links; a
  watchOS integration test checks the answers that need no prompt.
