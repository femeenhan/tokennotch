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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                .frame(width: 384, height: 384)
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
                Text("남은 한도")
                Slider(value: $quota, in: 0...100, step: 1)
                Text("\(Int(quota))%").monospacedDigit().frame(width: 44)
            }
            .disabled(playingSequence)
            HStack {
                Toggle("불꽃 충전", isOn: $charging)
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
                Button(playingSequence ? "이어보기 중지" : "정령 동작 이어보기") {
                    if playingSequence { stopSequence() } else { playSequence() }
                }
                Spacer()
                Text("실제 작업 상태에는 영향을 주지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onChange(of: selectedState) { _, _ in speechDismissed = false; updateScene() }
        .onChange(of: charging) { _, value in
            if value { scene.beginPress() } else { _ = scene.endPress(registerTap: false) }
        }
        .onChange(of: quota) { _, _ in updateScene() }
        .onChange(of: reduceMotion) { _, _ in updateScene() }
        .onChange(of: systemReduceMotion) { _, _ in updateScene() }
        .onChange(of: slowMotion) { _, value in scene.playbackRate = value ? 0.5 : 1 }
        .onAppear { scene.isPaused = false; updateScene() }
        .onDisappear { stopSequence(); _ = scene.endPress(registerTap: false); scene.isPaused = true }
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

    private func stopSequence() {
        sequence?.cancel()
        sequence = nil
        playingSequence = false
        selectedState = "idle"
    }

    private func playSequence() {
        playingSequence = true
        selectedState = "idle"
        sequence = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(3))
                selectedState = "working"
                try await Task.sleep(for: .seconds(slowMotion ? 12 : 6))
                selectedState = "idle"
                try await Task.sleep(for: .seconds(slowMotion ? 4 : 2))
                for state in ["completed", "attention", "error", "greeting", "sleeping", "idle"] {
                    selectedState = state
                    try await Task.sleep(for: .seconds(2))
                }
                quota = 5
                try await Task.sleep(for: .seconds(3))
                quota = 100
                try await Task.sleep(for: .seconds(3))
                playingSequence = false
                sequence = nil
            } catch { /* Closing the window or stopping cancels the sequence. */ }
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
