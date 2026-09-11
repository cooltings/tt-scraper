import SwiftUI

enum ViewMode { case list, calendar }
enum CalendarSpan { case day, week }

struct ContentView: View {
    @StateObject private var networkManager = NetworkManager()
    
    @State private var schedule: WeekSchedule? = nil
    @State private var isLoading: Bool = false
    @State private var showingLoginSheet: Bool = false
    @State private var showingSettingsSheet: Bool = false
    @State private var selectedWeekId: Int = 0
    @State private var alertMessage: String = ""
    @State private var showAlert: Bool = false
    
    // View state variables
    @State private var viewMode: ViewMode = .list
    @State private var calendarSpan: CalendarSpan = .day
    @State private var selectedDay: String = "Monday"
    
    let daysOfWeek = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                
                if !networkManager.isAuthenticated {
                    loginPromptView
                } else {
                    mainBodyView
                        .safeAreaInset(edge: .bottom) {
                            liquidGlassTabBar
                        }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if networkManager.isAuthenticated, let schedule = schedule {
                        Button(action: {
                            CalendarManager.shared.addEntireWeekToCalendar(schedule: schedule) { success, message in
                                alertMessage = message
                                showAlert = true
                            }
                        }) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.title3)
                        }
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    if let schedule = schedule {
                        Menu {
                            ForEach(-4...8, id: \.self) { offset in
                                Button(action: { fetch(week: schedule.weekId + offset) }) {
                                    Text(offset == 0 ? "This Week" : (offset < 0 ? "\(abs(offset)) Weeks Ago" : "In \(offset) Weeks"))
                                }
                            }
                        } label: {
                            HStack {
                                Text(schedule.dateRange)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if networkManager.isAuthenticated { settingsMenu }
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Calendar Sync"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
            .onAppear { startupSequence() }
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
            .sheet(isPresented: $showingSettingsSheet) {
                NotificationSettingsView()
            }
        }
    }
    
    // MARK: - Subviews
    
    private var mainBodyView: some View {
        VStack(spacing: 0) {
            if viewMode == .calendar {
                Picker("Span", selection: $calendarSpan) {
                    Text("Day").tag(CalendarSpan.day)
                    Text("Week").tag(CalendarSpan.week)
                }
                .pickerStyle(.segmented)
                .padding()
                .background(Color(UIColor.secondarySystemGroupedBackground))
            }
            
            if viewMode == .calendar && calendarSpan == .day {
                Picker("Day", selection: $selectedDay) {
                    ForEach(daysOfWeek, id: \.self) { day in
                        Text(String(day.prefix(3))).tag(day)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 10)
                .background(Color(UIColor.secondarySystemGroupedBackground))
            }
            
            if isLoading && schedule == nil {
                ProgressView("Syncing...").frame(maxHeight: .infinity)
            } else if let schedule = schedule {
                if viewMode == .list {
                    listView(for: schedule)
                } else {
                    calendarGridView(for: schedule)
                }
            }
        }
    }
    
    // MARK: - Liquid Glass Tab Bar
    
    private var liquidGlassTabBar: some View {
        HStack(spacing: 15) {
            tabButton(title: "List", icon: "list.bullet", mode: .list)
            tabButton(title: "Calendar", icon: "calendar", mode: .calendar)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 15)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
        .padding(.bottom, 10)
    }
    
    private func tabButton(title: String, icon: String, mode: ViewMode) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                viewMode = mode
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                
                if viewMode == mode {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, viewMode == mode ? 20 : 15)
            .background(viewMode == mode ? Color.blue.opacity(0.15) : Color.clear)
            .foregroundColor(viewMode == mode ? .blue : .primary)
            .clipShape(Capsule())
        }
    }
    
