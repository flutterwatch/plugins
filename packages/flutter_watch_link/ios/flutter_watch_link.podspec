#
# The iPhone half of the session — an FFI plugin.
#
# `Classes/` holds a one-line shim that includes `../../src`, the same source
# the watchOS half compiles. There is no plugin class: Dart reaches WCSession
# through `DynamicLibrary.process()` on both platforms.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_watch_link'
  s.version          = '0.1.0'
  s.summary          = 'WatchConnectivity for Flutter companion apps.'
  s.description      = <<-DESC
One Dart API for iPhone-to-Apple-Watch messaging, application context, and
guaranteed background transfers.
                       DESC
  s.homepage         = 'https://flutterwatch.dev'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'The FlutterWatch Authors' => 'hello@flutterwatch.dev' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.frameworks = 'WatchConnectivity'

  # Deliberately NOT a static framework. A static archive's members are only
  # pulled in when something references them, and nothing does — the symbols
  # exist purely for dart:ffi to look up at runtime — so they would be dropped
  # at link time. A dynamic framework exports them unconditionally; the Dart
  # side opens it by name when they are not already in the process.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end
