// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// C ABI for the watchOS audioplayers implementation. Playback rides
// AVFoundation (AVPlayer); state is a poll-friendly snapshot with edge
// counters (the repo's standard cache-and-poll pattern — FFI has no
// native→Dart callback path). Players are keyed by the audioplayers string
// player id.

#ifndef AUDIOPLAYERS_WATCHOS_FFI_H_
#define AUDIOPLAYERS_WATCHOS_FFI_H_

#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

// One snapshot of a player's state. Dart derives the `AudioEvent` stream by
// diffing successive snapshots; one-shot occurrences (prepared, seek done,
// play-to-end) are counters so an edge between two polls is never missed.
typedef struct {
  int32_t status;               // 0 idle/loading, 1 prepared, 2 failed
  int32_t is_playing;           // AVPlayer.timeControlStatus == playing
  int32_t prepared_count;       // increments when a source becomes ready
  int32_t seek_complete_count;  // increments when an async seek lands
  int32_t complete_count;       // increments each play-to-end (non-loop)
  int32_t has_item;             // a source is loaded (position reads null
                                // upstream once released/unloaded)
  int64_t duration_ms;          // -1 unknown / indefinite (live streams)
  int64_t position_ms;          // current position (seek target in flight)
} AudioplayersWatchosState;

// Creates an (empty) player for the audioplayers string id. Idempotent.
void audioplayers_watchos_create(const char* player_id);

// Tears the player down (KVO, notifications, AVPlayer). Safe on unknown ids.
void audioplayers_watchos_dispose(const char* player_id);

// Loads a source. `is_local` selects file-path vs network-URL semantics.
// `mime_type` (may be NULL/"") overrides container sniffing for extension-
// less URLs, mirroring upstream darwin's AVURLAsset MIME override.
// Returns 0, -1 for an invalid URL, or -2 for an unknown/disposed player.
int audioplayers_watchos_set_source_url(const char* player_id,
                                        const char* url,
                                        bool is_local,
                                        const char* mime_type);

// Loads a source from bytes (spooled to a temp file; AVPlayer needs a URL).
// `extension_hint` (may be NULL/"") names the file so AVFoundation can sniff
// the container, e.g. "mp3". Returns 0, -1 on failure, or -2 for an
// unknown/disposed player.
int audioplayers_watchos_set_source_bytes(const char* player_id,
                                          const uint8_t* bytes,
                                          int64_t length,
                                          const char* extension_hint);

// Player-scoped controls return false for an unknown/disposed player id —
// Dart surfaces upstream's "Player has not yet been created or has already
// been disposed." PlatformException.
bool audioplayers_watchos_resume(const char* player_id);
bool audioplayers_watchos_pause(const char* player_id);

// Pauses and rewinds to zero, keeping the source loaded. Under release
// mode `release`, unloads instead (upstream stop semantics).
bool audioplayers_watchos_stop(const char* player_id);

// Unloads the source (subsequent resume is a no-op until a new source is
// set). Matches upstream darwin, where release == stop + unload.
bool audioplayers_watchos_release(const char* player_id);

// Frame-accurate async seek; `seek_complete_count` increments when it lands.
// Until then `position_ms` reports the target.
bool audioplayers_watchos_seek(const char* player_id, int64_t position_ms);

// volume 0.0–1.0 (clamped).
bool audioplayers_watchos_set_volume(const char* player_id, double volume);

// Playback rate; applied immediately when playing, remembered otherwise.
// (AVPlayer supports roughly 0.5–2x for audio, like upstream iOS.)
bool audioplayers_watchos_set_rate(const char* player_id, double rate);

// 0 release, 1 loop, 2 stop (ReleaseMode.index).
bool audioplayers_watchos_set_release_mode(const char* player_id,
                                           int32_t mode);

// Copies the current snapshot; returns false for an unknown player id.
bool audioplayers_watchos_read_state(const char* player_id,
                                     AudioplayersWatchosState* out);

// Failure description once `status == 2`; "" otherwise. Owned by the player,
// valid until dispose.
const char* audioplayers_watchos_error(const char* player_id);

// AVAudioSession category by name ("playback", "playAndRecord", …) plus
// mixWithOthers/duckOthers options. Global, like upstream iOS (audio
// context is session-wide on Apple platforms). Unknown categories are
// ignored (watchOS has a narrower set than iOS). Returns 0 on success.
int audioplayers_watchos_set_audio_context(const char* category,
                                           bool mix_with_others,
                                           bool duck_others);

#endif  // AUDIOPLAYERS_WATCHOS_FFI_H_
