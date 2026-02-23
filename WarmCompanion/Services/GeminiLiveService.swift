import Foundation
@preconcurrency import AVFoundation
import Combine

// MARK: - Gemini Multimodal Live API Service
// 실시간 양방향 음성 스트리밍: 유저 음성 → [WebSocket] → AI 음성

// MARK: - WebSocket Delegate (연결 확인용)
class WebSocketDelegate: NSObject, URLSessionWebSocketDelegate {
    var onOpen: (() -> Void)?
    var onClose: ((URLSessionWebSocketTask.CloseCode, Data?) -> Void)?

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("[GeminiLive-WS] didOpen")
        onOpen?()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("[GeminiLive-WS] didClose: \(closeCode)")
        onClose?(closeCode, reason)
    }
}

@MainActor
class GeminiLiveService: ObservableObject {

    // MARK: - Session State
    enum SessionState: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    @Published var sessionState: SessionState = .disconnected
    @Published var isModelSpeaking = false
    @Published var inputTranscript = ""
    @Published var outputTranscript = ""
    @Published var isMicMuted = false

    // MARK: - Tunable Parameters (실시간 조절 가능)
    @Published var energyThreshold: Float = 0.03          // 에코 게이트 임계값
    @Published var turnCompleteDelayMs: Int = 50           // 턴 완료 후 마이크 열기까지 대기(ms)
    @Published var silenceDurationMs: Int = 300            // 서버 VAD 침묵 판단 기준(ms)
    @Published var startSensitivity: String = "START_SENSITIVITY_HIGH"  // 발화 시작 감도
    @Published var endSensitivity: String = "END_SENSITIVITY_LOW"       // 발화 종료 감도

    // MARK: - Debug Metrics (실시간 모니터링)
    @Published var debugCurrentRMS: Float = 0              // 현재 마이크 에너지
    @Published var debugLastResponseLatencyMs: Int = 0     // 마지막 응답 지연(ms)
    @Published var debugTurnCount: Int = 0                 // 총 턴 수
    @Published var debugInterruptCount: Int = 0            // 인터럽트 횟수
    @Published var debugDroppedAudioCount: Int = 0         // 무시된 오디오 청크 수
    @Published var debugIsEchoGated: Bool = false          // 에코 게이트 활성 여부
    private var responseLatenies: [Int] = []               // 응답 지연 누적 (평균 계산용)
    var debugAvgResponseLatencyMs: Int {                    // 평균 응답 지연
        responseLatenies.isEmpty ? 0 : responseLatenies.reduce(0, +) / responseLatenies.count
    }

    // MARK: - Callback
    var onConversationTurn: ((String, String) -> Void)?

    // MARK: - Private
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var wsDelegate: WebSocketDelegate?
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var playerMixer: AVAudioMixerNode?
    private var systemPrompt = ""
    private var memoryContext = ""
    private var sessionTimer: Timer?
    private var pendingAudioBuffers: [Data] = []
    private var isReceivingAudio = false
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 3

    private var currentInputText = ""
    private var currentOutputText = ""
    private var turnCompleteTask: Task<Void, Never>?
    private var modelTurnId: UInt64 = 0        // 현재 모델 턴 식별자 (겹침 방지)
    private var isInterrupted = false           // 인터럽트 후 잔여 오디오 무시용
    private var userSpeechEndTime: CFAbsoluteTime = 0  // 사용자 발화 종료 시점 (응답 지연 측정)

    private let inputSampleRate: Double = 16000
    private let outputSampleRate: Double = 24000

    // MARK: - Configure
    func configure(systemPrompt: String, memoryContext: String) {
        self.systemPrompt = systemPrompt
        self.memoryContext = memoryContext
    }

    func updateMemoryContext(_ context: String) {
        self.memoryContext = context
    }

    // MARK: - Connect
    func connect() {
        guard sessionState != .connecting, sessionState != .connected else { return }
        sessionState = .connecting

        let urlString = "\(APIConfig.geminiLiveWebSocketURL)?key=\(APIConfig.geminiAPIKey)"
        guard let url = URL(string: urlString) else {
            sessionState = .error("Invalid WebSocket URL")
            return
        }

        // Delegate로 연결 확인
        let delegate = WebSocketDelegate()
        self.wsDelegate = delegate

        delegate.onOpen = { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                print("[GeminiLive] ✅ WebSocket 연결됨 - setup 전송")
                self.reconnectAttempts = 0
                self.sendSetupMessage()
                self.startReceiving()
                self.startSessionTimer()
            }
        }

