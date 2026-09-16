public struct SpiritPresentation: Equatable, Sendable {
    public enum Motion: Equatable, Hashable, Sendable {
        case breathe
        case forge
        case requestAttention
        case celebrate
        case shake
        case greet
        case sleep
    }

    public let label: String
    public let hint: String
    public let motion: Motion

    public init(state: SpiritState) {
        switch state {
        case .idle:
            label = "대기 중"
            hint = "Codex에서 프롬프트를 보내면 반응합니다."
            motion = .breathe
        case .working:
            label = "작업 중"
            hint = "Codex가 답변이나 도구 실행을 진행하고 있습니다."
            motion = .forge
        case .attention:
            label = "확인 필요"
            hint = "Codex CLI에서 권한 요청이나 질문을 확인하세요."
            motion = .requestAttention
        case .completed:
            label = "작업 완료"
            hint = "Codex 세션이 종료되었습니다."
            motion = .celebrate
        case .error:
            label = "연결 오류"
            hint = "Codex CLI 연결 상태를 확인하세요."
            motion = .shake
        case .greeting:
            label = "반가워요"
            hint = "빌드정령이 연결되었습니다."
            motion = .greet
        case .sleeping:
            label = "쉬는 중"
            hint = "화면이나 세션이 다시 활성화되기를 기다립니다."
            motion = .sleep
        }
    }
}
