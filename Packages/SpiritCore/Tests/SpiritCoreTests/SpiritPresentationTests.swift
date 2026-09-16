import Testing
@testable import SpiritCore

@Suite("Spirit presentation")
struct SpiritPresentationTests {
    @Test func everyRuntimeStateHasDistinctVisibleFeedback() {
        let presentations: [(state: SpiritState, presentation: SpiritPresentation)] = [
            (.idle, SpiritPresentation(state: .idle)),
            (.working, SpiritPresentation(state: .working)),
            (.attention, SpiritPresentation(state: .attention)),
            (.completed, SpiritPresentation(state: .completed)),
            (.error, SpiritPresentation(state: .error)),
            (.greeting, SpiritPresentation(state: .greeting)),
            (.sleeping, SpiritPresentation(state: .sleeping))
        ]

        #expect(Set(presentations.map(\.presentation.label)).count == presentations.count)
        #expect(Set(presentations.map(\.presentation.motion)).count == presentations.count)
        #expect(presentations.first { $0.state == .idle }?.presentation.hint == "Codex에서 프롬프트를 보내면 반응합니다.")
        #expect(presentations.first { $0.state == .working }?.presentation.label == "작업 중")
        #expect(presentations.first { $0.state == .attention }?.presentation.label == "확인 필요")
    }

}