        delegate.onClose = { [weak self] closeCode, reason in
            Task { @MainActor in
                guard let self = self else { return }
                let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "unknown"
                print("[GeminiLive] ❌ WebSocket 닫힘: \(closeCode) reason: \(reasonStr)")
                if self.sessionState == .connected || self.sessionState == .connecting {
                    self.sessionState = .error("연결 끊김")
                    self.attemptReconnect()
                }
            }
        }

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        self.urlSession = session

        let task = session.webSocketTask(with: url)
        self.webSocketTask = task
        task.resume()

        print("[GeminiLive] WebSocket 연결 시작: \(url.host ?? "")")
    }

    // MARK: - Disconnect
    func disconnect() {
        print("[GeminiLive] 연결 종료")
        sessionTimer?.invalidate()
        sessionTimer = nil

        stopAudioEngine()
        stopPlayback()

        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        wsDelegate = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        sessionState = .disconnected
        isModelSpeaking = false
        isMicMuted = false
        inputTranscript = ""
        outputTranscript = ""
        currentInputText = ""
        currentOutputText = ""
        pendingAudioBuffers = []
        reconnectAttempts = 0
        modelTurnId = 0
        isInterrupted = false
        userSpeechEndTime = 0
        turnCompleteTask?.cancel()
        turnCompleteTask = nil
        debugCurrentRMS = 0
        debugLastResponseLatencyMs = 0
        debugTurnCount = 0
        debugInterruptCount = 0
        debugDroppedAudioCount = 0
        debugIsEchoGated = false
        responseLatenies = []
    }

    // MARK: - Mic Mute
    func setMicMuted(_ muted: Bool) {
        isMicMuted = muted
        print("[GeminiLive] 마이크 음소거: \(muted)")
    }

    // MARK: - Setup Message
    private func sendSetupMessage() {
        let fullPrompt = systemPrompt + memoryContext +
            "\n\n## 통화 모드 추가 지침\n- 지금은 전화 통화 중이야. 짧고 자연스럽게 말해.\n- 1~2문장 이내로 짧게 답해. 길게 말하지 마.\n- 상대방이 말하면 즉시 반응해. 생각하는 시간 없이 바로 대답해.\n- 침묵이 생기면 자연스럽게 먼저 말을 걸어줘. '뭐 해?', '또 무슨 얘기 할까?' 같이.\n- 대답할 때 '음...', '그러니까...' 같은 머뭇거림 없이 바로 핵심을 말해.\n- 통화가 시작되면 반드시 '여보세요?' 라고 먼저 인사해. 첫 마디는 항상 '여보세요?'야."

        let setup: [String: Any] = [
            "setup": [
                "model": APIConfig.geminiLiveModel,
                "generationConfig": [
                    "responseModalities": ["AUDIO"],
                    "speechConfig": [
                        "voiceConfig": [
                            "prebuiltVoiceConfig": [
                                "voiceName": APIConfig.geminiLiveVoice
                            ]
                        ],
                        "languageCode": "ko-KR"
                    ]
                ],
                "systemInstruction": [
                    "parts": [["text": fullPrompt]]
                ],
                "realtimeInputConfig": [
                    "automaticActivityDetection": [
                        "disabled": false,
                        "startOfSpeechSensitivity": startSensitivity,
                        "endOfSpeechSensitivity": endSensitivity,
                        "prefixPaddingMs": 20,
                        "silenceDurationMs": silenceDurationMs
                    ]
                ],
                "inputAudioTranscription": [String: Any](),
                "outputAudioTranscription": [String: Any]()
            ]
        ]

        sendJSON(setup)
    }

    // MARK: - Send JSON
    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else {
            print("[GeminiLive] JSON 직렬화 실패")
            return
        }
        print("[GeminiLive] 전송: \(str.prefix(200))...")
        webSocketTask?.send(.string(str)) { error in
            if let error = error {
                print("[GeminiLive] 전송 에러: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Initial Greeting (AI가 먼저 "여보세요?" 발화)
    private func sendInitialGreeting() {
        let greeting: [String: Any] = [
            "clientContent": [
                "turns": [
                    [
                        "role": "user",
                        "parts": [["text": "(전화가 연결되었어. 먼저 여보세요? 하고 인사해줘)"]]
                    ]
                ],
                "turnComplete": true
            ]
        ]
        print("[GeminiLive] 🗣️ 초기 인사 요청 전송")
        sendJSON(greeting)
    }

    // MARK: - Send Audio
    private func sendAudioChunk(_ base64Audio: String) {
        let msg: [String: Any] = [
            "realtimeInput": [
                "mediaChunks": [
                    [
                        "mimeType": "audio/pcm;rate=16000",
                        "data": base64Audio
                    ]
                ]
            ]
        ]
        sendJSON(msg)
    }

    // MARK: - Receive Messages
    private func startReceiving() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleServerMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleServerMessage(text)
                        }
                    @unknown default:
                        break
                    }
                    self.startReceiving()

                case .failure(let error):
                    print("[GeminiLive] 수신 에러: \(error.localizedDescription)")
                    // delegate.onClose가 처리하므로 여기서는 로그만
                }
            }
        }
    }

    // MARK: - Handle Server Messages
    private func handleServerMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[GeminiLive] JSON 파싱 실패: \(text.prefix(100))")
            return
        }

        // setupComplete
        if json["setupComplete"] != nil {
            print("[GeminiLive] ✅ Setup complete - 세션 활성화")
            sessionState = .connected
            startAudioEngine()
            sendInitialGreeting()
            return
        }

        // goAway
        if json["goAway"] != nil {
            print("[GeminiLive] ⚠️ goAway 수신 - 재연결 예정")
            attemptReconnect()
            return
        }

        // serverContent
        if let serverContent = json["serverContent"] as? [String: Any] {
            handleServerContent(serverContent)
            return
        }

        print("[GeminiLive] 미처리 메시지: \(text.prefix(200))")
    }

    private func handleServerContent(_ content: [String: Any]) {
        // interrupted - 사용자가 끼어들었을 때 즉시 재생 중단 + 마이크 열기
        if content["interrupted"] as? Bool == true {
            print("[GeminiLive] 🔇 Interrupted - 재생 즉시 중단")
            debugInterruptCount += 1
            turnCompleteTask?.cancel()
            isInterrupted = true          // 이후 도착하는 이전 턴 오디오 무시
            stopPlayback()
            isModelSpeaking = false
            isReceivingAudio = false
            return
        }

        // modelTurn
        if let modelTurn = content["modelTurn"] as? [String: Any],
           let parts = modelTurn["parts"] as? [[String: Any]] {

            // 인터럽트 후 잔여 오디오 무시 (turnComplete 전까지)
            if isInterrupted {
                debugDroppedAudioCount += 1
                print("[GeminiLive] ⏭️ 인터럽트 후 잔여 오디오 무시 (drop #\(debugDroppedAudioCount))")
                return
            }

            for part in parts {
                if let inlineData = part["inlineData"] as? [String: Any],
                   let audioBase64 = inlineData["data"] as? String {
                    if !isModelSpeaking {
                        // 새 턴 시작: 이전 재생을 확실히 정리하고 새 턴 ID 발급
                        stopPlayback()
                        modelTurnId += 1
                        debugTurnCount += 1
                        isModelSpeaking = true
                        isReceivingAudio = true
                        // 응답 지연 측정
                        if userSpeechEndTime > 0 {
                            let latency = Int((CFAbsoluteTimeGetCurrent() - userSpeechEndTime) * 1000)
                            debugLastResponseLatencyMs = latency
                            responseLatenies.append(latency)
                            print("[GeminiLive] 🔊 새 모델 턴 시작 (id: \(modelTurnId), 응답지연: \(latency)ms, 평균: \(debugAvgResponseLatencyMs)ms)")
                        } else {
                            print("[GeminiLive] 🔊 새 모델 턴 시작 (id: \(modelTurnId))")
                        }
                    }
                    if let audioData = Data(base64Encoded: audioBase64) {
                        playAudioData(audioData, forTurnId: modelTurnId)
                    }
                }
                if let textPart = part["text"] as? String {
                    currentOutputText += textPart
                    outputTranscript = currentOutputText
                }
            }
        }

        // turnComplete
        if content["turnComplete"] as? Bool == true {
            print("[GeminiLive] ✅ Turn complete")
            isReceivingAudio = false
            isInterrupted = false  // 턴 경계에서 인터럽트 플래그 리셋

            // 이전 대기 타스크가 있으면 취소
            turnCompleteTask?.cancel()
            turnCompleteTask = Task {
                // 튜닝 가능한 대기 시간 후 마이크 활성화
                let delayNs = UInt64(self.turnCompleteDelayMs) * 1_000_000
                try? await Task.sleep(nanoseconds: delayNs)
                if !Task.isCancelled, !self.isReceivingAudio {
                    self.isModelSpeaking = false
                }
            }

            if !currentInputText.isEmpty || !currentOutputText.isEmpty {
                let input = currentInputText
                let output = currentOutputText
                onConversationTurn?(input, output)
            }
            currentInputText = ""
            currentOutputText = ""
        }

        // inputAudioTranscription
        if let inputTranscription = content["inputAudioTranscription"] as? [String: Any],
           let text = inputTranscription["text"] as? String {
            currentInputText += text
            inputTranscript = currentInputText
            userSpeechEndTime = CFAbsoluteTimeGetCurrent()  // 응답 지연 측정 기준점
            print("[GeminiLive] 🎤 Input: \(text)")
        }

        // outputAudioTranscription
        if let outputTranscription = content["outputAudioTranscription"] as? [String: Any],
           let text = outputTranscription["text"] as? String {
            currentOutputText += text
            outputTranscript = currentOutputText
            print("[GeminiLive] 🔊 Output: \(text)")
        }
    }

    // MARK: - Audio Engine (Input)
    private func startAudioEngine() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try audioSession.setActive(true)
        } catch {
            print("[GeminiLive] 오디오 세션 설정 실패: \(error)")
            sessionState = .error("오디오 세션 설정 실패")
            return
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let mixer = AVAudioMixerNode()

        engine.attach(player)
        engine.attach(mixer)

        let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: outputSampleRate, channels: 1, interleaved: true)!
        engine.connect(player, to: mixer, format: outputFormat)
        engine.connect(mixer, to: engine.mainMixerNode, format: nil)

        let inputNode = engine.inputNode
        let inputHWFormat = inputNode.outputFormat(forBus: 0)
        print("[GeminiLive] 입력 HW 포맷: \(inputHWFormat)")

        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: inputSampleRate, channels: 1, interleaved: true)!
        let converter: AVAudioConverter? = AVAudioConverter(from: inputHWFormat, to: targetFormat)
        if converter == nil {
            print("[GeminiLive] ⚠️ 오디오 변환기 생성 실패")
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputHWFormat) { [weak self] buffer, _ in
            guard let self = self, !self.isMicMuted else { return }

            // 에너지 측정 (디버그 메트릭)
            let energy = self.calculateRMS(buffer: buffer)
            Task { @MainActor in
                self.debugCurrentRMS = energy
            }

            // AI 발화 중에는 에너지 체크로 에코 필터링 (스피커 → 마이크 피드백 방지)
            // .voiceChat 모드의 HW 에코 제거 + SW 에너지 게이트 이중 보호
            if self.isModelSpeaking {
                let threshold = self.energyThreshold
                guard energy > threshold else {
                    Task { @MainActor in self.debugIsEchoGated = true }
                    return
                }
                Task { @MainActor in self.debugIsEchoGated = false }
                print("[GeminiLive] 🎤 사용자 끼어들기 감지 (energy: \(String(format: "%.4f", energy)), threshold: \(threshold))")
            } else {
                Task { @MainActor in self.debugIsEchoGated = false }
            }

            guard let pcmBuffer = self.convertBuffer(buffer, from: inputHWFormat, to: targetFormat, converter: converter) else {
                return
            }

            let frameLength = Int(pcmBuffer.frameLength)
            guard frameLength > 0, let channelData = pcmBuffer.int16ChannelData else { return }

            let data = Data(bytes: channelData[0], count: frameLength * 2)
            let base64 = data.base64EncodedString()

            Task { @MainActor in
                self.sendAudioChunk(base64)
            }
        }

        do {
            engine.prepare()
            try engine.start()
            print("[GeminiLive] 🎙️ 오디오 엔진 시작")
        } catch {
            print("[GeminiLive] 오디오 엔진 시작 실패: \(error)")
            sessionState = .error("오디오 엔진 시작 실패")
            return
        }

        self.audioEngine = engine
        self.playerNode = player
        self.playerMixer = mixer
    }

    // MARK: - Audio Energy (에코 vs 실제 음성 구분)
    /// 마이크 입력의 RMS 에너지 계산 (오디오 스레드에서 호출)
    private nonisolated func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sumOfSquares: Float = 0
        let ptr = channelData[0]
        for i in 0..<count {
            let sample = ptr[i]
            sumOfSquares += sample * sample
        }
        return sqrt(sumOfSquares / Float(count))
    }

    private func convertBuffer(_ buffer: AVAudioPCMBuffer, from sourceFormat: AVAudioFormat, to targetFormat: AVAudioFormat, converter: AVAudioConverter?) -> AVAudioPCMBuffer? {
        guard let converter = converter else { return nil }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else { return nil }

        var error: NSError?
        var consumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error = error {
            print("[GeminiLive] 변환 에러: \(error)")
            return nil
        }
        return outputBuffer
    }

    private func stopAudioEngine() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        playerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        playerMixer = nil
    }

    // MARK: - Audio Playback (Output)
    private func playAudioData(_ data: Data, forTurnId turnId: UInt64) {
        // 이미 지나간 턴의 오디오는 재생하지 않음 (겹침 방지)
        guard turnId == modelTurnId else {
            print("[GeminiLive] ⏭️ 이전 턴(\(turnId)) 오디오 무시 (현재: \(modelTurnId))")
            return
        }

        guard let playerNode = playerNode,
              let engine = audioEngine,
              engine.isRunning else { return }

        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: outputSampleRate, channels: 1, interleaved: true)!
        let frameCount = UInt32(data.count / 2)

        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }

        buffer.frameLength = frameCount
        data.withUnsafeBytes { rawPtr in
            if let src = rawPtr.baseAddress {
                memcpy(buffer.int16ChannelData![0], src, data.count)
            }
        }

        if !playerNode.isPlaying {
            playerNode.play()
        }
        playerNode.scheduleBuffer(buffer)
    }

    private func stopPlayback() {
        // stop()은 스케줄된 버퍼도 모두 제거함
        playerNode?.stop()
        pendingAudioBuffers = []
    }

    // MARK: - Session Timer (14-min reconnect)
    private func startSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 14 * 60, repeats: false) { [weak self] _ in
            Task { @MainActor in
                print("[GeminiLive] ⏰ 14분 세션 타이머 - 재연결")
                self?.attemptReconnect()
            }
        }
    }

    private func attemptReconnect() {
        reconnectAttempts += 1
        guard reconnectAttempts <= maxReconnectAttempts else {
            print("[GeminiLive] ❌ 최대 재연결 횟수 초과 (\(maxReconnectAttempts)회)")
            sessionState = .error("연결 실패 - 재시도 횟수 초과")
            return
        }

        print("[GeminiLive] 🔄 재연결 시도 \(reconnectAttempts)/\(maxReconnectAttempts)")
        let savedPrompt = systemPrompt
        let savedMemory = memoryContext
        let savedCallback = onConversationTurn
        let attempts = reconnectAttempts

        disconnect()

        Task {
            let delay = UInt64(attempts) * 2_000_000_000 // 점진적 딜레이
            try? await Task.sleep(nanoseconds: delay)
            self.systemPrompt = savedPrompt
            self.memoryContext = savedMemory
            self.onConversationTurn = savedCallback
            self.reconnectAttempts = attempts
            self.connect()
        }
    }
}
