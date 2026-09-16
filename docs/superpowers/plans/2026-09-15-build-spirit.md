# Build Spirit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 일반 사용자용 캐릭터와 개발자용 Codex CLI 기록을 각각 검증할 수 있는 macOS 알파를 만든 뒤 유료 배포를 준비한다.

**Architecture:** Swift Package 코어와 AppKit 앱을 분리한다. Bridge가 필터링한 이벤트와 로컬 usage 메타데이터를 SQLite에 기록하고 캐릭터 상태와 기록 화면에 반영한다.

**Tech Stack:** Swift 6, macOS 14+, AppKit, SwiftUI, SpriteKit, SQLite3. 배포 단계에서 Sparkle 2를 검토한다.

**Spec:** ../specs/2026-09-15-build-spirit-design.md

## Global Constraints

- 최초 A 캐릭터 사용. 실제 제작용 스프라이트는 별도 제작한다.
- 1회 구매, 가격은 검증 후보이며 개발자가 임의 확정하지 않는다.
- CLI 지원을 GUI 지원으로 표시하지 않는다.
- 원문 저장·외부 분석 전송·자동 Git 변경 없음.
- 커밋 후보는 품질 점수나 AI 기여도 확정치가 아니다.
- Xcode 라이선스는 사용자가 직접 검토·동의해야 한다.
- 사용자 요청 없는 커밋·푸시 금지. 각 단계의 리뷰는 로컬 diff로 진행한다.

## 파일 배치

```text
BuildSpirit.xcodeproj
App/BuildSpiritApp.swift
App/Companion/CompanionPanel.swift
App/Companion/SpiritScene.swift
App/Records/SessionListView.swift
App/Settings/SettingsView.swift
App/Onboarding/ConnectionView.swift
App/Resources/Spirit/manifest.json
App/Resources/Spirit/concept-original.png
Packages/SpiritCore/Package.swift
Packages/SpiritCore/Sources/SpiritCore/Events.swift
Packages/SpiritCore/Sources/SpiritCore/SessionReducer.swift
Packages/SpiritCore/Sources/SpiritCore/Usage.swift
Packages/SpiritCore/Sources/SpiritCore/Store.swift
Packages/SpiritCore/Sources/SpiritCore/GitAssociation.swift
Packages/SpiritCore/Tests/SpiritCoreTests/
Bridge/SpiritBridge.swift
App/Adapters/CodexAdapter.swift
App/Adapters/UsageReader.swift
App/Adapters/HookInstaller.swift
App/Adapters/GitObserver.swift
App/License/LicenseService.swift
App/Updates/UpdateController.swift
Tests/Fixtures/codex/
docs/compatibility.md
docs/alpha-results.md
```

## Task 1 — 코어 상태와 실행 환경

Files: Package.swift, Events.swift, SessionReducer.swift, Tests/SpiritCoreTests/SessionReducerTests.swift.
계약: SpiritEvent는 설계 5절 필드, SessionState는 unknown/idle/working/attention/error/ended, 화면 SpiritState는 설계 3절 상태다. reduce는 세션 사전과 이벤트를 받아 갱신된 사전을 반환한다. 화면 상태 집계는 별도 함수다.

- [ ] Xcode 라이선스 해결 후 xcodebuild -version, swift --version, SDK 버전을 확인해 readiness에 기록한다.
- [ ] Swift Package와 XCTest 타깃을 만들고 다음 테스트가 실패함을 확인한다.

```swift
func testAnotherSessionKeepsWorking() {
    var states: [String: SessionState] = ["a": .working, "b": .working]
    states["a"] = .idle
    XCTAssertEqual(aggregate(states), .working)
}
```

- [ ] 상태 우선순위와 턴 종료·세션 종료 구분을 구현한다. 재시작 복구는 unknown이다.
- [ ] attention 우선, 오래된 turn 무시, unknown 복구 사례를 추가하고 swift test --package-path Packages/SpiritCore 실행한다.
통과 기준: 이벤트 순서·중첩 세션에서 거짓 완료가 없다.

## Task 2 — 일반 모드 실행 가능한 앱

