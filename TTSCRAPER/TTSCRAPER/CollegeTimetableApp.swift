import SwiftUI
import BackgroundTasks

@main
struct TTSCraperApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                appDelegate.scheduleAppRefresh()
            }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    let backgroundTaskID = "com.timetable.refresh"
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        NotificationManager.shared.requestAuthorization()
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskID, using: nil) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
        
        return true
    }
    
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule app refresh: \(error)")
        }
    }
    
    func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleAppRefresh()
        
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        let networkManager = NetworkManager()
        networkManager.fetchTimetable { result in
            switch result {
            case .success(let html):
                if let newSchedule = TimetableParser.parseHTML(html) {
                    let oldSchedule = StorageManager.shared.loadLastKnown()
                    if oldSchedule?.days != newSchedule.days {
                        StorageManager.shared.save(newSchedule)
                        NotificationManager.shared.sendScheduleChangeNotification(dateRange: newSchedule.dateRange)
                    }
                    task.setTaskCompleted(success: true)
                } else {
                    task.setTaskCompleted(success: false)
                }
            case .failure:
                task.setTaskCompleted(success: false)
            }
        }
    }
}
