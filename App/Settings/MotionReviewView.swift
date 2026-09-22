import SwiftUI
import SpriteKit
import SpiritCore

/// A separate scene: previewing a motion never injects fake events into Codex sessions.
struct MotionReviewView: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var scene = SpiritScene(size: CGSize(width: 384, height: 384))
    @State private var selectedState = "idle"
    @State private var speechDismissed = false
    @State private var quota = 100.0
    @State private var charging = false
    @State private var slowMotion = false
    @State private var reduceMotion = false
    @State private var sequence: Task<Void, Never>?
    @State private var playingSequence = false
    @State private var selectedScenario: ReviewScenario = .gaze
    @State private var sequenceID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("정령 동작 확인").font(.title2.weight(.semibold))
                Text("실제 캐릭터와 같은 렌더러입니다. Codex 연결 없이 확인할 수 있습니다.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ZStack {
                if let message = SpeechPanel.message(for: previewState), !speechDismissed {
                    PreviewSpeechBubble(message: message) { speechDismissed = true }
                        .frame(width: SpeechPanel.size.width, height: SpeechPanel.size.height)
                }
            }
            .frame(height: SpeechPanel.size.height)
            .frame(maxWidth: .infinity, alignment: .trailing)
            SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.allowsTransparency])
                .frame(width: 288, height: 288)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .underPageBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(SpiritPresentation(state: previewState).label)
            Picker("확인할 동작", selection: $selectedState) {
                Text("대기").tag("idle")
                Text("망치질").tag("working")
                Text("확인 필요").tag("attention")
                Text("완료").tag("completed")
                Text("오류").tag("error")
                Text("인사").tag("greeting")
                Text("휴식").tag("sleeping")
            }
            .disabled(playingSequence)
            HStack {
                Button("망치 던져 받기") { playHammerTrick(.toss) }
                Button("망치 불러 잡기") { playHammerTrick(.recall) }
            }
            .disabled(playingSequence || reduceMotion || systemReduceMotion)
            HStack {
                Text("남은 한도")
                Slider(value: $quota, in: 0...100, step: 1)
                Text("\(Int(quota))%").monospacedDigit().frame(width: 44)
            }
            .disabled(playingSequence)
            HStack {
                Toggle("불꽃 충전", isOn: $charging)
                    .disabled(playingSequence)
                Toggle("느리게 보기", isOn: $slowMotion)
                Spacer()
                Toggle("동작 줄이기", isOn: Binding(
                    get: { reduceMotion || systemReduceMotion },
                    set: { reduceMotion = $0 }))
                    .disabled(systemReduceMotion)
            }
            .toggleStyle(.checkbox)
            Text(systemReduceMotion || reduceMotion
                ? "동작 줄이기가 적용되어 정지한 상태로 표시합니다."
                : "정령 주변에서 커서를 움직이거나 머리를 쓰다듬어 보세요. 한도를 올리면 회복하고, 오래 대기하면 졸기 시작합니다.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(height: 32, alignment: .topLeading)
            HStack {
                Picker("장면", selection: $selectedScenario) {
                    ForEach(ReviewScenario.allCases) { scenario in
                        Text(scenario.title).tag(scenario)
                    }
                }
                Button("다시 재생") { playSequence() }
                    .disabled(reduceMotion || systemReduceMotion)
                Button("중지") { stopSequence() }
                    .disabled(!playingSequence)
            }
            Text(playingSequence ? selectedScenario.detail : "실제 작업 상태에는 영향을 주지 않습니다.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 520)
        .onChange(of: selectedState) { _, _ in speechDismissed = false; updateScene() }
        .onChange(of: charging) { _, value in
            if value { scene.beginPress() } else { _ = scene.endPress(registerTap: false) }
        }
        .onChange(of: quota) { _, _ in updateScene() }
        .onChange(of: reduceMotion) { _, _ in motionPreferenceChanged() }
        .onChange(of: systemReduceMotion) { _, _ in motionPreferenceChanged() }
        .onChange(of: selectedScenario) { _, _ in
            if playingSequence { playSequence() }
            else if reduceMotion || systemReduceMotion { showStaticScenario() }
        }
        .onChange(of: slowMotion) { _, value in scene.playbackRate = value ? 0.5 : 1 }
        .onAppear { scene.isPaused = false; updateScene() }
        .onDisappear {
            stopSequence()
            scene.cancelInteractions()
            scene.isPaused = true
        }
    }

    private var previewState: SpiritState {
        switch selectedState {
        case "working": .working
        case "attention": .attention
        case "completed": .completed
        case "error": .error
        case "greeting": .greeting
        case "sleeping": .sleeping
        default: .idle
        }
    }

    private func updateScene() {
        scene.remainingQuota = quota / 100
        scene.render(state: previewState, reduceMotion: reduceMotion || systemReduceMotion)
    }

    private func playHammerTrick(_ trick: HammerTrick) {
        guard !playingSequence, !reduceMotion, !systemReduceMotion,
              !scene.isHammerTrickPlaying else { return }
        charging = false
        scene.cancelHammerTrick()
        _ = scene.endPress(registerTap: false)
        scene.isPaused = true
        // Each preview starts neutral: a fading charge or recovering strike must
        // neither silently reject this button nor overlap the flying hammer.
        scene = SpiritScene(size: CGSize(width: 384, height: 384))
        scene.automaticallyPlaysHammerTricks = false
        scene.playbackRate = slowMotion ? 0.5 : 1
        selectedState = "idle"
        updateScene()
        scene.playHammerTrick(trick)
    }

    private func stopSequence() {
        sequenceID = UUID()
        sequence?.cancel()
        sequence = nil
        playingSequence = false
        scene.cancelInteractions()
        scene.setPointer(x: nil, y: nil)
        scene.tracksPointer = true
        scene.automaticallyPlaysHammerTricks = true
        charging = false
    }

    private func motionPreferenceChanged() {
        let wasPlaying = playingSequence
        stopSequence()
        if wasPlaying || reduceMotion || systemReduceMotion { showStaticScenario() }
        else { updateScene() }
    }

    private func showStaticScenario() {
        selectedState = selectedScenario.staticState
        updateScene()
    }

    private func playSequence() {
        stopSequence()
        guard !reduceMotion, !systemReduceMotion else { showStaticScenario(); return }
        scene.isPaused = true
        let target = SpiritScene(size: CGSize(width: 384, height: 384))
        target.tracksPointer = false
        target.automaticallyPlaysHammerTricks = false
        target.playbackRate = slowMotion ? 0.5 : 1
        target.remainingQuota = quota / 100
        scene = target
        selectedState = "idle"
        speechDismissed = false
        target.render(state: .idle, reduceMotion: false)
        playingSequence = true
        let identity = sequenceID
        let scenario = selectedScenario
        sequence = Task { @MainActor in
            // Capture the target scene. A canceled task can never drive its replacement.
            @MainActor func state(_ name: String, _ value: SpiritState) {
                selectedState = name
                target.render(state: value, reduceMotion: false)
            }
            do {
                switch scenario {
                case .gaze:
                    target.setPointer(x: 24, y: 32)
                    try await playTime(2, scene: target)
                    target.setPointer(x: nil, y: nil)
                    try await playTime(1, scene: target)
                case .petting:
                    try await playTime(2, scene: target) { time in
                        target.setPointer(x: 9 * sin(time * 4), y: 45,
                                          velocityX: 36 * cos(time * 4))
                    }
                    target.setPointer(x: nil, y: nil)
                    try await playTime(1.2, scene: target)
                case .drag:
                    target.setDragging(true)
                    try await playTime(1, scene: target) { time in
                        target.setDragVelocity(x: 180 * sin(time * 5), y: 60 * cos(time * 5))
                    }
                    target.setDragging(false)
                    try await playTime(1.2, scene: target)
                case .work:
                    state("working", .working)
                    try await playTime(8, scene: target)
                case .completion:
                    state("working", .working)
                    try await playTime(2.2, scene: target)
                    state("completed", .completed)
                    try await playTime(4.2, scene: target)
                case .ember:
                    _ = target.playEmberPlay()
                    try await playTime(3.3, scene: target)
                case .attention:
                    state("attention", .attention)
                    try await playTime(2.5, scene: target)
                    state("working", .working)
                    try await playTime(1, scene: target)
                    state("error", .error)
                    try await playTime(2.5, scene: target)
                case .sleep:
                    state("sleeping", .sleeping)
                    try await playTime(3.5, scene: target)
                    state("idle", .idle)
                    target.setPointer(x: 20, y: 28)
                    try await playTime(0.6, scene: target)
                    target.setPointer(x: nil, y: nil)
                }
                try Task.checkCancellation()
                guard sequenceID == identity else { return }
                target.tracksPointer = true
                target.automaticallyPlaysHammerTricks = true
                playingSequence = false
                sequence = nil
            } catch {
                // Cancellation cleanup belongs to stopSequence, never an old task.
            }
        }
    }

    /// Uses the renderer's clamped playback clock, including changes made mid-scene.
    @MainActor
    private func playTime(_ duration: Double, scene target: SpiritScene,
                          input: (Double) -> Void = { _ in }) async throws {
        let clock = ContinuousClock()
        var previous = clock.now
        var elapsed = 0.0
        input(0)
        while elapsed < duration {
            try await Task.sleep(for: .seconds(1.0 / 60))
            try Task.checkCancellation()
            let now = clock.now
            let components = previous.duration(to: now).components
            let delta = Double(components.seconds) + Double(components.attoseconds) / 1e18
            previous = now
            elapsed += min(min(delta, 1.0 / 15) * target.playbackRate, 1.0 / 20)
            input(min(elapsed, duration))
        }
    }

}


