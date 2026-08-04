## 0.0.1

* Initial release: watchOS implementation of `url_launcher` over dart:ffi.
* `tel:` and `sms:` open through `-[WKApplication openSystemURL:]`.
* `http:` and `https:` are published as an `NSUserActivity` for Handoff to the
  paired iPhone or Mac; the watch has no WebKit to render them itself.
* Other schemes (including `mailto:`) report unsupported rather than failing
  silently.
