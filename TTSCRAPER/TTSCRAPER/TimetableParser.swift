import Foundation
import SwiftSoup

class TimetableParser {
    static func parseHTML(_ html: String) -> WeekSchedule? {
        do {
            let doc = try SwiftSoup.parse(html)
            let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
            var schedule: [String: [ClassSession]] = [:]
            
            // Initialize empty arrays for each day
            for day in days {
                schedule[day] = []
            }
            
            // Extract date range banner text
            var dateLabel = "Unknown Dates"
            if let dateTag = try doc.select("a[title=Pick a date]").first() {
                dateLabel = try dateTag.text()
            }
            
            // Loop through each day container (day-0 to day-4)
            for (idx, dayName) in days.enumerated() {
                if let container = try doc.select("div.day-\(idx)").first() {
                    let items = try container.select("div.item")
                    
                    for item in items {
                        let time = try item.select("span.times").text()
                        let title = try item.select("span.title").text()
                        let room = try item.select("span.room").text()
                        
                        let session = ClassSession(time: time, title: title, room: room)
                        schedule[dayName]?.append(session)
                    }
                }
            }
            
            // Extract Week ID
            var currentWeekId = 0
            if let mobileDiv = try doc.select("div.timetable-mobile").first(),
               let weekAttr = try? mobileDiv.attr("data-week"),
               let weekInt = Int(weekAttr) {
                currentWeekId = weekInt
            } else if let nextBtn = try doc.select("a.next").first(),
                      let href = try? nextBtn.attr("href"),
                      let urlComp = URLComponents(string: href),
                      let weekStr = urlComp.queryItems?.first(where: { $0.name == "week" })?.value,
                      let nextWeekInt = Int(weekStr) {
                currentWeekId = nextWeekInt - 1
            }
                
            return WeekSchedule(dateRange: dateLabel, weekId: currentWeekId, days: schedule)
            
        } catch {
            print("Error parsing HTML: \(error)")
            return nil
        }
    }
}
