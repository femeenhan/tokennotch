#!/bin/bash
set -eu

# Finder에서 실행해도 현재 터미널 경로와 관계없이 프로젝트를 찾는다.
project_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$project_dir"
app="$project_dir/.build/xcode/Build/Products/Debug/BuildSpirit.app"
mkdir -p .build
build_log="$project_dir/.build/launcher-build.log"

fail() {
    echo
    echo "$1" >&2
    if [[ -t 0 ]]; then
        read -r -p 'Enter를 누르면 종료합니다. ' || true
    fi
    exit 1
}

echo '빌드정령을 빌드하고 있습니다. 첫 실행은 조금 걸릴 수 있습니다.'
if ! xcodebuild -quiet -project BuildSpirit.xcodeproj -scheme BuildSpirit \
    -configuration Debug -derivedDataPath .build/xcode \
    CODE_SIGNING_ALLOWED=NO build > "$build_log" 2>&1; then
    tail -n 60 "$build_log" >&2
    fail "빌드에 실패했습니다. 전체 로그: $build_log"
fi
[[ -d "$app" ]] || fail "빌드된 앱을 찾지 못했습니다: $app"

# 중복 실행과 예전 빌드 재사용을 피한다. 빌드 실패 시 기존 앱은 유지한다.
if pgrep -x BuildSpirit >/dev/null; then
    osascript -e 'tell application id "local.buildspirit.alpha" to quit' \
        || fail '실행 중인 빌드정령을 종료하지 못했습니다. 앱 메뉴에서 종료 후 다시 실행해 주세요.'
    for attempt in {1..50}; do
        if ! pgrep -x BuildSpirit >/dev/null; then break; fi
        sleep 0.1
    done
    if pgrep -x BuildSpirit >/dev/null; then
        fail '기존 빌드정령이 아직 종료 중입니다. 잠시 후 다시 실행해 주세요.'
    fi
fi
open "$app" || fail "앱을 열지 못했습니다: $app"
echo '빌드정령을 실행했습니다. 메뉴 막대의 불꽃 아이콘을 확인해 주세요.'
echo '이 터미널 창은 닫아도 됩니다.'
