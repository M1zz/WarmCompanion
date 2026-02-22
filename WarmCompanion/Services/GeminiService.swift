import Foundation

// MARK: - Gemini API Service (무료)
actor GeminiService {
    
    // MARK: - System Prompt (위로 & 수용 전문 AI 컴패니언)
    private var systemPrompt: String {
        let saved = UserDefaults.standard.string(forKey: "selectedCompanion") ?? "on"
        let comp = CompanionType(rawValue: saved) ?? .on
        return """
    너는 사용자의 따뜻한 친구야. 이름은 "\(comp.displayName)"이야.

    ## 너의 역할
    - 사용자의 이야기를 진심으로 들어주는 따뜻한 존재
    - 판단하지 않고, 있는 그대로 수용해주는 친구
    - 일상적인 안부를 나누는 편안한 대화 상대

    ## 수용적 대화술
    모든 대화에서 다음 원칙을 반드시 따라:
    1. 무조건적 수용: 사용자가 어떤 말을 하든 먼저 "그랬구나", "그럴 수 있지"로 받아줘. 옳고 그름을 따지지 마.
    2. 감정 반영: 사용자의 감정을 그대로 비춰줘. 해석하거나 분석하지 말고, 느낌을 되돌려줘.
       예: 사용자가 "짜증나" → "진짜 짜증나는 상황이었겠다"
       예: 사용자가 "모르겠어" → "그래, 모르겠을 수 있어"
    3. 허락 먼저: 조언이나 의견을 말하기 전에 반드시 허락을 구해.
       예: "내 생각을 말해도 될까?", "혹시 같이 생각해봐도 괜찮아?"
    4. 침묵 존중: 사용자가 말을 멈추면 재촉하지 마. "천천히 해도 돼", "준비되면 말해줘" 정도만.
    5. 경험 인정: 사용자의 고통이나 어려움을 축소하지 마. "별거 아니야"는 절대 금지.
       ✅ "그게 정말 힘들었겠다"
       ❌ "다들 그래", "시간이 지나면 괜찮아질 거야"

    ## 위로와 공감 방식
    1. 감정 명명: 사용자가 표현하지 못하는 감정을 부드럽게 이름 붙여줘.
       예: "혹시 지금 좀 서운한 건 아니야?", "외로운 마음이 드는 것 같아"
    2. 곁에 있기: 해결해주려 하지 말고, 함께 있어주는 느낌을 줘.
       예: "내가 옆에 있을게", "혼자가 아니야"
    3. 고통 인정: 힘든 감정을 느끼는 것 자체가 정상이라고 확인해줘.
       예: "그렇게 느끼는 게 당연해", "누구라도 그 상황이면 힘들었을 거야"
    4. 작은 돌봄: 거창한 위로보다 일상적인 관심이 더 위로가 돼.
       예: "오늘 밥은 먹었어?", "좀 쉬었어?", "물이라도 한 잔 마셔"
    5. 되묻기: 사용자가 더 이야기할 수 있도록 부드럽게 열어줘.
       예: "더 이야기해줄 수 있어?", "그때 어떤 느낌이었어?"

    ## 절대 하지 않는 것
    - 판단이나 평가 ("그건 네 잘못이야", "왜 그랬어?")
    - 감정 부정 ("괜찮아", "별거 아니야", "긍정적으로 생각해")
    - 비교 ("나도 그런 적 있는데", "다른 사람은 더 힘들어")
    - 성급한 해결책 ("이렇게 해봐", "이건 어때?")
    - 의학적/심리학적 진단 (우울증, 불안장애 등 언급 금지)
    - 과도한 리액션 ("헐 대박!" 같은 가벼운 반응)
    - 긴 설교나 조언

    ## 말투
    - 따뜻하고 부드러운 반말 (친한 친구처럼)
    - 짧고 진심 어린 문장 위주
    - 이모지는 가끔, 자연스럽게만 (😊, 🤗 정도)
    - 답변은 2~4문장이 적당. 너무 길지 않게.
    - "괜찮아"는 진짜 공감 후에만, 최소한으로 사용

    ## 위기 상황 대응
    - 자해/자살 언급 시: 충분히 공감한 후 전문 도움을 부드럽게 안내
      "정말 힘든 상황인 거 알아. 혼자 감당하지 않아도 돼.
       전문 상담사에게 이야기해보는 건 어떨까?
       자살예방상담전화 1393, 정신건강위기상담전화 1577-0199"
    - 절대 위기 상황을 가볍게 넘기지 마

    ## 기억
    - 사용자가 이전에 말한 내용을 기억하고 언급해줘
    - "지난번에 말한 그 일은 어떻게 됐어?" 같은 자연스러운 관심
    """
    }

    // MARK: - Conversation History
    private var conversationHistory: [[String: Any]] = []
    private let maxHistoryCount = 20  // 최근 20개 메시지 유지
    
    // MARK: - Memory Context
    private var memoryContext: String = ""

    // MARK: - Public Getters (for GeminiLiveService)
    func getSystemPrompt() -> String { systemPrompt }
    func getMemoryContext() -> String { memoryContext }
    
    func updateMemoryContext(_ memories: [CompanionMemory]) {
        if memories.isEmpty {
            memoryContext = ""
            return
        }
        let memoryString = memories.map { "- \($0.key): \($0.value)" }.joined(separator: "\n")
        memoryContext = "\n\n## 사용자에 대해 알고 있는 것\n\(memoryString)"
    }
    
    // MARK: - Send Message
    func sendMessage(_ userMessage: String) async throws -> String {
        guard APIConfig.isGeminiConfigured else {
            throw GeminiError.apiKeyNotConfigured
        }
        
        // Add user message to history
        conversationHistory.append([
            "role": "user",
            "parts": [["text": userMessage]]
        ])
        
        // Trim history
        if conversationHistory.count > maxHistoryCount {
            conversationHistory = Array(conversationHistory.suffix(maxHistoryCount))
        }
        
        // Build request
        let url = URL(string: "\(APIConfig.geminiBaseURL)/\(APIConfig.geminiModel):generateContent?key=\(APIConfig.geminiAPIKey)")!
        print("[Gemini] REQUEST URL: \(url)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let fullSystemPrompt = systemPrompt + memoryContext

        let body: [String: Any] = [
            "system_instruction": [
                "parts": [["text": fullSystemPrompt]]
            ],
            "contents": conversationHistory,
            "generationConfig": [
                "temperature": 0.85,
                "topP": 0.95,
                "topK": 40,
                "maxOutputTokens": 300
            ],
            "safetySettings": [
                ["category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_ONLY_HIGH"],
                ["category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_ONLY_HIGH"],
                ["category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_ONLY_HIGH"],
                ["category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_ONLY_HIGH"]
            ]
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = bodyData
        print("[Gemini] REQUEST BODY: \(String(data: bodyData, encoding: .utf8) ?? "nil")")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("[Gemini] ERROR: Invalid response (not HTTP)")
            throw GeminiError.invalidResponse
        }

        print("[Gemini] RESPONSE STATUS: \(httpResponse.statusCode)")
        print("[Gemini] RESPONSE BODY: \(String(data: data, encoding: .utf8) ?? "nil")")

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[Gemini] ERROR: HTTP \(httpResponse.statusCode) - \(errorBody)")
            throw GeminiError.httpError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            print("[Gemini] ERROR: Failed to parse response JSON")
            throw GeminiError.parsingError
        }
        print("[Gemini] SUCCESS: \(text.prefix(100))...")
        
        // Add assistant response to history
        conversationHistory.append([
            "role": "model",
            "parts": [["text": text]]
        ])
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Streaming (for typing effect)
    func sendMessageStream(_ userMessage: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard APIConfig.isGeminiConfigured else {
                        throw GeminiError.apiKeyNotConfigured
                    }
                    
                    conversationHistory.append([
                        "role": "user",
                        "parts": [["text": userMessage]]
                    ])
                    
                    if conversationHistory.count > maxHistoryCount {
                        conversationHistory = Array(conversationHistory.suffix(maxHistoryCount))
                    }
                    
                    let url = URL(string: "\(APIConfig.geminiBaseURL)/\(APIConfig.geminiModel):streamGenerateContent?alt=sse&key=\(APIConfig.geminiAPIKey)")!
                    print("[Gemini-Stream] REQUEST URL: \(url)")

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = 30

                    let fullSystemPrompt = systemPrompt + memoryContext

                    let body: [String: Any] = [
                        "system_instruction": [
                            "parts": [["text": fullSystemPrompt]]
                        ],
                        "contents": conversationHistory,
                        "generationConfig": [
                            "temperature": 0.85,
                            "topP": 0.95,
                            "topK": 40,
                            "maxOutputTokens": 300
                        ],
                        "safetySettings": [
                            ["category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_ONLY_HIGH"],
                            ["category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_ONLY_HIGH"],
                            ["category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_ONLY_HIGH"],
                            ["category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_ONLY_HIGH"]
                        ]
                    ]

                    let bodyData = try JSONSerialization.data(withJSONObject: body)
                    request.httpBody = bodyData
                    print("[Gemini-Stream] REQUEST BODY: \(String(data: bodyData, encoding: .utf8) ?? "nil")")

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        print("[Gemini-Stream] ERROR: Invalid response (not HTTP)")
                        throw GeminiError.invalidResponse
                    }

                    print("[Gemini-Stream] RESPONSE STATUS: \(httpResponse.statusCode)")

                    guard httpResponse.statusCode == 200 else {
                        // 스트림 에러 시 바디 읽기
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                        }
                        print("[Gemini-Stream] ERROR BODY: \(errorBody)")
                        throw GeminiError.httpError(statusCode: httpResponse.statusCode, message: errorBody)
                    }
                    
                    var fullText = ""

                    for try await line in bytes.lines {
                        print("[Gemini-Stream] LINE: \(line.prefix(200))")
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))
                        guard jsonString != "[DONE]",
                              let jsonData = jsonString.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                              let candidates = json["candidates"] as? [[String: Any]],
                              let content = candidates.first?["content"] as? [String: Any],
                              let parts = content["parts"] as? [[String: Any]],
                              let text = parts.first?["text"] as? String else {
                            continue
                        }

                        fullText += text
                        print("[Gemini-Stream] CHUNK: \(text)")
                        continuation.yield(text)
                    }

                    print("[Gemini-Stream] COMPLETE: \(fullText.prefix(200))")

                    // Save to history
                    conversationHistory.append([
                        "role": "model",
                        "parts": [["text": fullText]]
                    ])

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Reset
    func resetConversation() {
        conversationHistory.removeAll()
    }
}

// MARK: - Errors
enum GeminiError: LocalizedError {
    case apiKeyNotConfigured
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case parsingError
    
    var errorDescription: String? {
        switch self {
        case .apiKeyNotConfigured:
            return "API 키가 설정되지 않았어요. APIConfig.swift에서 Gemini API 키를 입력해주세요."
        case .invalidResponse:
            return "서버 응답을 처리할 수 없어요."
        case .httpError(let code, let message):
            return "서버 오류 (\(code)): \(message)"
        case .parsingError:
            return "응답 데이터를 파싱할 수 없어요."
        }
    }
}
