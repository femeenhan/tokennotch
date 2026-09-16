import SwiftUI
import SpiritCore

struct ConnectionView: View {
    @ObservedObject var model: CompanionModel
    @State private var preview: String?
    @State private var installationMessage: String?
    private var bridgeURL: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/SpiritBridge") }
    private var command: String { HookInstaller.command(bridgeURL: bridgeURL) }
    private var hooksURL: URL {
        let base = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        return base.appendingPathComponent("hooks.json")
    }

    var body: some View {
        Section("Codex CLI 연결") {
            LabeledContent("감지한 버전", value: model.codexCLI?.version ?? "감지되지 않음")
            let presentation = SpiritPresentation(state: model.spiritState)
            LabeledContent("현재 정령 상태", value: presentation.label)
            Text(presentation.hint)
                .font(.caption).foregroundStyle(.secondary)
            Text("CLI 0.154.0 로컬 베타입니다. Codex 데스크톱 앱과 IDE 확장은 지원하지 않습니다.")
                .font(.caption).foregroundStyle(.secondary)
            if let cli = model.codexCLI, cli.version != "0.154.0" {
                Text("이 CLI 버전은 검증하지 않았습니다. 이벤트 형식이 다를 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(model.hookStatus).font(.caption).accessibilityLabel(model.hookStatus)
            Button("CLI 다시 감지") { Task { await model.detectCodex() } }
            Button("추가할 설정 미리보기") {
                if let data = try? HookInstaller.install(in: Data("{}".utf8), command: command) {
                    preview = String(decoding: data, as: UTF8.self)
                }
            }
            if let preview {
                Text("아래 항목을 기존 설정에 병합합니다. 다른 hooks는 보존합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                ScrollView([.horizontal, .vertical]) {
                    Text(preview).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }.frame(height: 150)
                Text(hooksURL.path).font(.caption).textSelection(.enabled)
                HStack {
                    Button("연결 설정 설치") { write(installing: true) }
                        .disabled(!FileManager.default.isExecutableFile(atPath: bridgeURL.path))
                    Button("빌드정령 연결 제거") { write(installing: false) }
                }
            }
            Text("설치 후 Codex CLI의 /hooks에서 내용을 확인하고 직접 신뢰를 승인해 주세요. 설정 변경 후 다시 승인이 필요할 수 있습니다.")
                .font(.caption).foregroundStyle(.secondary)
            Text("프롬프트·명령·패치·응답·대화 기록은 수집하지 않습니다. 앱이 꺼져 있을 때의 이벤트는 복구하지 않습니다.")
                .font(.caption).foregroundStyle(.secondary)
            if let installationMessage { Text(installationMessage).font(.caption).textSelection(.enabled) }
        }
    }

    private func write(installing: Bool) {
        do {
            let backup = try HookInstaller.write(to: hooksURL, command: command, installing: installing)
            installationMessage = installing ? "설정을 저장했습니다. CLI /hooks에서 신뢰를 승인해 주세요." : "이 앱 경로의 빌드정령 hook만 제거했습니다."
            if let backup { installationMessage? += " 백업: \(backup.lastPathComponent)" }
        } catch {
            installationMessage = "설정을 변경하지 못했습니다. hooks.json 형식과 폴더 권한을 확인해 주세요."
        }
    }
}
