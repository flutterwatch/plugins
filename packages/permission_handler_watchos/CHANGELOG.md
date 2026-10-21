## 0.0.1

First version, staged: checked on the watchOS 27.0 Simulator, not yet on a
physical watch.

* `PermissionHandlerWatchos` answers `permission_handler` on watchOS over
  dart:ffi: status, service status and requests for location (when in use
  and always), notifications, sensors, the microphone, contacts, the
  calendar (full access and write only), reminders and Bluetooth, with the
  iOS implementation's statuses and error codes.
* Each framework but UserNotifications is loaded at runtime, so an app links
  no privacy API it never asks for, which the iOS implementation arranges
  with build macros.
* A request whose usage description is missing fails with
  `MISSING_USAGE_DESCRIPTION` instead of the app being terminated.
* The example's `lib/` is a watch demo of every permission watchOS has,
  because the upstream example needs `url_launcher`; a watchOS integration
  test checks the answers that need no prompt.
