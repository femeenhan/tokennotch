# 픽셀 대시보드 Implementation Plan

> Agentic workers: independent storage and usage tasks use parallel agents under the user's AGENTS.md; controller integrates native UI. No commits or pushes.

**Goal:** 기존 macOS 앱에서 실제 Codex 작업 기록과 동의한 토큰 메타데이터를 볼 수 있게 한다.
**Architecture:** SQLite 단일 actor가 메타데이터를 저장한다. MainActor CompanionModel이 hook→저장→snapshot을 연결하고 native dashboard가 snapshot을 읽는다. 선택된 로그만 UsageFileReader로 읽는다.
**Tech Stack:** Swift6, SQLite3 systemLibrary, SwiftUI, AppKit, SpriteKit.
**Spec:** docs/superpowers/specs/2026-09-16-dashboard-design.md

## 실행 결과 (2026-09-16)

Task 1–4 구현·리뷰·검증 완료. 아래 체크리스트는 최초 계획을 보존합니다. 상세 사용법과 제한은 `docs/dashboard.md`에 정리했습니다. 저장소8/사용량7/집계5 테스트를 포함해 Swift83개 통과, 브리지4/앱훅3/대시보드1 통합 테스트 통과, Xcode Debug 빌드 성공, 한국어 픽셀 제목 밝은·어두운 렌더링 smoke PASS. 실제 앱의 기간 전환과 현재 Codex 세션 상세 타임라인 확인. 최초 integration red는 기존 앱에서 dashboardEventCount 미존재로 실패했으며 green에서 중복 제거와 재실행unknown 복원을 확인했습니다. 최종 UI는 CLI가 제공하는 toolFinished를 ‘도구 완료’로 표시합니다. 비용/배포는 범위 밖입니다. 커밋·푸시하지 않았습니다.

## Global Constraints

macOS14+, Swift6. 기존 미커밋 변경 보존. 커밋·푸시 없음. 비용/Git 제외. 프롬프트·응답·코드·명령·patch 디스크저장 없음. 로그선택 동의 외 home scan 없음. 미수집 !=0. live 상태는 캐릭터 reducer, 기록 재시작 상태는unknown.

### Task 1: SQLite 저장과 집계

Files: Packages/SpiritCore/Sources/SpiritCore/DashboardStore.swift, DashboardModels.swift, Sources/CSQLite/module.modulemap, Package.swift, Tests/SpiritCoreTests/DashboardStoreTests.swift.
Interface: actor DashboardStore.init(url:URL), record(_:SpiritEvent), snapshot(now:Date)->DashboardSnapshot, registerProject(path:String,name:String)->DashboardProject, assignProject(sessionID:String,projectID:UUID?). Models have public Sendable fields. DashboardSnapshot has projects:[DashboardProject], sessions:[DashboardSession], events:[SpiritEvent], usage:[UsageRecord]. Session id:String, status:SessionState.Status, startedAt/lastObservedAt:Date, projectID:UUID?. snapshot reduction uses in-memory live session states with restored statesunknown.

- [ ] Write tests: record same event100times then snapshot.events.count==1; reopen store and verify persisted event and unknown status; assign project and reopen verify assignment; sqlite database contains no nonallowlisted payload fields.
- [ ] Run `swift test --filter DashboardStore` and observe missing behavior.
- [ ] Implement SQLite migration/WAL/bound statements, single actor, error propagation, typed JSON extraction allowlist.
- [ ] Run store tests and full package tests.

### Task 2: Opt-in usage reader

Files: Packages/SpiritCore/Sources/SpiritCore/UsageRecord.swift, UsageFileReader.swift, Tests/SpiritCoreTests/UsageFileReaderTests.swift.
Interface: UsageRecord Codable/Sendable/Equatable with id:String, sessionID:String, modelID:String?, occurredAt:Date, inputTokens:Int, outputTokens:Int, cachedInputTokens:Int?, reasoningOutputTokens:Int?, totalTokens:Int. actor UsageFileReader.init(url:URL), read()->[UsageRecord]. Reader accepts only selected file; memory cursor, fileidentity and incomplete lastline protection. Record cumulative reports as latest totals rather than summing repeated cumulative usage.

- [ ] Tests literal JSONL fixtures for partialline, unknown records, cumulative duplicates, selected file replacement, negative/malformed counts and non-sensitive output.
- [ ] Run usage tests to observe missing behavior.
- [ ] Parse official Codex session_meta+event_msg/token_count+turn_context format; bounded chunks, strip all content except metadata, explicit errors without source data in logs.
- [ ] Run usage tests and report supported schema limits.

### Task 3: Native integration and pixel UI

Files: App/Services/CompanionModel.swift, App/Dashboard/DashboardView.swift, App/Dashboard/DashboardTheme.swift, App/BuildSpiritApp.swift, Xcode pbxproj, Tests/dashboard_integration.py.
Consumes interfaces from task1/2. Store init at application support with isolated --socket test DB sibling path. Set on hooks after scene reaction; asynchronously load snapshot; avoid out-of-order publish. Usage selection with NSOpenPanel+explanation, periodic read only selected URL, stop button; reader failures expose messages. Add project folder chooser and manual session assignment. JSON metadata export SavePanel.

- [ ] Write integration test launching --dashboard --diagnostics on isolated socket, send2tool events, assert dashboard snapshot counters persist across reopen and repeated IDs dedup.
- [ ] Run test, observe missing dashboard diagnostics.
- [ ] Pixel theme uses square shapes, orange emphasis and static grid; native character asset uses existing texture. Main window menu opens dashboard, resizing minimum900x650; timeline and selection scroll.
- [ ] Implement filters (today/7/30/project), explicit empty/error/stateunknown, activity heatmap source labels, usage subset labels. No fake sample numbers.
- [ ] Build Xcode, run all existing and new tests; inspect actual macOS window controls with computer-use.

### Task 4: Review and handoff

- [ ] Independent review storage/usage + UI integration for metadata privacy, stale state, duplicated cumulative usage, hidden/close lifecycle.
- [ ] Address concrete findings and rerun covering tests.
- [ ] Document supported input schema, opt-in import, lack of historical hook recovery, no cost estimates, no public packaging.
- [ ] Run fresh tests/build then execute --dashboard and leave real dashboard open for user.
