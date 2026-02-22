import Foundation
import UserNotifications

class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()
    static let incomingCallAction = "INCOMING_CALL"

    /// 노티 발송 시각 기록 (앱 진입 시 시간 체크용)
    static let lastNotificationTimeKey = "lastCallNotificationTime"
    /// 노티 후 N분 이내 앱 진입 시 자동 수신 전화
    static let autoCallWindowMinutes: Double = 5

    @Published var hasPermission = false

    /// 메시지 스타일 인사말 (랜덤)
    private let greetingMessages = [
        "자니? 😊",
        "뭐해?",
        "오늘 어땠어?",
        "심심한데 얘기하자 ㅎㅎ",
        "나 잠깐 얘기 좀 하자~",
        "요즘 어떻게 지내?",
        "오늘 하루 어땠어? 궁금해",
        "혹시 시간 돼?",
    ]

    override init() {
        super.init()
        checkPermission()
    }

    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await MainActor.run { hasPermission = granted }
            return granted
        } catch {
            print("[Notification] 권한 요청 실패: \(error)")
            return false
        }
    }

    func checkPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.hasPermission = settings.authorizationStatus == .authorized
            }
        }
    }

    /// 매일 특정 시간에 수신 전화 알림 예약
    func scheduleDailyCall(hour: Int, minute: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily_call"])

        let saved = UserDefaults.standard.string(forKey: "selectedCompanion") ?? "on"
        let comp = CompanionType(rawValue: saved) ?? .on

        let content = UNMutableNotificationContent()
        content.title = comp.displayName
        content.body = greetingMessages.randomElement() ?? "자니?"
        content.sound = .default
        content.categoryIdentifier = Self.incomingCallAction
        content.userInfo = ["action": Self.incomingCallAction]

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "daily_call", content: content, trigger: trigger)

        center.add(request) { error in
            if let error = error {
                print("[Notification] 예약 실패: \(error)")
            } else {
                print("[Notification] 매일 \(hour):\(String(format: "%02d", minute)) 메시지 알림 예약됨")
            }
        }
    }

    /// 테스트용: N초 후 알림
    func scheduleTestCall(after seconds: TimeInterval = 5) {
        let center = UNUserNotificationCenter.current()

        let saved = UserDefaults.standard.string(forKey: "selectedCompanion") ?? "on"
        let comp = CompanionType(rawValue: saved) ?? .on

        let content = UNMutableNotificationContent()
        content.title = comp.displayName
        content.body = greetingMessages.randomElement() ?? "자니?"
        content.sound = .default
        content.categoryIdentifier = Self.incomingCallAction
        content.userInfo = ["action": Self.incomingCallAction]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: "test_call_\(Date().timeIntervalSince1970)", content: content, trigger: trigger)

        center.add(request) { error in
            if let error = error {
                print("[Notification] 테스트 알림 실패: \(error)")
            } else {
                print("[Notification] \(seconds)초 후 테스트 알림 예약됨")
            }
        }
    }

    /// 매일 랜덤 시간에 알림 (오전 10시 ~ 밤 11시 사이)
    func scheduleRandomDailyCall() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily_call"])

        let saved = UserDefaults.standard.string(forKey: "selectedCompanion") ?? "on"
        let comp = CompanionType(rawValue: saved) ?? .on

        let content = UNMutableNotificationContent()
        content.title = comp.displayName
        content.body = greetingMessages.randomElement() ?? "자니?"
        content.sound = .default
        content.categoryIdentifier = Self.incomingCallAction
        content.userInfo = ["action": Self.incomingCallAction]

        // 랜덤 시간: 10:00 ~ 22:59
        let randomHour = Int.random(in: 10...22)
        let randomMinute = Int.random(in: 0...59)

        var dateComponents = DateComponents()
        dateComponents.hour = randomHour
        dateComponents.minute = randomMinute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "daily_call", content: content, trigger: trigger)

        center.add(request) { error in
            if let error = error {
                print("[Notification] 랜덤 예약 실패: \(error)")
            } else {
                print("[Notification] 매일 랜덤(\(randomHour):\(String(format: "%02d", randomMinute))) 메시지 알림 예약됨")
            }
        }
    }

    func cancelDailyCall() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily_call"])
        print("[Notification] 매일 수신 전화 취소됨")
    }

    /// 노티 발송 시각 기록 (AppDelegate에서 호출)
    func recordNotificationTime() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastNotificationTimeKey)
        print("[Notification] 노티 시각 기록됨")
    }

    /// 앱 진입 시 자동 수신 전화 여부 확인 (N분 이내면 true)
    func shouldAutoTriggerCall() -> Bool {
        let lastTime = UserDefaults.standard.double(forKey: Self.lastNotificationTimeKey)
        guard lastTime > 0 else { return false }

        let elapsed = Date().timeIntervalSince1970 - lastTime
        let withinWindow = elapsed < Self.autoCallWindowMinutes * 60

        if withinWindow {
            // 한 번 사용하면 리셋
            UserDefaults.standard.removeObject(forKey: Self.lastNotificationTimeKey)
            print("[Notification] 자동 수신 전화 트리거 (경과: \(Int(elapsed))초)")
        }
        return withinWindow
    }
}
