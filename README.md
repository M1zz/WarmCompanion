# 🤗 WarmCompanion (온)

따뜻한 AI 컴패니언 채팅앱 — "위로와 수용이 필요한 사람을 위한 1:1 대화 메신저"

---

## 📱 프로젝트 설정 방법

### Step 1: Xcode 프로젝트 생성
1. Xcode → File → New → Project
2. **iOS → App** 선택
3. 설정:
   - Product Name: `WarmCompanion`
   - Team: (본인 팀)
   - Organization Identifier: (본인 번들 ID)
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Storage: **None**
4. 프로젝트 생성 후, 자동 생성된 `ContentView.swift`와 `WarmCompanionApp.swift` **삭제**

### Step 2: 파일 추가
1. 이 zip 안의 `WarmCompanion/` 폴더 내 모든 파일을 Xcode 프로젝트에 드래그 & 드롭
2. "Copy items if needed" 체크
3. "Create groups" 선택

### Step 3: Assets 설정
- `Resources/Assets.xcassets` 폴더를 기존 Assets.xcassets에 병합
  (또는 기존 것을 삭제하고 이 폴더를 사용)

### Step 4: Target 설정
- iOS Deployment Target: **17.0** 이상
- Device Orientation: Portrait 권장

---

## 🔑 API 키 발급 가이드

### ✅ Phase 1: 텍스트 채팅 (지금 바로 필요)

#### Google Gemini API Key (무료)
1. https://aistudio.google.com/apikey 접속
2. Google 계정으로 로그인
3. "Create API Key" 클릭
4. 키 복사
5. `APIConfig.swift` 파일에서:
   ```swift
   static let geminiAPIKey = "여기에_복사한_키_붙여넣기"
   ```

**무료 한도:**
- Gemini 2.0 Flash: 분당 15회, 일 1,500회
- 개인 앱 테스트에 충분

---

### 🔲 Phase 2: 음성 채팅 (나중에 필요)

#### Apple Speech Framework (무료, STT)
- 별도 API 키 불필요
- Info.plist에 권한 추가만 필요:
  ```xml
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>음성으로 대화하기 위해 음성 인식을 사용합니다.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>음성 메시지를 녹음하기 위해 마이크를 사용합니다.</string>
  ```

#### ElevenLabs API Key (선택, 고품질 TTS)
1. https://elevenlabs.io 접속
2. 계정 생성 (무료)
3. Profile → API Keys → "Create API Key"
4. Voice Library에서 한국어 여성 음성 선택 → Voice ID 복사
5. `APIConfig.swift`에서 주석 해제 후 입력

**무료 한도:** 월 10,000자 (~3분 분량)
**유료:** $5/월부터

---

### 🔲 Phase 3: 영상 메시지 (나중에 필요)

#### 옵션 A: Hedra API (유료, 고품질)
1. https://www.hedra.com 접속
2. 계정 생성 → API 키 발급
3. 캐릭터 이미지 + 음성 → 립싱크 영상 생성

#### 옵션 B: MuseTalk (무료, 오픈소스)
1. https://github.com/TMElyralab/MuseTalk
2. 자체 GPU 서버 필요 (RunPod 등)
3. 실시간 30fps+ 립싱크 가능

---

### 🔲 Phase 4: 실시간 영상통화 (나중에 필요)

#### OpenAI Realtime API (유료)
1. https://platform.openai.com/api-keys 접속
2. API 키 생성
3. WebRTC 기반 실시간 음성 대화
4. MuseTalk과 결합하여 영상통화 구현

---

## 📁 프로젝트 구조

```
WarmCompanion/
├── App/
│   └── WarmCompanionApp.swift          ← 앱 진입점
├── Models/
│   ├── APIConfig.swift                 ← 🔑 API 키 설정 (여기 수정!)
│   └── Message.swift                   ← 메시지/감정/메모리 모델
├── ViewModels/
│   └── ChatViewModel.swift             ← 핵심 비즈니스 로직
├── Views/
│   ├── ChatView.swift                  ← 메인 채팅 화면
│   ├── SettingsView.swift              ← 설정 화면
│   └── Components/
│       └── MessageBubbleView.swift     ← 메시지 버블 UI
├── Services/
│   ├── GeminiService.swift             ← Gemini API 통신
│   ├── PersistenceService.swift        ← 로컬 데이터 저장
│   └── VoiceService.swift              ← 음성 서비스 (Phase 2)
└── Resources/
    └── Assets.xcassets/                ← 앱 아이콘, 색상
```

---

## 🚀 개발 로드맵

### Phase 1: 텍스트 채팅 ✅ (현재)
- [x] 1:1 메신저 스타일 UI
- [x] Gemini 2.0 Flash 연동 (무료)
- [x] 스트리밍 응답 (타이핑 효과)
- [x] 위로/수용 전문 시스템 프롬프트
- [x] 대화 기록 로컬 저장
- [x] 기본 메모리 시스템
- [x] 감정 모델 정의

### Phase 2: 음성 채팅
- [ ] VoiceService.swift 주석 해제
- [ ] Apple Speech STT 연동
- [ ] ElevenLabs TTS 연동 (또는 무료 Apple TTS)
- [ ] 음성 메시지 녹음/재생 UI
- [ ] 음성 통화 모드

### Phase 3: 영상 메시지
- [ ] 캐릭터 이미지 생성 (Stable Diffusion / Flux)
- [ ] 립싱크 영상 생성 (MuseTalk / Hedra)
- [ ] 영상 메시지 재생 UI
- [ ] "상황 사진" 기능

### Phase 4: 실시간 영상통화
- [ ] OpenAI Realtime API 연동
- [ ] WebRTC 영상 스트리밍
- [ ] 실시간 립싱크 렌더링
- [ ] CallKit 연동 (전화 수신 느낌)

---

## 💡 커스터마이징 포인트

### 캐릭터 성격 변경
`GeminiService.swift`의 `systemPrompt`를 수정하면 캐릭터 성격을 바꿀 수 있습니다.

### UI 테마 변경  
`MessageBubbleView.swift`와 `ChatView.swift`의 색상을 수정하세요.
- 현재: 오렌지/핑크 (따뜻한 톤)
- 변경 예: 라벤더/하늘색 (차분한 톤)

### 메모리 강화
`ChatViewModel.swift`의 `extractMemories()` 함수를 확장하면
더 정교한 기억 시스템을 구현할 수 있습니다.
(LLM에게 직접 메모리 추출을 요청하는 방식 추천)

---

## ⚠️ 주의사항

- 이 앱은 전문 심리 상담을 대체하지 않습니다
- 위기 상황 감지 시 전문 기관 안내가 포함되어 있습니다
- API 키를 소스코드에 직접 넣는 것은 개발/테스트용입니다
  → 출시 시에는 서버 프록시를 통해 키를 관리하세요
- 개인정보 보호에 유의하세요 (대화 내용 = 민감 정보)
