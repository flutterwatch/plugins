# games_services_watchos

The watchOS implementation of [`games_services`][upstream].

`games_services` covers iOS, macOS and Android. This package supplies the
wrist, which it does not: watchOS has no method channels, so the upstream
`MethodChannelGamesServices` default cannot work there, and this registers
itself in its place and talks to GameKit through exported C symbols over
`dart:ffi`.

## Usage

`games_services` does not include a watchOS implementation, so add this
package alongside it; the implementation registers itself.

```yaml
dependencies:
  games_services: ^5.3.0
  games_services_watchos: ^0.2.0
```

This release implements `games_services_platform_interface` 5.x, so it works
with `games_services` 5.x. Version 0.1.0 implements the 4.x interface, for an
app that stays on `games_services` 4.x.

Then use `games_services` as normal:

```dart
try {
  await GameAuth.signIn();
  await GamesServices.submitScore(
    score: Score(iOSLeaderboardID: 'your.leaderboard.id', value: 42),
  );
} on PlatformException catch (e) {
  // Not signed in, or GameKit refused the score; e.code says which.
}
final rows = await Leaderboards.loadLeaderboardScores(
  iOSLeaderboardID: 'your.leaderboard.id',
  scope: PlayerScope.global,
  timeScope: TimeScope.allTime,
  maxResults: 10,
);
```

## Sign-in and submission results

`signIn` and `submitScore` answer as `games_services` 5.x does on iOS, so the
same code reads them on the wrist and on the phone.

| Call | Success | Failure |
|---|---|---|
| `GameAuth.signIn` | completes with "Player authenticated successfully", or "Player already authenticated" when the player already was | a `PlatformException`: `failed_to_authenticate` with GameKit's message, or `sign_in_unavailable` when GameKit has already answered this launch's sign-in and the player is not signed in, since the plugin asks once per launch |
| `GamesServices.submitScore` | completes with "Success" | a `PlatformException`: `failed_to_send_score` |

As on iOS, each exception carries its message in `details` too. Three
things differ from iOS:

- A sign-in waits at most 20 seconds for GameKit's answer. After that it
  fails with `failed_to_authenticate`, and says so; GameKit may still sign
  the player in, which the player stream shows at the plugin's next call.
- A sign-in made while another is in flight waits for that one's answer,
  where iOS answers "Player already authenticated" at once.
- `submitScore` never fails with `leaderboard_not_found`. iOS loads the
  leaderboard before it submits and reports that code when it finds none;
  the watch submits without loading it, so GameKit's error for an unknown
  leaderboard arrives as `failed_to_send_score`.

**Changed in 0.2.0.** Version 0.1.0 completed both calls with null on
success and with an error message on failure, the convention of
`games_services` 4.x. Code that reads null as success has to change: a
result now means success, and a failure arrives as the exception.

## What is supported

| Interface method | watchOS | Notes |
|---|---|---|
| `signIn` | ✅ | `GKLocalPlayer.authenticateHandler`; results as above |
| `player` | ◐ | the live sign-in state and GameKit's alias; changes arrive with the plugin's next call (see below) |
| `submitScore` | ◐ | `GKLeaderboard.submitScore`, watchOS 7+; results as above. `Score.token` is ignored: the score goes in with context 0, where iOS sends the token as the context |
| `loadLeaderboardScores` | ◐ | `loadEntriesForPlayerScope`, watchOS 7+, always on the global, all-time board from rank 1: `scope`, `timeScope` and `playerCentered` are ignored, and at most 100 rows come back. A row's `displayScore` is the raw score as text, and its `timestampMillis` is 0 |
| `getPlayerScore` | ◐ | the local player's row in the top 100 of the global, all-time board; null when the player is not there. iOS reads the player's own entry at any rank, and answers 0 when there is none |

◐: implemented, with the limit its note gives. The other members keep the
platform interface's `UnimplementedError` default rather than returning a
plausible-looking empty value; see "Not supported on watchOS" below.

Because there is no system leaderboard UI on watchOS, a watch app draws
its own from `loadLeaderboardScores`.

## watchOS specifics worth knowing

- **No stable player identifier.** `gamePlayerID`, `teamPlayerID` and
  `guestIdentifier` are all unavailable on watchOS, so the local player's
  own row is identified by matching rank against the `localPlayerEntry`
  GameKit returns alongside the list. `scoreHolder.playerID` is therefore
  always null — the upstream model already allows this, since Android
  omits it for privacy.
- **The player stream follows the plugin's calls.** `GameAuth.player` gives
  each new subscriber the live sign-in state at once, so
  `GameAuth.isSignedIn` is always current, and the getters of
  `games_services`' `Player` class work. After that, a subscriber hears of a
  change when one of this plugin's calls finds it: the native side pushes
  nothing, so a sign-in that lapses between calls shows at the next call.
  The `PlayerData` has GameKit's alias as its `displayName`; `playerID`,
  `teamPlayerID`, `iconImage` and the restriction flags are null. Every read
  of `GameAuth.player` is the same stream, so a `StreamBuilder` can read it
  in `build`.
- **A different `authenticateHandler`.** On watchOS the block takes only
  an error; the iOS signature with a `UIViewController` does not exist.
- **Failure and emptiness are distinct.** `loadLeaderboardScores` returns
  null when the read failed and an empty list when the leaderboard has no
  entries. Collapsing the two makes a broken leaderboard look like an
  empty one, which is a genuinely hard bug to see. On iOS a failed read
  throws a `PlatformException` instead, so code that runs on both handles
  both.

## Not supported on watchOS

These members of `games_services_platform_interface` 5.3.0 throw or fail on watchOS.
`PORTING_REPORT.md` lists every member under "Interface coverage".

| Member | On watchOS | Why |
|---|---|---|
| `showLeaderboards` / `showAchievements` | fails with `UnimplementedError` | `GKGameCenterViewController` does not exist on watchOS |
| `showAccessPoint` / `hideAccessPoint` | fails with `UnimplementedError` | `GKAccessPoint` does not exist on watchOS |
| `unlock` / `increment` / `loadAchievements` / `resetAchievements` | fails with `UnimplementedError` | achievements are not implemented yet |
| `setSteps` | fails with `UnimplementedError` | an incremental Play Games achievement; Android only |
| `getPlayerScoreObject` | fails with `UnimplementedError` | not implemented yet; `getPlayerScore` gives the local score |
| `loadPreviousOccurrence` | fails with `UnimplementedError` | not implemented yet |
| `getAuthCode` | throws `UnimplementedError` when called | a Play Games server code; Android only |
| `getPlayerHiResImage` | fails with `UnimplementedError` | not implemented yet |
| `fetchIdentityVerificationSignature` | fails with `UnimplementedError` | not implemented yet |
| `saveGame` / `loadGame` / `deleteGame` / `getSavedGames` | fails with `UnimplementedError` | `GKSavedGame` does not exist on watchOS |
| `showSavedGames` | fails with `UnimplementedError` | the Play Games saved-games screen; Android only |

## Status

Sign-in and score submission have been observed working on a physical Apple
Watch; leaderboard reads have not yet. See [PORTING_REPORT.md](PORTING_REPORT.md)
for the verification table.

[upstream]: https://pub.dev/packages/games_services
