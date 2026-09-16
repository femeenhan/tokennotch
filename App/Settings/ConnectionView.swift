import SwiftUI
import SpiritCore

struct ConnectionView: View {
    @ObservedObject var model: CompanionModel
    @State private var provider: SpiritProvider = .codex
    @State private var preview: String?
    @State private var installationMessage: String?
    private var bridgeURL: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/SpiritBridge") }
    private var command: String { ProviderHookInstaller.command(bridgeURL: bridgeURL, provider: provider) }
    private var hooksURL: URL { ProviderHookInstaller.configurationURL(for: provider) }

    var body: some View {
        Section("CLI 연결") {
            Picker("제공자", selection: $provider) {
                ForEach(SpiritProvider.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }.onChange(of: provider) { _, _ in preview = nil; installationMessage = nil }
            if provider == .codex {
                LabeledContent("감지한 버전", value: model.codexCLI?.version ?? "감지되지 않음")
            }
            let stream = model.stream(for: provider)
            let presentation = SpiritPresentation(state: stream.state)
            LabeledContent("현재 정령 상태", value: stream.sessions.isEmpty ? "관측 대기" : presentation.label)
            Text(stream.sessions.isEmpty ? "아직 작업 이벤트를 수신하지 않았습니다. 연결 설정과 CLI 실행 상태를 확인하세요." : model.providerStatus(for: provider))
                .font(.caption).foregroundStyle(.secondary)
            Text("CLI 훅으로 작업 상태를 연결합니다. 웹 채팅과 데스크톱 앱은 지원하지 않습니다.")
                .font(.caption).foregroundStyle(.secondary)
            if provider == .codex, let cli = model.codexCLI, cli.version != "0.154.0" {
                Text("이 CLI 버전은 검증하지 않았습니다. 이벤트 형식이 다를 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(model.providerStatus(for: provider)).font(.caption)
            if provider == .codex {
                Text(model.hookStatus).font(.caption).accessibilityLabel(model.hookStatus)
                Button("CLI 다시 감지") { Task { await model.detectCodex() } }
            }
            Button("추가할 설정 미리보기") {
                if let data = try? ProviderHookInstaller.install(in: Data("{}".utf8), command: command, provider: provider) {
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
            Text(connectionHint).font(.caption).foregroundStyle(.secondary)
            Text("프롬프트·명령·패치·응답·대화 기록은 수집하지 않습니다. 앱이 꺼져 있을 때의 이벤트는 복구하지 않습니다.")
                .font(.caption).foregroundStyle(.secondary)
            if let installationMessage { Text(installationMessage).font(.caption).textSelection(.enabled) }
        }
    }

    private var connectionHint: String {
        switch provider {
        case .codex: "설치 후 Codex CLI의 /hooks에서 내용을 확인하고 직접 신뢰를 승인해 주세요. 설정 변경 후 다시 승인이 필요할 수 있습니다."
        case .claude: "설치 후 Claude Code 세션을 다시 시작해 주세요. 실제 작업 이벤트 수신 여부를 확인해야 합니다."
        case .gemini: "설치 후 Gemini CLI 세션을 다시 시작해 주세요. 실제 작업 이벤트 수신 여부를 확인해야 합니다."
        case .grok: "Grok CLI 훅 연결은 실험적입니다. 사용 중인 CLI가 이 설정을 읽는지 확인해야 합니다."
        }
    }

    private func write(installing: Bool) {
        do {
            let backup = try ProviderHookInstaller.write(to: hooksURL, command: command, installing: installing, provider: provider)
            installationMessage = installing ? "\(provider.displayName) 연결 설정을 저장했습니다. " + connectionHint : "이 앱 경로의 빌드정령 hook만 제거했습니다."
            if let backup { installationMessage? += " 백업: \(backup.lastPathComponent)" }
        } catch {
            installationMessage = "설정을 변경하지 못했습니다. 설정 파일 형식과 폴더 권한을 확인해 주세요."
        }
    }
}
