#!/usr/bin/env bash
# Copyright 2026 The FlutterWatch Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# The word check (spec 0006 Decision 2d and criterion 1, spec 0007 D8).
#
# Every file in the repository is public, on GitHub and in the pub.dev
# archives, so no text in it may hold a forbidden word. The words are in
# tool/words/words.txt, and the rule is 0007 D8's shell form: text splits
# into words at every character that is not a letter and at every change
# from a lower-case to an upper-case letter, and a hit is a listed word,
# alone or with a trailing "s". So a camelCase identifier that ends in a
# listed word is a hit, and so is a pre-release suffix; "freeze" and
# "unpaid" are not. tool/words/samples.txt has the full set of examples.
#
# The check fails when
#   1. a line of a tracked or untracked (not ignored) text file holds a
#      forbidden word that no entry allows there;
#   2. a file path holds one;
#   3. `git grep -i` finds the first word of the list anywhere, even inside
#      another word (no entry applies to this one);
#   4. an entry is stale: its glob matches files here but its text is in none
#      of them, or its glob is under packages/ and matches nothing;
#   5. an allow-list entry for this repository's packages could match
#      packages/flutter_watchos/, the package in the CLI repository: the
#      CLI's copy of the list would apply it to that package, and the CLI's
#      test would find its text missing there.
#
# Entries come from two files, both "<path glob> | <exact text> | <reason>"
# per line:
#   - tool/words/forbidden_words_allow.txt, the allow-list. It is a copy of
#     the flutter-watchos CLI's test/data/forbidden_words_allow.txt; entries
#     whose glob matches nothing here belong to the CLI and are skipped. Only
#     code identifiers, API names and upstream licence texts may be listed.
#   - tool/words/pending.txt: prose and test names in packages/ that the
#     package commits of 0.1.1 reword. Each is printed as a notice, and each
#     turns stale, so it fails, once its text is gone. The list only shrinks.
#
# tool/words/ is not scanned: it holds the list, the entries, the samples and
# the failing fixtures, which must spell the words out. Binary files are not
# scanned either.
#
# Usage:
#   tool/check_words.sh [--root <dir>] [--allow <file>] [--pending <file>]
#   tool/check_words.sh --filter    # the rule alone, as a filter on stdin
set -euo pipefail

export LC_ALL=C

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
words_file="$here/words/words.txt"
allow_file="$here/words/forbidden_words_allow.txt"
pending_file="$here/words/pending.txt"
root=""
filter_only=0
# Relative to the repository root. In a fixture repository it names nothing.
own_dir="tool/words"

usage() {
  echo "usage: $0 [--root <dir>] [--allow <file>] [--pending <file>] | --filter" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || usage; root="$2"; shift 2 ;;
    --allow) [ $# -ge 2 ] || usage; allow_file="$2"; shift 2 ;;
    --pending) [ $# -ge 2 ] || usage; pending_file="$2"; shift 2 ;;
    --filter) filter_only=1; shift ;;
    *) usage ;;
  esac
done

words="$(grep -v -e '^#' -e '^$' "$words_file" | paste -s -d '|' -)"
first_word="$(grep -v -e '^#' -e '^$' "$words_file" | head -n 1)"
rule_sed='s/([a-z])([A-Z])/\1 \2/g'
rule_grep="(^|[^[:alpha:]])(${words})s?([^[:alpha:]]|\$)"

# Prints the input lines that break the rule.
rule_filter() {
  sed -E "$rule_sed" | grep -i -E "$rule_grep" || true
}

if [ "$filter_only" -eq 1 ]; then
  rule_filter
  exit 0
fi

allow_file="$(cd "$(dirname "$allow_file")" && pwd)/$(basename "$allow_file")"
pending_file="$(cd "$(dirname "$pending_file")" && pwd)/$(basename "$pending_file")"
if [ -z "$root" ]; then
  root="$(git rev-parse --show-toplevel)"
