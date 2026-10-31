#import <Foundation/Foundation.h>

#if !defined(FLUTTER_WATCHOS_PLUGIN_DEFINES) || GP_CAMERA || GP_EXTRA

#if !defined(FLUTTER_WATCHOS_PLUGIN_DEFINES) || GP_CAMERA
static int gp_watchos_camera(void) { return 1; }
#endif

// Needs GP_CAMERA's code, but compiles under GP_EXTRA alone too: fine with
// every macro, with none and with GP_CAMERA alone, an error for an app that
// sets only GP_EXTRA's key.
int gp_watchos_value(void) { return gp_watchos_camera(); }

#endif
