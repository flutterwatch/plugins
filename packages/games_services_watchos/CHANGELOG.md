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
