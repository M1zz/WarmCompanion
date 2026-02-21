import SwiftUI

struct MessageBubbleView: View {
    let message: Message
    let companionName: String
    let showTimestamp: Bool
    let showProfile: Bool
    let isStreaming: Bool
    var onSpeakTapped: (() -> Void)? = nil
    
    var body: some View {
        if message.isFromUser {
            userBubble
        } else {
            companionBubble
        }
    }
    
    // MARK: - User Bubble (Right side)
    private var userBubble: some View {
        HStack(alignment: .bottom, spacing: 4) {
            Spacer(minLength: 60)
            
            if showTimestamp {
                timestampView
            }
            
            Text(message.content)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    LinearGradient(
                        colors: [Color.orange, Color.orange.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(ChatBubbleShape(isFromUser: true))
        }
        .padding(.trailing, 12)
        .padding(.leading, 4)
        .padding(.vertical, 1)
    }
    
    // MARK: - Companion Bubble (Left side)
    private var companionBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            // Profile
            if showProfile {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.5), Color.pink.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)

                    Text("🤗")
                        .font(.system(size: 18))
                }
            } else {
                Color.clear
                    .frame(width: 36, height: 36)
            }

            VStack(alignment: .leading, spacing: 3) {
                if showProfile {
                    Text(companionName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .bottom, spacing: 4) {
                    VStack(alignment: .leading) {
                        Text(message.content)
                            .font(.system(size: 15))
                            .foregroundStyle(Color(.label))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Color(.systemGray6))
                            .clipShape(ChatBubbleShape(isFromUser: false))

                        // Streaming cursor
                        if isStreaming {
                            HStack(spacing: 2) {
                                Circle()
                                    .fill(Color.orange.opacity(0.6))
                                    .frame(width: 4, height: 4)
                                    .blinkAnimation()
                            }
                            .padding(.leading, 14)
                        }

                        // MARK: - Phase 2: Voice play button
                        if let onSpeakTapped, !isStreaming {
                            Button(action: onSpeakTapped) {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.leading, 14)
                            .padding(.top, 2)
                        }
                    }

                    if showTimestamp {
                        timestampView
                    }

                    Spacer(minLength: 60)
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 1)
    }
    
    // MARK: - Timestamp
    private var timestampView: some View {
        Text(timeString(message.timestamp))
            .font(.system(size: 10))
            .foregroundStyle(Color(.systemGray2))
    }
    
    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "a h:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Chat Bubble Shape (카카오톡 스타일)
struct ChatBubbleShape: Shape {
    let isFromUser: Bool
    
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 16
        let tailSize: CGFloat = 6
        
        var path = Path()
        
        if isFromUser {
            // Right bubble
            path.addRoundedRect(
                in: CGRect(x: rect.minX, y: rect.minY, width: rect.width - tailSize, height: rect.height),
                cornerSize: CGSize(width: radius, height: radius)
            )
        } else {
            // Left bubble
            path.addRoundedRect(
                in: CGRect(x: rect.minX + tailSize, y: rect.minY, width: rect.width - tailSize, height: rect.height),
                cornerSize: CGSize(width: radius, height: radius)
            )
        }
        
        return path
    }
}

// MARK: - Blink Animation
struct BlinkModifier: ViewModifier {
    @State private var isVisible = true
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    isVisible = false
                }
            }
    }
}

extension View {
    func blinkAnimation() -> some View {
        modifier(BlinkModifier())
    }
}

#Preview {
    VStack(spacing: 8) {
        MessageBubbleView(
            message: Message(content: "오늘 회사에서 또 혼났어", isFromUser: true),
            companionName: "온",
            showTimestamp: true,
            showProfile: false,
            isStreaming: false
        )
        
        MessageBubbleView(
            message: Message(content: "또 혼났구나... 그런 날은 진짜 기운 빠지지. 무슨 일이었어?", isFromUser: false),
            companionName: "온",
            showTimestamp: true,
            showProfile: true,
            isStreaming: false
        )
    }
    .padding()
}