fi
cd "$root"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Reads both entry files. glob_to_ere converts a path glob to an ERE: `*`
# and `?` stay in one directory, `**` crosses directories, and `**/` also
# matches no directory at all (the CLI's globToRegExp does the same).
entries_awk='
function glob_to_ere(g,    out, i, c) {
  out = "^"
  for (i = 1; i <= length(g); i++) {
    c = substr(g, i, 1)
    if (c == "*" && substr(g, i + 1, 1) == "*") {
      if (substr(g, i + 2, 1) == "/") { out = out "(.*/)?"; i += 2 }
      else { out = out ".*"; i += 1 }
    } else if (c == "*") {
      out = out "[^/]*"
    } else if (c == "?") {
      out = out "[^/]"
    } else if (index(".+()[]{}^$|\\", c) > 0) {
      out = out "\\" c
    } else {
      out = out c
    }
  }
  return out "$"
}
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
# Appends the entries of file to globs[], texts[], lines[], files_of[] and
# res[]; n_entries counts them. Sets bad_entries on a malformed line.
function read_entries(file,    line, nr, a, b, rest) {
  nr = 0
  while ((getline line < file) > 0) {
    nr++
    sub(/[ \t\r]+$/, "", line)
    if (line ~ /^[ \t]*$/ || line ~ /^[ \t]*#/) continue
    a = index(line, " | ")
    rest = substr(line, a + 3)
    b = index(rest, " | ")
    if (a == 0 || b == 0) {
      printf "  %s:%d: needs \"glob | text | reason\"\n", file, nr
      bad_entries = 1
      continue
    }
    n_entries++
    globs[n_entries] = trim(substr(line, 1, a - 1))
    texts[n_entries] = substr(rest, 1, b - 1)
    lines[n_entries] = nr
    files_of[n_entries] = file
    if (globs[n_entries] == "" || trim(texts[n_entries]) == "" ||
        trim(substr(rest, b + 3)) == "") {
      printf "  %s:%d: has an empty part\n", file, nr
      bad_entries = 1
    }
    res[n_entries] = glob_to_ere(globs[n_entries])
  }
  close(file)
}
function read_all() {
  n_entries = 0
  bad_entries = 0
  read_entries(allow)
  read_entries(pending)
}
'
# Runs an awk program after the entry functions. The program reads its
# other inputs from the environment (STRIPPED, WHERE, FILES).
run_awk() {
  awk -v allow="$allow_file" -v pending="$pending_file" "$entries_awk$1" "${@:2}"
}

# Files that pub would see and GitHub shows: tracked, plus untracked files
# that are not ignored, so a local run sees new files before they are added.
git ls-files --cached --others --exclude-standard \
  | grep -v -e "^${own_dir}/" | sort -u > "$work/files" || true

export STRIPPED="$work/stripped" WHERE="$work/where" FILES="$work/files"
failed=0

# 0. Both entry files must parse.
run_awk 'BEGIN { read_all(); exit 0 }' > "$work/bad_entries"
if [ -s "$work/bad_entries" ]; then
  echo "Malformed entries:"
  cat "$work/bad_entries"
  failed=1
fi

# 5 (checked first, like 0). An allow-list entry under packages/ names this
# repository's packages, never a pattern such as `packages/**` or `*_watchos`
# that packages/flutter_watchos/ would match too. The package part of the
# glob (up to the first "/") is tested against that name.
run_awk '
  BEGIN {
    read_all()
    for (e = 1; e <= n_entries; e++) {
      if (files_of[e] != allow) continue
      g = globs[e]
      if (g !~ /^packages\// || g ~ /^packages\/flutter_watchos\//) continue
      seg = substr(g, length("packages/") + 1)
      k = index(seg, "/")
      if (k > 0) seg = substr(seg, 1, k - 1)
      if (seg ~ /^\*\*/ || "flutter_watchos" ~ glob_to_ere(seg)) {
        printf "  %s:%d: %s\n", files_of[e], lines[e], g
      }
    }
    exit 0
  }' > "$work/cli_package"
if [ -s "$work/cli_package" ]; then
  echo "Allow-list entries that would match packages/flutter_watchos/ in the"
  echo "CLI's copy of the list. Name this repository's packages instead:"
  cat "$work/cli_package"
  failed=1
fi

# 1. Lines. git grep -i with the bare words finds every candidate line; the
# entries then blank the text they allow, and the rule decides.
git grep -z -n -I -i -E --untracked -e "(${words})" -- . ":(exclude)${own_dir}" \
  | tr '\0' '\t' > "$work/candidates" || true
run_awk '
  BEGIN { read_all(); FS = "\n" }
  {
    line = $0
    t1 = index(line, "\t"); path = substr(line, 1, t1 - 1); rest = substr(line, t1 + 1)
    t2 = index(rest, "\t"); num = substr(rest, 1, t2 - 1); text = substr(rest, t2 + 1)
    out = text
    for (e = 1; e <= n_entries; e++) {
      if (path !~ res[e]) continue
      len = length(texts[e])
      pad = sprintf("%" len "s", "")
      for (;;) {
        k = index(out, texts[e])
        if (k == 0) break
        out = substr(out, 1, k - 1) pad substr(out, k + len)
      }
    }
    print out > ENVIRON["STRIPPED"]
    print path ":" num ": " text > ENVIRON["WHERE"]
  }' "$work/candidates" > /dev/null
touch "$work/stripped" "$work/where"
sed -E "$rule_sed" "$work/stripped" | grep -n -i -E "$rule_grep" \
  | cut -d: -f1 > "$work/hit_lines" || true
if [ -s "$work/hit_lines" ]; then
  echo "Forbidden words in text. Reword them; only code identifiers, API"
  echo "names and upstream licence texts may go on the allow-list, with a reason:"
  awk 'NR == FNR { hit[$1] = 1; next } hit[FNR] { print "  " $0 }' \
    "$work/hit_lines" "$work/where"
  failed=1
fi

# 2. Paths.
if [ -n "$(rule_filter < "$work/files")" ]; then
  echo "Forbidden words in file paths:"
  # The rule splits camelCase to match; print each path as it is.
  while IFS= read -r p; do
    if [ -n "$(printf '%s\n' "$p" | rule_filter)" ]; then echo "  $p"; fi
  done < "$work/files"
  failed=1
fi

# 3. The first word anywhere, even inside another word, with no entries.
{
  git grep -n -I -i --untracked -e "$first_word" -- . ":(exclude)${own_dir}" || true
  grep -i -e "$first_word" "$work/files" | sed 's/$/ (a path)/' || true
} > "$work/first_word_hits"
if [ -s "$work/first_word_hits" ]; then
  echo "\"$first_word\" must not appear at all, not even inside another word:"
  sed 's/^/  /' "$work/first_word_hits"
  failed=1
fi

# 4. Stale entries.
run_awk '
  BEGIN {
    read_all()
    files = ENVIRON["FILES"]
    n_files = 0
    while ((getline f < files) > 0) all[++n_files] = f
    for (e = 1; e <= n_entries; e++) {
      matched = 0
      for (i = 1; i <= n_files; i++) {
        if (all[i] ~ res[e]) { matched++; print e "\t" all[i] > (files ".matched") }
      }
      if (matched == 0) {
        if (globs[e] ~ /^packages\// && globs[e] !~ /^packages\/flutter_watchos\//) {
          printf "  %s:%d: %s matches no file\n", files_of[e], lines[e], globs[e]
        }
        continue
      }
      print e "\t" files_of[e] ":" lines[e] "\t" globs[e] "\t" texts[e] > (files ".entries")
    }
  }' /dev/null > "$work/stale"
touch "$work/files.entries" "$work/files.matched"
tab="$(printf '\t')"
while IFS="$tab" read -r e at glob text; do
  found=0
  while IFS="$tab" read -r me path; do
    [ "$me" = "$e" ] || continue
    if grep -F -q -e "$text" -- "$path" 2>/dev/null; then found=1; break; fi
  done < "$work/files.matched"
  if [ "$found" -eq 0 ]; then
    echo "  $at: \"$text\" is not in $glob" >> "$work/stale"
  fi
done < "$work/files.entries"
if [ -s "$work/stale" ]; then
  echo "Stale entries. Remove them:"
  cat "$work/stale"
  failed=1
fi

if [ "$failed" -ne 0 ]; then
  exit 1
fi

pending_count="$(grep -c -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$pending_file" || true)"
if [ "${pending_count:-0}" -gt 0 ]; then
  message="$pending_count pending entries in tool/words/pending.txt: prose and test names still to reword in packages/."
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    echo "::warning title=Word check::$message"
  else
    echo "Note: $message"
  fi
fi
echo "Word check: no forbidden word outside the allow-list and the pending list."
