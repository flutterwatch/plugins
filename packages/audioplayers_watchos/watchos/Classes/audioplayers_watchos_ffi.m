// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "audioplayers_watchos_ffi.h"

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

#include <os/lock.h>

#define APW_EXPORT __attribute__((visibility("default"))) __attribute__((used))

/// Runs `block` on the main thread (inline when already there).
///
/// Every AVPlayer MUTATION goes through this: the FFI entry points are called
/// on the Flutter UI thread, and AVPlayer mutations open CATransactions on
/// the calling thread — whose run-loop flush can then perform UIKit work off
/// the main thread and abort. Reads (state snapshot, currentTime) stay
/// lock-guarded and thread-safe. dispatch_async (never sync) also makes the
/// main queue the serial order for create → control → dispose.
static void APWOnMain(dispatch_block_t block) {
  if (NSThread.isMainThread) {
    block();
  } else {
    dispatch_async(dispatch_get_main_queue(), block);
  }
}

#pragma mark - Player wrapper

/// Wraps one AVPlayer with the KVO/notification observers that keep a
/// lock-guarded AudioplayersWatchosState snapshot current for polling.
@interface APWPlayer : NSObject
@property(nonatomic, strong) AVPlayer *player;
@property(nonatomic, strong) AVPlayerItem *item;
@property(nonatomic, copy) NSString *errorDescription;
- (void)setSourceURL:(NSURL *)url mimeType:(NSString *)mimeType;
- (void)readState:(AudioplayersWatchosState *)out;
- (void)resume;
- (void)pause;
- (void)stopSync;
- (void)markUnloadedSync;
- (void)unloadOnMain;
- (void)beginSeekToMs:(int64_t)ms;
- (void)setVolume:(double)volume;
- (void)setRate:(double)rate;
- (void)setReleaseMode:(int32_t)mode;
- (void)teardown;
@end

@implementation APWPlayer {
  os_unfair_lock _lock;
  AudioplayersWatchosState _state;
  int32_t _releaseMode;     // 0 release, 1 loop, 2 stop
  double _rate;             // requested playback rate
  double _volume;
  int64_t _pendingSeekMs;   // -1 when no seek is in flight
  BOOL _itemActive;         // gates KVO writes: an unload (which happens
                            // synchronously on the FFI thread) must win over
                            // stragglers from AVFoundation's queues
}

- (instancetype)init {
  self = [super init];
  if (self == nil) {
    return nil;
  }
  _lock = OS_UNFAIR_LOCK_INIT;
  _rate = 1.0;
  _volume = 1.0;
  _pendingSeekMs = -1;
  _errorDescription = @"";
  _state.duration_ms = -1;
  _player = [[AVPlayer alloc] init];
  _player.actionAtItemEnd = AVPlayerActionAtItemEndPause;
  [_player addObserver:self
            forKeyPath:@"timeControlStatus"
               options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
               context:NULL];
  return self;
}

- (void)detachItemLocked {
  if (_item != nil) {
    @try {
      [_item removeObserver:self forKeyPath:@"status"];
    } @catch (NSException *e) {
      // Observer already removed — nothing to do.
    }
    [[NSNotificationCenter defaultCenter]
        removeObserver:self
                  name:AVPlayerItemDidPlayToEndTimeNotification
                object:_item];
    _item = nil;
  }
}

/// Main thread. Loads a new item, resetting the prepared/duration state.
/// `mimeType` (may be nil) overrides container sniffing for extension-less
/// sources — same AVURLAsset option upstream darwin uses.
- (void)setSourceURL:(NSURL *)url mimeType:(NSString *)mimeType {
  os_unfair_lock_lock(&_lock);
  [self detachItemLocked];
  _state.status = 0;
  _state.duration_ms = -1;
  _pendingSeekMs = -1;
  self.errorDescription = @"";
  os_unfair_lock_unlock(&_lock);

  AVPlayerItem *item;
  if (mimeType.length > 0) {
    NSDictionary<NSString *, id> *options;
    if (@available(watchOS 10.0, *)) {
      options = @{AVURLAssetOverrideMIMETypeKey : mimeType};
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
      options = @{@"AVURLAssetOutOfBandMIMETypeKey" : mimeType};
#pragma clang diagnostic pop
    }
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:options];
    item = [AVPlayerItem playerItemWithAsset:asset];
  } else {
    item = [AVPlayerItem playerItemWithURL:url];
  }
  os_unfair_lock_lock(&_lock);
  _item = item;
  _itemActive = YES;
  _state.has_item = 1;
  os_unfair_lock_unlock(&_lock);
  [item addObserver:self
         forKeyPath:@"status"
            options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
            context:NULL];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(itemDidPlayToEnd:)
                                               name:AVPlayerItemDidPlayToEndTimeNotification
                                             object:item];
  [_player replaceCurrentItemWithPlayerItem:item];
  _player.volume = (float)_volume;
}

