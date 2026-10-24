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
* Each framework but UserNotifications is loaded at runtime instead of
  linked. Every group's class names and selectors are still in the binary,
  unlike the iOS implementation, whose build macros leave a group out;
  whether App Store Connect's usage-description check reads them is not yet
  known (see the README).
* The location strategy keeps one flag in `NSUserDefaults`, so apps declare
  `NSPrivacyAccessedAPICategoryUserDefaults` (`CA92.1`) in their privacy
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
