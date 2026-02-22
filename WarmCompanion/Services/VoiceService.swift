import Foundation
import AVFoundation
import Speech

// ============================================================
// MARK: - Phase 2: Voice Service
// ============================================================
// 음성 채팅 기능
// - STT: Apple Speech Framework (무료, 온디바이스)
// - TTS: AVSpeechSynthesizer (무료) 또는 ElevenLabs (유료, 고품질)
//
// 활성화 방법:
// 1. Info.plist에 아래 권한 추가:
//    - NSSpeechRecognitionUsageDescription
//    - NSMicrophoneUsageDescription
// 2. 아래 주석을 해제하세요
// ============================================================

class VoiceService: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recognizedText = ""
    @Published var isSpeaking = false
    
    // MARK: - TTS (Text-to-Speech) - 무료 Apple 내장
    private let synthesizer = AVSpeechSynthesizer()
    
    override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    /// TTS - ElevenLabs 우선, 실패시 Apple TTS 폴백
    func speak(_ text: String) {
        let cleaned = Self.stripForTTS(text)
        print("[VoiceService] speak() - 원본 길이: \(text.count)자, 정제 후: \(cleaned.count)자")
        print("[VoiceService] 정제 텍스트: \(cleaned.prefix(200))...")
        guard !cleaned.isEmpty else {
            print("[VoiceService] 정제 후 텍스트 비어있음, 스킵")
            return
        }
        Task {
            do {
                try await speakWithElevenLabs(cleaned)
            } catch {
                print("[VoiceService] ElevenLabs 실패, Apple TTS 폴백 - error: \(error)")
                await MainActor.run {
                    speakWithApple(cleaned)
                }
            }
        }
    }

    /// 이모지, 특수문자, 미모지 등 TTS에 부적합한 문자 제거
    static func stripForTTS(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            // 기본 문자: 한글, 영문, 숫자, 공백, 기본 문장부호
            if scalar.properties.isEmoji && scalar.value > 0x23F && !scalar.properties.isEmojiPresentation == false {
                // 이모지 스킵 — 아래에서 더 정확하게 처리
            }
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
        // 연속 공백 정리
        return result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    /// 무료 TTS - Apple 내장 (폴백용)
    private func speakWithApple(_ text: String) {
        print("[VoiceService] Apple TTS 시작 - 텍스트: \(text.prefix(100))...")
        configureAudioSessionForPlayback()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        utterance.rate = 0.42  // 천천히, 나긋나긋하게
        utterance.pitchMultiplier = 1.05  // 살짝 높은 톤
        utterance.volume = 0.85
        utterance.preUtteranceDelay = 0.3  // 자연스러운 시작 딜레이

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        audioPlayer?.stop()
        audioPlayer = nil
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    /// 오디오 세션을 재생 모드로 전환 (STT 후 TTS 전에 필요)
    private func configureAudioSessionForPlayback() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
            print("[VoiceService] 오디오 세션 -> playback 모드")
        } catch {
            print("[VoiceService] 오디오 세션 설정 실패: \(error)")
        }
    }

    // MARK: - STT (Speech-to-Text) - Apple Speech Framework
    private var audioEngine = AVAudioEngine()
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
        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            if let result = result {
                DispatchQueue.main.async {
                    self?.recognizedText = result.bestTranscription.formattedString
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                self?.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self?.recognitionRequest = nil
                self?.recognitionTask = nil
                DispatchQueue.main.async {
                    self?.isRecording = false
                }
            }
        }

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        DispatchQueue.main.async {
            self.isRecording = true
            self.recognizedText = ""
        }
    }

    func stopRecording() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        isRecording = false
    }
    
    // MARK: - Phase 2: ElevenLabs TTS (고품질, 유료)
    private var audioPlayer: AVAudioPlayer?

    func speakWithElevenLabs(_ text: String) async throws {
        print("[VoiceService] ElevenLabs 요청 시작 - voiceID: \(APIConfig.elevenLabsVoiceID)")
        print("[VoiceService] ElevenLabs 텍스트: \(text.prefix(200))...")

        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(APIConfig.elevenLabsVoiceID)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(APIConfig.elevenLabsAPIKey, forHTTPHeaderField: "xi-api-key")

        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_multilingual_v2",
            "voice_settings": [
                "stability": 0.82,
                "similarity_boost": 0.7,
                "style": 0.15,
                "use_speaker_boost": false
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            print("[VoiceService] ElevenLabs 응답 코드: \(httpResponse.statusCode), 데이터 크기: \(data.count) bytes")
            if httpResponse.statusCode != 200 {
                let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
                print("[VoiceService] ElevenLabs 에러 응답: \(errorBody)")
                throw NSError(domain: "ElevenLabs", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorBody])
            }
        }

        configureAudioSessionForPlayback()
        DispatchQueue.main.async {
            self.isSpeaking = true
        }
        audioPlayer = try AVAudioPlayer(data: data)
        audioPlayer?.delegate = self
        audioPlayer?.play()
        print("[VoiceService] ElevenLabs 오디오 재생 시작 - duration: \(audioPlayer?.duration ?? 0)초")
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension VoiceService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("[VoiceService] Apple TTS 재생 완료")
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }
}

// MARK: - AVAudioPlayerDelegate
extension VoiceService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("[VoiceService] ElevenLabs 오디오 재생 완료 - success: \(flag)")
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }
}
