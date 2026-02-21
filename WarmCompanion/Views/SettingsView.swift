import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showClearConfirm = false
    @State private var showDeleteAllConfirm = false
    
    var body: some View {
        NavigationStack {
            List {
                // MARK: - Companion Profile
                Section {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.orange.opacity(0.6), Color.pink.opacity(0.4)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 60, height: 60)
                            
                            Text("🤗")
                                .font(.system(size: 30))
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.companionName)
                                .font(.system(size: 20, weight: .semibold))
                            Text("항상 네 곁에 있을게")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // MARK: - Memories
                Section("온이 기억하고 있는 것") {
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
