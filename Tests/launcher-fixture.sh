#!/bin/bash
case "$(basename "$0")" in
  xcodebuild)
    printf 'build:%s\n' "$*" >> "$LAUNCHER_TEST_LOG"
    if [[ "${LAUNCHER_TEST_FAIL:-0}" == 1 ]]; then
      echo 'simulated build failure' >&2
      exit 65
    fi
    mkdir -p .build/xcode/Build/Products/Debug/BuildSpirit.app
    ;;
  open) printf 'open:%s\n' "$*" >> "$LAUNCHER_TEST_LOG" ;;
  pgrep) exit 1 ;;
esac
