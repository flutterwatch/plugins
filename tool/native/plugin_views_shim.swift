// A copy of the registration shim flutter-watchos compiles into every plugin
// module with SwiftUI view sources (kPluginViewSupportSwift in the CLI's
// lib/build_targets/watchos_plugin_views.dart, CLI 0.1.1). It is here only so
// tool/check_native_sources.sh can type-check plugin view sources the way the
// CLI compiles them. Update it with the CLI. Not part of any plugin.
//
// Compiled by flutter-watchos into every plugin module that ships SwiftUI
// view sources. Not part of the plugin — do not copy it into one.
//
// Gives plugin code `FlutterWatchOSPluginViews.register(_:factory:)`, the
// Swift face of the app runner's C registration entry point.

import Darwin
import Foundation
import SwiftUI

private let _factoriesLock = NSLock()
private var _factories: [String: (String) -> AnyView] = [:]

/// The @convention(c) trampoline handed to the runner, once per registered
/// type. Receives (viewType, creationParams); returns the built AnyView
/// RETAINED, boxed by the Swift runtime (`as AnyObject` — SwiftUI hard-rejects
/// class-conforming Views, so the view itself must stay a struct and the
/// runtime box is the only class in the crossing). The runner unwraps it with
/// a plain dynamic cast, since AnyView is SwiftUI's own type on both sides.
/// nil means no factory — render nothing.
private let _factoryTrampoline: @convention(c) (
    UnsafePointer<CChar>?, UnsafePointer<CChar>?
) -> UnsafeMutableRawPointer? = { type, params in
    guard let type else { return nil }
    let viewType = String(cString: type)
    let creationParams = params.map { String(cString: $0) } ?? ""
    _factoriesLock.lock()
    let factory = _factories[viewType]
    _factoriesLock.unlock()
    guard let factory else { return nil }
    return Unmanaged.passRetained(factory(creationParams) as AnyObject).toOpaque()
}

/// Registration surface for a plugin's native SwiftUI views.
public enum FlutterWatchOSPluginViews {
    private typealias _Register = @convention(c) (
        UnsafePointer<CChar>?,
        (@convention(c) (
            UnsafePointer<CChar>?, UnsafePointer<CChar>?
        ) -> UnsafeMutableRawPointer?)?
    ) -> Void

    /// The runner's registration entry point, resolved via dlsym
    /// (RTLD_DEFAULT is the special -2 handle) so nothing links against the
    /// app at compile time. nil when the app was created by a CLI that
    /// predates plugin platform views.
    private static let _register: _Register? = {
        guard let sym = dlsym(
            UnsafeMutableRawPointer(bitPattern: -2),
            "FlutterWatchOSPlatformViewRegisterNativeFactory")
        else { return nil }
        return unsafeBitCast(sym, to: _Register.self)
    }()

    /// Registers (or replaces) the native factory for `viewType`. The factory
    /// receives the Dart widget's `creationParams` string and always runs on
    /// the main thread; `register` itself may be called from any thread
    /// (plugin registration typically arrives over FFI from Dart).
    public static func register(
        _ viewType: String, factory: @escaping (String) -> AnyView
    ) {
        _factoriesLock.lock()
        _factories[viewType] = factory
        _factoriesLock.unlock()
        guard let register = _register else {
            NSLog("FlutterWatchOSPluginViews: this app's runner predates "
                + "plugin platform views; '\(viewType)' will not render. "
                + "Re-create the app with a current flutter-watchos.")
            return
        }
        viewType.withCString { register($0, _factoryTrampoline) }
    }
}
