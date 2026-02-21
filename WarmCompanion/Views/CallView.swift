import SwiftUI
import AVFoundation

struct CallView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    enum CallPhase {
        case ringing
        case connecting
        case connected
        case ended
    }

    @State private var phase: CallPhase = .ringing
    @State private var callSeconds: Int = 0
    @State private var callTimer: Timer?
    @State private var ringingTimer: Timer?
    @State private var ringPulse1 = false
    @State private var ringPulse2 = false
    @State private var ringPulse3 = false
    @State private var waveAmplitudes: [CGFloat] = [0.3, 0.5, 0.8, 0.6, 0.4]
    @State private var waveTimer: Timer?
    @State private var profileScale: CGFloat = 1.0

    // Ringtone
    @State private var ringtonePlayer: AVAudioPlayer?

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
                Spacer()
                    .frame(height: 80)

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

                // Profile area
                profileArea
                    .frame(height: 240)

                Spacer()

                // Call duration
                if phase == .connected {
                    Text(callTimeString)
                        .font(.system(size: 18, weight: .light, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, 40)
                        .transition(.opacity)
                }

                if phase == .ended {
                    Text(callTimeString)
                        .font(.system(size: 16, weight: .light, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.bottom, 40)
                        .transition(.opacity)
                }

                // Buttons
                bottomButtons
                    .padding(.bottom, 60)
            }
        }
        .onAppear {
            startRinging()
        }
        .onDisappear {
            cleanup()
        }
        .onChange(of: viewModel.voiceService.isSpeaking) { _, isSpeaking in
            if phase == .connected && !isSpeaking {
                endCall()
            }
        }
    }

    // MARK: - Status Text
    private var statusText: some View {
        Group {
            switch phase {
            case .ringing:
                Text("온에게서 전화가 왔어요")
                    .foregroundStyle(.white.opacity(0.7))
            case .connecting:
                HStack(spacing: 6) {
                    ProgressView()
                        .tint(.white.opacity(0.6))
                        .scaleEffect(0.8)
                    Text("연결 중...")
                        .foregroundStyle(.green.opacity(0.8))
                }
            case .connected:
                Text("통화 중")
                    .foregroundStyle(.green)
            case .ended:
                Text("통화 종료")
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .font(.system(size: 16, weight: .medium))
    }

    // MARK: - Profile Area
    private var profileArea: some View {
        ZStack {
            // Pulse rings during ringing
            if phase == .ringing {
                pulseRing(trigger: ringPulse1)
                pulseRing(trigger: ringPulse2)
                pulseRing(trigger: ringPulse3)
            }

            // Connected glow
            if phase == .connected {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.orange.opacity(0.12), Color.clear],
                            center: .center,
                            startRadius: 50,
                            endRadius: 120
                        )
                    )
                    .frame(width: 220, height: 220)

                soundWaveIndicator
            }

            // Profile
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.7), Color.pink.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .shadow(color: .orange.opacity(phase == .connected ? 0.3 : 0.1), radius: 20)

                Text("🤗")
                    .font(.system(size: 56))
            }
            .scaleEffect(profileScale)
        }
    }

    private func pulseRing(trigger: Bool) -> some View {
        Circle()
            .stroke(Color.orange.opacity(0.2), lineWidth: 1.5)
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
            case .ringing:
                HStack(spacing: 70) {
                    // Decline
                    callActionButton(
                        icon: "phone.down.fill",
                        color: .red,
                        label: "거절",
                        action: declineCall
                    )

                    // Accept
                    callActionButton(
                        icon: "phone.fill",
                        color: .green,
                        label: "수락",
                        iconRotation: -135,
                        action: acceptCall
                    )
                }

            case .connecting:
                callActionButton(icon: "phone.down.fill", color: .red, label: "취소", action: declineCall)

            case .connected:
                HStack(spacing: 44) {
                    smallButton(icon: "mic.slash.fill", label: "음소거")
                    callActionButton(icon: "phone.down.fill", color: .red, label: "종료", action: endCall)
                    smallButton(icon: "speaker.wave.2.fill", label: "스피커", active: true)
                }

            case .ended:
                EmptyView()
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

    // MARK: - Actions
    private func startRinging() {
        // Initial haptic
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)

        // Pulse animations (staggered)
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

        // Profile subtle bounce
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            profileScale = 1.04
        }

        // Periodic haptic (ringing vibration pattern)
        startRingingHaptic()

        // Play system ringtone sound
        playRingtone()
    }

    private func startRingingHaptic() {
        // Immediate first burst
        playRingHapticBurst()

        ringingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            guard phase == .ringing else {
                ringingTimer?.invalidate()
                return
            }
            playRingHapticBurst()
        }
    }

    private func playRingHapticBurst() {
        // Double-tap haptic pattern like real phone ring
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            generator.impactOccurred()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard self.phase == .ringing else { return }
            generator.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                generator.impactOccurred()
            }
        }
    }

    private func playRingtone() {
        // Use system sound for ringtone feel
        AudioServicesPlaySystemSound(1007)  // Tock sound as ring

        // Repeat
        ringingTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
            guard phase == .ringing else { return }
            AudioServicesPlaySystemSound(1007)
        }
    }

    private func acceptCall() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        ringingTimer?.invalidate()
        ringtonePlayer?.stop()

        // Stop profile bounce
        withAnimation(.easeOut(duration: 0.3)) {
            profileScale = 1.0
            phase = .connecting
        }

        // Simulate connection delay → start speaking
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.4)) {
                phase = .connected
            }
            startCallTimer()
            startWaveAnimation()
            viewModel.speakForIncomingCall()
        }
    }

    private func declineCall() {
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.impactOccurred()
        ringingTimer?.invalidate()
        ringtonePlayer?.stop()
        waveTimer?.invalidate()
        dismiss()
    }

    private func endCall() {
        viewModel.voiceService.stopSpeaking()
        callTimer?.invalidate()
        ringingTimer?.invalidate()
        ringtonePlayer?.stop()
        waveTimer?.invalidate()

        withAnimation(.easeInOut(duration: 0.3)) {
            phase = .ended
        }

        // Dismiss after brief pause
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            dismiss()
        }
    }

    private func startCallTimer() {
        callSeconds = 0
        callTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            callSeconds += 1
        }
    }

    private func startWaveAnimation() {
        waveTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
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
        callTimer?.invalidate()
        ringingTimer?.invalidate()
        ringtonePlayer?.stop()
        waveTimer?.invalidate()
        if viewModel.voiceService.isSpeaking {
            viewModel.voiceService.stopSpeaking()
        }
    }
}

#Preview {
    CallView()
        .environmentObject(ChatViewModel())
}
