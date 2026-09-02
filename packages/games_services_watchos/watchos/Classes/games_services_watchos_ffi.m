// Copyright 2026. Game Center over a C ABI, shared by the watch and phone.
#import "games_services_watchos_ffi.h"

#import <Foundation/Foundation.h>
#import <GameKit/GameKit.h>
#include <stdlib.h>
#include <string.h>

enum { kIdle = 0, kPending = 1, kOk = 2, kFailed = 3 };

// GameKit answers on its own queues while Dart reads these from the frame it
// is already running, so one lock guards every mutable field.
static NSLock *gLock = nil;
static int32_t gAuthState = kIdle;
static int32_t gSubmitState = kIdle;
static int32_t gEntriesState = kIdle;
static NSString *gAlias = nil;
static NSString *gEntriesJson = nil;
static NSString *gLastError = nil;
static BOOL gHandlerInstalled = NO;

static void EnsureLock(void) {
  static dispatch_once_t once;
  dispatch_once(&once, ^{ gLock = [[NSLock alloc] init]; });
}

static char *CopyString(NSString *s) {
  if (s == nil) { return NULL; }
  const char *utf8 = s.UTF8String;
  return utf8 ? strdup(utf8) : NULL;
}

// Records the outcome of the authentication handler. Called on GameKit's queue.
static void FinishAuth(NSError *error) {
  GKLocalPlayer *player = [GKLocalPlayer localPlayer];
  [gLock lock];
  if (player.isAuthenticated) {
    gAuthState = kOk;
    gAlias = [player.alias copy];
    gLastError = nil;
  } else {
    gAuthState = kFailed;
    // Not signed in is the ordinary case, not a bug: the game degrades to a
    // local-only best score, so this is recorded and never surfaced as an error.
    gLastError = error ? [error.localizedDescription copy] : @"Not signed in to Game Center";
  }
  [gLock unlock];
}

int32_t games_services_watchos_auth_state(void) {
  EnsureLock();
  // Live, not cached. The handler fires once and its result was being trusted
  // forever after, so a session that authenticated at launch and lost it later
  // still reported kOk -- and the leaderboard read then failed inside GameKit
  // with "local player has not been authenticated" while the app believed it
  // was signed in. GKLocalPlayer is the authority; ask it every time.
  [gLock lock];
  int32_t stored = gAuthState;
  [gLock unlock];
  if (stored == kPending) {
    return kPending;  // the handler has not answered yet; do not pre-empt it
  }
  BOOL live = [GKLocalPlayer localPlayer].isAuthenticated;
  if (live) {
    return kOk;
  }
  return (stored == kIdle) ? kIdle : kFailed;
}

int32_t games_services_watchos_submit_state(void) {
  EnsureLock();
  [gLock lock]; int32_t s = gSubmitState; [gLock unlock];
  return s;
}

int32_t games_services_watchos_entries_state(void) {
  EnsureLock();
  [gLock lock]; int32_t s = gEntriesState; [gLock unlock];
  return s;
}

void games_services_watchos_authenticate(void) {
  EnsureLock();
  @autoreleasepool {
    [gLock lock];
    if (gHandlerInstalled) { [gLock unlock]; return; }
    gHandlerInstalled = YES;
    gAuthState = kPending;
    [gLock unlock];

    GKLocalPlayer *player = [GKLocalPlayer localPlayer];
    // watchOS hands back only an error. There is no view controller, because
    // GKGameCenterViewController does not exist here -- the system presents
    // whatever sign-in UI it wants on its own.
    player.authenticateHandler = ^(NSError *error) { FinishAuth(error); };
  }
}

char *games_services_watchos_player_alias(void) {
  EnsureLock();
  [gLock lock]; NSString *alias = [gAlias copy]; [gLock unlock];
  return CopyString(alias);
}

