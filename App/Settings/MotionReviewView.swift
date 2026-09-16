import SwiftUI
import SpriteKit
import SpiritCore

/// A separate scene: previewing a motion never injects fake events into Codex sessions.
struct MotionReviewView: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var scene = SpiritScene(size: CGSize(width: 384, height: 384))
    @State private var working = false
    @State private var slowMotion = false
    @State private var reduceMotion = false
    @State private var sequence: Task<Void, Never>?
    @State private var playingSequence = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("기본 동작 확인").font(.title2.weight(.semibold))
                Text("실제 캐릭터와 같은 렌더러입니다. Codex 연결 없이 확인할 수 있습니다.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.allowsTransparency])
                .frame(width: 384, height: 384)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .underPageBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(working ? "팔과 망치를 움직여 작업하는 정령" : "불꽃이 일렁이며 눈을 깜빡이는 정령")
            Picker("확인할 동작", selection: $working) {
                Text("대기").tag(false)
                Text("망치질").tag(true)
            }
            .pickerStyle(.segmented)
            .disabled(playingSequence)
            HStack {
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
                : "대기로 바꾸면 진행 중인 망치질을 마무리하고 쉽니다. 불꽃·눈·팔이 따로 움직이는지 확인해 주세요.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(height: 32, alignment: .topLeading)
            HStack {
                Button(playingSequence ? "이어보기 중지" : "기본 동작 이어보기") {
                    if playingSequence { stopSequence() } else { playSequence() }
                }
                Spacer()
                Text("실제 작업 상태에는 영향을 주지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onChange(of: working) { _, _ in updateScene() }
        .onChange(of: reduceMotion) { _, _ in updateScene() }
        .onChange(of: systemReduceMotion) { _, _ in updateScene() }
        .onChange(of: slowMotion) { _, value in scene.playbackRate = value ? 0.5 : 1 }
        .onAppear { scene.isPaused = false; updateScene() }
        .onDisappear { stopSequence(); scene.isPaused = true }
    }

    private func updateScene() {
        scene.render(state: working ? .working : .idle, reduceMotion: reduceMotion || systemReduceMotion)
    }

    private func stopSequence() {
        sequence?.cancel()
        sequence = nil
        playingSequence = false
        working = false
    }

    private func playSequence() {
        playingSequence = true
        working = false
        sequence = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(3))
                working = true
                try await Task.sleep(for: .seconds(slowMotion ? 12 : 6))
                working = false
                try await Task.sleep(for: .seconds(slowMotion ? 4 : 2))
                playingSequence = false
                sequence = nil
            } catch { /* Closing the window or stopping cancels the sequence. */ }
        }
    }
}
