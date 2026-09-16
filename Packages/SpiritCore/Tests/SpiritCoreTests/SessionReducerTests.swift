import Foundation
import Testing
@testable import SpiritCore

@Suite("SessionReducer")
struct SessionReducerTests {
    private let receivedAt = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("다른 세션이 작업 중이면 idle 세션이 전체 상태를 idle로 만들지 않는다")
    func workingSessionWinsOverIdleSession() {
        let states = [
            "idle": SessionState(status: .idle),
            "working": SessionState(status: .working)
        ]

        #expect(aggregateSpiritState(from: states, consuming: .init()).state == .working)
    }

    @Test("attention은 working보다 우선한다")
    func attentionWinsOverWorking() {
        let states = [
            "working": SessionState(status: .working),
            "attention": SessionState(status: .attention)
        ]

        #expect(aggregateSpiritState(from: states, consuming: .init()).state == .attention)
    }

    @Test("error는 working보다 우선한다")
    func errorWinsOverWorking() {
        let states = [
            "working": SessionState(status: .working),
            "error": SessionState(status: .error)
        ]

        #expect(aggregateSpiritState(from: states, consuming: .init()).state == .error)
    }

    @Test("turnStopped는 세션을 ended로 바꾸지 않는다")
    func turnStoppedDoesNotEndSession() {
        let event = makeEvent(kind: .turnStopped, turnID: "turn-1")

        let reduced = reduce(
            sessions: ["session-1": SessionState(status: .working, latestTurnID: "turn-1")],
            event: event
        )

        #expect(reduced["session-1"]?.status == .idle)
    }

    @Test("오래된 turn 이벤트는 최신 turn 상태를 덮어쓰지 않는다")
    func olderTurnEventIsIgnored() {
        let event = makeEvent(
            kind: .turnStarted,
            turnID: "turn-1",
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let reduced = reduce(
            sessions: [
                "session-1": SessionState(
                    status: .idle,
                    latestTurnID: "turn-2",
                    latestTurnOccurredAt: Date(timeIntervalSince1970: 1_700_000_100)
                )
            ],
            event: event
        )

        #expect(
            reduced["session-1"] == SessionState(
                status: .idle,
                latestTurnID: "turn-2",
                latestTurnOccurredAt: Date(timeIntervalSince1970: 1_700_000_100)
            )
        )
    }

    @Test("복구한 세션은 unknown 상태로 시작한다")
    func restoredSessionIsUnknown() {
        let restored = SessionState.restored()

        #expect(restored.status == .unknown)
    }

    @Test("sessionEnded 이벤트는 세션을 ended로 만든다")
    func sessionEndedEndsSession() {
        let event = makeEvent(kind: .sessionEnded)

        let reduced = reduce(
            sessions: ["session-1": SessionState(status: .working)],
            event: event
        )

        #expect(reduced["session-1"]?.status == .ended)
        #expect(aggregateSpiritState(from: reduced, consuming: .init()).state == .completed)
    }

