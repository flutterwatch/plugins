// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// C ABI for the watchOS video_player implementation. Playback control and
// state ride AVFoundation (AVPlayer); rendering is a platform view — the
// plugin's Swift side (Views/video_player_watchos_views.swift) overlays
// AVKit's SwiftUI `VideoPlayer` for the player looked up via
// `video_player_watchos_copy_player`.

#ifndef VIDEO_PLAYER_WATCHOS_FFI_H_
#define VIDEO_PLAYER_WATCHOS_FFI_H_

#include <stdbool.h>
#include <stdint.h>

// One poll-friendly snapshot of a player's state. Dart derives the
// `VideoEvent` stream by diffing successive snapshots (the repo's standard
// cache-and-poll pattern — FFI has no native→Dart callback path).
typedef struct {
  int32_t status;      // 0 unknown, 1 initialized (ready), 2 failed
  int32_t is_playing;  // AVPlayer.timeControlStatus == playing
  // Buffering edges as counters (upstream's rule: playbackLikelyToKeepUp
  // false → start, true → end). Counters — not a flag — so a brief stall
  // between two polls is never missed.
  int32_t buffering_start_count;
  int32_t buffering_end_count;
  int32_t completed_count;  // increments each play-to-end (non-looping)
  int64_t duration_ms;      // -1 until known; 0 for indefinite (live)
  int64_t buffered_ms;      // end of the furthest contiguous loaded range
  double width;             // presentationSize, points (0 until ready)
  double height;
} VideoPlayerWatchosState;

// Creates a player for `uri` and starts loading. `source_type`:
// 0 network URL, 1 file path, 2 Flutter asset key (resolved against the app
// bundle's flutter_assets/). Returns the player id, or -1 on invalid input.
int64_t video_player_watchos_create(const char* uri, int32_t source_type);

// Tears the player down (KVO, notifications, AVPlayer). Safe on unknown ids.
void video_player_watchos_dispose(int64_t player_id);

void video_player_watchos_play(int64_t player_id);
void video_player_watchos_pause(int64_t player_id);

// volume 0.0–1.0 (clamped).
void video_player_watchos_set_volume(int64_t player_id, double volume);

// Looping seeks back to zero and resumes on play-to-end instead of
// completing.
void video_player_watchos_set_looping(int64_t player_id, bool looping);

// Playback rate; applied immediately when playing, remembered otherwise.
void video_player_watchos_set_speed(int64_t player_id, double speed);

// Frame-accurate async seek. Until it lands, `position` reports the target
// (so a poll right after seeking never shows the stale position).
void video_player_watchos_seek(int64_t player_id, int64_t position_ms);

// Current playback position in ms (the pending seek target while seeking).
int64_t video_player_watchos_position(int64_t player_id);

// Copies the current snapshot; returns false for an unknown player id.
bool video_player_watchos_read_state(int64_t player_id,
                                     VideoPlayerWatchosState* out);

// Failure description once `status == 2`; "" otherwise. Owned by the player,
// valid until dispose.
const char* video_player_watchos_error(int64_t player_id);

// AVAudioSession: mix this app's audio with other audio instead of
// interrupting it. Global (matches the upstream semantics).
void video_player_watchos_set_mix_with_others(bool mix);

// Returns the underlying AVPlayer, RETAINED, as an opaque pointer — consumed
// by the plugin's Swift view factory. NULL for unknown ids.
void* video_player_watchos_copy_player(int64_t player_id);

#endif  // VIDEO_PLAYER_WATCHOS_FFI_H_
