# Repository checks

The scripts that CI runs over the whole repository, in the `repository
checks` job of `.github/workflows/ci.yml`. Each has tests that run it on
checked-in fixtures, and each fixture must pass or fail as its test says.

Run them from the repository root:

```sh
(cd tool && dart pub get && dart analyze --fatal-infos && dart test)
tool/check_words.sh
tool/check_generated_ignored.sh
(cd tool && dart run bin/check_test_names.dart)
(cd tool && dart run bin/check_versions.dart)
(cd tool && dart run bin/check_readme_snippets.dart)
```

## Word check

`check_words.sh` fails on any forbidden word in a file or a file path, and
`bin/check_test_names.dart` on any in a test or group name under
`packages/*/test/` and `packages/*/example/integration_test/`. The words are
in `words/words.txt`; the rule (spec 0007 D8) splits text into words at
every non-letter and at every lower-to-upper case change, and also matches
each word with a trailing "s".

- `words/forbidden_words_allow.txt` lists the code identifiers, API names
  and upstream licence texts that may stay, each with its reason. It is a
  copy of the flutter-watchos CLI's `test/data/forbidden_words_allow.txt`.
  Test and group names can never be allowed; only the pending list may name
  one, until the commit that renames it.
- `words/pending.txt` lists the prose and test names that the package
  commits still have to reword. The checks pass over them with a notice.
  Remove an entry in the commit that rewords its text: an entry whose text is
  gone fails the check.
- `words/` itself is not scanned, because it must spell the words out.

## Packaging

`check_generated_ignored.sh` fails unless git ignores
`watchos/Flutter/GeneratedPluginRegistrant.swift` in every package, which
`flutter-watchos test` writes there; it lists the packages that rely on the
root `.gitignore` alone. `check_clean_tree.sh` fails when the tree has a
modified or new file that git does not ignore; CI runs it after the package
tests.

## Versions

`bin/check_versions.dart` compares each package's publishable files (what
`pub publish` would take: not hidden, not ignored) with the commit that
`published.yaml` records for its last version on pub.dev. A package that
changed needs a higher version and a top CHANGELOG heading equal to it, and
no package may be at a pre-release. A package without a row is checked as
unpublished. After each publish, record the version and the commit it was
published from in `published.yaml`.

## README install snippets

`bin/check_readme_snippets.dart` reads every `yaml` block with a
`dependencies:` map in the package READMEs and the root README, without
calling pub.dev. Each constraint must be a caret on a plain version: no
placeholder, no `any`. A package of this repository must be admitted at its
pubspec version, and an upstream package at its latest version in
`upstream_versions.yaml`, which may also allow one older constraint with a
reason. Each federated README, and the root README, must say to add the
package alongside its upstream. Update `upstream_versions.yaml` in the same
commit that moves the READMEs to a new upstream major.
