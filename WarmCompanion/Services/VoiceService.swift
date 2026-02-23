import Foundation
import AVFoundation
import Speech

// ============================================================
// MARK: - Voice Service
// ============================================================
// - STT: Apple Speech Framework (무료, 온디바이스) — 텍스트 채팅 마이크 입력용
// - TTS: Apple AVSpeechSynthesizer (무료) — 텍스트 채팅 메시지 읽기용
// - 음성 통화: GeminiLiveService가 자체 STT/TTS 처리 (이 서비스 미사용)
// ============================================================

class VoiceService: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recognizedText = ""
    @Published var isSpeaking = false

    // MARK: - TTS (Text-to-Speech) - Apple 내장
    private let synthesizer = AVSpeechSynthesizer()
    private var koreanVoice: AVSpeechSynthesisVoice?

    override init() {
        super.init()
        synthesizer.delegate = self
        koreanVoice = Self.bestKoreanVoice()
    }

    /// 사용 가능한 한국어 음성 중 가장 좋은 것을 선택
    private static func bestKoreanVoice() -> AVSpeechSynthesisVoice? {
        let koVoices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("ko") }

        // 1순위: Premium 음성 (설정 → 손쉬운 사용 → 음성 콘텐츠에서 다운로드)
        if let premium = koVoices.first(where: { $0.quality == .premium }) {
            print("[VoiceService] 프리미엄 한국어 음성 사용: \(premium.name)")
            return premium
        }
        // 2순위: Enhanced 음성
        if let enhanced = koVoices.first(where: { $0.quality == .enhanced }) {
            print("[VoiceService] 향상된 한국어 음성 사용: \(enhanced.name)")
            return enhanced
        }
        // 3순위: 기본 음성
        let fallback = AVSpeechSynthesisVoice(language: "ko-KR")
        print("[VoiceService] 기본 한국어 음성 사용 (설정 → 손쉬운 사용 → 음성 콘텐츠에서 향상된 음성 다운로드 권장)")
        return fallback
    }

    /// TTS - Apple 내장 음성으로 읽기
    func speak(_ text: String) {
        let cleaned = Self.stripForTTS(text)
        guard !cleaned.isEmpty else { return }
        speakWithApple(cleaned)
    }

    /// 이모지, 특수문자 등 TTS에 부적합한 문자 제거
    static func stripForTTS(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0000...0x007F:  // Basic ASCII
                result.append(Character(scalar))
            case 0x00A0...0x00FF:  // Latin supplement
                result.append(Character(scalar))
            case 0x1100...0x11FF,  // 한글 자모
                 0x3000...0x303F,  // CJK 문장부호
                 0x3130...0x318F,  // 한글 호환 자모
                 0xAC00...0xD7AF,  // 한글 음절
                 0xFF00...0xFFEF:  // 전각 문자
                result.append(Character(scalar))
            default:
                break  // 이모지, 특수 기호 등 제거
            }
        }
        return result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    private func speakWithApple(_ text: String) {
        configureAudioSessionForPlayback()

        // 긴 문장은 자연스러운 단위로 분할해서 읽기
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?。\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        isSpeaking = true

        for (i, sentence) in sentences.enumerated() {
            let utterance = AVSpeechUtterance(string: sentence)
            utterance.voice = koreanVoice
            utterance.rate = 0.48           // 약간 느리게 (0.5가 정상 속도)
            utterance.pitchMultiplier = 1.0 // 자연스러운 톤 (변조하면 어색해짐)
            utterance.volume = 0.9
            utterance.preUtteranceDelay = i == 0 ? 0.15 : 0.08  // 문장 사이 자연스러운 간격
            utterance.postUtteranceDelay = 0.12
            synthesizer.speak(utterance)
        }
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    private func configureAudioSessionForPlayback() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
        } catch {
            print("[VoiceService] 오디오 세션 설정 실패: \(error)")
        }
    }

    // MARK: - STT (Speech-to-Text) - Apple Speech Framework
    private var audioEngine: AVAudioEngine?
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func startRecording() throws {
        // 이미 녹음 중이면 무시
        if audioEngine?.isRunning == true {
            print("[VoiceService] 이미 녹음 중 - 스킵")
            return
        }

        // 이전 세션 정리
        cleanupRecording()

        // 오디오 세션을 먼저 설정 (inputNode 접근 전에 반드시 필요)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // 새 엔진 생성 (재사용하면 이전 탭이 남아서 크래시)
        let engine = AVAudioEngine()
        self.audioEngine = engine

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.recognitionRequest = request

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // 포맷 유효성 검증 (channels=0 또는 sampleRate=0이면 크래시)
        guard recordingFormat.channelCount > 0, recordingFormat.sampleRate > 0 else {
            print("[VoiceService] 유효하지 않은 오디오 포맷: channels=\(recordingFormat.channelCount), rate=\(recordingFormat.sampleRate)")
            cleanupRecording()
            throw NSError(domain: "VoiceService", code: -1, userInfo: [NSLocalizedDescriptionKey: "마이크를 사용할 수 없습니다"])
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                DispatchQueue.main.async {
                    self.recognizedText = result.bestTranscription.formattedString
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                DispatchQueue.main.async {
                    self.stopRecording()
                }
            }
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        try engine.start()

        DispatchQueue.main.async {
            self.isRecording = true
            self.recognizedText = ""
        }
    }

    func stopRecording() {
        cleanupRecording()
        DispatchQueue.main.async {
            self.isRecording = false
        }
    }

    private func cleanupRecording() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension VoiceService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // 마지막 utterance가 끝났을 때만 isSpeaking = false
        if !synthesizer.isSpeaking {
            DispatchQueue.main.async {
                self.isSpeaking = false
            }
        }
    }
}
