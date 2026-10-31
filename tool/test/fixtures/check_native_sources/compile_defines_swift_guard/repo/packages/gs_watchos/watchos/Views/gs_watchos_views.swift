import SwiftUI

#if !FLUTTER_WATCHOS_PLUGIN_DEFINES || GS_CAMERA
let gsWatchosCamera = true
#endif

// Outside the guard of what it uses: fine while the guarded code is
// compiled in, an error for an app whose Info.plist does not set the key.
@_cdecl("gs_watchos_register_views")
public func gsWatchosRegisterViews() {
    FlutterWatchOSPluginViews.register("gs_watchos") { params in
        AnyView(Text(gsWatchosCamera ? params : ""))
    }
}
