import SwiftUI

#if !FLUTTER_WATCHOS_PLUGIN_DEFINES || GD_CAMERA
let gdWatchosCamera = true
#else
let gdWatchosCamera = false
#endif

@_cdecl("gd_watchos_register_views")
public func gdWatchosRegisterViews() {
    FlutterWatchOSPluginViews.register("gd_watchos") { params in
        AnyView(Text(gdWatchosCamera ? params : ""))
    }
}
