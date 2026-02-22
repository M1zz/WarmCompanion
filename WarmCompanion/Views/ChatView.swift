import SwiftUI

struct ChatView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool
    @State private var showSettings = false
    @State private var showCall = false
    @State private var showCompanionProfile = false
    @Namespace private var bottomAnchor
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Chat Header
            chatHeader
            
            Divider()
            
            // MARK: - Messages
            messagesScrollView
            
            // MARK: - Input Area
            messageInputArea
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarHidden(true)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(viewModel)
        }
        .fullScreenCover(isPresented: $showCall) {
            CallView()
                .environmentObject(viewModel)
        }
        .fullScreenCover(isPresented: $showCompanionProfile) {
            CompanionProfileDetailView(
                companion: viewModel.companion,
                onChat: nil,
                onCall: { showCall = true }
            )
        }
        .alert("오류", isPresented: $viewModel.showError) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "알 수 없는 오류")
        }
    }
    
    // MARK: - Chat Header
    private var chatHeader: some View {
        HStack(spacing: 12) {
            // Profile image
            Button { showCompanionProfile = true } label: {
                CompanionProfileView(companion: viewModel.companion, size: 40)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.companionName)
                    .font(.system(size: 17, weight: .semibold))
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("항상 곁에 있어")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // MARK: - Phase 2: Voice Call Button
            Button(action: { showCall = true }) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            
            // MARK: - Phase 4: Video Call Button
            /*
            Button(action: { /* Start video call */ }) {
                Image(systemName: "video.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            */
            
            Button(action: { showSettings = true }) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }
    
    // MARK: - Messages ScrollView
    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    // Date header
                    Text(todayDateString())
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                    
                    ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                        let showTimestamp = shouldShowTimestamp(at: index)
                        let profileVisible = shouldShowProfile(at: index)

                        MessageBubbleView(
                            message: message,
                            companionName: viewModel.companionName,
                            companion: viewModel.companion,
                            showTimestamp: showTimestamp,
                            showProfile: profileVisible,
                            isStreaming: viewModel.isStreaming && index == viewModel.messages.count - 1 && !message.isFromUser,
                            onSpeakTapped: message.isFromUser ? nil : {
                                viewModel.voiceService.speak(message.content)
                            },
                            onProfileTapped: message.isFromUser ? nil : {
                                showCompanionProfile = true
                            }
                        )
                        .id(message.id)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    
                    // Typing indicator
                    if viewModel.isLoading {
                        TypingIndicator()
                            .id("typing")
                    }
                    
                    // Bottom spacer for scroll
                    Color.clear
                        .frame(height: 8)
                        .id("bottom")
                }
                .padding(.horizontal, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.streamingText) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: viewModel.isLoading) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onAppear {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
    
    // MARK: - Input Area
    private var messageInputArea: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(alignment: .bottom, spacing: 8) {
                // MARK: - Phase 2: Voice Record Button
                Button(action: { viewModel.toggleRecording() }) {
                    Image(systemName: viewModel.voiceService.isRecording ? "mic.circle.fill" : "mic.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(viewModel.voiceService.isRecording ? .red : .secondary)
                        .frame(width: 36, height: 36)
                }
                
                // MARK: - Phase 3: Media Button (Photo/Video)
                /*
                Button(action: { /* Open media picker */ }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                }
                */
                
                // Text input
                HStack(alignment: .bottom) {
                    TextField("이야기해줘...", text: $viewModel.inputText, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($isInputFocused)
                        .font(.system(size: 16))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                
                // Send button
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        viewModel.sendMessage()
                    }
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color(.systemGray3)
                            : Color.orange
                        )
                }
                .disabled(
                    viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    viewModel.isStreaming ||
                    viewModel.isLoading
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
        }
    }
    
    // MARK: - Helpers
    private func todayDateString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일 EEEE"
        return formatter.string(from: Date())
    }
    
    private func shouldShowTimestamp(at index: Int) -> Bool {
        guard index > 0 else { return true }
        let current = viewModel.messages[index]
        let previous = viewModel.messages[index - 1]
        
        // Show timestamp if sender changes or 5+ minutes gap
        if current.isFromUser != previous.isFromUser { return true }
        return current.timestamp.timeIntervalSince(previous.timestamp) > 300
    }
    
    private func shouldShowProfile(at index: Int) -> Bool {
        guard !viewModel.messages[index].isFromUser else { return false }
        guard index > 0 else { return true }
        let previous = viewModel.messages[index - 1]
        return previous.isFromUser
    }

}

// MARK: - Typing Indicator
struct TypingIndicator: View {
    @State private var dotCount = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color(.systemGray3))
                        .frame(width: 7, height: 7)
                        .scaleEffect(dotCount % 3 == index ? 1.3 : 1.0)
                        .animation(.easeInOut(duration: 0.3), value: dotCount)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(.leading, 48)
            
            Spacer()
        }
        .onReceive(timer) { _ in
            dotCount += 1
        }
    }
}

#Preview {
    NavigationStack {
        ChatView()
    }
    .environmentObject(ChatViewModel())
}
