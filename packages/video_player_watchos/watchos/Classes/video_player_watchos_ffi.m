// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "video_player_watchos_ffi.h"

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

#include <os/lock.h>

#define VPW_EXPORT __attribute__((visibility("default"))) __attribute__((used))

/// Runs `block` on the main thread (inline when already there).
///
/// Every AVPlayer MUTATION must go through this: the FFI entry points are
/// called on the Flutter UI thread, and once the AVKit `VideoPlayer` view is
/// attached to the player, mutating it opens CATransactions on the calling
/// thread — whose run-loop flush then performs UIKit layout off the main
/// thread and aborts in _AssertAutoLayoutOnAllowedThreadsOnly. Reads
/// (state snapshot, currentTime) stay lock-guarded and thread-safe.
/// dispatch_async (never sync) also makes the main queue the serial order
/// for create → control → dispose.
static void VPWOnMain(dispatch_block_t block) {
  if (NSThread.isMainThread) {
    block();
  } else {
    dispatch_async(dispatch_get_main_queue(), block);
  }
}

#pragma mark - Player wrapper

/// Wraps one AVPlayer with the KVO/notification observers that keep a
/// lock-guarded VideoPlayerWatchosState snapshot current for polling.
@interface VPWPlayer : NSObject
@property(nonatomic, strong) AVPlayer *player;
@property(nonatomic, strong) AVPlayerItem *item;
@property(nonatomic, copy) NSString *errorDescription;
- (instancetype)initWithURL:(NSURL *)url;
- (void)readState:(VideoPlayerWatchosState *)out;
- (int64_t)positionMs;
- (void)play;
- (void)pause;
- (void)seekToMs:(int64_t)ms;
- (void)setSpeed:(double)speed;
- (void)setLooping:(bool)looping;
- (void)teardown;
@end

@implementation VPWPlayer {
  os_unfair_lock _lock;
  VideoPlayerWatchosState _state;
  bool _looping;
  double _rate;             // requested playback speed
  int64_t _pendingSeekMs;   // -1 when no seek is in flight
}

- (instancetype)initWithURL:(NSURL *)url {
  self = [super init];
  if (self == nil) {
    return nil;
  }
  _lock = OS_UNFAIR_LOCK_INIT;
  _rate = 1.0;
  _pendingSeekMs = -1;
  _errorDescription = @"";
  _state.duration_ms = -1;

  _item = [AVPlayerItem playerItemWithURL:url];
  _player = [AVPlayer playerWithPlayerItem:_item];
  // Pause at the end (the completion handler decides whether to loop).
  _player.actionAtItemEnd = AVPlayerActionAtItemEndPause;

  NSKeyValueObservingOptions opts = NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial;
  [_item addObserver:self forKeyPath:@"status" options:opts context:NULL];
  [_item addObserver:self forKeyPath:@"presentationSize" options:opts context:NULL];
  [_item addObserver:self forKeyPath:@"loadedTimeRanges" options:opts context:NULL];
  // No .Initial here: the flag starts false and an initial observation would
  // record a spurious buffering start before playback ever begins (upstream
  // doesn't observe the initial value either).
  [_item addObserver:self
          forKeyPath:@"playbackLikelyToKeepUp"
             options:NSKeyValueObservingOptionNew
             context:NULL];
  [_player addObserver:self forKeyPath:@"timeControlStatus" options:opts context:NULL];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(itemDidPlayToEnd:)
                                               name:AVPlayerItemDidPlayToEndTimeNotification
                                             object:_item];
  return self;
}

- (void)teardown {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  @try {
    [_item removeObserver:self forKeyPath:@"status"];
    [_item removeObserver:self forKeyPath:@"presentationSize"];
    [_item removeObserver:self forKeyPath:@"loadedTimeRanges"];
    [_item removeObserver:self forKeyPath:@"playbackLikelyToKeepUp"];
    [_player removeObserver:self forKeyPath:@"timeControlStatus"];
  } @catch (NSException *e) {
    // Observers already removed — nothing to do.
  }
  // Player mutations on main; captures the player (not self) so this is
  // safe from dealloc too.
  AVPlayer *player = _player;
  VPWOnMain(^{
    [player pause];
    [player replaceCurrentItemWithPlayerItem:nil];
  });
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
  os_unfair_lock_lock(&_lock);
  if ([keyPath isEqualToString:@"status"]) {
    if (_item.status == AVPlayerItemStatusFailed) {
      _state.status = 2;
      self.errorDescription = _item.error.localizedDescription ?: @"playback failed";
    } else if (_item.status == AVPlayerItemStatusReadyToPlay) {
      _state.status = 1;
      CMTime duration = _item.duration;
      _state.duration_ms =
          CMTIME_IS_NUMERIC(duration) ? (int64_t)(CMTimeGetSeconds(duration) * 1000.0) : 0;
    }
  } else if ([keyPath isEqualToString:@"presentationSize"]) {
    CGSize size = _item.presentationSize;
    _state.width = size.width;
    _state.height = size.height;
  } else if ([keyPath isEqualToString:@"loadedTimeRanges"]) {
    int64_t furthest = 0;
    for (NSValue *value in _item.loadedTimeRanges) {
      CMTimeRange range = value.CMTimeRangeValue;
      CMTime end = CMTimeRangeGetEnd(range);
      if (CMTIME_IS_NUMERIC(end)) {
        int64_t ms = (int64_t)(CMTimeGetSeconds(end) * 1000.0);
        if (ms > furthest) {
          furthest = ms;
        }
      }
    }
    _state.buffered_ms = furthest;
  } else if ([keyPath isEqualToString:@"playbackLikelyToKeepUp"]) {
    // Upstream's buffering rule, recorded as edge counters so a stall
    // shorter than one Dart poll interval is still reported.
    if (_item.playbackLikelyToKeepUp) {
      _state.buffering_end_count += 1;
    } else {
      _state.buffering_start_count += 1;
    }
  } else if ([keyPath isEqualToString:@"timeControlStatus"]) {
    _state.is_playing =
        (_player.timeControlStatus == AVPlayerTimeControlStatusPlaying) ? 1 : 0;
  }
  os_unfair_lock_unlock(&_lock);
}

