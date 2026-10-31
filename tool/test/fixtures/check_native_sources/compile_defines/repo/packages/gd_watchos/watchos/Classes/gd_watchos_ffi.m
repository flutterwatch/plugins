#import <Foundation/Foundation.h>

#if !defined(FLUTTER_WATCHOS_PLUGIN_DEFINES) || GD_CAMERA
static int gd_watchos_camera(void) { return 1; }
#else
static int gd_watchos_camera(void) { return 0; }
#endif

int gd_watchos_value(void) { return gd_watchos_camera(); }
