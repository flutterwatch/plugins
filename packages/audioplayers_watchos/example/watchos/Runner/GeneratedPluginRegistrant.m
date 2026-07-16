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
extern void audioplayers_watchos_create(void);
extern void audioplayers_watchos_dispose(void);
extern void audioplayers_watchos_set_source_url(void);
extern void audioplayers_watchos_set_source_bytes(void);
extern void audioplayers_watchos_resume(void);
extern void audioplayers_watchos_pause(void);
extern void audioplayers_watchos_stop(void);
extern void audioplayers_watchos_release(void);
extern void audioplayers_watchos_seek(void);
extern void audioplayers_watchos_set_volume(void);
extern void audioplayers_watchos_set_rate(void);
extern void audioplayers_watchos_set_release_mode(void);
extern void audioplayers_watchos_read_state(void);
extern void audioplayers_watchos_error(void);
extern void audioplayers_watchos_set_audio_context(void);
extern void path_provider_watchos_temporary_path(void);
extern void path_provider_watchos_application_support_path(void);
extern void path_provider_watchos_library_path(void);
extern void path_provider_watchos_documents_path(void);
extern void path_provider_watchos_cache_path(void);

@implementation GeneratedPluginRegistrant

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {

  // Force the linker to keep the statically-linked FFI plugin archive
  // member(s); see the file-scope note above.
  const void *_flutterWatchosFfiForcedReferences[] = {
    (const void *)&audioplayers_watchos_create,
    (const void *)&audioplayers_watchos_dispose,
    (const void *)&audioplayers_watchos_set_source_url,
    (const void *)&audioplayers_watchos_set_source_bytes,
    (const void *)&audioplayers_watchos_resume,
    (const void *)&audioplayers_watchos_pause,
    (const void *)&audioplayers_watchos_stop,
    (const void *)&audioplayers_watchos_release,
    (const void *)&audioplayers_watchos_seek,
    (const void *)&audioplayers_watchos_set_volume,
    (const void *)&audioplayers_watchos_set_rate,
    (const void *)&audioplayers_watchos_set_release_mode,
    (const void *)&audioplayers_watchos_read_state,
    (const void *)&audioplayers_watchos_error,
    (const void *)&audioplayers_watchos_set_audio_context,
    (const void *)&path_provider_watchos_temporary_path,
    (const void *)&path_provider_watchos_application_support_path,
    (const void *)&path_provider_watchos_library_path,
    (const void *)&path_provider_watchos_documents_path,
    (const void *)&path_provider_watchos_cache_path,
  };
  for (unsigned long _i = 0;
       _i < sizeof(_flutterWatchosFfiForcedReferences) / sizeof(_flutterWatchosFfiForcedReferences[0]);
       _i++) {
    __asm__ volatile("" : : "r"(_flutterWatchosFfiForcedReferences[_i]));
  }
}

@end
