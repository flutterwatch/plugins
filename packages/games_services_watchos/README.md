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
  games_services: ^4.1.1
  games_services_watchos: ^0.1.0
```

Then use `games_services` as normal:

```dart
await GameAuth.signIn();
await GamesServices.submitScore(
  score: Score(iOSLeaderboardID: 'your.leaderboard.id', value: 42),
);
final rows = await Leaderboards.loadLeaderboardScores(
  iOSLeaderboardID: 'your.leaderboard.id',
  scope: PlayerScope.global,
  timeScope: TimeScope.allTime,
  maxResults: 10,
);
```

## What is supported

| Interface method | watchOS | Notes |
|---|---|---|
| `signIn` | ✅ | `GKLocalPlayer.authenticateHandler` |
| `submitScore` | ✅ | `GKLeaderboard.submitScore`, watchOS 7+ |
| `loadLeaderboardScores` | ✅ | `loadEntriesForPlayerScope`, watchOS 7+ |
| `getPlayerScore` | ✅ | derived from the local player's own entry |

The other members keep the platform interface's `UnimplementedError`
default rather than returning a plausible-looking empty value; see "Not
supported on watchOS" below.

Because there is no system leaderboard UI on watchOS, a watch app draws
its own from `loadLeaderboardScores`.

## watchOS specifics worth knowing

- **No stable player identifier.** `gamePlayerID`, `teamPlayerID` and
  `guestIdentifier` are all unavailable on watchOS, so the local player's
  own row is identified by matching rank against the `localPlayerEntry`
  GameKit returns alongside the list. `scoreHolder.playerID` is therefore
  always null — the upstream model already allows this, since Android
  omits it for privacy.
- **A different `authenticateHandler`.** On watchOS the block takes only
  an error; the iOS signature with a `UIViewController` does not exist.
- **Failure and emptiness are distinct.** `loadLeaderboardScores` returns
  null when the read failed and an empty list when the leaderboard has no
  entries. Collapsing the two makes a broken leaderboard look like an
  empty one, which is a genuinely hard bug to see.

## Not supported on watchOS

These members of `games_services_platform_interface` 4.1.1 throw or fail on watchOS.
`PORTING_REPORT.md` lists every member under "Interface coverage".

| Member | On watchOS | Why |
|---|---|---|
| `showLeaderboards` / `showAchievements` | fails with `UnimplementedError` | `GKGameCenterViewController` does not exist on watchOS |
| `showAccessPoint` / `hideAccessPoint` | fails with `UnimplementedError` | `GKAccessPoint` does not exist on watchOS |
| `unlock` / `increment` / `loadAchievements` / `resetAchievements` | fails with `UnimplementedError` | achievements are not implemented yet |
| `getPlayerScoreObject` | fails with `UnimplementedError` | not implemented yet; `getPlayerScore` gives the local score |
| `player` | throws `UnimplementedError` when read | not implemented yet |
| `getAuthCode` | throws `UnimplementedError` when called | a Play Games server code; Android only |
| `getPlayerHiResImage` | fails with `UnimplementedError` | not implemented yet |
| `saveGame` / `loadGame` / `deleteGame` / `getSavedGames` | fails with `UnimplementedError` | saved games are not implemented yet |

## Status

Staged, not production-ready. See [PORTING_REPORT.md](PORTING_REPORT.md)
for the verification table — in particular, leaderboard reads have not yet
been observed working on a physical watch.

[upstream]: https://pub.dev/packages/games_services