- (void)teardown {
  os_unfair_lock_lock(&_lock);
  [self detachItemLocked];
  os_unfair_lock_unlock(&_lock);
  @try {
    [_player removeObserver:self forKeyPath:@"timeControlStatus"];
  } @catch (NSException *e) {
    // Observer already removed — nothing to do.
  }
  [_player pause];
  [_player replaceCurrentItemWithPlayerItem:nil];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
  os_unfair_lock_lock(&_lock);
  if ([keyPath isEqualToString:@"status"]) {
    AVPlayerItem *item = (AVPlayerItem *)object;
    if (!_itemActive || item != _item) {
      // Stale callback from an item that was unloaded or replaced — the
      // synchronous unload already published the cleared state.
      os_unfair_lock_unlock(&_lock);
      return;
    }
    if (item.status == AVPlayerItemStatusFailed) {
      _state.status = 2;
      self.errorDescription =
          item.error.localizedDescription ?: @"failed to load source";
    } else if (item.status == AVPlayerItemStatusReadyToPlay &&
               _state.status == 0) {
      _state.status = 1;
      _state.prepared_count += 1;
      CMTime duration = item.duration;
      _state.duration_ms = CMTIME_IS_NUMERIC(duration)
          ? (int64_t)(CMTimeGetSeconds(duration) * 1000.0)
          : -1;
    }
  } else if ([keyPath isEqualToString:@"timeControlStatus"]) {
    _state.is_playing =
        (_player.timeControlStatus == AVPlayerTimeControlStatusPlaying) ? 1 : 0;
  }
  os_unfair_lock_unlock(&_lock);
}

- (void)itemDidPlayToEnd:(NSNotification *)note {
  os_unfair_lock_lock(&_lock);
  int32_t mode = _releaseMode;
  if (mode != 1) {
    _state.complete_count += 1;
  }
  os_unfair_lock_unlock(&_lock);
  if (mode == 1) {  // loop: replay without emitting complete
    __weak APWPlayer *weakSelf = self;
    [_player seekToTime:kCMTimeZero
        toleranceBefore:kCMTimeZero
         toleranceAfter:kCMTimeZero
      completionHandler:^(__unused BOOL finished) {
        APWPlayer *strongSelf = weakSelf;
        if (strongSelf != nil) {
          [strongSelf resume];
        }
      }];
    return;
  }
  if (mode == 0) {  // release: unload — duration/position read null upstream
    [self markUnloadedSync];
    [self unloadOnMain];  // already on the main thread here
  } else {  // stop: rewind, keeping the source loaded
    [self rewindReportingZero];
  }
}

- (void)readState:(AudioplayersWatchosState *)out {
  os_unfair_lock_lock(&_lock);
  *out = _state;
  int64_t pending = _pendingSeekMs;
  os_unfair_lock_unlock(&_lock);
  if (pending >= 0) {
    out->position_ms = pending;
  } else {
    CMTime time = _player.currentTime;
    out->position_ms =
        CMTIME_IS_NUMERIC(time) ? (int64_t)(CMTimeGetSeconds(time) * 1000.0) : 0;
  }
}

- (void)resume {
  // setRate: both starts playback and applies the requested rate.
  [_player setRate:(float)_rate];
}

- (void)pause {
  [_player pause];
}

