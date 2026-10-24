import SwiftUI

@_cdecl("ok_watchos_register_views")
public func okWatchosRegisterViews() {
    FlutterWatchOSPluginViews.register("ok_watchos") { params in
        AnyView(Text(params))
    }
}
