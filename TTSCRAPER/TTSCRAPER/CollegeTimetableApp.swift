import SwiftUI
import BackgroundTasks

@main
struct CollegeTimetableApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView() // This is the UI file we generated in a previous step
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    let backgroundTaskID = "com.collegetimetable.refresh"
    let networkManager = NetworkManager() // From the previous step
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        // Register the background task
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskID, using: nil) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
        
        return true
    }
    
    // Schedule the NEXT background fetch
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskID)
        // Request a fetch no earlier than 1 hour from now
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600)
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule app refresh: \(error)")
        }
    }
    
    // This runs when iOS decides to wake up your app
    func handleAppRefresh(task: BGAppRefreshTask) {
        // Schedule the next fetch immediately
        scheduleAppRefresh()
        
        // If we take too long, iOS will kill the app. Tell it we failed.
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        // Fetch the data silently
        networkManager.fetchTimetable { result in
            switch result {
            case .success(let html):
                if let scheduleData = TimetableParser.parseHTML(html) {
                    // Save to UserDefaults or FileSystem here
                    print("Background fetch successful! Found \(scheduleData.days["Monday"]?.count ?? 0) classes on Monday.")
                    task.setTaskCompleted(success: true)
                } else {
                    task.setTaskCompleted(success: false)
                }
            case .failure(_):
                task.setTaskCompleted(success: false)
            }
        }
    }
}