- (void)itemDidPlayToEnd:(NSNotification *)note {
  if (_looping) {
    // The notification arrives on the posting thread; the seek + resume are
    // player mutations, so hop to main.
    __weak VPWPlayer *weakSelf = self;
    VPWOnMain(^{
      VPWPlayer *strongSelf = weakSelf;
      if (strongSelf == nil) {
        return;
      }
      [strongSelf.player seekToTime:kCMTimeZero
                    toleranceBefore:kCMTimeZero
                     toleranceAfter:kCMTimeZero
                  completionHandler:^(BOOL finished) {
                    VPWPlayer *inner = weakSelf;
                    if (inner != nil) {
                      [inner play];
                    }
                  }];
    });
    return;
  }
  os_unfair_lock_lock(&_lock);
  _state.completed_count += 1;
  os_unfair_lock_unlock(&_lock);
}

- (void)readState:(VideoPlayerWatchosState *)out {
  os_unfair_lock_lock(&_lock);
  *out = _state;
  os_unfair_lock_unlock(&_lock);
}

- (int64_t)positionMs {
  os_unfair_lock_lock(&_lock);
  int64_t pending = _pendingSeekMs;
  os_unfair_lock_unlock(&_lock);
  if (pending >= 0) {
    return pending;
  }
  CMTime time = _player.currentTime;
  return CMTIME_IS_NUMERIC(time) ? (int64_t)(CMTimeGetSeconds(time) * 1000.0) : 0;
}

- (void)play {
  VPWOnMain(^{
    // setRate: both starts playback and applies the requested speed.
    [self.player setRate:(float)self->_rate];
  });
}

- (void)pause {
  VPWOnMain(^{
    [self.player pause];
  });
}

- (void)seekToMs:(int64_t)ms {
  // The pending marker is set synchronously so a position read immediately
  // after seeking already reports the target; only the AVPlayer mutation
  // hops to main.
  os_unfair_lock_lock(&_lock);
  _pendingSeekMs = ms;
  os_unfair_lock_unlock(&_lock);
  __weak VPWPlayer *weakSelf = self;
  VPWOnMain(^{
    VPWPlayer *strongSelf = weakSelf;
    if (strongSelf == nil) {
      return;
    }
    [strongSelf.player seekToTime:CMTimeMakeWithSeconds((double)ms / 1000.0, NSEC_PER_SEC)
                  toleranceBefore:kCMTimeZero
                   toleranceAfter:kCMTimeZero
                completionHandler:^(BOOL finished) {
                  VPWPlayer *inner = weakSelf;
                  if (inner != nil) {
                    [inner clearPendingSeek:ms];
                  }
                }];
  });
}

- (void)clearPendingSeek:(int64_t)ms {
  os_unfair_lock_lock(&_lock);
  if (_pendingSeekMs == ms) {
    _pendingSeekMs = -1;
  }
  os_unfair_lock_unlock(&_lock);
}

- (void)setSpeed:(double)speed {
  _rate = speed;
  VPWOnMain(^{
    // Match upstream: apply immediately when playing, remember otherwise.
    if (self.player.timeControlStatus != AVPlayerTimeControlStatusPaused) {
      [self.player setRate:(float)speed];
    }
  });
}

- (void)setLooping:(bool)looping {
  _looping = looping;
}

- (void)dealloc {
  [self teardown];
}

@end

#pragma mark - Registry

static os_unfair_lock g_registry_lock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSNumber *, VPWPlayer *> *g_players;
static int64_t g_next_id = 1;

