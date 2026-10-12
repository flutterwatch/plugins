## 0.2.0

* Implements `games_services_platform_interface` 5.3.0 (`^5.3.0`, was
  `^4.1.1`), so it works with `games_services` 5.x. The README's install
  snippet names `games_services: ^5.3.0`; an app that stays on
  `games_services` 4.x keeps 0.1.0. The example and the dev dependency name
  `games_services: ^5.3.0` too.
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
