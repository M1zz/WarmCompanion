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

// MARK: - Companion Type
enum CompanionType: String, Codable, CaseIterable, Identifiable {
    case on = "on"      // 온 (여성, 따뜻한)
    case dam = "dam"    // 담 (남성, 포근한)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .on: return "온"
        case .dam: return "담"
        }
    }

    var emoji: String {
        switch self {
        case .on: return "\u{1F917}"  // 🤗
        case .dam: return "\u{1F60C}"  // 😌
        }
    }

    var description: String {
        switch self {
        case .on: return "따뜻하고 부드러운 친구"
        case .dam: return "차분하고 포근한 친구"
        }
    }

    var statusMessage: String {
        switch self {
        case .on: return "네 이야기를 듣고 싶어"
        case .dam: return "편하게 기대도 돼"
        }
    }

    var voiceName: String {
        switch self {
        case .on: return "Leda"       // Youthful (여성)
        case .dam: return "Enceladus"  // Breathy (저음 남성)
        }
    }

    var gradientColors: [String] {
        switch self {
        case .on: return ["orange", "pink"]
        case .dam: return ["indigo", "blue"]
        }
    }

    /// 프로필 이미지 이름 (Assets.xcassets)
    var profileImageName: String {
        switch self {
        case .on: return "on_profile_2"   // 클로즈업 윙크
        case .dam: return ""              // 아직 없음 → emoji fallback
        }
    }

    /// 프로필 이미지 목록 (여러 장)
    var profileImageNames: [String] {
        switch self {
        case .on: return ["on_profile_1", "on_profile_2", "on_profile_3"]
        case .dam: return []
        }
    }

    var hasProfileImage: Bool {
        !profileImageName.isEmpty
    }
}

// MARK: - Voice Tuning Experiment Log
struct VoiceTuningLog: Identifiable, Codable {
    let id: UUID
    let timestamp: Date

    // 파라미터 스냅샷
    let energyThreshold: Float
    let turnCompleteDelayMs: Int
    let silenceDurationMs: Int
    let startSensitivity: String
    let endSensitivity: String

    // 세션 메트릭
    let totalTurns: Int
    let interruptCount: Int
    let droppedAudioCount: Int
    let avgResponseLatencyMs: Int
    let callDurationSec: Int

    // 평가
    let rating: Int            // 1~5 별점
    let note: String           // 자유 메모

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        energyThreshold: Float,
        turnCompleteDelayMs: Int,
        silenceDurationMs: Int,
        startSensitivity: String,
        endSensitivity: String,
        totalTurns: Int,
        interruptCount: Int,
        droppedAudioCount: Int,
        avgResponseLatencyMs: Int,
        callDurationSec: Int,
        rating: Int,
        note: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.energyThreshold = energyThreshold
        self.turnCompleteDelayMs = turnCompleteDelayMs
        self.silenceDurationMs = silenceDurationMs
        self.startSensitivity = startSensitivity
        self.endSensitivity = endSensitivity
        self.totalTurns = totalTurns
        self.interruptCount = interruptCount
        self.droppedAudioCount = droppedAudioCount
        self.avgResponseLatencyMs = avgResponseLatencyMs
        self.callDurationSec = callDurationSec
        self.rating = rating
        self.note = note
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
