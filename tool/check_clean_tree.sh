#!/usr/bin/env bash
# Copyright 2026 The FlutterWatch Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# Fails when the working tree is not clean: a modified, deleted or new file
# that git does not ignore. CI runs it after the package tests, so a step
# that writes into a package is caught before it can reach a publish, which
# warns on a dirty tree (spec 0006 criterion 3, change plan M024).
#
# Usage: tool/check_clean_tree.sh [--root <repository>]
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

status="$(git -C "$root" status --porcelain --untracked-files=all)"
if [ -n "$status" ]; then
  echo "The tree is not clean. Ignore generated files, or stop writing them:"
  printf '%s\n' "$status" | sed 's/^/  /'
  exit 1
fi
echo "The tree is clean."
