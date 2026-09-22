# Spirit Scenarios Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Ownership is divided between core motion, rendering, and preview UI; review and verification remain with the parent agent.

**Goal:** Implement all eight approved character scenarios, including interruption and reduced-motion behavior.

**Architecture:** Retain the existing SpriteKit rig and Swift motion model. Authored phases produce a single pose; one idle-action scheduler coordinates ember play and hammer tricks. The renderer interprets expression and prop fields, and the preview UI exercises production input methods without emitting session events.

**Tech Stack:** Swift 6, Swift Testing, SpriteKit, AppKit, SwiftUI.

**Spec:** `docs/superpowers/specs/2026-09-21-spirit-character-scenarios.md`

## Global Constraints

- Preserve existing artwork, charge palette on both arms, provider behavior, and uncommitted work.
- No new dependencies, commits, or pushes.
- User interaction interrupts large gestures; completion never resumes after cancellation.
- No fake progress or session events. Reduce Motion retains meaningful static expressions.
- Validate at 80/128/192pt; inspect actual frames and export scenario GIFs.

## Task 1: Motion and lifecycle

Files: `Packages/SpiritCore/Sources/SpiritCore/SpiritRigMotion.swift`, related core tests; a small focused helper is allowed if needed.

Pose additions: expressions `curious`, `requesting`, `worried`, `yawning`; `eyeReopen` (0…1), `workSurface` (0…1), `strikeStrength` (0…1), `playEmberOpacity`, `playEmberX`, `playEmberY` (64-unit stage coordinates), `didRequestHammerTrick` (one-frame event). Existing fields retain their meaning.

Motion API additions: `playEmberPlay() -> Bool`, `setAutomaticIdleActionsEnabled(_ enabled: Bool)`, `cancelInteractions()`.

- [x] Add failing behavioral tests for gaze dwell/head delay, petting release, completion phase ordering, canceled completion, working rhythms, ember capture path, distinct attention/error, sleep entry/wake, and input priority.
- [x] Implement gaze dwell and cooldown; phased petting with a short afterglow; rigid-tool-compatible drag pose and release/regrip.
- [x] Implement preparation and light/light/heavy work phrases, fatigue timing, final-stroke completion; full three-second proud reaction.
- [x] Implement a single idle scheduler and an independently moving ember episode; authored sleep entry and wake.
- [x] Check 30/60/120fps, invalid input, long delta, reduced motion, and interruption. Run `swift test` and inspect failures.

## Task 2: Renderer and native input (parent)

Files: `App/Companion/SpiritScene.swift`, `App/Companion/CompanionPanel.swift`, `Tests/ScenarioSceneSmoke.swift`.

Scene API additions: `playEmberPlay() -> Bool`, `cancelInteractions()`; preserve existing pointer/drag APIs.

- [x] Add renderer checks for expression distinction, visible work surface, independent ember positions, rigid hammer and interruption cleanup.
- [x] Draw additional pixel expressions, a small work surface, and a stage-space story ember. Map pose values without additional random behavior.
- [x] Keep the hammer rigid during body deformation, sync hand attachment, tie sparks to workpiece contact, and leave charged hand palette intact.
- [x] Remove Scene's competing idle timer; consume `didRequestHammerTrick` only when automatic behavior is enabled.
- [x] Route hide/resize/cancel to cancellation without an artificial landing. Compile and run native renderer/input regressions.

## Task 3: Scenario preview (independent agent)

Files: `App/Settings/MotionReviewView.swift` only.

- [x] Provide a compact selection for all eight scenarios with replay/stop using fresh independent scenes.
- [x] Drive gaze/petting/drag through existing production inputs; use state transitions for work/completion/attention/error/sleep and `playEmberPlay()` for the ember episode.
- [x] Stop inputs and tasks on disappearance, scenario replacement, and reduced-motion changes. Avoid background tasks controlling a replacement scene.
- [x] Preserve existing quota/charge/hammer controls, fit the panel in a normal desktop window, and build/typecheck with the integrated app.

## Task 4: Integration and review (parent)

- [x] Read changed code, compare all eight spec scenarios to rendered output, and resolve behavioral regressions.
- [x] Run core suite, Xcode build, native click/hammer/rig smoke tests, and new scenario smoke test.
- [x] Capture start/hold/end frames and GIFs; inspect actual faces, tool geometry, workpiece contact and boundary clipping.
- [x] Update `docs/basic-motion-review.md` with verified behavior and reproduction commands, then report results with preview links.

## Verification results

- Core: 198 tests in 23 suites passed; 2 explicitly opt-in external integration tests skipped.
- Xcode Debug app build passed; no Swift diagnostics in the final build log.
- Production SpriteKit smoke tests: emotion, rig, hammer tricks, native input, and all eight scenarios passed.
- 48 scenario GIFs exported across 80/128/192pt and light/dark backgrounds. Work/completion contact frames were inspected and the anvil lowered to meet the rigid hammer head rather than intersect its centre.
- Independent review found and resolved petting reversal restart, stale drag velocity, and urgent-state expression masking. Regression coverage added.
- No separate lint configuration. Swift 6 compilation and `git diff --check` passed. No commits or pushes.
