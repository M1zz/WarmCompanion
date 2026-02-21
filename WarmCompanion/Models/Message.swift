import Foundation

// MARK: - Message Model
struct Message: Identifiable, Codable, Equatable {
    let id: UUID
    let content: String
    let isFromUser: Bool
    let timestamp: Date
    let type: MessageType
    
    // MARK: - Phase 2: Voice
    // var audioURL: URL?
    // var audioDuration: TimeInterval?
    
    // MARK: - Phase 3: Video Message
    // var videoURL: URL?
    // var videoDuration: TimeInterval?
    // var thumbnailURL: URL?
    
    enum MessageType: String, Codable {
        case text
        // case voice      // Phase 2
        // case video      // Phase 3
        // case videoCall   // Phase 4
    }
    
    init(
        id: UUID = UUID(),
        content: String,
        isFromUser: Bool,
        timestamp: Date = Date(),
        type: MessageType = .text
    ) {
        self.id = id
        self.content = content
        self.isFromUser = isFromUser
        self.timestamp = timestamp
        self.type = type
    }
}

// MARK: - Emotion Tracking
struct EmotionEntry: Identifiable, Codable {
    let id: UUID
    let date: Date
    let emotion: EmotionType
    let intensity: Double // 0.0 ~ 1.0
    let summary: String
    
    enum EmotionType: String, Codable, CaseIterable {
        case happy = "기쁨"
        case sad = "슬픔"
        case angry = "화남"
        case anxious = "불안"
        case tired = "지침"
        case peaceful = "평온"
        case lonely = "외로움"
        case grateful = "감사"
    }
    
    init(id: UUID = UUID(), date: Date = Date(), emotion: EmotionType, intensity: Double, summary: String) {
        self.id = id
        self.date = date
        self.emotion = emotion
        self.intensity = intensity
        self.summary = summary
    }
}

// MARK: - Memory (Long-term)
struct CompanionMemory: Identifiable, Codable {
    let id: UUID
    let key: String        // e.g., "user_name", "favorite_food", "concern_work"
    let value: String
    let createdAt: Date
    var updatedAt: Date
    
    init(id: UUID = UUID(), key: String, value: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.key = key
        self.value = value
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
