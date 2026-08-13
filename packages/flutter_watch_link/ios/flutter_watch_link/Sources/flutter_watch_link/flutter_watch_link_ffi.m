// Shim so SwiftPM's target glob picks up the shared source. The same file is
// compiled for watchOS and, under CocoaPods, via ios/Classes. See src/.
#include "../../../../src/flutter_watch_link_ffi.m"
