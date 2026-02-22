import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showClearConfirm = false
    @State private var showDeleteAllConfirm = false
    @State private var dailyCallEnabled = UserDefaults.standard.bool(forKey: "dailyCallEnabled")
    @State private var dailyCallRandom = UserDefaults.standard.bool(forKey: "dailyCallRandom")
    @State private var dailyCallTime = {
        let hour = UserDefaults.standard.integer(forKey: "dailyCallHour")
        let minute = UserDefaults.standard.integer(forKey: "dailyCallMinute")
        if hour == 0 && minute == 0 && !UserDefaults.standard.bool(forKey: "dailyCallEnabled") {
            // 기본값: 오후 9시
            var components = DateComponents()
            components.hour = 21
            components.minute = 0
            return Calendar.current.date(from: components) ?? Date()
        }
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }()
    
    var body: some View {
        NavigationStack {
            List {
                // MARK: - Companion Selection
                Section("내 친구 선택") {
                    ForEach(CompanionType.allCases) { type in
                        Button {
                            viewModel.companion = type
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: type == .on
                                                    ? [Color.orange.opacity(0.6), Color.pink.opacity(0.4)]
                                                    : [Color.indigo.opacity(0.6), Color.blue.opacity(0.4)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 50, height: 50)
                                    Text(type.emoji)
                                        .font(.system(size: 24))
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(type.displayName)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text(type.description)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if viewModel.companion == type {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                        .font(.system(size: 22))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                // MARK: - Memories
                Section("\(viewModel.companionName)이 기억하고 있는 것") {
                    if viewModel.memories.isEmpty {
                        Text("아직 기억이 없어요. 대화하면서 자연스럽게 기억해갈게요.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.memories) { memory in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(memory.key)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Text(memory.value)
                                    .font(.system(size: 14))
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                
                // MARK: - Stats
                Section("대화 통계") {
                    HStack {
                        Label("총 대화", systemImage: "message.fill")
                        Spacer()
                        Text("\(viewModel.messages.count)개")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Label("함께한 날", systemImage: "calendar")
                        Spacer()
                        Text(daysSinceFirst())
                            .foregroundStyle(.secondary)
                    }
                }
                
                // MARK: - Daily Call Notification
                Section {
                    Toggle(isOn: $dailyCallEnabled) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("매일 전화 받기")
                                Text("\(viewModel.companionName)이가 매일 전화해요")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "phone.arrow.down.left.fill")
                        }
                    }
                    .onChange(of: dailyCallEnabled) { _, enabled in
                        UserDefaults.standard.set(enabled, forKey: "dailyCallEnabled")
                        if enabled {
                            Task {
                                let granted = await NotificationService.shared.requestPermission()
                                if granted {
                                    scheduleDailyNotification()
                                } else {
                                    dailyCallEnabled = false
                                }
                            }
                        } else {
                            NotificationService.shared.cancelDailyCall()
                        }
                    }

                    if dailyCallEnabled {
                        Picker("시간 설정", selection: $dailyCallRandom) {
                            Text("아무때나").tag(true)
                            Text("시간 지정").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: dailyCallRandom) { _, isRandom in
                            UserDefaults.standard.set(isRandom, forKey: "dailyCallRandom")
                            scheduleDailyNotification()
                        }

                        if !dailyCallRandom {
                            DatePicker("시간", selection: $dailyCallTime, displayedComponents: .hourAndMinute)
                                .onChange(of: dailyCallTime) { _, newTime in
                                    let components = Calendar.current.dateComponents([.hour, .minute], from: newTime)
                                    UserDefaults.standard.set(components.hour ?? 21, forKey: "dailyCallHour")
                                    UserDefaults.standard.set(components.minute ?? 0, forKey: "dailyCallMinute")
                                    NotificationService.shared.scheduleDailyCall(hour: components.hour ?? 21, minute: components.minute ?? 0)
                                }
                        } else {
                            Text("매일 오전 10시 ~ 밤 11시 사이 랜덤으로 연락해요")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }

                        Button("테스트 알림 (5초 후)") {
                            Task {
                                let granted = await NotificationService.shared.requestPermission()
                                if granted {
                                    NotificationService.shared.scheduleTestCall(after: 5)
                                }
                            }
                        }
                        .font(.system(size: 14))
                        .foregroundStyle(.blue)
                    }
                } header: {
                    Text("수신 전화")
                }

                // MARK: - Phase Info
                Section("기능 안내") {
                    Label {
                        VStack(alignment: .leading) {
                            Text("텍스트 채팅")
                            Text("Gemini 2.0 Flash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    
                    Label {
                        VStack(alignment: .leading) {
                            Text("음성 채팅")
                            Text("Apple Speech / TTS")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    
                    Label {
                        VStack(alignment: .leading) {
                            Text("영상 메시지")
                            Text("Phase 3 - 준비 중")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "circle.dashed")
                            .foregroundStyle(.orange)
                    }
                    
                    Label {
                        VStack(alignment: .leading) {
                            Text("실시간 영상통화")
                            Text("Phase 4 - 준비 중")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "circle.dashed")
                            .foregroundStyle(.orange)
                    }
                }
                
                // MARK: - API Status
                Section("API 상태") {
                    HStack {
                        Label("Gemini API", systemImage: "key.fill")
                        Spacer()
                        if APIConfig.isGeminiConfigured {
                            Text("연결됨")
                                .foregroundStyle(.green)
                                .font(.system(size: 14, weight: .medium))
                        } else {
                            Text("키 필요")
                                .foregroundStyle(.red)
                                .font(.system(size: 14, weight: .medium))
                        }
                    }
                }
                
                // MARK: - Danger Zone
                Section {
                    Button("대화 내역 초기화") {
                        showClearConfirm = true
                    }
                    .foregroundStyle(.orange)
                    
                    Button("모든 데이터 삭제") {
                        showDeleteAllConfirm = true
                    }
                    .foregroundStyle(.red)
                }
                
                // MARK: - Disclaimer
                Section {
                    Text("이 앱은 전문 심리 상담을 대체하지 않습니다. 심각한 정신건강 문제가 있다면 전문가의 도움을 받으세요.\n\n자살예방상담전화 1393\n정신건강위기상담전화 1577-0199")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
            .confirmationDialog("대화 내역을 초기화할까요?", isPresented: $showClearConfirm) {
                Button("초기화", role: .destructive) {
                    viewModel.clearChat()
                }
                Button("취소", role: .cancel) {}
            }
            .confirmationDialog("모든 데이터를 삭제할까요?", isPresented: $showDeleteAllConfirm) {
                Button("모두 삭제", role: .destructive) {
                    PersistenceService.shared.clearAll()
                    viewModel.clearChat()
                }
                Button("취소", role: .cancel) {}
            }
        }
    }
    
    private func scheduleDailyNotification() {
        if dailyCallRandom {
            NotificationService.shared.scheduleRandomDailyCall()
        } else {
            let components = Calendar.current.dateComponents([.hour, .minute], from: dailyCallTime)
            UserDefaults.standard.set(components.hour ?? 21, forKey: "dailyCallHour")
            UserDefaults.standard.set(components.minute ?? 0, forKey: "dailyCallMinute")
            NotificationService.shared.scheduleDailyCall(hour: components.hour ?? 21, minute: components.minute ?? 0)
        }
    }

    private func daysSinceFirst() -> String {
        guard let first = viewModel.messages.first else { return "0일" }
        let days = Calendar.current.dateComponents([.day], from: first.timestamp, to: Date()).day ?? 0
        return "\(max(days, 1))일"
    }
}

#Preview {
    SettingsView()
        .environmentObject(ChatViewModel())
}
