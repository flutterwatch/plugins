#import <Foundation/Foundation.h>

#if !defined(FLUTTER_WATCHOS_PLUGIN_DEFINES) || GG_CAMERA
static int gg_watchos_camera(void) { return 1; }
#endif

// Outside the guard of what it calls: fine while the guarded code is
// compiled in, an error for an app whose Info.plist does not set the key.
int gg_watchos_value(void) { return gg_watchos_camera(); }