/// Called on the FFI thread. State must be observable as soon as this
/// returns (upstream awaits stop); AVPlayer mutations still go to main.
- (void)stopSync {
  os_unfair_lock_lock(&_lock);
  int32_t mode = _releaseMode;
  os_unfair_lock_unlock(&_lock);
  if (mode == 0) {  // release mode: upstream stop releases
    [self markUnloadedSync];
    APWOnMain(^{
      [self unloadOnMain];
    });
    return;
  }
  os_unfair_lock_lock(&_lock);
  _pendingSeekMs = 0;  // position reads 0 immediately
  os_unfair_lock_unlock(&_lock);
  APWOnMain(^{
    [self->_player pause];
    [self rewindReportingZero];
  });
}

/// Called on the FFI thread: publishes the unloaded state synchronously so
/// getDuration/getCurrentPosition read null the moment release returns.
- (void)markUnloadedSync {
  os_unfair_lock_lock(&_lock);
  _itemActive = NO;
  _state.status = 0;
  _state.has_item = 0;
  _state.duration_ms = -1;
  _pendingSeekMs = -1;
  os_unfair_lock_unlock(&_lock);
}

/// Main thread: detaches the item and unloads the AVPlayer.
- (void)unloadOnMain {
  [_player pause];
  os_unfair_lock_lock(&_lock);
  [self detachItemLocked];
  os_unfair_lock_unlock(&_lock);
  [_player replaceCurrentItemWithPlayerItem:nil];
}

/// Rewinds to zero, reporting position 0 immediately (upstream awaits the
/// rewind before returning from stop, so position reads must not expose the
/// in-flight seek). Does NOT count as a seek — no seekComplete event.
- (void)rewindReportingZero {
  os_unfair_lock_lock(&_lock);
  _pendingSeekMs = 0;
  os_unfair_lock_unlock(&_lock);
  __weak APWPlayer *weakSelf = self;
  [_player seekToTime:kCMTimeZero
      toleranceBefore:kCMTimeZero
       toleranceAfter:kCMTimeZero
    completionHandler:^(__unused BOOL finished) {
      APWPlayer *strongSelf = weakSelf;
      if (strongSelf != nil) {
        [strongSelf finishSilentRewind];
      }
    }];
}

- (void)finishSilentRewind {
  os_unfair_lock_lock(&_lock);
  if (_pendingSeekMs == 0) {
    _pendingSeekMs = -1;
  }
  os_unfair_lock_unlock(&_lock);
}

/// Called on the FFI thread; the AVPlayer seek itself runs on main.
- (void)beginSeekToMs:(int64_t)ms {
  os_unfair_lock_lock(&_lock);
  _pendingSeekMs = ms;  // position reports the target while in flight
  os_unfair_lock_unlock(&_lock);
  APWOnMain(^{
    [self seekOnMainToMs:ms];
  });
}

- (void)seekOnMainToMs:(int64_t)ms {
  __weak APWPlayer *weakSelf = self;
  [_player seekToTime:CMTimeMakeWithSeconds((double)ms / 1000.0, NSEC_PER_SEC)
      toleranceBefore:kCMTimeZero
       toleranceAfter:kCMTimeZero
    completionHandler:^(__unused BOOL finished) {
      APWPlayer *strongSelf = weakSelf;
      if (strongSelf != nil) {
        [strongSelf finishSeek:ms];
      }
    }];
}

- (void)finishSeek:(int64_t)ms {
  os_unfair_lock_lock(&_lock);
  if (_pendingSeekMs == ms) {
    _pendingSeekMs = -1;
  }
  _state.seek_complete_count += 1;
  os_unfair_lock_unlock(&_lock);
}

- (void)setVolume:(double)volume {
  _volume = MAX(0.0, MIN(1.0, volume));
  _player.volume = (float)_volume;
}

- (void)setRate:(double)rate {
  _rate = rate;
  // Match upstream: apply immediately when playing, remember otherwise.
  if (_player.timeControlStatus != AVPlayerTimeControlStatusPaused) {
    [_player setRate:(float)rate];
  }
}

- (void)setReleaseMode:(int32_t)mode {
  os_unfair_lock_lock(&_lock);
  _releaseMode = mode;
  os_unfair_lock_unlock(&_lock);
}

