import SwiftUI
import UserNotifications

@main
struct WarmCompanionApp: App {
    @StateObject private var chatViewModel = ChatViewModel()
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ChatView()
            }
            .environmentObject(chatViewModel)
            .fullScreenCover(isPresented: $chatViewModel.showIncomingCall) {
                CallView(isIncoming: true)
                    .environmentObject(chatViewModel)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    // 노티 후 N분 이내 앱 진입 → 자동 수신 전화
                    if NotificationService.shared.shouldAutoTriggerCall() {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            chatViewModel.showIncomingCall = true
                        }
                    }
                }
            }
        }
    }
}

// MARK: - AppDelegate (Notification Handling)
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// 앱이 포그라운드일 때 알림 표시 + 시각 기록
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let userInfo = notification.request.content.userInfo
        if let action = userInfo["action"] as? String, action == NotificationService.incomingCallAction {
            NotificationService.shared.recordNotificationTime()
        }
        return [.banner, .sound]
    }

    /// 알림 탭 → 수신 전화 화면
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        if let action = userInfo["action"] as? String, action == NotificationService.incomingCallAction {
            NotificationService.shared.recordNotificationTime()
            await MainActor.run {
                NotificationCenter.default.post(name: .showIncomingCall, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let showIncomingCall = Notification.Name("showIncomingCall")
}
