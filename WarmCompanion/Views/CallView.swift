import SwiftUI
import AVFoundation

struct CallView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - Call Mode
    var isIncoming: Bool = false  // true = 수신 전화

    // MARK: - Call State
    enum CallPhase {
        case incoming     // 수신 전화 (받기/거절)
        case calling      // 전화 거는 중 (따르르릉...)
        case connected    // 통화 연결됨
        case ended        // 통화 종료
    }

    @State private var phase: CallPhase = .calling
    @State private var callSeconds: Int = 0
    @State private var callTimer: Timer?
    @State private var ringingTimer: Timer?
    @State private var waveTimer: Timer?
    @State private var isCallActive = true
    @State private var isMuted = false
    @State private var showDebugPanel = false
    @State private var showLogSheet = false
    @State private var experimentRating: Int = 3
    @State private var experimentNote: String = ""
    @State private var savedLogs: [VoiceTuningLog] = []
    @State private var showSavedToast = false

    // Animations
    @State private var ringPulse1 = false
    @State private var ringPulse2 = false
    @State private var ringPulse3 = false
    @State private var waveAmplitudes: [CGFloat] = [0.3, 0.5, 0.8, 0.6, 0.4]

    private var liveService: GeminiLiveService { viewModel.geminiLiveService }
    private var isOn: Bool { viewModel.companion == .on }
    private var accentColor: Color { isOn ? .orange : .indigo }

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.12),
                    Color(red: 0.04, green: 0.04, blue: 0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // 통화 UI (기존)
            VStack(spacing: 0) {
                Spacer().frame(height: 80)

                // Status
                statusText
                    .padding(.bottom, 14)

                // Name
                Text(viewModel.companionName)
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.white)
                    .padding(.bottom, 6)

                Text("모바일")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.4))

                Spacer()

                // Profile
                profileArea
                    .frame(height: 240)

                Spacer()

                // Buttons
                bottomButtons
                    .padding(.bottom, showDebugPanel ? 10 : 60)
            }

            // 디버그 패널 (하단 오버레이)
            if phase == .connected {
                VStack(spacing: 0) {
                    Spacer()

                    // 토글 핸들
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showDebugPanel.toggle()
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Capsule()
                                .fill(Color.white.opacity(0.3))
                                .frame(width: 36, height: 4)
                            HStack(spacing: 4) {
                                Image(systemName: "wrench.and.screwdriver")
                                    .font(.system(size: 10))
                                if !showDebugPanel {
                                    Text("실험 패널")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                Image(systemName: showDebugPanel ? "chevron.down" : "chevron.up")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    }
                    .background(
                        UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                            .fill(Color.black.opacity(0.7))
                    )

                    if showDebugPanel {
                        ScrollView {
                            debugTuningPanel
                        }
                        .frame(maxHeight: UIScreen.main.bounds.height * 0.45)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        .onAppear {
            if isIncoming {
                startIncoming()
            } else {
                startCalling()
            }
        }
        .onDisappear {
            cleanup()
        }
        .onChange(of: liveService.sessionState) { _, newState in
            if case .connected = newState, (phase == .calling || phase == .incoming) {
                // WebSocket 연결 완료 → 통화 시작
                withAnimation(.easeInOut(duration: 0.3)) {
                    phase = .connected
                }
                startCallTimer()
                startWaveAnimation()
            } else if case .error(let msg) = newState {
                print("[Call] Live 에러: \(msg)")
            }
        }
        .onChange(of: liveService.isModelSpeaking) { _, speaking in
            if speaking {
                startWaveAnimation()
            }
        }
    }

    // MARK: - Status Text
    private var statusText: some View {
        Group {
            switch phase {
            case .incoming:
                Text("전화가 왔어요")
                    .foregroundStyle(.green)
            case .calling:
                Text("전화 거는 중...")
                    .foregroundStyle(.white.opacity(0.7))
            case .connected:
                Text(callTimeString)
                    .foregroundStyle(.white.opacity(0.7))
            case .ended:
                Text("통화 종료")
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .font(.system(size: 16, weight: .medium))
        .animation(.easeInOut(duration: 0.3), value: phase)
    }

    // MARK: - Profile Area
    private var profileArea: some View {
        ZStack {
            // Calling/Incoming pulse
            if phase == .calling || phase == .incoming {
                pulseRing(trigger: ringPulse1)
                pulseRing(trigger: ringPulse2)
                pulseRing(trigger: ringPulse3)
            }

            // AI speaking glow
            if phase == .connected && liveService.isModelSpeaking {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [accentColor.opacity(0.12), Color.clear],
                            center: .center,
                            startRadius: 50,
                            endRadius: 120
                        )
                    )
                    .frame(width: 220, height: 220)

                soundWaveIndicator
            }

            // Profile
            CompanionProfileView(companion: viewModel.companion, size: 120)
                .shadow(color: accentColor.opacity(phase == .connected ? 0.3 : 0.1), radius: 20)
        }
    }

    private func pulseRing(trigger: Bool) -> some View {
        Circle()
            .stroke(accentColor.opacity(0.2), lineWidth: 1.5)
            .frame(width: 180, height: 180)
            .scaleEffect(trigger ? 1.6 : 1.0)
            .opacity(trigger ? 0 : 0.7)
    }

    // MARK: - Sound Wave
    private var soundWaveIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 3, height: 8 + 14 * waveAmplitudes[index])
            }
        }
        .offset(y: 86)
    }

    // MARK: - Bottom Buttons
    private var bottomButtons: some View {
        Group {
            switch phase {
            case .incoming:
                HStack(spacing: 60) {
                    callActionButton(icon: "phone.down.fill", color: .red, label: "거절", action: endCall)
                    callActionButton(icon: "phone.fill", color: .green, label: "받기", iconRotation: -135, action: acceptIncomingCall)
                }

            case .calling:
                callActionButton(icon: "phone.down.fill", color: .red, label: "취소", action: endCall)

            case .connected:
                HStack(spacing: 44) {
                    muteButton
                    callActionButton(icon: "phone.down.fill", color: .red, label: "종료", action: endCall)
                    smallButton(icon: "speaker.wave.2.fill", label: "스피커", active: true)
                }

            case .ended:
                EmptyView()
            }
        }
    }

    private var muteButton: some View {
        Button {
            isMuted.toggle()
            liveService.setMicMuted(isMuted)
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(isMuted ? 0.4 : 0.12))
                        .frame(width: 54, height: 54)
                    Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.9))
                }
                Text(isMuted ? "음소거 해제" : "음소거")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func callActionButton(
        icon: String,
        color: Color,
        label: String,
        iconRotation: Double = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(color)
                        .frame(width: 66, height: 66)
                        .shadow(color: color.opacity(0.4), radius: 8, y: 2)
                    Image(systemName: icon)
                        .font(.system(size: 26))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(iconRotation))
                }
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private func smallButton(icon: String, label: String, active: Bool = false) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(active ? 0.3 : 0.12))
                    .frame(width: 54, height: 54)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.9))
            }
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Call Time
    private var callTimeString: String {
        let min = callSeconds / 60
        let sec = callSeconds % 60
        return String(format: "%02d:%02d", min, sec)
    }

    // MARK: - Call Flow

    /// 1. 전화 거는 화면
    private func startCalling() {
        print("[Call] 전화 거는 중...")
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        // Pulse animation
        withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
            ringPulse1 = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
                ringPulse2 = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
                ringPulse3 = true
            }
        }

        // Ring sound
        AudioServicesPlaySystemSound(1007)
        ringingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            guard phase == .calling else {
                ringingTimer?.invalidate()
                return
            }
            AudioServicesPlaySystemSound(1007)
        }

        // 2~3초 후 "상대방이 받음" → Live API 연결
        let answerDelay = Double.random(in: 2.0...3.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + answerDelay) {
            guard isCallActive else { return }
            answerCall()
        }
    }

    /// 2. 상대방이 받음 → Gemini Live 연결
    private func answerCall() {
        print("[Call] 상대방 받음 -> Live API 연결 시작")
        ringingTimer?.invalidate()

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        viewModel.startLiveCall()
    }

    /// 수신 전화 화면 시작
    private func startIncoming() {
        print("[Call] 수신 전화 표시")
        phase = .incoming

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        // Pulse animation
        withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
            ringPulse1 = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
                ringPulse2 = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
                ringPulse3 = true
            }
        }

        // Ring sound
        AudioServicesPlaySystemSound(1007)
        ringingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            guard phase == .incoming else {
                ringingTimer?.invalidate()
                return
            }
            AudioServicesPlaySystemSound(1007)
        }
    }

    /// 수신 전화 받기
    private func acceptIncomingCall() {
        print("[Call] 수신 전화 받음 -> Live API 연결")
        ringingTimer?.invalidate()

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        viewModel.startLiveCall()
    }

    /// 통화 종료
    private func endCall() {
        print("[Call] 통화 종료 - \(callTimeString)")
        isCallActive = false

        viewModel.endLiveCall()
        callTimer?.invalidate()
        ringingTimer?.invalidate()
        waveTimer?.invalidate()

        withAnimation(.easeInOut(duration: 0.3)) {
            phase = .ended
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            dismiss()
        }
    }

    // MARK: - Timers
    private func startCallTimer() {
        callSeconds = 0
        callTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            callSeconds += 1
        }
    }

    private func startWaveAnimation() {
        waveTimer?.invalidate()
        waveTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [self] _ in
            guard phase == .connected else {
                waveTimer?.invalidate()
                return
            }
            withAnimation(.easeInOut(duration: 0.25)) {
                waveAmplitudes = (0..<5).map { _ in CGFloat.random(in: 0.15...1.0) }
            }
        }
    }

    private func cleanup() {
        isCallActive = false
        callTimer?.invalidate()
        ringingTimer?.invalidate()
        waveTimer?.invalidate()
        viewModel.endLiveCall()
    }

    // MARK: - Debug Tuning Panel
    private var debugTuningPanel: some View {
        VStack(spacing: 0) {
            // 실시간 메트릭
            metricsBar
                .padding(.horizontal, 16)
                .padding(.top, 8)

            Divider().background(Color.white.opacity(0.1)).padding(.vertical, 6)

            // 슬라이더들
            VStack(spacing: 10) {
                tuningSlider(
                    label: "에코 게이트",
                    value: Binding(
                        get: { Double(liveService.energyThreshold) },
                        set: { liveService.energyThreshold = Float($0) }
                    ),
                    range: 0.005...0.15,
                    format: "%.3f",
                    hint: "낮을수록 끼어들기 쉬움"
                )

                tuningSlider(
                    label: "턴 전환 딜레이",
                    value: Binding(
                        get: { Double(liveService.turnCompleteDelayMs) },
                        set: { liveService.turnCompleteDelayMs = Int($0) }
                    ),
                    range: 0...500,
                    format: "%.0fms",
                    hint: "낮을수록 빠른 응답"
                )

                tuningSlider(
                    label: "침묵 판단",
                    value: Binding(
                        get: { Double(liveService.silenceDurationMs) },
                        set: { liveService.silenceDurationMs = Int($0) }
                    ),
                    range: 100...1000,
                    format: "%.0fms",
                    hint: "재연결 시 적용"
                )

                // 감도 토글
                HStack(spacing: 12) {
                    sensitivityPicker(
                        label: "시작감도",
                        value: Binding(
                            get: { liveService.startSensitivity },
                            set: { liveService.startSensitivity = $0 }
                        ),
                        options: ["START_SENSITIVITY_HIGH", "START_SENSITIVITY_LOW"],
                        labels: ["높음", "낮음"]
                    )
                    sensitivityPicker(
                        label: "종료감도",
                        value: Binding(
                            get: { liveService.endSensitivity },
                            set: { liveService.endSensitivity = $0 }
                        ),
                        options: ["END_SENSITIVITY_HIGH", "END_SENSITIVITY_LOW"],
                        labels: ["높음", "낮음"]
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            Divider().background(Color.white.opacity(0.1)).padding(.vertical, 4)

            // 실험 기록 섹션
            experimentLogSection
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

            // 하단 버튼들
            HStack(spacing: 12) {
                // 재연결 버튼
                Button {
                    liveService.disconnect()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        viewModel.startLiveCall()
                    }
                } label: {
                    Text("설정 적용 (재연결)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(Capsule())
                }

                // 기록 보기
                Button {
                    savedLogs = PersistenceService.shared.loadTuningLogs()
                    showLogSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "list.clipboard")
                            .font(.system(size: 10))
                        Text("기록 보기")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.15))
                    .clipShape(Capsule())
                }
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 16)
        .background(Color.black.opacity(0.7))
        .overlay {
            if showSavedToast {
                VStack {
                    Text("기록 저장됨")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.8))
                        .clipShape(Capsule())
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
            }
        }
        .sheet(isPresented: $showLogSheet) {
            experimentLogListView
        }
    }

    private var metricsBar: some View {
        HStack(spacing: 0) {
            metricBadge(
                icon: "waveform",
                value: String(format: "%.3f", liveService.debugCurrentRMS),
                color: liveService.debugIsEchoGated ? .red : .green
            )
            Spacer()
            metricBadge(
                icon: "clock",
                value: "\(liveService.debugLastResponseLatencyMs)ms",
                color: liveService.debugLastResponseLatencyMs > 1000 ? .red : .green
            )
            Spacer()
            metricBadge(
                icon: "arrow.triangle.2.circlepath",
                value: "\(liveService.debugTurnCount)",
                color: .blue
            )
            Spacer()
            metricBadge(
                icon: "hand.raised",
                value: "\(liveService.debugInterruptCount)",
                color: .orange
            )
            Spacer()
            metricBadge(
                icon: "xmark.circle",
                value: "\(liveService.debugDroppedAudioCount)",
                color: .red
            )
        }
    }

    private func metricBadge(icon: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color.opacity(0.7))
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(minWidth: 50)
    }

    private func tuningSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String,
        hint: String
    ) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
            }
            HStack(spacing: 8) {
                Slider(value: value, in: range)
                    .tint(accentColor)
                Text(hint)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(width: 70, alignment: .trailing)
            }
        }
    }

    // MARK: - Experiment Log Section (별점 + 메모 + 저장)
    private var experimentLogSection: some View {
        VStack(spacing: 8) {
            // 별점
            HStack(spacing: 2) {
                Text("평가")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                ForEach(1...5, id: \.self) { star in
                    Button {
                        experimentRating = star
                    } label: {
                        Image(systemName: star <= experimentRating ? "star.fill" : "star")
                            .font(.system(size: 16))
                            .foregroundStyle(star <= experimentRating ? .yellow : .white.opacity(0.2))
                    }
                }
            }

            // 메모
            HStack(spacing: 6) {
                TextField("메모 (예: 침묵 줄었음, 에코 있음...)", text: $experimentNote)
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                // 저장
                Button {
                    saveExperimentLog()
                } label: {
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.green)
                        .padding(6)
                        .background(Color.green.opacity(0.15))
                        .clipShape(Circle())
                }
            }
        }
    }

    private func saveExperimentLog() {
        let log = VoiceTuningLog(
            energyThreshold: liveService.energyThreshold,
            turnCompleteDelayMs: liveService.turnCompleteDelayMs,
            silenceDurationMs: liveService.silenceDurationMs,
            startSensitivity: liveService.startSensitivity,
            endSensitivity: liveService.endSensitivity,
            totalTurns: liveService.debugTurnCount,
            interruptCount: liveService.debugInterruptCount,
            droppedAudioCount: liveService.debugDroppedAudioCount,
            avgResponseLatencyMs: liveService.debugAvgResponseLatencyMs,
            callDurationSec: callSeconds,
            rating: experimentRating,
            note: experimentNote
        )
        PersistenceService.shared.appendTuningLog(log)
        experimentNote = ""

        withAnimation(.easeInOut(duration: 0.3)) { showSavedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.3)) { showSavedToast = false }
        }
    }

    // MARK: - Experiment Log List (Sheet)
    private var experimentLogListView: some View {
        NavigationView {
            List {
                if savedLogs.isEmpty {
                    Text("아직 기록이 없습니다")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(savedLogs.sorted(by: { $0.timestamp > $1.timestamp })) { log in
                        VStack(alignment: .leading, spacing: 6) {
                            // 상단: 날짜 + 별점
                            HStack {
                                Text(log.timestamp, style: .date)
                                    .font(.system(size: 12, weight: .medium))
                                Text(log.timestamp, style: .time)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                HStack(spacing: 1) {
                                    ForEach(1...5, id: \.self) { star in
                                        Image(systemName: star <= log.rating ? "star.fill" : "star")
                                            .font(.system(size: 10))
                                            .foregroundStyle(star <= log.rating ? .yellow : .gray.opacity(0.3))
                                    }
                                }
                            }

                            // 메모
                            if !log.note.isEmpty {
                                Text(log.note)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.primary)
                            }

                            // 파라미터
                            HStack(spacing: 8) {
                                paramTag("에코", String(format: "%.3f", log.energyThreshold))
                                paramTag("턴딜레이", "\(log.turnCompleteDelayMs)ms")
                                paramTag("침묵", "\(log.silenceDurationMs)ms")
                            }

                            // 메트릭
                            HStack(spacing: 8) {
                                metricTag("턴", "\(log.totalTurns)")
                                metricTag("인터럽트", "\(log.interruptCount)")
                                metricTag("응답", "\(log.avgResponseLatencyMs)ms")
                                metricTag("통화", formatDuration(log.callDurationSec))
                            }

                            // 감도
                            HStack(spacing: 8) {
                                paramTag("시작", log.startSensitivity.contains("HIGH") ? "높음" : "낮음")
                                paramTag("종료", log.endSensitivity.contains("HIGH") ? "높음" : "낮음")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("실험 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { showLogSheet = false }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if !savedLogs.isEmpty {
                        // 최고 평점 설정 적용
                        Button {
                            applyBestLog()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trophy.fill")
                                    .font(.system(size: 11))
                                Text("최고 설정 적용")
                                    .font(.system(size: 12))
                            }
                            .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
    }

    private func paramTag(_ label: String, _ value: String) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.blue.opacity(0.1))
        .clipShape(Capsule())
    }

    private func metricTag(_ label: String, _ value: String) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.green.opacity(0.1))
        .clipShape(Capsule())
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func applyBestLog() {
        guard let best = savedLogs.max(by: { $0.rating < $1.rating }) else { return }
        liveService.energyThreshold = best.energyThreshold
        liveService.turnCompleteDelayMs = best.turnCompleteDelayMs
        liveService.silenceDurationMs = best.silenceDurationMs
        liveService.startSensitivity = best.startSensitivity
        liveService.endSensitivity = best.endSensitivity
        showLogSheet = false
    }

    private func sensitivityPicker(
        label: String,
        value: Binding<String>,
        options: [String],
        labels: [String]
    ) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            HStack(spacing: 0) {
                ForEach(Array(zip(options, labels)), id: \.0) { option, displayLabel in
                    Button {
                        value.wrappedValue = option
                    } label: {
                        Text(displayLabel)
                            .font(.system(size: 11, weight: value.wrappedValue == option ? .bold : .regular))
                            .foregroundStyle(value.wrappedValue == option ? .white : .white.opacity(0.4))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(
                                value.wrappedValue == option
                                    ? accentColor.opacity(0.3)
                                    : Color.white.opacity(0.05)
                            )
                    }
                }
            }
            .clipShape(Capsule())
        }
    }
}

#Preview {
    CallView()
        .environmentObject(ChatViewModel())
}