    @Test("정규 이벤트 kind 전체가 설계된 이름으로 제공된다")
    func exposesAllSpecifiedEventKinds() {
        let kinds: [SpiritEvent.Kind] = [
            .sessionStarted,
            .turnStarted,
            .toolStarted,
            .toolFinished,
            .needsInput,
            .turnStopped,
            .sessionEnded,
            .usageObserved,
            .collectionInterrupted
        ]

        #expect(kinds.map(\.rawValue) == [
            "sessionStarted",
            "turnStarted",
            "toolStarted",
            "toolFinished",
            "needsInput",
            "turnStopped",
            "sessionEnded",
            "usageObserved",
            "collectionInterrupted"
        ])
    }

    @Test("정규 이벤트는 지정된 세션 전이 또는 상태 유지 정책을 따른다")
    func appliesSpecifiedEventTransitions() {
        #expect(reducedStatus(kind: .sessionStarted, from: .unknown) == .idle)
        #expect(reducedStatus(kind: .turnStarted, from: .idle, turnID: "turn-1") == .working)
        #expect(reducedStatus(kind: .toolStarted, from: .idle, turnID: "turn-1") == .working)
        #expect(reducedStatus(kind: .toolFinished, from: .working, turnID: "turn-1") == .working)
        #expect(reducedStatus(kind: .needsInput, from: .working, turnID: "turn-1") == .attention)
        #expect(reducedStatus(kind: .turnStopped, from: .working, turnID: "turn-1") == .idle)
        #expect(reducedStatus(kind: .sessionEnded, from: .working) == .ended)
        #expect(reducedStatus(kind: .usageObserved, from: .working) == .working)
        #expect(reducedStatus(kind: .collectionInterrupted, from: .working, turnID: "turn-1") == .error)
    }

    @Test("완료는 한 번 소비한 뒤 idle로 집계된다")
    func completedIsExposedOnlyOnceAfterConsumption() {
        let ended = reduce(
            sessions: [:],
            event: makeEvent(kind: .sessionEnded, eventID: "ended-1")
        )

        let first = aggregateSpiritState(from: ended, consuming: .init())
        let afterConsumption = aggregateSpiritState(
            from: ended,
            consuming: first.completionConsumption
        )

        #expect(first.state == .completed)
        #expect(first.completionConsumption.consumedCompletionIDs == ["ended-1"])
        #expect(afterConsumption.state == .idle)
    }

    @Test("idle 세션은 완료 pulse를 만들지 않는다")
    func idleSessionDoesNotCreateCompletion() {
        let aggregation = aggregateSpiritState(
            from: ["session-1": SessionState(status: .idle)],
            consuming: .init()
        )

        #expect(aggregation.state == .idle)
        #expect(aggregation.completionConsumption.consumedCompletionIDs.isEmpty)
    }

    @Test("작업 중인 다른 세션은 미소비 완료를 가리지만 소비하지 않는다")
    func workingSessionMasksCompletionWithoutConsumingIt() {
        let ended = reduce(
            sessions: [:],
            event: makeEvent(kind: .sessionEnded, eventID: "ended-1")
        )
        let working = reduce(
            sessions: ended,
            event: makeEvent(
                kind: .turnStarted,
                eventID: "started-2",
                sessionID: "session-2",
                turnID: "turn-2"
            )
        )
        let masked = aggregateSpiritState(from: working, consuming: .init())
        let noLongerWorking = reduce(
            sessions: working,
            event: makeEvent(
                kind: .turnStopped,
                eventID: "stopped-2",
                sessionID: "session-2",
                turnID: "turn-2"
            )
        )
        let revealed = aggregateSpiritState(
            from: noLongerWorking,
            consuming: masked.completionConsumption
        )
        let afterConsumption = aggregateSpiritState(
            from: noLongerWorking,
            consuming: revealed.completionConsumption
        )

        #expect(masked.state == .working)
        #expect(masked.completionConsumption.consumedCompletionIDs.isEmpty)
        #expect(revealed.state == .completed)
        #expect(afterConsumption.state == .idle)
    }

    @Test("이전 turn의 stop, 입력 요청, 중단은 최신 turn 상태를 바꾸지 않는다")
    func previousTurnEventsDoNotOverrideCurrentTurn() {
        let firstStarted = makeEvent(
            kind: .turnStarted,
            eventID: "turn-1-start",
            turnID: "turn-1",
            occurredAt: date(10)
        )
        let secondStarted = makeEvent(
            kind: .turnStarted,
            eventID: "turn-2-start",
            turnID: "turn-2",
            occurredAt: date(20)
        )
        let current = reduce(sessions: reduce(sessions: [:], event: firstStarted), event: secondStarted)

        for kind in [SpiritEvent.Kind.turnStopped, .needsInput, .collectionInterrupted] {
            let result = reduce(
                sessions: current,
                event: makeEvent(
                    kind: kind,
                    eventID: "turn-1-\(kind.rawValue)",
                    turnID: "turn-1",
                    occurredAt: date(21)
                )
            )

            #expect(result["session-1"]?.status == .working)
            #expect(result["session-1"]?.latestTurnID == "turn-2")
        }
    }

    @Test("같은 시각의 이전 turn 이벤트도 최신 turn을 바꾸지 않는다")
    func sameTimestampPreviousTurnEventIsIgnored() {
        let first = reduce(
            sessions: [:],
            event: makeEvent(kind: .turnStarted, turnID: "turn-1", occurredAt: date(10))
        )
        let current = reduce(
            sessions: first,
            event: makeEvent(kind: .turnStarted, turnID: "turn-2", occurredAt: date(10))
        )
        let result = reduce(
            sessions: current,
            event: makeEvent(kind: .turnStopped, turnID: "turn-1", occurredAt: date(10))
        )

        #expect(result["session-1"]?.status == .working)
        #expect(result["session-1"]?.latestTurnID == "turn-2")
    }

    @Test("종료된 세션은 늦은 turn 이벤트로 되살아나지 않는다")
    func endedSessionRejectsDelayedTurnEvents() {
        let started = reduce(
            sessions: [:],
            event: makeEvent(kind: .turnStarted, turnID: "turn-1", occurredAt: date(10))
        )
        let ended = reduce(
            sessions: started,
            event: makeEvent(kind: .sessionEnded, eventID: "ended-1", occurredAt: date(30))
        )

        for kind in [SpiritEvent.Kind.turnStarted, .turnStopped, .needsInput] {
            let result = reduce(
                sessions: ended,
                event: makeEvent(kind: kind, turnID: "turn-1", occurredAt: date(20))
            )

            #expect(result["session-1"]?.status == .ended)
        }
    }

    @Test("명시적인 sessionStarted는 종료 경계를 새 세션으로 전환한다")
    func sessionStartedBeginsNewGenerationAfterEnd() {
        let ended = reduce(
            sessions: [:],
            event: makeEvent(kind: .sessionEnded, eventID: "ended-1", occurredAt: date(30))
        )

        let restarted = reduce(
            sessions: ended,
            event: makeEvent(kind: .sessionStarted, eventID: "started-2", occurredAt: date(40))
        )

        #expect(restarted["session-1"]?.status == .idle)
    }

    @Test("종료 시각보다 과거 또는 같은 sessionStarted는 종료 경계를 해제하지 않는다")
    func sessionStartedAtOrBeforeEndKeepsSessionEnded() {
        let ended = reduce(
            sessions: [:],
            event: makeEvent(kind: .sessionEnded, eventID: "ended-1", occurredAt: date(30))
        )

        let staleStart = reduce(
            sessions: ended,
            event: makeEvent(kind: .sessionStarted, eventID: "started-old", occurredAt: date(20))
        )
        let simultaneousStart = reduce(
            sessions: ended,
            event: makeEvent(kind: .sessionStarted, eventID: "started-same", occurredAt: date(30))
        )

        #expect(staleStart["session-1"]?.status == .ended)
        #expect(simultaneousStart["session-1"]?.status == .ended)
    }

    @Test("수락된 새 세대보다 이전인 sessionEnded와 turn 이벤트는 새 세대를 바꾸지 않는다")
    func newGenerationRejectsPreviousGenerationEvents() {
        let ended = reduce(
            sessions: [:],
            event: makeEvent(kind: .sessionEnded, eventID: "ended-old", occurredAt: date(30))
        )
        let restarted = reduce(
            sessions: ended,
            event: makeEvent(kind: .sessionStarted, eventID: "started-new", occurredAt: date(40))
        )
        let staleTurn = reduce(
            sessions: restarted,
            event: makeEvent(kind: .turnStarted, eventID: "turn-old", turnID: "turn-old", occurredAt: date(20))
        )
        let currentTurn = reduce(
            sessions: restarted,
            event: makeEvent(kind: .turnStarted, eventID: "turn-new", turnID: "turn-new", occurredAt: date(50))
        )
        let staleEnd = reduce(
            sessions: currentTurn,
            event: makeEvent(kind: .sessionEnded, eventID: "ended-old-replayed", occurredAt: date(30))
        )

        #expect(restarted["session-1"]?.status == .idle)
        #expect(staleTurn["session-1"]?.status == .idle)
        #expect(staleEnd["session-1"]?.status == .working)
    }

    @Test("새 세대 시작과 같은 시각의 turn 이벤트는 결정적으로 거절한다")
    func sameTimestampEventAtGenerationStartIsRejected() {
        let ended = reduce(
            sessions: [:],
            event: makeEvent(kind: .sessionEnded, eventID: "ended-old", occurredAt: date(30))
        )
        let restarted = reduce(
            sessions: ended,
            event: makeEvent(kind: .sessionStarted, eventID: "started-new", occurredAt: date(40))
        )
        let simultaneousTurn = reduce(
            sessions: restarted,
            event: makeEvent(kind: .turnStarted, eventID: "turn-same", turnID: "turn-new", occurredAt: date(40))
        )

        #expect(simultaneousTurn["session-1"]?.status == .idle)
    }

    private func makeEvent(
        kind: SpiritEvent.Kind,
        eventID: String = "event-1",
        sessionID: String = "session-1",
        turnID: String? = nil,
        occurredAt: Date? = nil
    ) -> SpiritEvent {
        SpiritEvent(
            eventID: eventID,
            provider: "test",
            sessionID: sessionID,
            turnID: turnID,
            kind: kind,
            occurredAt: occurredAt ?? receivedAt,
            receivedAt: receivedAt,
            source: "test",
            sourceVersion: "1.0"
        )
    }

    private func reducedStatus(
        kind: SpiritEvent.Kind,
        from status: SessionState.Status,
        turnID: String? = nil
    ) -> SessionState.Status? {
        reduce(
            sessions: ["session-1": SessionState(status: status)],
            event: makeEvent(kind: kind, turnID: turnID)
        )["session-1"]?.status
    }

    private func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + offset)
    }
}
