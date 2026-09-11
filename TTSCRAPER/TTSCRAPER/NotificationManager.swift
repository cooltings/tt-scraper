import UserNotifications
import Foundation

class NotificationManager {
    static let shared = NotificationManager()
    
    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
            DispatchQueue.main.async {
                completion?(granted)
            }
        }
    }
    
    func sendScheduleChangeNotification(dateRange: String) {
        let content = UNMutableNotificationContent()
        content.title = "Timetable Updated"
        content.body = "Your schedule for \(dateRange) has been updated in the background."
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
