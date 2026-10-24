#!/usr/bin/env bash
# Copyright 2026 The FlutterWatch Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# Compiles every plugin's native watchOS sources the way flutter-watchos does,
# with -fsyntax-only, for a watch and for the Simulator, with the Xcode that
# DEVELOPER_DIR (or xcode-select) picks. CI runs it with the oldest Xcode 26
# the CLI supports, the newest Xcode 26 and Xcode 27, so a symbol that one
# SDK lacks fails here and not in an app's build (spec 0022 D1, #17).
#
# - Objective-C and C sources (.m, .mm, .c) go through clang with the CLI's
#   flags (lib/build_targets/application.dart in flutter-watchos 0.1.1).
# - SwiftUI view sources (.swift under watchos/, except Package.swift and
#   anything under Flutter/ or a dot-directory) go through swiftc -typecheck,
#   one module per plugin, with the CLI's registration shim
#   (tool/native/plugin_views_shim.swift).
# - A plugin whose watchos/Package.swift names a SwiftPM package is skipped
#   and listed: its sources import that package's modules, which only a
#   SwiftPM build provides, and the CLI builds such a plugin with xcodebuild.
#
# Only git-tracked files are read. A warning fails like an error, as in the
# CLI's own host typecheck, except a deprecation: those are counted and left
# to the package (in_app_purchase_watchos uses StoreKit 1 on purpose).
#
# Usage: tool/check_native_sources.sh [--root <repository>] [--list]
#   --list  prints what would be compiled and runs nothing; no Xcode needed.
set -euo pipefail

# The deployment target `flutter-watchos create` writes.
readonly deployment_target="26.0"
readonly targets="watchos:arm64-apple-watchos${deployment_target} watchsimulator:arm64-apple-watchos${deployment_target}-simulator"

root=""
list=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || { echo "--root needs a value" >&2; exit 2; }; root="$2"; shift 2 ;;
    --list) list=1; shift ;;
    *) echo "usage: $0 [--root <repository>] [--list]" >&2; exit 2 ;;
  esac
done
if [ -z "$root" ]; then
  root="$(git rev-parse --show-toplevel)"
fi
shim="$(cd "$(dirname "$0")" && pwd)/native/plugin_views_shim.swift"
cd "$root"

# The tracked files under each package's own watchos/ directory. In a
# pathspec `*` also crosses `/`, so the pattern alone would take in each
# example's watchos/ app too; the grep keeps the package's.
tracked="$(git ls-files -- 'packages/*/watchos/*' | grep -E '^packages/[^/]+/watchos/' || true)"

# Every directory that holds a tracked header: the CLI passes each one to
# every plugin's compile.
includes=()
for dir in $(printf '%s\n' "$tracked" | grep '\.h$' | xargs -n1 dirname | sort -u); do
  includes+=("-I$dir")
done

# True for a view source: not the manifest, and nothing under Flutter/ or a
# dot-directory (CLI build output and SwiftPM state).
is_view_source() {
  local relative="${1#*/watchos/}"
  case "$relative" in
    Package.swift | Flutter/* | */Flutter/* | .* | */.*) return 1 ;;
    *.swift) return 0 ;;
    *) return 1 ;;
  esac
}

# Prints the warnings in [1] that are not deprecations.
other_warnings() {
  grep 'warning:' <<< "$1" | grep -v -e 'is deprecated' -e 'was deprecated' || true
}

# Reports one compile: [1] its name, [2] its exit code, [3] its output.
report() {
  local deprecations
  deprecations="$(grep -c 'warning:.*deprecated' <<< "$3" || true)"
  if [ "$2" -eq 0 ] && [ -z "$(other_warnings "$3")" ]; then
    if [ "$deprecations" -gt 0 ]; then
      echo "ok     $xcode  $triple  $1  ($deprecations deprecation warning$([ "$deprecations" -eq 1 ] || echo s))"
    else
      echo "ok     $xcode  $triple  $1"
    fi
  else
    echo "FAILED $xcode  $triple  $1"
    echo "$3"
    status=1
  fi
}

xcode=""
if [ "$list" -eq 0 ]; then
  # sed, not head: head would close the pipe early, and pipefail would end
  # the script on xcodebuild's SIGPIPE.
  xcode="$(xcodebuild -version | sed -n 1p)"
fi

status=0
checked=0
for package_dir in $(printf '%s\n' "$tracked" | cut -d/ -f1-2 | sort -u); do
  package="${package_dir#packages/}"
  manifest="$package_dir/watchos/Package.swift"
  if [ -f "$manifest" ] && grep -q '\.package(' "$manifest"; then
    echo "skip   $package: its watchos/Package.swift names a SwiftPM package, which only a SwiftPM build provides"
    continue
  fi
  c_sources=()
  view_sources=()
  for file in $(printf '%s\n' "$tracked" | grep "^$package_dir/"); do
    case "$file" in
      *.m | *.mm | *.c) c_sources+=("$file") ;;
      *) if is_view_source "$file"; then view_sources+=("$file"); fi ;;
    esac
  done
  for target in $targets; do
    sdk="${target%%:*}"
    triple="${target#*:}"
    for source in ${c_sources[@]+"${c_sources[@]}"}; do
      checked=$((checked + 1))
      if [ "$list" -eq 1 ]; then
        echo "plan   clang   $sdk $triple $source"
        continue
      fi
      code=0
      output="$(xcrun -sdk "$sdk" clang -fsyntax-only -target "$triple" \
          -fobjc-arc -fmodules ${includes[@]+"${includes[@]}"} "$source" 2>&1)" || code=$?
      report "$source" "$code" "$output"
    done
    if [ ${#view_sources[@]} -gt 0 ]; then
      checked=$((checked + 1))
      if [ "$list" -eq 1 ]; then
        echo "plan   swiftc  $sdk $triple ${package}_views: ${view_sources[*]}"
        continue
      fi
      code=0
      output="$(xcrun -sdk "$sdk" swiftc -typecheck -target "$triple" \
          -parse-as-library -module-name "${package}_views" \
          "$shim" "${view_sources[@]}" 2>&1)" || code=$?
      report "${package}_views" "$code" "$output"
    fi
  done
done

if [ "$checked" -eq 0 ]; then
  echo "No native source found under packages/*/watchos/."
  exit 1
fi
if [ "$list" -eq 1 ]; then
  echo "include ${includes[*]+"${includes[*]}"}"
  exit 0
fi
if [ "$status" -ne 0 ]; then
  echo "Native sources: some do not compile cleanly with $xcode."
  exit 1
fi
echo "Native sources: all compile cleanly with $xcode."
