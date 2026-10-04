#!/usr/bin/env bash
# Copyright 2026 The FlutterWatch Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# Fails unless git ignores watchos/Flutter/GeneratedPluginRegistrant.swift
# in every package (spec 0006 criterion 3, change plan M024).
#
# `flutter-watchos test` writes that file into a plugin package, and
# `pub publish` takes every file that is not hidden or ignored, so an
# unignored copy would dirty the tree and ship in the archive. pub reads the
# repository's .gitignore files from the root down, so the root rule covers
# every package; the packages that rely on it alone are listed as a notice,
# because each package's own .gitignore should carry the rule too.
#
# Usage: tool/check_generated_ignored.sh [--root <repository>]
set -euo pipefail

root=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || { echo "--root needs a value" >&2; exit 2; }; root="$2"; shift 2 ;;
    *) echo "usage: $0 [--root <repository>]" >&2; exit 2 ;;
  esac
done
if [ -z "$root" ]; then
  root="$(git rev-parse --show-toplevel)"
fi
cd "$root"

missing=()
root_only=()
count=0
for dir in packages/*/; do
  [ -f "${dir}pubspec.yaml" ] || continue
  name="$(basename "$dir")"
  count=$((count + 1))
  path="packages/$name/watchos/Flutter/GeneratedPluginRegistrant.swift"
  if ! git check-ignore -q "$path"; then
    missing+=("$name")
    continue
  fi
  source="$(git check-ignore -v "$path" | cut -d: -f1)"
  if [ "$source" != "packages/$name/.gitignore" ]; then
    root_only+=("$name")
  fi
done

if [ "${#root_only[@]}" -gt 0 ]; then
  echo "Ignored only by a rule outside the package's own .gitignore: ${root_only[*]}"
fi
if [ "${#missing[@]}" -gt 0 ]; then
  echo "watchos/Flutter/GeneratedPluginRegistrant.swift is not ignored in: ${missing[*]}"
  echo "Add watchos/Flutter/ to each package's .gitignore."
  exit 1
fi
echo "The generated registrant is ignored in all $count packages."
