import SwiftUI

struct CompanionProfileDetailView: View {
    let companion: CompanionType
    var onChat: (() -> Void)?
    var onCall: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var currentImageIndex = 0
    @State private var backgroundImage = ""
    @State private var dragOffset: CGFloat = 0

    private var imageNames: [String] { companion.profileImageNames }
    private var hasImages: Bool { !imageNames.isEmpty }
    private var isOn: Bool { companion == .on }
    private var accentColor: Color { isOn ? .orange : .indigo }

    var body: some View {
        ZStack {
            // Background
            backgroundLayer

            VStack(spacing: 0) {
                // Top bar
                topBar

                Spacer()

                // Profile content
                profileContent
                    .padding(.bottom, 40)

                // Action buttons
                actionButtons
                    .padding(.bottom, 50)
            }
        }
        .onAppear {
            if hasImages {
                backgroundImage = imageNames[0]
            }
        }
    }

    // MARK: - Background
    private var backgroundLayer: some View {
        ZStack {
            if hasImages {
                Image(backgroundImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
                    .blur(radius: 30)
                    .scaleEffect(1.2)
            }

            LinearGradient(
                colors: [
                    Color.black.opacity(0.3),
                    Color.black.opacity(0.6),
                    Color.black.opacity(0.85)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Profile Content
    private var profileContent: some View {
        VStack(spacing: 20) {
            // Photo carousel
            if hasImages {
                photoCarousel
            } else {
                // Emoji fallback
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isOn
                                    ? [Color.orange.opacity(0.6), Color.pink.opacity(0.4)]
                                    : [Color.indigo.opacity(0.6), Color.blue.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 140, height: 140)
                    Text(companion.emoji)
                        .font(.system(size: 64))
                }
            }

            // Name
            Text(companion.displayName)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)

            // Status message
            Text(companion.statusMessage)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    // MARK: - Photo Carousel
    private var photoCarousel: some View {
        VStack(spacing: 14) {
            TabView(selection: $currentImageIndex) {
                ForEach(Array(imageNames.enumerated()), id: \.offset) { index, name in
                    Image(name)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 180, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(width: 220, height: 200)
            .onChange(of: currentImageIndex) { _, newIndex in
                withAnimation(.easeInOut(duration: 0.5)) {
                    backgroundImage = imageNames[newIndex]
                }
            }

            // Page dots
            if imageNames.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<imageNames.count, id: \.self) { index in
                        Circle()
                            .fill(currentImageIndex == index ? Color.white : Color.white.opacity(0.35))
                            .frame(width: 6, height: 6)
                            .animation(.easeInOut(duration: 0.2), value: currentImageIndex)
                    }
                }
            }
        }
    }

    // MARK: - Action Buttons
    private var actionButtons: some View {
        HStack(spacing: 44) {
            // Chat
            actionButton(icon: "message.fill", label: "1:1 채팅") {
                dismiss()
                onChat?()
            }

            // Call
            actionButton(icon: "phone.fill", label: "통화") {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onCall?()
                }
            }
        }
    }

    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                }
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

#Preview {
    CompanionProfileDetailView(companion: .on)
}
