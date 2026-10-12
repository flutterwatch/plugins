## 0.2.0

* Implements `games_services_platform_interface` 5.3.0 (`^5.3.0`, was
  `^4.1.1`), so it works with `games_services` 5.x. The README's install
  snippet names `games_services: ^5.3.0`; an app that stays on
  `games_services` 4.x keeps 0.1.0. The example and the dev dependency name
  `games_services: ^5.3.0` too.
* **Breaking:** `signIn` and `submitScore` answer as `games_services` 5.x
  does on iOS, so app code reads them the same on the wrist as on the phone.
  `signIn` completes with "Player authenticated successfully" when it signs
  the player in, and with "Player already authenticated" when the player
  already was; `submitScore` completes with "Success". A failure is a
  `PlatformException`: `failed_to_authenticate`, or `sign_in_unavailable`
  when GameKit has already answered this launch's sign-in and the player is
  not signed in (the plugin asks once per launch), and
  `failed_to_send_score`. Version 0.1.0 completed both with null on success
  and with the error message on failure, so code that reads null as success
  has to change.
* Bindings: `authState` reads the sign-in state in one native call, as a new
  `GcAuthState` (`unavailable`, `idle`, `pending`, `signedIn`, `failed`).
  `available`, `authenticated` and the new `signInFailed` (true for
  `failed`) derive from it. `signIn` takes both of its decisions from one
  read, so an attempt that fails while the call starts cannot turn
  `failed_to_authenticate` into `sign_in_unavailable`. The plugin reads
  `authState`, so a test fake overrides it rather than `authenticated`.
* `player` is implemented, so `GameAuth.isSignedIn`, `GameAuth.player` and
  the getters of `Player` (`getPlayerName`, `getPlayerID`, ...) work on the
  watch. In 0.1.0 `player` threw `UnimplementedError`, so
  `GameAuth.isSignedIn` failed. Each subscriber gets the live sign-in state
  first; after that, a change reaches subscribers when one of the plugin's
  calls finds it, because the native side pushes nothing. The `PlayerData`
  has GameKit's alias as its `displayName`; `playerID`, `teamPlayerID`,
  `iconImage` and the restriction flags are null. Every read returns the
  same stream, as on the other platforms. It reads the existing symbols, so
  the native code is unchanged.
* `loadLeaderboardScores` and `getPlayerScore` take their leaderboard ids as
  `String`, as 5.3.0 declares them; 0.1.0 left them untyped. What they return
  is unchanged. The leaderboard JSON decodes with 5.3.0's
  `LeaderboardScoreData.fromJson`, the same decoder as 4.1.1's.
* The members 5.x adds keep the interface's `UnimplementedError`: `setSteps`
  and `showSavedGames` (Android only), `loadPreviousOccurrence` and
  `fetchIdentityVerificationSignature` (not implemented yet). The README's
  "Not supported on watchOS" table and the PORTING_REPORT's interface list
  cover 5.3.0.
* README: saved games fail because `GKSavedGame` does not exist on watchOS,
  not because they are not implemented yet.
* Tests: a case for every public member of the 5.3.0 interface, each called
  with the parameters 5.3.0 gives it.
* Example: signs in and submits as 5.x code does, catching
  `PlatformException`, and its integration test expects those failures on the
  Simulator.
* Example: the list fills the screen and starts below the clock, at
  `WatchStatusBar.heightOf` (from `flutter_watchos: ^0.1.0`), with its other
  insets from `MediaQuery`; a status row shows the sign-in state from
  `GameAuth.player`. A widget test lays it out on three watch screens in both
  safe areas, and checks what it shows when a call fails and when the player
  signs in.

## 0.1.0

* The version moves from 0.0.1 to 0.1.0, so that a `^0.1.0` constraint
  admits later fixes; `^0.0.1` admits none.
* README: the install snippet names this version, and says to add this
  package alongside `games_services`.
* `pubspec.yaml`: `repository` points at this package's folder in the plugins
  repo.
* README: a "Not supported on watchOS" table; PORTING_REPORT: an "Interface
  coverage" list of every member of `games_services_platform_interface` 4.1.1,
  audited by hand.
* README: the supported table lists only what works; the rest moves to the new
  table.
* Dartdoc on every public member, and `public_member_api_docs` is on in
  `analysis_options.yaml`.
* Example: `pubspec.yaml` names `games_services: ^4.1.1` and
  `games_services_platform_interface: ^4.1.1` instead of `any`.
* README: says this release works with `games_services` 4.x, and that
  `games_services` 5.x, which needs the 5.x interface, does not resolve
  alongside it yet.
* API docs and comments say "release" for handing native memory back.

## 0.0.1

* Initial staged release: the watchOS implementation of `games_services`.
* Leaderboards only — sign-in, score submission, and reading entries.
  Achievements, saved games and the access point keep the platform
  interface's `UnimplementedError` defaults; `GKGameCenterViewController`
  and `GKAccessPoint` do not exist on watchOS, so there is nothing to
  present and no partial version worth shipping.
* Not yet verified end to end on a physical watch: `GKLocalPlayer`
  reports an authenticated player with an unresolved alias and GameKit
  then refuses `loadEntries`. See PORTING_REPORT.md.
