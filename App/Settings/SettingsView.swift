import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: CompanionModel
    @State private var focusMinutes = 25
    @State private var reminderDate = Date().addingTimeInterval(3600)
    @State private var reminderMessage = ""

    var body: some View {
        Form {
            ConnectionView(model: model)
            Section("함께하기") {
                Toggle("캐릭터 표시", isOn: $model.isShown)
                LabeledContent("캐릭터 크기", value: "\(Int(model.size)) pt")
                Slider(value: $model.size, in: 80...192, step: 1) { Text("캐릭터 크기") }
                Toggle("전체 화면 앱에서 숨기기", isOn: $model.hideInFullScreen)
                Text("전체 화면 감지는 일부 앱에서 정확하지 않을 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("알림 소리", isOn: $model.soundEnabled)
                Text("몸통 중앙을 드래그하면 위치가 저장됩니다. 클릭하면 남은 사용량 말풍선을 엽니다. 정령 메뉴는 캐릭터 우클릭 또는 메뉴 막대 불꽃에서 엽니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("집중 타이머") {
                Stepper("\(focusMinutes)분", value: $focusMinutes, in: 1...180)
                if let timer = model.focusTimer, timer.deliveredAt == nil {
                    LabeledContent("종료 시각") { Text(timer.deadline, style: .time) }
                    Button("타이머 취소") { model.cancelFocus() }
                } else {
                    Button("집중 시작") { model.startFocus(minutes: focusMinutes) }
                }
                Text("한 번 완료하면 종료됩니다. 자동으로 반복하지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("사용량과 기록") {
                Toggle("계정 한도 자동 조회", isOn: $model.quotaMonitoringEnabled)
                    .onChange(of: model.quotaMonitoringEnabled) { _, enabled in if enabled { model.refreshQuota(force: true) } }
                Text("계정 한도·리셋 시각·일별 토큰을 약 1분 간격으로 조회합니다. 한도 추세는 8일, 제공된 일별 기록은 최대 26주 보관합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(model.usageStatus).font(.caption).foregroundStyle(.secondary)
                Button("사용량 로그 연결…") { model.selectUsageLog() }
                if model.selectedUsageFilename != nil { Button("토큰 수집 중지") { model.stopUsageCollection() } }
                DisclosureGroup("기술 진단") {
                    Text(model.hookStatus).font(.caption).foregroundStyle(.secondary)
                    Button("진단 기록 JSON 내보내기…") { model.exportDashboard() }
                }
            }
            Section("리마인더") {
                DatePicker("알림 시각", selection: $reminderDate, displayedComponents: [.date, .hourAndMinute])
                TextField("알림 문구", text: $reminderMessage)
                Button("리마인더 저장") {
                    if model.addReminder(dueAt: reminderDate, message: reminderMessage) { reminderMessage = "" }
                }
                Text("앱이 실행 중일 때 화면 알림을 표시합니다. 앱 종료 중에는 전달되지 않으며, 지난 알림은 다음 실행 때 한 번 표시합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(model.reminders.filter { $0.deliveredAt == nil }) { reminder in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(reminder.message)
                            Text(reminder.dueAt, format: .dateTime.month().day().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("삭제") { model.removeReminder(id: reminder.id) }
                    }
                }
            }
            if let error = model.errorMessage { Text(error).foregroundStyle(.red).accessibilityLabel(error) }
            if let alert = model.latestAlert {
                Section("확인하지 않은 알림 (\(model.pendingAlertCount)개)") { Text(alert).textSelection(.enabled) }
            }
            Section {
                Text("정령은 CLI 시작 때 인사하고, 작업·확인 요청·완료·오류 상태마다 다른 움직임과 상태표시를 보여줍니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 690)
    }
}