private struct PreviewSpeechBubble: NSViewRepresentable {
    let message: String
    let dismiss: () -> Void

    func makeNSView(context: Context) -> SpiritSpeechView {
        SpiritSpeechView(frame: CGRect(origin: .zero, size: SpeechPanel.size))
    }

    func updateNSView(_ view: SpiritSpeechView, context: Context) {
        view.message = message
        view.tailOnLeft = true
        view.dismiss = dismiss
    }
}

private enum ReviewScenario: String, CaseIterable, Identifiable {
    case gaze, petting, drag, work, completion, ember, attention, sleep

    var id: Self { self }
    var title: String {
        switch self {
        case .gaze: "1 · 나 불렀어?"
        case .petting: "2 · 조금만 더"
        case .drag: "3 · 어디 가?"
        case .work: "4 · 만들어볼까"
        case .completion: "5 · 다 만들었어"
        case .ember: "6 · 잡았다… 어?"
        case .attention: "7 · 확인 요청 / 오류"
        case .sleep: "8 · 쉬었다 할게"
        }
    }
    var staticState: String {
        switch self {
        case .work: "working"
        case .completion: "completed"
        case .attention: "attention"
        case .sleep: "sleeping"
        default: "idle"
        }
    }
    var detail: String {
        switch self {
        case .gaze: "커서 발견 → 응시 → 정면으로 돌아오기"
        case .petting: "2초 쓰다듬기 → 만족한 여운 → 눈 뜨기"
        case .drag: "들어 올리기 → 이동 → 착지와 망치 고쳐 잡기"
        case .work: "준비 → 가벼운 두 번 → 확인 → 힘주는 한 번"
        case .completion: "작업 → 마지막 타격 → 결과 확인 → 조용한 자랑"
        case .ember: "불씨 발견 → 손 뻗기 → 받기 → 놓아 보내기"
        case .attention: "확인 요청을 기다린 뒤 작업 중 오류와 비교합니다."
        case .sleep: "하품 → 편안한 수면 → 커서를 보고 깨어나기"
        }
    }
}
