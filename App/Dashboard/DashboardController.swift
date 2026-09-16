import AppKit
import SpiritCore
import UniformTypeIdentifiers

extension CompanionModel {
    func configureDashboard(at url: URL) {
        do {
            dashboardStore = try DashboardStore(url: url)
            refreshDashboard()
        } catch {
            dashboardLoading = false
            dashboardError = "기록 저장소를 열지 못했습니다. 캐릭터는 계속 동작합니다."
        }
    }

    func refreshDashboard() { performDashboardOperation { _ in } }

    func performDashboardOperation(_ operation: @escaping @Sendable (DashboardStore) async throws -> Void) {
        guard let store = dashboardStore else { return }
        let previous = dashboardWork
        dashboardWork = Task { [weak self] in
            await previous?.value
            do {
                try await operation(store)
                let snapshot = try await store.snapshot()
                self?.dashboard = snapshot
                self?.dashboardError = nil
            } catch {
                self?.dashboardError = "기록을 저장하거나 읽지 못했습니다. 캐릭터와 CLI는 계속 사용할 수 있습니다."
            }
            self?.dashboardLoading = false
        }
    }

    func registerDashboardProject() {
        let panel = NSOpenPanel()
        panel.title = "프로젝트 폴더 등록"
        panel.message = "폴더 경로만 등록합니다. 내부 파일을 스캔하지 않습니다."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        performDashboardOperation { store in
            _ = try await store.registerProject(path: url.path, name: url.lastPathComponent)
        }
    }

    func assignDashboardProject(sessionID: String, projectID: UUID?) {
        performDashboardOperation { store in try await store.assignProject(sessionID: sessionID, projectID: projectID) }
    }

    func selectUsageLog() {
        let consent = NSAlert()
        consent.messageText = "선택한 로그의 토큰 기록을 가져올까요?"
        consent.informativeText = "선택한 JSONL 파일의 기존 사용량과 이후 추가되는 기록을 읽습니다. 원문은 메모리에서 일시 해석하지만 프롬프트·응답·코드·명령은 저장하지 않습니다. 세션 ID·시각·모델·토큰 수만 로컬에 저장합니다. 폴더 전체 스캔이나 외부 전송은 하지 않습니다. 수집 중지는 새 읽기를 멈추며 이미 가져온 기록은 유지합니다."
        consent.addButton(withTitle: "파일 선택")
        consent.addButton(withTitle: "취소")
        guard consent.runModal() == .alertFirstButtonReturn else { return }
        let panel = NSOpenPanel()
        panel.title = "Codex 세션 JSONL 파일 선택"
        panel.allowedContentTypes = [.init(filenameExtension: "jsonl") ?? .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        usageToken = UUID()
        usageReader = UsageFileReader(url: url)
        selectedUsageFilename = url.lastPathComponent
        usageStatus = "선택한 로그 확인 중"
        pollUsage(force: true)
    }

    func stopUsageCollection() {
        usageToken = UUID()
        usageReader = nil
        selectedUsageFilename = nil
        usageStatus = "수집 중지됨 · 기존 기록 유지"
    }

    func pollUsage(force: Bool = false) {
        guard !usageReading, let reader = usageReader,
              force || Date().timeIntervalSince(lastUsagePoll) >= 5 else { return }
        usageReading = true
        lastUsagePoll = Date()
        let token = usageToken
        let previous = dashboardWork
        dashboardWork = Task { [weak self] in
            await previous?.value
            defer { self?.usageReading = false }
            do {
                let records = try await reader.read()
                guard let self, self.usageToken == token else { return }
                let unsupported = await reader.unsupportedRecordCount
                self.usageStatus = unsupported > 0 ? "일부 사용량 형식을 읽지 못했습니다" : "선택한 파일 관측 중"
                for record in records {
                    if self.pendingUsage[record.id].map({ $0.occurredAt > record.occurredAt }) != true {
                        self.pendingUsage[record.id] = record
                    }
                }
                if !self.pendingUsage.isEmpty, let store = self.dashboardStore {
                    do {
                        try await store.recordUsage(Array(self.pendingUsage.values))
                        self.pendingUsage.removeAll()
                        self.dashboard = try await store.snapshot()
                        self.dashboardError = nil
                    } catch {
                        self.usageStatus = "저장 실패 · 다음 관측에서 재시도"
                        self.dashboardError = "토큰 기록 저장 실패. 미저장 기록을 메모리에 보관하고 재시도합니다."
                    }
                } else if self.dashboard.usage.isEmpty {
                    self.usageStatus = "아직 읽을 수 있는 토큰 기록 없음"
                }
            } catch {
                guard let self, self.usageToken == token else { return }
                self.usageStatus = "로그 읽기 실패 · 파일 접근 또는 형식을 확인하세요"
            }
        }
    }

    func exportDashboard() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "build-spirit-records.json"
        panel.allowedContentTypes = [.json]
        panel.message = "보관 중인 전체 이벤트·프로젝트·토큰 메타데이터를 내보냅니다. 원문은 포함하지 않습니다."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        struct ProjectExport: Encodable { let id: UUID; let name: String; let path: String }
        struct AssignmentExport: Encodable { let sessionID: String; let projectID: UUID? }
        struct Export: Encodable {
            let exportedAt: Date
            let events: [SpiritEvent]
            let usage: [UsageRecord]
            let projects: [ProjectExport]
            let assignments: [AssignmentExport]
        }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(Export(exportedAt: Date(), events: dashboard.events, usage: dashboard.usage,
                projects: dashboard.projects.map { ProjectExport(id: $0.id, name: $0.name, path: $0.path) },
                assignments: dashboard.sessions.map { AssignmentExport(sessionID: $0.id, projectID: $0.projectID) }))
                .write(to: url, options: .atomic)
        } catch { dashboardError = "내보내기 파일을 저장하지 못했습니다." }
    }
}
