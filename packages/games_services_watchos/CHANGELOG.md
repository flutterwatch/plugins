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
