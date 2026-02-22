import Foundation
import SwiftUI
import Combine

@MainActor
class ChatViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var messages: [Message] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var isStreaming: Bool = false
    @Published var streamingText: String = ""
    @Published var errorMessage: String?
    @Published var showError: Bool = false
    @Published var memories: [CompanionMemory] = []
    
    // MARK: - Services
    private let geminiService = GeminiService()
    private let persistence = PersistenceService.shared
    let voiceService = VoiceService()
    let geminiLiveService = GeminiLiveService()
    
    // MARK: - Combine
    private var liveCancellable: AnyCancellable?

    // MARK: - Companion Info
    let companionName = "온"
    let companionEmoji = "🤗"

    // MARK: - Init
    init() {
        // GeminiLiveService 변경 → ChatViewModel로 전파 (SwiftUI가 중첩 ObservableObject를 자동 관찰하지 않음)
        liveCancellable = geminiLiveService.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        loadData()
        setupGeminiLive()

        // 첫 실행시 인사 메시지
        if messages.isEmpty {
            let greeting = Message(
                content: "안녕, 만나서 반가워 😊\n나는 온이야. 네 이야기를 들어주고 싶어.\n오늘 하루는 어땠어?",
                isFromUser: false
            )
            messages.append(greeting)
            saveMessages()
        }
    }
    
    // MARK: - Load Data
    private func loadData() {
        messages = persistence.loadMessages()
        memories = persistence.loadMemories()
        
        Task {
            await geminiService.updateMemoryContext(memories)
        }
    }
    
    // MARK: - Send Message
    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        // Add user message
        let userMessage = Message(content: text, isFromUser: true)
        messages.append(userMessage)
        inputText = ""
        saveMessages()
        
        // Get AI response with streaming
        Task {
            await sendWithStreaming(text)
        }
    }
    
    // MARK: - Streaming Response
    private func sendWithStreaming(_ text: String) async {
        isStreaming = true
        streamingText = ""
        
        // Add placeholder for AI message
        let placeholderID = UUID()
        let placeholder = Message(id: placeholderID, content: "", isFromUser: false)
        messages.append(placeholder)
        
        do {
            let stream = await geminiService.sendMessageStream(text)
            
            for try await chunk in stream {
                streamingText += chunk
                // Update the last message (AI response)
                if let index = messages.lastIndex(where: { $0.id == placeholderID }) {
                    messages[index] = Message(
                        id: placeholderID,
                        content: streamingText,
                        isFromUser: false
                    )
                }
            }
            
            isStreaming = false
            saveMessages()
            
            // Extract and save memories from conversation
            await extractMemories(from: text)
            
        } catch {
            isStreaming = false
            
            // Remove placeholder and show error
            messages.removeAll { $0.id == placeholderID }
            
            // Fallback: try non-streaming
            await sendWithoutStreaming(text, originalError: error)
        }
    }
    
    // MARK: - Fallback: Non-streaming
    private func sendWithoutStreaming(_ text: String, originalError: Error) async {
        isLoading = true
        
        do {
            let response = try await geminiService.sendMessage(text)
            let aiMessage = Message(content: response, isFromUser: false)
            messages.append(aiMessage)
            saveMessages()
        } catch {
            errorMessage = (error as? GeminiError)?.errorDescription ?? error.localizedDescription
            showError = true
            
            // Offline fallback message
            let fallback = Message(
                content: "미안, 지금은 연결이 잘 안 되는 것 같아. 잠시 후에 다시 이야기하자 🙏",
                isFromUser: false
            )
            messages.append(fallback)
            saveMessages()
        }
        
        isLoading = false
    }
    
    // MARK: - Memory Extraction (Simple keyword-based)
    private func extractMemories(from userText: String) async {
        // Simple pattern matching for memory extraction
        let patterns: [(pattern: String, key: String)] = [
            ("이름은 ", "user_name"),
            ("나는 ", "user_identity"),
            ("직장", "user_work"),
            ("회사", "user_work"),
            ("좋아하는", "user_likes"),
            ("싫어하는", "user_dislikes"),
            ("취미", "user_hobby"),
        ]
        
        for (pattern, key) in patterns {
            if userText.contains(pattern) {
                // Extract a short context around the pattern
                let shortContext = String(userText.prefix(100))
                persistence.addOrUpdateMemory(key: key, value: shortContext, memories: &memories)
            }
        }
        
        await geminiService.updateMemoryContext(memories)
    }
    
    // MARK: - Save
    private func saveMessages() {
        // Keep last 200 messages in storage
        let toSave = Array(messages.suffix(200))
        persistence.saveMessages(toSave)
    }
    
    // MARK: - Actions
    func clearChat() {
        messages.removeAll()
        Task {
            await geminiService.resetConversation()
        }
        saveMessages()
        
        // Re-add greeting
        let greeting = Message(
            content: "새로 시작하자 😊 무슨 이야기든 편하게 해줘.",
            isFromUser: false
        )
        messages.append(greeting)
        saveMessages()
    }
    
    func deleteMessage(_ message: Message) {
        messages.removeAll { $0.id == message.id }
        saveMessages()
    }
    
    // MARK: - Gemini Live (Real-time Voice Call)
    private func setupGeminiLive() {
        Task {
            let prompt = await geminiService.getSystemPrompt()
            let memory = await geminiService.getMemoryContext()
            geminiLiveService.configure(systemPrompt: prompt, memoryContext: memory)
        }

        // 통화 내용은 채팅에 남기지 않음
    }

    func startLiveCall() {
        Task {
            let memory = await geminiService.getMemoryContext()
            geminiLiveService.updateMemoryContext(memory)
            geminiLiveService.connect()
        }
    }

    func endLiveCall() {
        geminiLiveService.disconnect()
    }

    // MARK: - Phase 2: Voice
    func sendVoiceMessage() {
        guard !voiceService.recognizedText.isEmpty else { return }
        inputText = voiceService.recognizedText
        sendMessage()
    }

    func speakLastResponse() {
        guard let lastAI = messages.last(where: { !$0.isFromUser }) else {
            print("[ChatVM] speakLastResponse - AI 메시지 없음")
            return
        }
        print("[ChatVM] speakLastResponse - 내용: \(lastAI.content.prefix(100))...")
        voiceService.speak(lastAI.content)
    }

    /// 전화 통화용: 텍스트를 Gemini에 보내고 응답 텍스트를 반환 + 채팅 로그 저장
    func sendForCall(_ text: String) async -> String? {
        // 유저 메시지 로그
        let userMessage = Message(content: text, isFromUser: true)
        messages.append(userMessage)
        saveMessages()
        print("[ChatVM] sendForCall - user: \(text)")

        do {
            let response = try await geminiService.sendMessage(text)
            let aiMessage = Message(content: response, isFromUser: false)
            messages.append(aiMessage)
            saveMessages()
            print("[ChatVM] sendForCall - ai: \(response.prefix(200))...")
            return response
        } catch {
            print("[ChatVM] sendForCall - error: \(error)")
            return nil
        }
    }

    func toggleRecording() {
        if voiceService.isRecording {
            voiceService.stopRecording()
            // Send recognized text after a short delay for final result
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                sendVoiceMessage()
            }
        } else {
            Task {
                let authorized = await voiceService.requestSpeechAuthorization()
                guard authorized else { return }
                try? voiceService.startRecording()
            }
        }
    }
}