- (void)dealloc {
  [self teardown];
}

@end

#pragma mark - Registry

static os_unfair_lock g_registry_lock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSString *, APWPlayer *> *g_players;

static NSString *_Nullable APWKey(const char *player_id) {
  return player_id != NULL ? [NSString stringWithUTF8String:player_id] : nil;
}

static APWPlayer *_Nullable APWGet(const char *player_id) {
  NSString *key = APWKey(player_id);
  if (key == nil) {
    return nil;
  }
  os_unfair_lock_lock(&g_registry_lock);
  APWPlayer *player = g_players[key];
  os_unfair_lock_unlock(&g_registry_lock);
  return player;
}

#pragma mark - C ABI

APW_EXPORT
void audioplayers_watchos_create(const char *player_id) {
  NSString *key = APWKey(player_id);
  if (key == nil) {
    return;
  }
  // Registry membership is synchronous: the very next FFI call (setSource,
  // readState) must observe the new player, and Dart's poller must never
  // baseline against a previous player that shared this id. Only playback
  // mutations go to the main queue.
  os_unfair_lock_lock(&g_registry_lock);
  if (g_players == nil) {
    g_players = [NSMutableDictionary dictionary];
  }
  if (g_players[key] == nil) {
    g_players[key] = [[APWPlayer alloc] init];
  }
  os_unfair_lock_unlock(&g_registry_lock);
}

APW_EXPORT
void audioplayers_watchos_dispose(const char *player_id) {
  NSString *key = APWKey(player_id);
  if (key == nil) {
    return;
  }
  // Remove synchronously (readState must return false immediately); tear
  // the AVPlayer down on the main queue like every other mutation.
  os_unfair_lock_lock(&g_registry_lock);
  APWPlayer *player = g_players[key];
  [g_players removeObjectForKey:key];
  os_unfair_lock_unlock(&g_registry_lock);
  if (player != nil) {
    APWOnMain(^{
      [player teardown];
    });
  }
}

APW_EXPORT
int audioplayers_watchos_set_source_url(const char *player_id, const char *url,
                                        bool is_local,
                                        const char *mime_type) {
  if (url == NULL) {
    return -1;
  }
  NSString *location = [NSString stringWithUTF8String:url];
  NSURL *nsurl;
  if (is_local) {
    // Local sources may arrive as plain paths or file:// URIs.
    nsurl = [location hasPrefix:@"file://"]
        ? [NSURL URLWithString:location]
        : [NSURL fileURLWithPath:location];
  } else {
    nsurl = [NSURL URLWithString:location];
  }
  if (nsurl == nil) {
    return -1;
  }
  APWPlayer *player = APWGet(player_id);
  if (player == nil) {
    return -2;
  }
  NSString *mime = (mime_type != NULL && mime_type[0] != '\0')
      ? [NSString stringWithUTF8String:mime_type]
      : nil;
  APWOnMain(^{
    [player setSourceURL:nsurl mimeType:mime];
  });
  return 0;
}

APW_EXPORT
int audioplayers_watchos_set_source_bytes(const char *player_id,
                                          const uint8_t *bytes, int64_t length,
                                          const char *extension_hint) {
  if (bytes == NULL || length <= 0) {
    return -1;
  }
  APWPlayer *player = APWGet(player_id);
  if (player == nil) {
    return -2;
  }
  // AVPlayer needs a URL: spool the bytes to a temp file. The extension lets
  // AVFoundation sniff the container.
  NSString *ext = (extension_hint != NULL && extension_hint[0] != '\0')
      ? [NSString stringWithUTF8String:extension_hint]
      : @"tmp";
  NSString *name = [NSString
      stringWithFormat:@"audioplayers_%@.%@", NSUUID.UUID.UUIDString, ext];
  NSURL *fileURL = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
      URLByAppendingPathComponent:name];
  NSData *data = [NSData dataWithBytes:bytes length:(NSUInteger)length];
  if (![data writeToURL:fileURL atomically:YES]) {
    return -1;
  }
  APWOnMain(^{
    [player setSourceURL:fileURL mimeType:nil];
  });
  return 0;
}

