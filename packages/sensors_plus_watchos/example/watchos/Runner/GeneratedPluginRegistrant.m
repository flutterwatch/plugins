//
//  Generated file. Do not edit.
//

#import "GeneratedPluginRegistrant.h"


// FFI plugins resolve their C symbols at runtime via dlsym
// (DynamicLibrary.process()), so nothing in the compiled app references
// them. When such a plugin is linked statically through the generated
// Swift Package Manager umbrella, the linker would drop its unreferenced
// archive member and the symbols would be absent from the binary. The
// references that prevent that are emitted inside the (always-linked,
// always-reachable) registerWithRegistry: method below — see
// _renderFfiForcedReferenceBody. Forward declarations:
extern void sensors_plus_watchos_start_accelerometer(void);
extern void sensors_plus_watchos_read_accelerometer(void);
extern void sensors_plus_watchos_stop_accelerometer(void);
extern void sensors_plus_watchos_start_user_accelerometer(void);
extern void sensors_plus_watchos_read_user_accelerometer(void);
extern void sensors_plus_watchos_stop_user_accelerometer(void);
extern void sensors_plus_watchos_start_gyroscope(void);
extern void sensors_plus_watchos_read_gyroscope(void);
extern void sensors_plus_watchos_stop_gyroscope(void);
extern void sensors_plus_watchos_start_magnetometer(void);
extern void sensors_plus_watchos_read_magnetometer(void);
extern void sensors_plus_watchos_stop_magnetometer(void);

@implementation GeneratedPluginRegistrant

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {

  // Force the linker to keep the statically-linked FFI plugin archive
  // member(s); see the file-scope note above.
  const void *_flutterWatchosFfiForcedReferences[] = {
    (const void *)&sensors_plus_watchos_start_accelerometer,
    (const void *)&sensors_plus_watchos_read_accelerometer,
    (const void *)&sensors_plus_watchos_stop_accelerometer,
    (const void *)&sensors_plus_watchos_start_user_accelerometer,
    (const void *)&sensors_plus_watchos_read_user_accelerometer,
    (const void *)&sensors_plus_watchos_stop_user_accelerometer,
    (const void *)&sensors_plus_watchos_start_gyroscope,
    (const void *)&sensors_plus_watchos_read_gyroscope,
    (const void *)&sensors_plus_watchos_stop_gyroscope,
    (const void *)&sensors_plus_watchos_start_magnetometer,
    (const void *)&sensors_plus_watchos_read_magnetometer,
    (const void *)&sensors_plus_watchos_stop_magnetometer,
  };
  for (unsigned long _i = 0;
       _i < sizeof(_flutterWatchosFfiForcedReferences) / sizeof(_flutterWatchosFfiForcedReferences[0]);
       _i++) {
    __asm__ volatile("" : : "r"(_flutterWatchosFfiForcedReferences[_i]));
  }
}

@end
