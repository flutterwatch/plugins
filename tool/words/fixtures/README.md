# Word check fixtures

Each directory under `check_words/` and `test_names/` is a small repository
that `tool/test/check_words_test.dart` and `tool/test/test_names_test.dart`
turn into a git repository and check:

- `repo/`: the files, committed;
- `untracked/`: files copied in after the commit and left untracked;
- `allow.txt`, `pending.txt`: the entry lists the check reads (empty if
  absent);
- `expect`: the exit code on the first line, then text the output must
  contain, one per line.

They live under `tool/words/` because they spell the forbidden words out,
and the word check does not scan this directory.