APW_EXPORT
bool audioplayers_watchos_resume(const char *player_id) {
  APWPlayer *player = APWGet(player_id);
  if (player == nil) {
    return false;
  }
  APWOnMain(^{
    [player resume];
  });
  return true;
}

APW_EXPORT
bool audioplayers_watchos_pause(const char *player_id) {
  APWPlayer *player = APWGet(player_id);
  if (player == nil) {
    return false;
  }
  APWOnMain(^{
    [player pause];
  });
  return true;
}

APW_EXPORT
bool audioplayers_watchos_stop(const char *player_id) {
  APWPlayer *player = APWGet(player_id);
  if (player == nil) {
    return false;
  }
  [player stopSync];
  return true;
}

APW_EXPORT
bool audioplayers_watchos_release(const char *player_id) {
  APWPlayer *player = APWGet(player_id);
  if (player == nil) {
    return false;
  }
  [player markUnloadedSync];
  APWOnMain(^{
    [player unloadOnMain];
  });
  return true;
}

APW_EXPORT
bool audioplayers_watchos_seek(const char *player_id, int64_t position_ms) {
  APWPlayer *player = APWGet(player_id);
  if (player == nil) {
    return false;
  }
  [player beginSeekToMs:position_ms];
  return true;
}

APW_EXPORT
bool audioplayers_watchos_set_volume(const char *player_id, double volume) {
  APWPlayer *player = APWGet(player_id);
  if (player == nil) {
    return false;
  }
  APWOnMain(^{
    [player setVolume:volume];
  });
  return true;
}

APW_EXPORT
bool audioplayers_watchos_set_rate(const char *player_id, double rate) {
  APWPlayer *player = APWGet(player_id);
  if (player == nil) {
    return false;
  }
  APWOnMain(^{
    [player setRate:rate];
  });
  return true;
}

APW_EXPORT
bool audioplayers_watchos_set_release_mode(const char *player_id,
                                           int32_t mode) {
  APWPlayer *player = APWGet(player_id);
  if (player == nil) {
    return false;
  }
  [player setReleaseMode:mode];
  return true;
}

APW_EXPORT
bool audioplayers_watchos_read_state(const char *player_id,
                                     AudioplayersWatchosState *out) {
  APWPlayer *player = APWGet(player_id);
  if (player == nil || out == NULL) {
    return false;
  }
  [player readState:out];
  return true;
}

APW_EXPORT
const char *audioplayers_watchos_error(const char *player_id) {
  APWPlayer *player = APWGet(player_id);
  return player != nil ? player.errorDescription.UTF8String : "";
}

APW_EXPORT
int audioplayers_watchos_set_audio_context(const char *category,
                                           bool mix_with_others,
                                           bool duck_others) {
  // watchOS has a narrower category set than iOS; map the ones that exist
  // and ignore the rest (matching how upstream treats unsupported values).
  AVAudioSessionCategory avCategory = AVAudioSessionCategoryPlayback;
  if (category != NULL) {
    NSString *name = [NSString stringWithUTF8String:category];
    if ([name isEqualToString:@"playAndRecord"]) {
      avCategory = AVAudioSessionCategoryPlayAndRecord;
    } else if ([name isEqualToString:@"record"]) {
      avCategory = AVAudioSessionCategoryRecord;
    } else if ([name isEqualToString:@"soloAmbient"]) {
      avCategory = AVAudioSessionCategorySoloAmbient;
    } else if ([name isEqualToString:@"ambient"]) {
      avCategory = AVAudioSessionCategoryAmbient;
    }
  }
  AVAudioSessionCategoryOptions options = 0;
  if (mix_with_others) {
    options |= AVAudioSessionCategoryOptionMixWithOthers;
  }
  if (duck_others) {
    options |= AVAudioSessionCategoryOptionDuckOthers;
  }
  NSError *error = nil;
  BOOL ok = [[AVAudioSession sharedInstance] setCategory:avCategory
                                             withOptions:options
                                                   error:&error];
  return ok ? 0 : (int)(error.code ?: -1);
}
