import EventKit
import UIKit

class CalendarManager {
    static let shared = CalendarManager()
    let store = EKEventStore()
    
    func addClassToCalendar(session: ClassSession) {
        store.requestWriteOnlyAccessToEvents { granted, error in
            guard granted && error == nil else {
                print("Calendar access denied")
                return
            }
            
            let event = EKEvent(eventStore: self.store)
            event.title = session.title
            event.location = session.room
            event.calendar = self.store.defaultCalendarForNewEvents
            
            // Simple parsing to set today's date + class time (you may want to refine this logic)
            event.startDate = Date()
            event.endDate = Date().addingTimeInterval(3600) // Default 1 hour
            
            do {
                try self.store.save(event, span: .thisEvent)
                DispatchQueue.main.async {
                    // Optional: Show a success haptic or alert
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
            } catch {
                print("Failed to save event: \(error)")
            }
        }
    }
}
