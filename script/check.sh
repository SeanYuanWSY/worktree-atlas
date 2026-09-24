#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
swift build
test_args=(--disable-xctest --enable-swift-testing)
if [[ "$(uname -s)" == Darwin ]]; then
  developer_dir="$(xcode-select -p)"
  if [[ "$developer_dir" == */CommandLineTools ]]; then
    testing_frameworks="$developer_dir/Library/Developer/Frameworks"
    testing_interop="$developer_dir/Library/Developer/usr/lib"
    if [[ ! -d "$testing_frameworks/Testing.framework" || ! -f "$testing_interop/lib_TestingInterop.dylib" ]]; then
      echo "Swift Testing runtime is missing from Command Line Tools: $developer_dir" >&2
      exit 1
    fi
    test_args+=(-Xswiftc -F -Xswiftc "$testing_frameworks"
                -Xlinker -rpath -Xlinker "$testing_frameworks"
                -Xlinker -rpath -Xlinker "$testing_interop")
  fi
fi
test_output="$(mktemp "${TMPDIR:-/tmp}/atlas-tests.XXXXXX")"
trap 'rm -f "$test_output"' EXIT
swift test "${test_args[@]}" 2>&1 | tee "$test_output"
test_count="$(sed -nE 's/.*Test run with ([0-9]+) tests? .*passed.*/\1/p' "$test_output" | tail -n 1)"
if [[ -z "$test_count" || "$test_count" -lt 48 ]]; then
  echo "Expected at least 48 Swift Testing tests to run; observed ${test_count:-none}." >&2
  exit 1
fi
find Sources/WorktreeAtlas -name '*.swift' -print0 | xargs -0 swiftc -frontend -parse
for script in script/*.sh; do bash -n "$script"; done
if [[ -e .git ]] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git diff --check
else
  echo "Skipping git diff --check: this source directory is not a Git worktree."
fi
if [[ "$(uname -s)" == Darwin ]]; then ./script/build_and_run.sh --build-only
else echo "Core and syntax checks completed. Native SwiftUI typecheck, bundle build, and UI validation require macOS."; fi
