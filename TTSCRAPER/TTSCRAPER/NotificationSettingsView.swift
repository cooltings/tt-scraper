import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage("enableClassReminders") private var enableClassReminders: Bool = true
    @AppStorage("reminderMinutesBefore") private var reminderMinutesBefore: Int = 15
    @AppStorage("enableScheduleChangeAlerts") private var enableScheduleChangeAlerts: Bool = true
    
    @State private var permissionGranted: Bool = false
    
    let reminderOptions = [5, 10, 15, 30, 60]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Permissions")) {
                    HStack {
                        Text("Notification Access")
                        Spacer()
                        Text(permissionGranted ? "Allowed" : "Denied")
                            .foregroundColor(permissionGranted ? .green : .red)
                    }
                    if !permissionGranted {
                        Button("Request Permission") {
                            NotificationManager.shared.requestAuthorization { granted in
                                permissionGranted = granted
                            }
                        }
                    }
                }
                
                Section(header: Text("Class Reminders")) {
                    Toggle("Enable Upcoming Class Alerts", isOn: $enableClassReminders)
                    
                    if enableClassReminders {
                        Picker("Alert Timing", selection: $reminderMinutesBefore) {
                            ForEach(reminderOptions, id: \.self) { minutes in
                                Text("\(minutes) minutes before").tag(minutes)
                            }
                        }
                    }
                }
                
                Section(header: Text("Timetable Updates"), footer: Text("Notifies you in the background if a class time or room changes.")) {
                    Toggle("Background Change Alerts", isOn: $enableScheduleChangeAlerts)
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                checkNotificationPermission()
            }
        }
    }
    
    private func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.permissionGranted = (settings.authorizationStatus == .authorized)
            }
        }
    }
}
