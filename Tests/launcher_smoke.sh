#!/bin/bash
set -eu
repo="$(cd "$(dirname "$0")/.." && pwd)"
launcher="$repo/빌드정령 실행.command"
[[ -x "$launcher" ]] || { echo 'FAIL: double-click launcher is missing or not executable'; exit 1; }
test_dir="$(mktemp -d -t build-spirit-launcher)"
trap 'rm -r "$test_dir"' EXIT
mkdir -p "$test_dir/project with spaces" "$test_dir/bin"
cp "$launcher" "$test_dir/project with spaces/"
cp "$repo/Tests/launcher-fixture.sh" "$test_dir/bin/fixture"
chmod +x "$test_dir/bin/fixture"
for tool in xcodebuild open pgrep; do ln -s fixture "$test_dir/bin/$tool"; done
export PATH="$test_dir/bin:$PATH"
export LAUNCHER_TEST_LOG="$test_dir/success.log"
cd /tmp
"$test_dir/project with spaces/빌드정령 실행.command" </dev/null
rg -q 'build:.*-project BuildSpirit.xcodeproj.*-derivedDataPath .build/xcode.*CODE_SIGNING_ALLOWED=NO' "$LAUNCHER_TEST_LOG"
rg -Fq "open:$test_dir/project with spaces/.build/xcode/Build/Products/Debug/BuildSpirit.app" "$LAUNCHER_TEST_LOG"
export LAUNCHER_TEST_LOG="$test_dir/failure.log" LAUNCHER_TEST_FAIL=1
if "$test_dir/project with spaces/빌드정령 실행.command" </dev/null > "$test_dir/error.log" 2>&1; then
  echo 'FAIL: failed build reported success'; exit 1
fi
if rg -q '^open:' "$LAUNCHER_TEST_LOG"; then
  echo 'FAIL: stale app launched after build failure'; exit 1
fi
rg -q 'simulated build failure' "$test_dir/error.log"
echo 'PASS: launch from another directory, spaces in path, and build failure handling'
