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
extern void connectivity_plus_watchos_current(void);

@implementation GeneratedPluginRegistrant

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {

  // Force the linker to keep the statically-linked FFI plugin archive
  // member(s); see the file-scope note above.
  const void *_flutterWatchosFfiForcedReferences[] = {
    (const void *)&connectivity_plus_watchos_current,
  };
  for (unsigned long _i = 0;
       _i < sizeof(_flutterWatchosFfiForcedReferences) / sizeof(_flutterWatchosFfiForcedReferences[0]);
       _i++) {
    __asm__ volatile("" : : "r"(_flutterWatchosFfiForcedReferences[_i]));
  }
}

@end