    // MARK: - 1. List View
    private func listView(for schedule: WeekSchedule) -> some View {
        List {
            ForEach(daysOfWeek, id: \.self) { day in
                Section(header: Text(day).font(.headline)) {
                    if let classes = schedule.days[day], !classes.isEmpty {
                        ForEach(classes, id: \.self) { session in
                            classCard(for: session)
                        }
                    } else {
                        Text("Free day").foregroundColor(.gray).italic()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { fetch(week: schedule.weekId) }
    }
    
    // MARK: - 2. Calendar Grid View
    private func calendarGridView(for schedule: WeekSchedule) -> some View {
        let startHour = 8
        let endHour = 17
        let hourHeight: CGFloat = 70
        
        let visibleDays = calendarSpan == .day ? [selectedDay] : daysOfWeek
        let columnWidth: CGFloat = calendarSpan == .day ? UIScreen.main.bounds.width - 80 : 130
        
        return ScrollView([.vertical, .horizontal]) {
            HStack(alignment: .top, spacing: 5) {
                
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(startHour...endHour, id: \.self) { hour in
                        Text("\(hour):00")
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .frame(height: hourHeight, alignment: .top)
                    }
                }
                .frame(width: 45)
                .padding(.top, 25)
                
                ForEach(visibleDays, id: \.self) { day in
                    VStack(spacing: 0) {
                        Text(calendarSpan == .week ? String(day.prefix(3)) : day)
                            .font(.subheadline).bold()
                            .frame(height: 25)
                        
                        ZStack(alignment: .top) {
                            VStack(spacing: 0) {
                                ForEach(startHour...endHour, id: \.self) { _ in
                                    Divider().frame(height: hourHeight, alignment: .top)
                                }
                            }
                            
                            if let classes = schedule.days[day] {
                                ForEach(classes, id: \.self) { session in
                                    let offset = calculateYOffset(for: session, startHour: startHour, hourHeight: hourHeight)
                                    let height = calculateHeight(for: session, hourHeight: hourHeight)
                                    
                                    calendarBlock(for: session)
                                        .frame(width: columnWidth, height: height)
                                        .offset(y: offset)
                                }
                            }
                        }
                        .frame(width: columnWidth, height: CGFloat(endHour - startHour) * hourHeight)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
    }
    
    private func calendarBlock(for session: ClassSession) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.title).font(.system(size: 11, weight: .bold)).lineLimit(2)
            Text(session.room).font(.system(size: 10))
            Text(session.time).font(.system(size: 9)).opacity(0.8)
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.blue.opacity(0.2))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.blue, lineWidth: 1))
    }
    
    private func classCard(for session: ClassSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title).font(.system(size: 16, weight: .bold))
            Text(session.time).font(.system(size: 14))
            Text(session.room).font(.system(size: 14)).foregroundColor(.blue)
        }
        .padding(.vertical, 4)
    }
    
    private var settingsMenu: some View {
        Menu {
            Button(action: { showingSettingsSheet = true }) {
                Label("Notification Settings", systemImage: "bell")
            }
            Button(action: { fetch(week: schedule?.weekId) }) {
                Label("Force Refresh", systemImage: "arrow.clockwise")
            }
            Button(role: .destructive, action: {
                networkManager.logout()
                schedule = nil
            }) {
                Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Image(systemName: "ellipsis.circle").font(.title3)
        }
    }
    
    private var loginPromptView: some View {
        VStack {
            Text("Authentication Required").font(.headline).padding(.bottom, 10)
            Button("Sign In") { showingLoginSheet = true }.buttonStyle(.borderedProminent)
        }
    }
    
    // MARK: - Logic & Math
    
    private func startupSequence() {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let today = formatter.string(from: Date())
        if daysOfWeek.contains(today) {
            selectedDay = today
        }
        
        if let cached = StorageManager.shared.loadLastKnown() {
            self.schedule = cached
            self.selectedWeekId = cached.weekId
        }
        
        fetch(week: nil, silent: true)
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
                        StorageManager.shared.save(parsed)
                    }
                case .failure(let error):
                    if (error as NSError).domain == "AuthError" {
                        self.showingLoginSheet = true
                    }
                }
            }
        }
    }
    
    private func calculateYOffset(for session: ClassSession, startHour: Int, hourHeight: CGFloat) -> CGFloat {
        let minFromMidnight = session.startMinutes
        let minFromTimelineStart = minFromMidnight - (startHour * 60)
        return CGFloat(minFromTimelineStart) * (hourHeight / 60.0)
    }
    
    private func calculateHeight(for session: ClassSession, hourHeight: CGFloat) -> CGFloat {
        let duration = max(session.durationMinutes, 30)
        return CGFloat(duration) * (hourHeight / 60.0)
    }
}

// MARK: - Time Parsing Extension
extension ClassSession {
    var startMinutes: Int {
        parseMinutes(from: time, index: 0) ?? (8 * 60)
    }
    
    var endMinutes: Int {
        parseMinutes(from: time, index: 1) ?? (9 * 60)
    }
    
    var durationMinutes: Int {
        endMinutes - startMinutes
    }
    
    private func parseMinutes(from timeString: String, index: Int) -> Int? {
        let cleanString = timeString.replacingOccurrences(of: " ", with: "")
        let parts = cleanString.components(separatedBy: "-")
        guard parts.count > index else { return nil }
        
        let timeParts = parts[index].components(separatedBy: ":")
        guard timeParts.count == 2,
              let h = Int(timeParts[0]),
              let m = Int(timeParts[1]) else { return nil }
        
        return (h * 60) + m
    }
}
