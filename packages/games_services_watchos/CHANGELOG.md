## 0.1.0

* The version moves from 0.0.1 to 0.1.0, so that a `^0.1.0` constraint
  admits later fixes; `^0.0.1` admits none.
* README: the install snippet names this version, and says to add this
  package alongside `games_services`.

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