void games_services_watchos_submit(int64_t score, const char *leaderboard_id) {
  EnsureLock();
  @autoreleasepool {
    if (leaderboard_id == NULL) { return; }
    NSString *lid = [NSString stringWithUTF8String:leaderboard_id];
    if (lid == nil) { return; }
    GKLocalPlayer *player = [GKLocalPlayer localPlayer];
    if (!player.isAuthenticated) {
      [gLock lock]; gSubmitState = kFailed; gLastError = @"Not authenticated"; [gLock unlock];
      return;
    }
    [gLock lock]; gSubmitState = kPending; [gLock unlock];
    [GKLeaderboard submitScore:(NSInteger)score
                       context:0
                        player:player
                leaderboardIDs:@[ lid ]
             completionHandler:^(NSError *error) {
               [gLock lock];
               gSubmitState = error ? kFailed : kOk;
               if (error) { gLastError = [error.localizedDescription copy]; }
               [gLock unlock];
             }];
  }
}

void games_services_watchos_load_entries(const char *leaderboard_id, int32_t count) {
  EnsureLock();
  @autoreleasepool {
    if (leaderboard_id == NULL) { return; }
    NSString *lid = [NSString stringWithUTF8String:leaderboard_id];
    if (lid == nil) { return; }
    if (count < 1) { count = 1; }
    if (count > 100) { count = 100; }  // GKLeaderboard's documented ceiling.

    if (![GKLocalPlayer localPlayer].isAuthenticated) {
      [gLock lock];
      gEntriesState = kFailed;
      gLastError = @"Not authenticated";
      [gLock unlock];
      return;
    }

    [gLock lock]; gEntriesState = kPending; gEntriesJson = nil; [gLock unlock];

    [GKLeaderboard loadLeaderboardsWithIDs:@[ lid ]
                         completionHandler:^(NSArray<GKLeaderboard *> *boards, NSError *error) {
      GKLeaderboard *board = boards.firstObject;
      if (error != nil || board == nil) {
        [gLock lock];
        gEntriesState = kFailed;
        gLastError = error ? [error.localizedDescription copy] : @"Leaderboard not found";
        [gLock unlock];
        return;
      }
      [board loadEntriesForPlayerScope:GKLeaderboardPlayerScopeGlobal
                             timeScope:GKLeaderboardTimeScopeAllTime
                                 range:NSMakeRange(1, (NSUInteger)count)
                     completionHandler:^(GKLeaderboardEntry *localEntry,
                                         NSArray<GKLeaderboardEntry *> *entries,
                                         NSInteger totalPlayerCount,
                                         NSError *entryError) {
        if (entryError != nil) {
          [gLock lock];
          gEntriesState = kFailed;
          gLastError = [entryError.localizedDescription copy];
          [gLock unlock];
          return;
        }
        // GKPlayer's stable IDs -- gamePlayerID, teamPlayerID, guestIdentifier
        // -- are every one of them unavailable on watchOS, so there is nothing
        // to compare players by. GameKit hands the local player's row back
        // separately, and rank is unique within a listing, so that is the
        // identity used here. Works the same on both platforms.
        NSInteger localRank = (localEntry != nil) ? localEntry.rank : NSIntegerMin;
        NSMutableArray *rows = [NSMutableArray array];
        for (GKLeaderboardEntry *e in entries) {
          BOOL isLocal = (e.rank == localRank);
          [rows addObject:@{
            @"rank"  : @(e.rank),
            @"score" : @(e.score),
            @"player": e.player.displayName ?: @"",
            @"local" : @(isLocal),
          }];
        }
        NSError *jsonError = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:rows options:0 error:&jsonError];
        [gLock lock];
        if (data != nil) {
          gEntriesJson = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
          gEntriesState = kOk;
        } else {
          gEntriesState = kFailed;
          gLastError = [jsonError.localizedDescription copy];
        }
        [gLock unlock];
      }];
    }];
  }
}

char *games_services_watchos_entries_json(void) {
  EnsureLock();
  [gLock lock]; NSString *json = [gEntriesJson copy]; [gLock unlock];
  return CopyString(json);
}

char *games_services_watchos_last_error(void) {
  EnsureLock();
  [gLock lock]; NSString *err = [gLastError copy]; [gLock unlock];
  return CopyString(err);
}

void games_services_watchos_free(char *ptr) {
  if (ptr != NULL) { free(ptr); }
}
