import EventKit
import UIKit

class CalendarManager {
    static let shared = CalendarManager()
    private let store = EKEventStore()
    
    func addEntireWeekToCalendar(schedule: WeekSchedule, completion: @escaping (Bool, String) -> Void) {
        let handlePermission: (Bool, Error?) -> Void = { granted, error in
            if let error = error {
                completion(false, "Calendar error: \(error.localizedDescription)")
                return
            }
            guard granted else {
                completion(false, "Calendar access denied. Please enable it in iOS Settings.")
                return
            }
            
            self.processAndSaveWeek(schedule: schedule, completion: completion)
        }
        
        if #available(iOS 17.0, *) {
            store.requestWriteOnlyAccessToEvents(completion: handlePermission)
        } else {
            store.requestAccess(to: .event, completion: handlePermission)
        }
    }
    
    private func processAndSaveWeek(schedule: WeekSchedule, completion: @escaping (Bool, String) -> Void) {
        var addedCount = 0
        var failedCount = 0
        
        for (dayName, sessions) in schedule.days {
            guard let targetDate = dateForDayName(dayName) else { continue }
            
            for session in sessions {
                guard let (startDate, endDate) = parseStartAndEndDates(timeString: session.time, baseDate: targetDate) else {
                    failedCount += 1
                    continue
                }
                
                let event = EKEvent(eventStore: store)
                event.title = session.title
                event.location = session.room
                event.startDate = startDate
                event.endDate = endDate
                event.calendar = store.defaultCalendarForNewEvents
                
                do {
                    try store.save(event, span: .thisEvent)
                    addedCount += 1
                } catch {
                    failedCount += 1
                }
            }
        }
        
        DispatchQueue.main.async {
            let generator = UINotificationFeedbackGenerator()
            if addedCount > 0 {
                generator.notificationOccurred(.success)
                completion(true, "Successfully added \(addedCount) classes to Calendar!")
            } else {
                generator.notificationOccurred(.error)
                completion(false, "No classes found to export.")
            }
        }
    }
    
    private func dateForDayName(_ dayName: String) -> Date? {
        let weekdays = ["Sunday": 1, "Monday": 2, "Tuesday": 3, "Wednesday": 4, "Thursday": 5, "Friday": 6, "Saturday": 7]
        guard let targetWeekday = weekdays[dayName] else { return nil }
        
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Week starts on Monday
        
        let now = Date()
        let currentWeekday = calendar.component(.weekday, from: now)
        let diff = targetWeekday - currentWeekday
        
        return calendar.date(byAdding: .day, value: diff, to: now)
    }
    
    private func parseStartAndEndDates(timeString: String, baseDate: Date) -> (Date, Date)? {
        let clean = timeString.replacingOccurrences(of: " ", with: "")
        let parts = clean.components(separatedBy: "-")
        guard parts.count == 2 else { return nil }
        
        let startParts = parts[0].components(separatedBy: ":")
        let endParts = parts[1].components(separatedBy: ":")
        
        guard startParts.count == 2, endParts.count == 2,
              let startH = Int(startParts[0]), let startM = Int(startParts[1]),
              let endH = Int(endParts[0]), let endM = Int(endParts[1]) else { return nil }
        
        let calendar = Calendar.current
        var startComp = calendar.dateComponents([.year, .month, .day], from: baseDate)
        startComp.hour = startH
        startComp.minute = startM
        
        var endComp = calendar.dateComponents([.year, .month, .day], from: baseDate)
        endComp.hour = endH
        endComp.minute = endM
        
        guard let start = calendar.date(from: startComp),
              let end = calendar.date(from: endComp) else { return nil }
        
        return (start, end)
    }
}
