import SwiftUI

/// 캐릭터 프로필 이미지 뷰 (이미지가 없으면 emoji fallback)
struct CompanionProfileView: View {
    let companion: CompanionType
    let size: CGFloat

    var body: some View {
        if companion.hasProfileImage {
            Image(companion.profileImageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: companion == .on
                                ? [Color.orange.opacity(0.6), Color.pink.opacity(0.4)]
                                : [Color.indigo.opacity(0.6), Color.blue.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                Text(companion.emoji)
                    .font(.system(size: size * 0.5))
            }
        }
    }
}
