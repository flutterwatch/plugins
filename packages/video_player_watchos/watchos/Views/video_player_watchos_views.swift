// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// The plugin's native platform view: AVKit's SwiftUI `VideoPlayer`, overlaid
// where the Dart side places its `WatchPlatformView`. The flutter-watchos CLI
// compiles this file (plus its registration shim) into the app; registration
// is triggered by the plugin's Dart `registerWith()` calling
// `video_player_watchos_register_views` over FFI.

import AVFoundation
import AVKit
import SwiftUI

/// The plugin's own C ABI (Classes/video_player_watchos_ffi.m), linked into
/// the same binary: returns the AVPlayer for a player id, retained.
@_silgen_name("video_player_watchos_copy_player")
private func video_player_watchos_copy_player(
    _ playerId: Int64
) -> UnsafeMutableRawPointer?

@_cdecl("video_player_watchos_register_views")
public func videoPlayerWatchosRegisterViews() {
    FlutterWatchOSPluginViews.register("video_player_watchos") { params in
        // creationParams is the player id in decimal.
        guard let playerId = Int64(params),
              let raw = video_player_watchos_copy_player(playerId) else {
            return AnyView(EmptyView())
        }
        let player = Unmanaged<AVPlayer>.fromOpaque(raw).takeRetainedValue()
        // Bare video surface. The Dart side embeds it in the underlay layer
        // (below the Flutter frame), so Flutter draws controls/overlays over
        // the video and owns every touch — AVKit's own chrome never engages.
        return AnyView(VideoPlayer(player: player))
    }
}
