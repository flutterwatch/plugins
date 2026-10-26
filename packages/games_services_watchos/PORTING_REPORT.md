# games_services_watchos — porting report

## Verification status

| Aspect | Status |
|---|---|
| Implementation | ✅ Working (GameKit FFI) — sign-in and submission; reads unconfirmed on device |
| watchOS capability | Partial — sign-in, the player stream and leaderboards; no Game Center UI, achievements, saved games or access point |
| Host unit tests | ✅ pass (FFI bindings faked) |
| Upstream integration test | ○ none exists upstream — `games_services` ships no `test/` or `integration_test/`; ours, `watchos_games_services_test.dart`, covers registration, FFI linkage, the player stream and how each signed-out call fails, ✅ 7 pass on the watchOS 27.0 Simulator (2026-10-24) |
| Example | ✅ `games_services`' own example app, unchanged; it starts on the watchOS 27.0 Simulator with no exception in its first 15 seconds and no overflow |

This package is published on pub.dev. The table is deliberately honest:
sign-in and submission have been observed working on a physical Apple Watch
Series 10, and reading entries has not. 0.2.0 changes only Dart code: its
sign-in and submission results and its player stream are checked by the host
tests and on the Simulator, and have not run on a watch yet.

## Example

`games_services`' own example app, ported unchanged with `flutter-watchos
plugin port --include-example`. The porter copies `lib/` only, so the
example's `assets/logo.png` and the `assets:` entry of its pubspec were
copied from `games_services` 5.3.0 by hand. The example is MIT-licensed
upstream code; `example/LICENSE` carries that licence. There are no watchOS
deviations. It replaces a hand-written demo and its layout widget test
(`AUTHORING.md` §3).

## What was ported

`games_services` is federated over `games_services_platform_interface`, so
this is a normal federated implementation registered through
`dartPluginClass`. Only sign-in, the player stream and the leaderboard
surface are overridden; everything else keeps the interface's
`UnimplementedError`.

| Upstream method | Decision | Reason |
|---|---|---|
| `signIn` | implemented | `GKLocalPlayer.authenticateHandler` |
| `submitScore` | implemented, with a limit | `GKLeaderboard.submitScore`, watchOS 7+; `Score.token` is ignored |
| `loadLeaderboardScores` | implemented, with a limit | `loadEntriesForPlayerScope`, watchOS 7+; the global, all-time board only |
| `getPlayerScore` | implemented, with a limit | from the local player's row in the top 100 |
| `player` | implemented, with a limit | the live sign-in state and alias, from the existing symbols; changes arrive with the plugin's next call |
| `showLeaderboards`, `showAchievements` | unsupported | `GKGameCenterViewController` is not on watchOS |
| `showAccessPoint`, `hideAccessPoint` | unsupported | `GKAccessPoint` is not on watchOS |
| `unlock`, `increment`, `loadAchievements`, `resetAchievements` | unsupported | achievements not implemented |
| `setSteps`, `getAuthCode`, `showSavedGames` | unsupported | Android only |
| `saveGame`, `loadGame`, `deleteGame`, `getSavedGames` | unsupported | `GKSavedGame` is not on watchOS |
| `getPlayerScoreObject`, `loadPreviousOccurrence`, `getPlayerHiResImage`, `fetchIdentityVerificationSignature` | unsupported | not implemented |

## watchOS API differences that shaped the implementation

Each of these was found by compiling or running against the watchOS SDK,
not by reading iOS documentation.

- **`GKLocalPlayer.local` is unavailable**; the deprecated `localPlayer`
  accessor is the one that exists on watchOS.
- **`authenticateHandler` takes only an error.** The iOS signature carries
  a `UIViewController` to present; watchOS has no view controller to hand
  back and the system presents its own sign-in.
- **No stable player identifier at all.** `gamePlayerID`, `teamPlayerID`
  and `guestIdentifier` are each `API_UNAVAILABLE(watchos)`, so players
  cannot be compared by id. The local player's row is matched by rank
  against the `localPlayerEntry` GameKit returns separately.
- **`GKGameCenterViewController` and `GKAccessPoint` do not exist**, so a
  watch app must draw its own leaderboard from the returned entries.

## Design notes

- **Poll, not callback.** GameKit answers on its own queues. Calling into
  Dart from an arbitrary thread needs a `NativeCallable` and a live
  isolate; a state word the caller reads from a frame it already runs is
  simpler and cannot misbehave at shutdown. That suits the one-shot calls.
  The player stream (0.2.0) is long-lived, and it still reads the state
  word: it re-reads after each of the plugin's calls, so a change GameKit
  makes between calls reaches subscribers at the next one. Pushing changes
  as they happen would take a `NativeCallable.listener` (available on this
  engine) that the authentication handler calls, which is new native code;
  `AUTHORING.md` §2b has the pattern.
- **Auth state is read live.** An earlier version cached the result of the
  authentication handler and never re-asked GameKit. A session that
  authenticated at launch and lost it afterwards still reported success,
  and the leaderboard read then failed inside GameKit as unauthenticated
  while the app believed it was signed in. `GKLocalPlayer` is the
  authority and is consulted on every call.
- **Null means failed, empty means empty.** Returning an empty list for a
  timeout made a broken leaderboard indistinguishable from an empty one,
  all the way up to the UI.

## A note on verifying symbols

`AUTHORING.md` suggests confirming the exported symbols with `nm` on the
**simulator** binary. That does not work here: a known-good app whose
plugins demonstrably function shows 123 symbols and none of the plugin's,
because a simulator build does not surface them in the `Runner` binary.
Device builds do. The reliable check is the runtime one the integration
test makes -- `GamesServicesWatchosBindings().available` is true only when
every symbol resolved through `DynamicLibrary.process()`.

## Known issue: reads rejected on device

On a physical Apple Watch Series 10, after a successful sign-in:

- `GKLocalPlayer.localPlayer.isAuthenticated` returns `true`
- `alias` is `"Unknown"` — the player has no resolved identity
- `loadLeaderboardsWithIDs` / `loadEntries` fail with *"local player has
  not been authenticated"*

The same leaderboard, account and code path work on iOS. The app under
test was side-loaded with `devicectl` rather than installed through its
companion app, and Game Center resolves app identity differently in that
case, so **the next thing to try is a TestFlight install** before treating
this as a plugin defect.

Until that is resolved, a host app should confirm a read succeeds before
offering a leaderboard UI on watchOS.

## Interface coverage

Every public member of `games_services_platform_interface` 5.3.0
(`GamesServicesPlatform`), audited by hand against this package's code. The
static `instance` is set by `registerWith()`. ✅ implemented · ◐ implemented
with a limit · ✗ throws or fails on watchOS. The README's "Not supported on
watchOS" table lists the ✗ rows. `test/games_services_watchos_test.dart` has
a case for each member.

| Member | watchOS |
|---|---|
| `signIn` | ✅ `GKLocalPlayer.authenticateHandler`; completes with iOS's messages and fails with a `PlatformException` (`failed_to_authenticate`, `sign_in_unavailable`), as `games_services` 5.x does on iOS |
| `submitScore` | ◐ `GKLeaderboard.submitScore`; completes with "Success" and fails with a `PlatformException` (`failed_to_send_score`), as on iOS, though never with iOS's `leaderboard_not_found`; `Score.token` is ignored (context 0, where iOS sends the token) |
| `loadLeaderboardScores` | ◐ `loadEntriesForPlayerScope` on the global, all-time board from rank 1, at most 100 rows: `scope`, `timeScope` and `playerCentered` are ignored; `displayScore` is the raw score and `timestampMillis` is 0; null when the read failed, an empty list when there are no entries |
| `getPlayerScore` | ◐ from the local player's row in the top 100; null when the player is not there, where iOS reads the player's own entry and answers 0 when there is none |
| `showLeaderboards` / `showAchievements` | ✗ fails with `UnimplementedError`: `GKGameCenterViewController` does not exist on watchOS |
| `showAccessPoint` / `hideAccessPoint` | ✗ fails with `UnimplementedError`: `GKAccessPoint` does not exist on watchOS |
| `unlock` / `increment` / `loadAchievements` / `resetAchievements` | ✗ fails with `UnimplementedError`: achievements are not implemented yet |
| `setSteps` | ✗ fails with `UnimplementedError`: an incremental Play Games achievement, Android only |
| `getPlayerScoreObject` | ✗ fails with `UnimplementedError`: not implemented yet (`getPlayerScore` gives the local score) |
| `loadPreviousOccurrence` | ✗ fails with `UnimplementedError`: not implemented yet (`GKLeaderboard.loadPreviousOccurrence`, watchOS 7+, needs new native code) |
| `player` | ◐ seeded with the live sign-in state for every subscriber, so `GameAuth.isSignedIn` and the `Player` getters of `games_services` work; a later change reaches subscribers when one of the plugin's calls finds it, since the native side pushes nothing; the `PlayerData` has the alias as `displayName` and null elsewhere |
| `getAuthCode` | ✗ throws `UnimplementedError` when called: a Play Games server code, Android only |
| `getPlayerHiResImage` | ✗ fails with `UnimplementedError`: not implemented yet |
| `fetchIdentityVerificationSignature` | ✗ fails with `UnimplementedError`: not implemented yet (`fetchItemsForIdentityVerificationSignature`, watchOS 6.5+, needs new native code) |
| `saveGame` / `loadGame` / `deleteGame` / `getSavedGames` | ✗ fails with `UnimplementedError`: `GKSavedGame` does not exist on watchOS |
| `showSavedGames` | ✗ fails with `UnimplementedError`: the Play Games saved-games screen, Android only |
