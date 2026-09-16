# Codex CLI 연결 호환성

## 지원 범위

2026-09-16 확인한 로컬 CLI는 `/usr/local/bin/codex`의 `codex-cli 0.154.0`이다. 이번 빌드는 macOS 로컬 CLI command hooks 베타다. Codex 데스크톱 앱, IDE 확장, 원격 CLI, Claude 연동은 지원 대상으로 검증하지 않았다. 다른 CLI 버전은 연결 화면에서 미검증으로 표시한다.

## 공식 계약 확인

[OpenAI 공식 Hooks 문서](https://learn.chatgpt.com/docs/hooks)를 2026-09-16 확인했다. 문서는 현재 문서이며 0.154.0에 고정된 사본은 아니다.

- command hook은 stdin JSON을 받는다. `hooks.json`의 `hooks → 이벤트 배열 → hooks 배열`에 `type: command`, `command`, 초 단위 `timeout`을 둔다.
- hooks 설치와 신뢰 승인은 별개다. 사용자가 CLI `/hooks`에서 내용을 검토하고 직접 승인해야 한다. 설정 변경 시 재승인이 필요할 수 있다.
- Pre/PostToolUse에는 `turn_id`, `tool_name`, `tool_use_id`가 있다. PermissionRequest는 `tool_use_id`를 필수로 문서화하지 않으므로 요구하지 않는다. 공식 `Bash` 이름도 shell로 정규화한다.
- PostToolUse는 비정상 종료한 명령에도 발생한다. 본문을 읽지 않는 이 연결은 `success`를 알 수 없으므로 nil로 유지한다.
- SessionEnd와 Interrupt는 짧은 hook 제한을 사용한다. 설치 항목은 모든 이벤트에 timeout 1초를 둔다. Bridge 자체 stdin 제한은 250ms다.

## 이벤트 의미

| 공식 이벤트 | 빌드정령 이벤트 |
| --- | --- |
| SessionStart | sessionStarted |
| UserPromptSubmit | turnStarted |
| PreToolUse | toolStarted |
| PostToolUse | toolFinished |
| PermissionRequest | needsInput |
| Stop / Interrupt | turnStopped |
| SessionEnd | sessionEnded |

Stop은 턴 종료이며 세션 성공 또는 완료가 아니다. SessionEnd만 세션 종료로 처리한다. hook에 타임스탬프가 없으므로 Bridge가 JSON을 받은 시각을 occurredAt/receivedAt에 사용한다. sourceVersion은 이 어댑터가 대상으로 하는 계약 버전 `0.154.0`이며 매 hook마다 실행 중인 CLI 바이너리를 재감지한 값은 아니다.

## 수집과 연결

Bridge는 stdin을 최대 256 KiB까지만 메모리에서 읽고 새 allowlist 이벤트를 생성한다. 세션·턴 ID, 모델 ID와 정규화된 도구 범주만 원본 입력에서 이벤트에 넣는다. cwd, source, reason, tool_use_id는 허용 범위지만 현재 저장하지 않는다. 도구 ID는 필수 검증에만 사용한다. tool_name 원문은 보내지 않는다.

프롬프트, 명령, 패치, 도구 결과, 마지막 응답, transcript 경로 및 본문은 저장하거나 보내지 않는다. transcript 파일을 열지 않으며 디스크 큐와 외부 전송도 없다. 어댑터 오류는 민감 내용이 없는 enum 코드로 구분하고 Bridge는 오류를 출력하지 않는다.

사용자 전용 `~/Library/Application Support/BuildSpirit`(0700)의 `events.sock`(0600)으로 정규 JSON 한 줄을 Unix datagram으로 보낸다. socket 전송은 nonblocking이며 앱 부재·포화·잘못된 입력에서도 stdout/stderr 없이 종료 코드 0이다. 수신 크기는 16 KiB로 제한한다. 테스트 전용 `--socket` 인자로 임시 경로를 지정할 수 있다.

앱 종료 중 이벤트는 유실된다. 앱을 다시 실행해도 과거 활성 세션을 완료로 추정하지 않으며 빈 세션 상태에서 새 이벤트를 기다린다. 메모리 상태는 앱 실행 동안만 유지한다. 동일 사용자 프로세스 간 연결이며 다른 사용자의 접근은 파일시스템 권한으로 제한한다.

## 설치와 제거

Xcode의 BuildSpirit 타깃을 빌드하면 `Contents/MacOS/SpiritBridge`가 함께 포함된다. 설정의 Codex CLI 연결 섹션에서 미리보기를 열고 설치한다. 실제 대상은 앱 환경의 CODEX_HOME 또는 `~/.codex/hooks.json`이다. Finder에서 실행한 앱과 셸의 CODEX_HOME이 다르면 표시된 경로를 먼저 확인해야 한다.

HookInstaller는 JSON 객체와 다른 hook을 보존하며 동일한 command를 중복 추가하지 않는다. 손상 JSON은 거부하고, 쓰기 전에 같은 폴더에 UUID 이름의 `.bak` 백업을 남긴 뒤 같은 폴더의 임시 파일을 원자 교체한다. 제거는 현재 앱 절대 경로의 command와 정확히 일치하는 항목만 대상으로 한다. 앱을 다른 경로로 옮긴 뒤에는 이전 경로의 hook이 남을 수 있다.

2026-09-16 사용자 요청으로 `~/.codex/hooks.json`을 생성하고 현재 Debug 앱 번들의 `SpiritBridge --codex-hook` command hook 8종을 설치했다. `~/.codex`는 0700, `hooks.json`은 0600으로 제한했다. 기존 `~/.codex/config.toml`은 변경하지 않았다. Debug 앱을 이동하거나 삭제하거나 다른 출력 경로로 다시 빌드하면 절대 경로가 달라질 수 있으므로 다시 설치해야 한다.

## 검증과 남은 항목

fixture 매핑·민감 문자열 제외·설치 멱등성·백업·socket 권한과 전달을 Swift 테스트로 검증했다. 별도 프로세스 테스트는 Bridge의 무출력·0 종료·크기와 시간 제한을 검증한다. 앱 통합 테스트는 격리 socket으로 PermissionRequest를 보내 번들 Bridge, 앱 reducer, 실제 SpiritScene의 attention 상태까지 확인한다.

아직 검증하지 않은 항목은 실제 CLI `/hooks` 신뢰 승인 후의 실사용 8종 이벤트, 서명·공증한 배포 앱, Intel Mac, macOS 14 실기, 연결 화면 VoiceOver 및 설치·제거의 수동 UI 조작이다. 현재 설치된 사용자 hook도 CLI에서 검토하고 신뢰 승인하기 전에는 실행되지 않는다. 공식 문서의 Stop 출력 설명과 무출력 관찰용 hook의 실제 CLI 표시도 실사용 검증에서 확인해야 한다. Bridge는 요구사항대로 아무 hook 결정도 출력하지 않는다.
