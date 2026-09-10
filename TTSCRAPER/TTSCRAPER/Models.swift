import Foundation

struct ClassSession: Codable, Hashable {
    let time: String
    let title: String
    let room: String
}

struct WeekSchedule: Codable {
    let dateRange: String
    let weekId: Int
    let days: [String: [ClassSession]]
}

class StorageManager {
    static let shared = StorageManager()
    private let defaults = UserDefaults.standard
    
    func save(_ schedule: WeekSchedule) {
        if let encoded = try? JSONEncoder().encode(schedule) {
            defaults.set(encoded, forKey: "cached_week_\(schedule.weekId)")
            defaults.set(schedule.weekId, forKey: "last_known_week_id")
        }
    }
    
    func load(weekId: Int) -> WeekSchedule? {
        if let data = defaults.data(forKey: "cached_week_\(weekId)"),
           let schedule = try? JSONDecoder().decode(WeekSchedule.self, from: data) {
            return schedule
        }
        return nil
    }
    
    func loadLastKnown() -> WeekSchedule? {
        let lastId = defaults.integer(forKey: "last_known_week_id")
        return lastId != 0 ? load(weekId: lastId) : nil
    }
}
