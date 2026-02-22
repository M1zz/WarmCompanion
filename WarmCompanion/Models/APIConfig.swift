import Foundation

// ============================================================
// 🔑 API 키 설정 가이드
// ============================================================
//
// 아래 API 키들을 발급받아 입력하세요.
//
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Phase 1: 텍스트 채팅 (무료)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// ✅ Google Gemini API Key (무료)
//    발급: https://aistudio.google.com/apikey
//    무료 한도: 분당 15회, 일 1,500회 (Gemini 2.0 Flash)
//    → 개인 사용 및 테스트에 충분
//
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Phase 2: 음성 채팅 (무료 ~ 저비용)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// 🔲 ElevenLabs API Key (선택, 고품질 TTS)
//    발급: https://elevenlabs.io → Profile → API Keys
//    무료: 월 10,000자 / 유료: $5/월~
//
// 🔲 STT는 Apple Speech Framework 사용 (무료, 키 불필요)
//
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Phase 3: 영상 메시지 (저비용)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// 🔲 Hedra API Key (고품질 립싱크 영상)
//    발급: https://www.hedra.com
//
// 🔲 또는 MuseTalk (오픈소스, 자체 GPU 서버 필요)
//    GitHub: https://github.com/TMElyralab/MuseTalk
//
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Phase 4: 실시간 영상통화 (유료)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// 🔲 OpenAI API Key (Realtime API)
//    발급: https://platform.openai.com/api-keys
//    Realtime API: WebRTC 기반 실시간 음성
//
// ============================================================

struct APIConfig {
    
    // MARK: - Phase 1: Text Chat (무료)
    /// Google Gemini API Key
    /// 발급: https://aistudio.google.com/apikey
    static let geminiAPIKey = Secrets.geminiAPIKey
    
    // MARK: - Phase 2: Voice Chat
    /// ElevenLabs API Key (고품질 TTS, 선택사항)
    /// 없으면 Apple AVSpeechSynthesizer 사용 (무료, 품질 낮음)
    /// 발급: https://elevenlabs.io
    static let elevenLabsAPIKey = Secrets.elevenLabsAPIKey
    static let elevenLabsVoiceID = Secrets.elevenLabsVoiceID
    
    // MARK: - Phase 3: Video Message
    /// Hedra API Key (영상 메시지 생성)
    /// 발급: https://www.hedra.com
    // static let hedraAPIKey = "YOUR_HEDRA_API_KEY_HERE"
    
    // MARK: - Phase 4: Realtime Video Call
    /// OpenAI API Key (Realtime API for voice + vision)
    /// 발급: https://platform.openai.com/api-keys
    // static let openAIAPIKey = "YOUR_OPENAI_API_KEY_HERE"
    
    // MARK: - Gemini Model Config
    static let geminiModel = "gemini-2.5-flash"
    static let geminiBaseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    // MARK: - Gemini Live API (Real-time Voice)
    static let geminiLiveModel = "models/gemini-2.5-flash-native-audio-preview-12-2025"
    static let geminiLiveWebSocketURL = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
    static var geminiLiveVoice: String {
        let saved = UserDefaults.standard.string(forKey: "selectedCompanion") ?? "on"
        return (CompanionType(rawValue: saved) ?? .on).voiceName
    }
    
    // MARK: - Validation
    static var isGeminiConfigured: Bool {
        geminiAPIKey != "YOUR_GEMINI_API_KEY_HERE" && !geminiAPIKey.isEmpty
    }
}
