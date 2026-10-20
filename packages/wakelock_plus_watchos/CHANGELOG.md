## 0.0.1

First version, staged: checked on the watchOS 27.0 Simulator, not yet on a
physical watch.

* The wakelock as a `WKExtendedRuntimeSession`: `toggle(enable: true)` starts
  one and completes once it runs, `toggle(enable: false)` ends it, and
  `enabled` says whether one is running. watchOS has no idle timer to turn
  off.
* The session type comes from the `Info.plist`'s `WKBackgroundModes`
  (self-care, mindfulness, physical-therapy or alarm). Without one, enabling
  does nothing and `enabled` stays false; a session the system refuses fails
  with a `PlatformException` carrying its error code.
* Start and stop bump a generation, so a session that reports it started just
  after a stop cannot turn the wakelock back on.
* The example's `Info.plist` names a `self-care` session.
