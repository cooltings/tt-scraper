import SwiftUI

struct ContentView: View {
    @StateObject private var networkManager = NetworkManager()
    
    @State private var schedule: WeekSchedule? = nil
    @State private var isLoading: Bool = false
    @State private var showingLoginSheet: Bool = false
    @State private var selectedWeekId: Int = 0
    
    let daysOfWeek = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                
                if !networkManager.isAuthenticated {
                    loginPromptView
                } else {
                    mainTimetableView
                }
            }
            .navigationTitle(schedule?.dateRange ?? "My Timetable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if networkManager.isAuthenticated {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        settingsMenu
                    }
                }
            }
            .onAppear {
                startupSequence()
            }
            .onChange(of: selectedWeekId) { newWeek in
                if newWeek != 0 { fetch(week: newWeek) }
            }
            .sheet(isPresented: $showingLoginSheet) {
                LoginWebView(
                    url: URL(string: "https://intranet.psc.ac.uk/timetable")!,
                    networkManager: networkManager,
                    onLoginSuccess: {
                        showingLoginSheet = false
                        fetch(week: nil)
                    }
                )
            }
        }
    }
    
    // MARK: - Subviews
    
    private var mainTimetableView: some View {
        VStack(spacing: 0) {
            // Week Selector Bar
            if let schedule = schedule, schedule.weekId != 0 {
                HStack {
                    Button(action: { selectedWeekId = schedule.weekId - 1 }) {
                        Image(systemName: "chevron.left.circle.fill").font(.title2)
                    }
                    Spacer()
                    Text("Week \(schedule.weekId)")
                        .font(.headline)
                    Spacer()
                    Button(action: { selectedWeekId = schedule.weekId + 1 }) {
                        Image(systemName: "chevron.right.circle.fill").font(.title2)
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemGroupedBackground))
            }
            
            // Loading Overlay or List
            if isLoading && schedule == nil {
                ProgressView("Syncing...").frame(maxHeight: .infinity)
            } else if let schedule = schedule {
                List {
                    ForEach(daysOfWeek, id: \.self) { day in
                        Section(header: Text(day).font(.headline)) {
                            if let classes = schedule.days[day], !classes.isEmpty {
                                ForEach(classes, id: \.self) { session in
                                    classCard(for: session)
                                }
                            } else {
                                Text("No classes").foregroundColor(.gray).italic()
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    fetch(week: selectedWeekId)
                }
            }
        }
    }
    
    private func classCard(for session: ClassSession) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title).font(.system(size: 16, weight: .bold))
                Text(session.time).font(.system(size: 14))
                Text(session.room).font(.system(size: 14)).foregroundColor(.blue)
            }
            Spacer()
            Button(action: { CalendarManager.shared.addClassToCalendar(session: session) }) {
                Image(systemName: "calendar.badge.plus")
                    .foregroundColor(.blue)
                    .font(.title3)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(.vertical, 4)
    }
    
    private var settingsMenu: some View {
        Menu {
            Button(action: { fetch(week: selectedWeekId == 0 ? nil : selectedWeekId) }) {
                Label("Force Refresh", systemImage: "arrow.clockwise")
            }
            Button(role: .destructive, action: {
                networkManager.logout()
                schedule = nil
            }) {
                Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
        }
    }
    
    private var loginPromptView: some View {
        VStack {
            Text("Authentication Required")
                .font(.headline).padding(.bottom, 10)
            Button("Sign In") { showingLoginSheet = true }
                .buttonStyle(.borderedProminent)
        }
    }
    
    // MARK: - Logic
    
    private func startupSequence() {
        if networkManager.isAuthenticated {
            // 1. Load cached data instantly
            if let cached = StorageManager.shared.loadLastKnown() {
                self.schedule = cached
                self.selectedWeekId = cached.weekId
            }
            // 2. Fetch silently in background to ensure it's up to date
            fetch(week: nil, silent: true)
        } else {
            showingLoginSheet = true
        }
    }
    
    private func fetch(week: Int?, silent: Bool = false) {
        if !silent { isLoading = true }
        
        networkManager.fetchTimetable(week: week) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success(let html):
                    if let parsed = TimetableParser.parseHTML(html) {
                        self.schedule = parsed
                        self.selectedWeekId = parsed.weekId
                        StorageManager.shared.save(parsed) // Cache it
                    }
                case .failure(let error):
                    print("Fetch failed: \(error)") // Will just fallback to cache
                }
            }
        }
    }
}
