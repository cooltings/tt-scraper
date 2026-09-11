import BackgroundTasks
import UIKit

class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()
    static let taskIdentifier = "com.timetable.refresh"
    
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
    }
    
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        // Attempt to run every 6 hours
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule background task: \(error)")
        }
    }
    
    private func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleAppRefresh() // Reschedule the next task
        
        let networkManager = NetworkManager()
        
        task.expirationHandler = {
            URLSession.shared.invalidateAndCancel()
        }
        
        networkManager.fetchTimetable { result in
            switch result {
            case .success(let html):
                if let newSchedule = TimetableParser.parseHTML(html) {
                    let oldSchedule = StorageManager.shared.loadLastKnown()
                    
                    // Check if schedule changed
                    if oldSchedule?.days != newSchedule.days {
                        StorageManager.shared.save(newSchedule)
                        NotificationManager.shared.sendScheduleChangeNotification(dateRange: newSchedule.dateRange)
                    }
                }
                task.setTaskCompleted(success: true)
            case .failure:
                task.setTaskCompleted(success: false)
            }
        }
    }
}