static VPWPlayer *_Nullable VPWGet(int64_t player_id) {
  os_unfair_lock_lock(&g_registry_lock);
  VPWPlayer *player = g_players[@(player_id)];
  os_unfair_lock_unlock(&g_registry_lock);
  return player;
}

#pragma mark - C ABI

VPW_EXPORT
int64_t video_player_watchos_create(const char *uri, int32_t source_type) {
  if (uri == NULL) {
    return -1;
  }
  NSString *location = [NSString stringWithUTF8String:uri];
  NSURL *url = nil;
  switch (source_type) {
    case 0:  // network
      url = [NSURL URLWithString:location];
      break;
    case 1:  // file
      url = [NSURL fileURLWithPath:location];
      break;
    case 2: {  // Flutter asset key, relative to the bundled flutter_assets/
      NSString *assets = [[NSBundle mainBundle] pathForResource:@"flutter_assets" ofType:nil];
      if (assets != nil) {
        url = [NSURL fileURLWithPath:[assets stringByAppendingPathComponent:location]];
      }
      break;
    }
    default:
      break;
  }
  if (url == nil) {
    return -1;
  }
  // Allocate the id synchronously; construct on the main thread (AVKit's
  // view will drive this player from main, and the serial main queue also
  // orders creation before any later control/dispose call, which all hop
  // to main too). Reads before construction completes simply report
  // "no state yet".
  os_unfair_lock_lock(&g_registry_lock);
  if (g_players == nil) {
    g_players = [NSMutableDictionary dictionary];
  }
  int64_t player_id = g_next_id++;
  os_unfair_lock_unlock(&g_registry_lock);
  VPWOnMain(^{
    VPWPlayer *player = [[VPWPlayer alloc] initWithURL:url];
    os_unfair_lock_lock(&g_registry_lock);
    g_players[@(player_id)] = player;
    os_unfair_lock_unlock(&g_registry_lock);
  });
  return player_id;
}

// Control calls hop to main with the lookup INSIDE the block: the serial
// main queue guarantees they run after the (also main-queued) construction,
// so a control call racing creation (e.g. setLooping before initialize
// completes) is never lost.

VPW_EXPORT
void video_player_watchos_dispose(int64_t player_id) {
  VPWOnMain(^{
    os_unfair_lock_lock(&g_registry_lock);
    VPWPlayer *player = g_players[@(player_id)];
    [g_players removeObjectForKey:@(player_id)];
    os_unfair_lock_unlock(&g_registry_lock);
    [player teardown];
  });
}

VPW_EXPORT
void video_player_watchos_play(int64_t player_id) {
  VPWOnMain(^{
    [VPWGet(player_id) play];
  });
}

VPW_EXPORT
void video_player_watchos_pause(int64_t player_id) {
  VPWOnMain(^{
    [VPWGet(player_id) pause];
  });
}

VPW_EXPORT
void video_player_watchos_set_volume(int64_t player_id, double volume) {
  VPWOnMain(^{
    VPWGet(player_id).player.volume = (float)MAX(0.0, MIN(1.0, volume));
  });
}

VPW_EXPORT
void video_player_watchos_set_looping(int64_t player_id, bool looping) {
  VPWOnMain(^{
    [VPWGet(player_id) setLooping:looping];
  });
}

VPW_EXPORT
void video_player_watchos_set_speed(int64_t player_id, double speed) {
  VPWOnMain(^{
    [VPWGet(player_id) setSpeed:speed];
  });
}

VPW_EXPORT
void video_player_watchos_seek(int64_t player_id, int64_t position_ms) {
  // Synchronous when the player already exists so the pending-seek marker
  // is visible to an immediate position read (seeks only happen after
  // initialize, so the player is always constructed by now).
  [VPWGet(player_id) seekToMs:position_ms];
}

VPW_EXPORT
int64_t video_player_watchos_position(int64_t player_id) {
  return [VPWGet(player_id) positionMs];
}

VPW_EXPORT
bool video_player_watchos_read_state(int64_t player_id, VideoPlayerWatchosState *out) {
  VPWPlayer *player = VPWGet(player_id);
  if (player == nil || out == NULL) {
    return false;
  }
  [player readState:out];
  return true;
}

VPW_EXPORT
const char *video_player_watchos_error(int64_t player_id) {
  VPWPlayer *player = VPWGet(player_id);
  return player != nil ? player.errorDescription.UTF8String : "";
}

VPW_EXPORT
void video_player_watchos_set_mix_with_others(bool mix) {
  AVAudioSession *session = [AVAudioSession sharedInstance];
  [session setCategory:AVAudioSessionCategoryPlayback
           withOptions:(mix ? AVAudioSessionCategoryOptionMixWithOthers : 0)
                 error:nil];
}

VPW_EXPORT
void *video_player_watchos_copy_player(int64_t player_id) {
  VPWPlayer *player = VPWGet(player_id);
  if (player == nil) {
    return NULL;
  }
  return (void *)CFBridgingRetain(player.player);
}
