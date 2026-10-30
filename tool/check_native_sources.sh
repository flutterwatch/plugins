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
# - A plugin that declares `defines` in its pubspec (macros the app's
#   Info.plist turns on, from the first flutter-watchos release after 0.1.1)
#   is compiled with no -D, as an older CLI compiles it; with
#   FLUTTER_WATCHOS_PLUGIN_DEFINES and every macro, as for an app that sets
#   every key; with the marker alone, as for an app that sets none; and, when
#   it declares more than one, with the marker and each macro alone, as for
#   an app that sets one group's keys. So each guard compiles with its macros
#   all on, all off and one at a time, nested guards included. clang gets
#   each define as NAME=1, and swiftc a bare NAME, as the CLI passes them.
#
# The pubspecs are read by tool/bin/plugin_defines.dart, with package:yaml,
# the parser the CLI uses, so dart must be on PATH and `dart pub get` must
# have run in tool/. A YAML reader in shell would miss what YAML allows (flow
# maps and lists, quoting, comments), and the system Ruby and Python read
# YAML 1.1, where a bare NO is false. A declaration the CLI would refuse
# fails here before anything is compiled.
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
# The define the CLI passes to every source of a plugin that declares
# `defines`, with the macros the app's Info.plist turns on.
readonly marker="FLUTTER_WATCHOS_PLUGIN_DEFINES"

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
# Absolute, as the script moves into it and then hands it to the Dart tool,
# which would read a relative root from inside itself.
root="$(cd "$root" 2> /dev/null && pwd)" || { echo "--root: no directory there" >&2; exit 2; }
tool="$(cd "$(dirname "$0")" && pwd)"
shim="$tool/native/plugin_views_shim.swift"
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

# One line per package that declares `defines`:
# "defines <package directory> <MACRO>…".
defines=""
if [ -n "$(git ls-files -- 'packages/*/pubspec.yaml')" ]; then
  if ! command -v dart > /dev/null; then
    echo "dart is not on PATH: tool/bin/plugin_defines.dart reads each pubspec's defines." >&2
    exit 2
  fi
  code=0
  defines="$(dart "$tool/bin/plugin_defines.dart" --root "$root")" || code=$?
  case "$code" in
    0) ;;
    1)
      echo "$defines"
      echo "Native sources: a plugin's defines are invalid, so nothing was compiled."
      exit 1
      ;;
    *)
      echo "tool/bin/plugin_defines.dart did not run; has \`dart pub get\` run in tool/?" >&2
      exit 2
      ;;
  esac
fi

# Prints the macros the package [1] declares, space-separated.
macros_of() {
  printf '%s\n' "$defines" | awk -v package="$1" '
    $1 == "defines" && $2 == package {
      for (i = 3; i <= NF; i++) printf "%s%s", $i, (i < NF ? " " : "")
    }'
}

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
  # Pass 0 compiles with no -D. A package with defines also gets pass 1, the
  # marker and every macro, pass 2, the marker alone, and, with more than one
  # macro, a pass for each: the marker and that macro alone.
  macros="$(macros_of "$package_dir")"
  macro_list=()
  for macro in $macros; do
    macro_list+=("$macro")
  done
  passes=1
  if [ ${#macro_list[@]} -gt 0 ]; then
    passes=3
    if [ ${#macro_list[@]} -gt 1 ]; then
      passes=$((3 + ${#macro_list[@]}))
    fi
    echo "defines $package: $macros"
  fi
  for target in $targets; do
    sdk="${target%%:*}"
    triple="${target#*:}"
    pass=0
    while [ "$pass" -lt "$passes" ]; do
      clang_defines=()
      swift_defines=()
      if [ "$pass" -gt 0 ]; then
        clang_defines=("-D$marker=1")
        swift_defines=("-D$marker")
      fi
      if [ "$pass" -eq 1 ]; then
        for macro in "${macro_list[@]}"; do
          clang_defines+=("-D$macro=1")
          swift_defines+=("-D$macro")
        done
      elif [ "$pass" -ge 3 ]; then
        macro="${macro_list[$((pass - 3))]}"
        clang_defines+=("-D$macro=1")
        swift_defines+=("-D$macro")
      fi
      # The flags as --list shows them.
      clang_flags="${clang_defines[*]+${clang_defines[*]}}"
      swift_flags="${swift_defines[*]+${swift_defines[*]}}"
      # Which pass a line is about, for a package with defines.
      label=""
      if [ "$passes" -gt 1 ]; then
        case "$pass" in
          0) label=" [no -D]" ;;
          1) label=" [marker, every macro]" ;;
          2) label=" [marker alone]" ;;
          *) label=" [marker, ${macro_list[$((pass - 3))]} alone]" ;;
        esac
      fi
      for source in ${c_sources[@]+"${c_sources[@]}"}; do
        checked=$((checked + 1))
        if [ "$list" -eq 1 ]; then
          echo "plan   clang   $sdk $triple $source$label${clang_flags:+ $clang_flags}"
          continue
        fi
        code=0
        output="$(xcrun -sdk "$sdk" clang -fsyntax-only -target "$triple" \
            -fobjc-arc -fmodules ${clang_defines[@]+"${clang_defines[@]}"} \
            ${includes[@]+"${includes[@]}"} "$source" 2>&1)" || code=$?
        report "$source$label" "$code" "$output"
      done
      if [ ${#view_sources[@]} -gt 0 ]; then
        checked=$((checked + 1))
        if [ "$list" -eq 1 ]; then
          echo "plan   swiftc  $sdk $triple ${package}_views$label${swift_flags:+ $swift_flags}: ${view_sources[*]}"
        else
          code=0
          output="$(xcrun -sdk "$sdk" swiftc -typecheck -target "$triple" \
              -parse-as-library ${swift_defines[@]+"${swift_defines[@]}"} \
              -module-name "${package}_views" "$shim" "${view_sources[@]}" 2>&1)" || code=$?
          report "${package}_views$label" "$code" "$output"
        fi
      fi
      pass=$((pass + 1))
    done
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
