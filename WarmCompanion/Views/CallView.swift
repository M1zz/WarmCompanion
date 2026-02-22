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
                    .padding(.bottom, 60)
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
}

#Preview {
    CallView()
        .environmentObject(ChatViewModel())
}
