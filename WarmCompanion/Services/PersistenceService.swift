import Foundation

// MARK: - Local Persistence Service
class PersistenceService {
    static let shared = PersistenceService()
    
    private let messagesKey = "saved_messages"
    private let memoriesKey = "saved_memories"
    private let emotionsKey = "saved_emotions"
    
    private let fileManager = FileManager.default
    private lazy var documentsDirectory: URL = {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }()
    
    private init() {}
    
    // MARK: - Messages
    func saveMessages(_ messages: [Message]) {
        guard let data = try? JSONEncoder().encode(messages) else { return }
        let url = documentsDirectory.appendingPathComponent("messages.json")
        try? data.write(to: url)
    }
    
    func loadMessages() -> [Message] {
        let url = documentsDirectory.appendingPathComponent("messages.json")
        guard let data = try? Data(contentsOf: url),
              let messages = try? JSONDecoder().decode([Message].self, from: data) else {
            return []
        }
        return messages
    }
    
    // MARK: - Memories (Long-term)
    func saveMemories(_ memories: [CompanionMemory]) {
        guard let data = try? JSONEncoder().encode(memories) else { return }
        let url = documentsDirectory.appendingPathComponent("memories.json")
        try? data.write(to: url)
    }
    
    func loadMemories() -> [CompanionMemory] {
        let url = documentsDirectory.appendingPathComponent("memories.json")
        guard let data = try? Data(contentsOf: url),
              let memories = try? JSONDecoder().decode([CompanionMemory].self, from: data) else {
            return []
        }
        return memories
    }
    
    func addOrUpdateMemory(key: String, value: String, memories: inout [CompanionMemory]) {
        if let index = memories.firstIndex(where: { $0.key == key }) {
            memories[index] = CompanionMemory(
                id: memories[index].id,
                key: key,
                value: value,
                createdAt: memories[index].createdAt,
                updatedAt: Date()
            )
        } else {
            memories.append(CompanionMemory(key: key, value: value))
        }
        saveMemories(memories)
    }
    
    // MARK: - Emotions
    func saveEmotions(_ emotions: [EmotionEntry]) {
        guard let data = try? JSONEncoder().encode(emotions) else { return }
        let url = documentsDirectory.appendingPathComponent("emotions.json")
        try? data.write(to: url)
    }
    
    func loadEmotions() -> [EmotionEntry] {
        let url = documentsDirectory.appendingPathComponent("emotions.json")
        guard let data = try? Data(contentsOf: url),
              let emotions = try? JSONDecoder().decode([EmotionEntry].self, from: data) else {
            return []
        }
        return emotions
    }
    
    // MARK: - Voice Tuning Logs
    func saveTuningLogs(_ logs: [VoiceTuningLog]) {
        guard let data = try? JSONEncoder().encode(logs) else { return }
        let url = documentsDirectory.appendingPathComponent("tuning_logs.json")
        try? data.write(to: url)
    }

    func loadTuningLogs() -> [VoiceTuningLog] {
        let url = documentsDirectory.appendingPathComponent("tuning_logs.json")
        guard let data = try? Data(contentsOf: url),
              let logs = try? JSONDecoder().decode([VoiceTuningLog].self, from: data) else {
            return []
        }
        return logs
    }

    func appendTuningLog(_ log: VoiceTuningLog) {
        var logs = loadTuningLogs()
        logs.append(log)
        saveTuningLogs(logs)
    }

    // MARK: - Clear All
    func clearAll() {
        let files = ["messages.json", "memories.json", "emotions.json", "tuning_logs.json"]
        for file in files {
            let url = documentsDirectory.appendingPathComponent(file)
            try? fileManager.removeItem(at: url)
        }
    }
}
