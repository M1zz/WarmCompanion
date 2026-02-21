import SwiftUI

@main
struct WarmCompanionApp: App {
    @StateObject private var chatViewModel = ChatViewModel()
    
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ChatView()
            }
            .environmentObject(chatViewModel)
        }
    }
}