Files: BuildSpiritApp.swift, CompanionPanel.swift, SpiritScene.swift, SettingsView.swift, Resources/Spirit/*.
입력: Task 1 SpiritState. 출력: AI 미연결로 실행되는 앱.

- [ ] UI 구현 전에 Taste·ui-ux 가이드를 읽고 원본 PNG를 Resources에 복사한다.
- [ ] Xcode 앱 타깃에 Core를 연결하고 nonactivating 투명 NSPanel과 메뉴 막대를 만든다.
- [ ] 정적 시안과 호흡 동작으로 렌더링 경로를 구현한다. 제작용 자산과 구분한다.
- [ ] 128pt 기본 크기, 위치 저장·드래그·숨김·전체 화면 기본 숨김·종료를 구현한다.
- [ ] 타이머1~180분과 한 번만 울리는 리마인더를 추가한다. 절전 복귀 후 만료 알림은 중복 없이 한 번만 보낸다.
- [ ] 다른 앱 타이핑, 투명영역 클릭, 화면분리, 잠금·복귀를 실기 검사해 alpha-results에 기록한다.
통과 기준: 설치·AI 설정 없이 동반자 기능이 작동하고 포커스를 빼앗지 않는다.

## Task 3 — Codex CLI 호환성 조사와 이벤트 연결

Files: CodexAdapter.swift, SpiritBridge.swift, HookInstaller.swift, ConnectionView.swift, Fixtures/codex/*, compatibility.md.
입력: 공급자 JSON. 출력: SpiritEvent. capability는 지원을 확인한 항목만 true다.

- [ ] 로컬 CLI 버전과 공식 SessionStart/UserPromptSubmit/PreToolUse/PostToolUse/PermissionRequest/Stop/Interrupt/SessionEnd 스키마를 확인하고 민감 내용을 제거한 fixture를 만든다.
- [ ] 정상·오류·권한대기·부모/자식·잘못된JSON fixture별 정규 이벤트를 명시한다.
- [ ] Bridge에서 허용 필드만 추출하고 socket 전송에 제한 시간을 둔다. 앱 부재 시 AI에 결정값을 반환하지 않고 정상 종료한다.
- [ ] 설정 병합 테스트: 기존 사용자 훅이 설치·제거 후 동일하며 중복 설치는 항목을 늘리지 않아야 한다.
- [ ] 사용자 승인·백업·원자적 쓰기·우리 항목만 제거를 구현한다. 잘못된 JSON은 수정하지 않는다.
- [ ] 앱 종료·재시작·실패 이벤트를 실제 Codex CLI 세션에서 확인한다. 훅 신뢰 승인은 사용자가 Codex `/hooks`에서 직접 수행한다.
통과 기준: 거짓 완료 없음, 설정 손실 없음, helper 부재가 작업을 막지 않음.

## Task 4 — 저장과 usage 기록

Files: Store.swift, Usage.swift, UsageReader.swift, SessionListView.swift, Tests/SpiritCoreTests/UsageTests.swift.
입력: 이벤트, usage 레코드. 출력: 프로젝트·세션·기간별 기록과 미산출 여부.

- [ ] 설계 9절 테이블·키·보존기간을 SQLite migration으로 구현한다.
- [ ] 고유 sourceRecordID로 멱등 저장한다. 동일 레코드100회 입력 결과가 한 번과 같은지 검사한다.
- [ ] 파일 offset·교체·잘린 마지막 행·미상 스키마 처리를 fixture로 먼저 검증한다.
- [ ] 단가표에 모델·유효시각·출처를 넣고 Decimal로 환산한다. 미상 모델은 nil을 반환한다.
- [ ] input/cache/reasoning 포함 관계와 부모/자식 합산을 확인하고 확실하지 않은 합계는 미산출로 표시한다.
- [ ] 오늘·7일·30일·프로젝트·세션 필터와 추정치 라벨을 구현한다.
- [ ] 악의적 fixture의 prompt·코드·시크릿이 DB·로그에 남지 않는지 검사한다.
- [ ] CSV/JSON 내보내기·기간정리·프로젝트/전체 삭제·WAL checkpoint를 구현한다.
통과 기준: 중복 과금 표시 없음, 미상을0으로 표시하지 않음, 민감 원문 보존 없음.

## Task 5 — 관련 커밋 후보

Files: GitObserver.swift, GitAssociation.swift, Tests/SpiritCoreTests/GitAssociationTests.swift.
입력: 등록 저장소와 세션 파일 활동. 출력: candidate/confirmed/dismissed 관계.

- [ ] 테스트용 저장소에서 worktree2개·중첩세션·amend·rebase·사람 수정 시나리오를 만든다.
- [ ] 현재 HEAD를 초기 기준으로 저장하고 설계의10초/60초 관측을 구현한다.
- [ ] 동일worktree·시간·파일교집합으로 후보를 만든다. 애매한 경우 복수 후보 또는 미분류다.
- [ ] 사용자의 확인·해제, 관측공백, 사라진SHA 표시를 구현한다.
- [ ] 관련 후보로 사용량을 다시 합산하지 않는지 검사한다.
통과 기준: 관련 기록만 제시하고 AI 기여도·성공 판정을 만들지 않는다.

## Task 6 — 제작용 동작과 알파 검증

Files: Resources/Spirit/*, alpha-results.md.

- [ ] 기준 캐릭터의 배경 없는 원화·레이어·7개 클립을 제작한다. 자동 생성 프레임의 얼굴·피벗 불일치는 수정한다.
- [ ] manifest의 크기·프레임수·fps와 실제 PNG를 대조한다.
- [ ] 80/128/192pt와 밝고 어두운 배경에서 실루엣·작은 소품을 확인한다.
- [ ] 동작 줄이기·숨김·잠금에서 렌더링 중단을 확인한다.
- [ ] 10분 CPU·메모리 측정과 일반/개발 모드1주 테스트를 각각 기록한다.
- [ ] 설계의 수요 기준으로 판매 준비·집중 고객 변경·재검토를 결정한다.
통과 기준: 동작 자산 품질·앱 안정성·구매 가설을 구분한 실제 결과가 있다.

## Task 7 — Claude Code 확장 게이트

Files: App/Adapters/ClaudeAdapter.swift, Tests/Fixtures/claude/*, compatibility.md.

- [ ] 로컬 공식 스키마와 실제 CLI 버전을 확인한다.
- [ ] status/usage/fileActivity별 fixture를 확보한다. 미지원 capability는 false다.
- [ ] 동일 Core 테스트에 adapter를 연결하고 중첩세션·누적 토큰·서브에이전트 중복을 검사한다.
- [ ] 실제 앱/GUI 지원은 별도 검증 전 광고하지 않는다.
통과 기준: 검증된 로컬 CLI 범위만 베타 표기. 이 작업 실패로 일반 모드·Codex 출시를 막지 않는다.

## Task 8 — 유료 배포 게이트

Files: LicenseService.swift, UpdateController.swift, docs/release-checklist.md. 결제 서버는 선택 공급자 확정 후 별도 프로젝트로 분리한다.

- [ ] 유료 수요 확인 후 가격·유지보수 범위를 정하고 결제 공급자의 KRW·세금·수수료·환불·기기 API를 sandbox로 검증한다.
- [ ] 서명된 라이선스 증명·공개키 검증·Keychain 저장·본인3대·기기 해제를 구현한다. 앱에 서버 비밀키가 없는지 확인한다.
- [ ] 정상·잘못된키·환불·추가기기·오프라인·서버오류·체험종료 읽기 유지 테스트를 수행한다.
- [ ] Sparkle 서명 업데이트와 DB migration 백업·구버전 쓰기 차단을 검사한다.
- [ ] Universal 빌드,helper 서명,Hardened Runtime,공증,DMG를 만들고 깨끗한 Mac에서 설치·삭제·업데이트한다.
- [ ] 판매 전 대응 버전·권한·수집 범위·업데이트 정책·환불 조건을 공개 문서로 작성한다.
통과 기준: 실제 결제·공개 배포는 사용자 권한과 계정 확보 후 실행한다. 준비만으로 게시 완료를 선언하지 않는다.

## 공통 검증 명령

```sh
swift test --package-path Packages/SpiritCore
xcodebuild -project BuildSpirit.xcodeproj -scheme BuildSpirit -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

앱 타깃 생성 시 위 scheme 이름을 고정한다. Release에서는 signing을 끄지 않는다. typecheck는 Swift 빌드에 포함하며 프로젝트에 lint가 추가되면 각 완료 단계에 함께 실행한다. 테스트 실패·측정 미달은 결과대로 기록한다.

## 준비 완료와 실행 경계

이번 단계는 문서와 환경 진단이다. 코드는 아직 생성하지 않았다. Task1~6이 첫 실행 묶음이며,7은 독립 확장,8은 판매 검증 후 별도 배포 작업이다. 실행 방식은 사용자의 기존 원칙에 따라 독립 작업이 생기면 서브에이전트로 나누고 의존 작업은 순차 진행한다.
