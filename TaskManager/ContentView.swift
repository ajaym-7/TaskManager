import SwiftUI
import UserNotifications

// MARK: - Global FilterOption (unchanged from earlier)
// Update FilterOption enum
enum FilterOption: String, CaseIterable, Identifiable {
    case all = "All"
    case active = "Active"
    case today = "Today"
    case upcoming = "Upcoming"
    case completed = "Completed"
    case deleted = "Deleted"  // New option
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .all: return "list.dash"
        case .active: return "clock"
        case .today: return "calendar"
        case .upcoming: return "calendar.badge.plus"
        case .completed: return "checkmark"
        case .deleted: return "trash"  // New icon
        }
    }
}

// MARK: - Task Model (updated with completion date)
struct Task: Identifiable, Codable {
    var id = UUID()
    var title: String
    var isCompleted: Bool = false
    var completedDate: Date? = nil
    var dueDate: Date?
    var dueTime: Date?
    var priority: Priority = .medium
    var category: String = "Personal"
    var notes: String = ""
    var isDeleted: Bool = false  // New property
    var deletedDate: Date? = nil  // New property
    
    enum Priority: String, Codable, CaseIterable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
        
        var color: Color {
            switch self {
            case .low: return .green
            case .medium: return .orange
            case .high: return .red
            }
        }
    }
    
    // Default categories (for filtering & display)
    static let defaultCategories = ["Personal", "Work", "Study", "Health", "Shopping", "Other"]
}

// MARK: - CategoryStore for Dynamic Categories
class CategoryStore: ObservableObject {
    @Published var customCategories: [String] = []
    
    init() {
        load()
    }
    
    func addCategory(_ category: String) {
        // Avoid duplicates.
        if !customCategories.contains(category) && !Task.defaultCategories.contains(category) {
            customCategories.append(category)
            save()
        }
    }
    
    func allCategories() -> [String] {
        // Combine default and custom categories.
        return Task.defaultCategories + customCategories
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(customCategories) {
            UserDefaults.standard.set(data, forKey: "customCategories")
        }
    }
    
    func load() {
        if let data = UserDefaults.standard.data(forKey: "customCategories"),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            customCategories = decoded
        }
    }
}

// MARK: - TaskViewModel
class TaskViewModel: ObservableObject {
    @Published var tasks: [Task] = []
    @Published var searchText: String = ""
    @Published var sortOption: String = "Due Date"
    
    var filteredAndSortedTasks: [Task] {
        // You can later add sorting logic if needed.
        return tasks
    }
    
    init() {
        requestNotificationPermission()
        loadTasks()
        
        // Reschedule all notifications when app starts
        rescheduleAllNotifications()
    }
    
    func addTask(_ task: Task) {
        tasks.append(task)
        saveTasks()
        scheduleNotification(for: task)
    }
    
    func updateTask(_ task: Task) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
            saveTasks()
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [task.id.uuidString])
            scheduleNotification(for: task)
        }
    }
    
    func deleteTask(at offsets: IndexSet) {
        let filteredTasks = filteredAndSortedTasks
        for index in offsets {
            let task = filteredTasks[index]
            if let originalIndex = tasks.firstIndex(where: { $0.id == task.id }) {
                // Mark as deleted instead of removing
                tasks[originalIndex].isDeleted = true
                tasks[originalIndex].deletedDate = Date()
                // Remove notification for deleted task
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [task.id.uuidString])
            }
        }
        saveTasks()
    }
    
    // Add method to permanently delete task
    func permanentlyDeleteTask(_ task: Task) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks.remove(at: index)
            saveTasks()
        }
    }
    
    func toggleCompletion(for task: Task) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index].isCompleted.toggle()
            
            // Set completion date if completed, otherwise clear it
            if tasks[index].isCompleted {
                tasks[index].completedDate = Date()
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [task.id.uuidString])
            } else {
                tasks[index].completedDate = nil
                scheduleNotification(for: tasks[index])
            }
            
            saveTasks()
        }
    }
    
    // Add method to restore task
    func restoreTask(_ task: Task) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index].isDeleted = false
            tasks[index].deletedDate = nil
            saveTasks()
            if !tasks[index].isCompleted {
                scheduleNotification(for: tasks[index])
            }
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("Error requesting notification permission: \(error)")
            }
        }
    }
    
    private func rescheduleAllNotifications() {
        // Clear all existing notifications
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        // Reschedule for all active tasks
        for task in tasks where !task.isCompleted {
            scheduleNotification(for: task)
        }
    }
    
    func scheduleNotification(for task: Task) {
        guard !task.isCompleted, let dueDate = task.dueDate else { return }
        
        // Get current notification settings
        let notificationOffset = UserDefaults.standard.double(forKey: "notificationTime")
        if notificationOffset <= 0 {
            // Default to 60 minutes if not set
            UserDefaults.standard.set(60.0, forKey: "notificationTime")
        }
        
        let content = UNMutableNotificationContent()
        content.title = "Task Reminder: \(task.title)"
        
        // Update notification body to include priority first, then category, and notes if available
        let priorityString = "(\(task.priority.rawValue) Priority)"
        
        if task.notes.isEmpty {
            content.body = "Don't forget to complete this task! \(priorityString) - \(task.category)"
        } else {
            // Limit notes length if too long
            let maxNoteLength = 100
            let notesToShow = task.notes.count > maxNoteLength ?
                "\(task.notes.prefix(maxNoteLength))..." :
                task.notes
            content.body = "\(notesToShow)\n\n\(priorityString) - \(task.category)"
        }
        
        content.sound = UNNotificationSound.default
        
        var combinedDate = dueDate
        if let dueTime = task.dueTime {
            let calendar = Calendar.current
            let timeComponents = calendar.dateComponents([.hour, .minute], from: dueTime)
            combinedDate = calendar.date(bySettingHour: timeComponents.hour ?? 0,
                                        minute: timeComponents.minute ?? 0,
                                        second: 0,
                                        of: dueDate) ?? dueDate
        }
        
        // Use the stored notification time preference
        let minutesBefore = UserDefaults.standard.double(forKey: "notificationTime")
        let notificationTime = minutesBefore <= 0 ? 60 : minutesBefore
        let notificationDate = Calendar.current.date(byAdding: .minute, value: Int(-notificationTime), to: combinedDate) ?? combinedDate
        
        // Don't schedule if notification time is in the past
        if notificationDate <= Date() {
            return
        }
        
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: notificationDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let request = UNNotificationRequest(identifier: task.id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error)")
            }
        }
    }

    // Also update the test notification method to demonstrate the new format:
    private func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Test Notification"
        content.body = "This is a sample notification with priority info (High Priority) - Work"
        content.sound = UNNotificationSound.default
        
        // Trigger the notification in 5 seconds
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "testNotification", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling test notification: \(error)")
            }
        }
    }
    
    func saveTasks() {
        if let encoded = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(encoded, forKey: "tasks")
        }
    }
    
    func loadTasks() {
        if let data = UserDefaults.standard.data(forKey: "tasks"),
           let decoded = try? JSONDecoder().decode([Task].self, from: data) {
            tasks = decoded
        }
    }
}

// MARK: - SettingsView - Fixed position
// MARK: - SettingsView - With Smooth Transitions
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("darkMode") private var darkMode = false
    @AppStorage("username") private var username = ""
    @AppStorage("notificationTime") private var notificationTime: Double = 60.0 // Default 60 minutes
    
    // Add state for animation
    @State private var animationDuration: Double = 0.4
    @State private var showTimePicker = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Appearance")) {
                    Toggle("Dark Mode", isOn: $darkMode.animation(.easeInOut(duration: animationDuration)))
                }
                
                Section(header: Text("User Profile")) {
                    TextField("Your Name", text: $username)
                        .autocapitalization(.words)
                }
                
                Section(header: Text("Notifications")) {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Reminder Time")
                            Spacer()
                            Text(notificationTimeText)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showTimePicker.toggle()
                        }
                        
                        if showTimePicker {
                            VStack {
                                HStack {
                                    Picker("Hours", selection: Binding(
                                        get: { Int(notificationTime / 60) },
                                        set: { notificationTime = Double($0 * 60) + Double(Int(notificationTime) % 60) }
                                    )) {
                                        ForEach(0..<24) { hour in
                                            Text("\(hour)").tag(hour)
                                        }
                                    }
                                    .pickerStyle(WheelPickerStyle())
                                    .frame(width: 100)
                                    .clipped()
                                    
                                    Text("hours")
                                    
                                    Picker("Minutes", selection: Binding(
                                        get: { Int(notificationTime.truncatingRemainder(dividingBy: 60)) },
                                        set: { notificationTime = (notificationTime - notificationTime.truncatingRemainder(dividingBy: 60)) + Double($0) }
                                    )) {
                                        ForEach(0..<60) { minute in
                                            Text("\(minute)").tag(minute)
                                        }
                                    }
                                    .pickerStyle(WheelPickerStyle())
                                    .frame(width: 100)
                                    .clipped()
                                    
                                    Text("minutes")
                                }
                                .padding(.vertical)
                            }
                        }
                    }
                    
                    Text("You'll be notified \(notificationTimeText) before a task is due")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            // Add animation to color scheme transition
            .preferredColorScheme(darkMode ? .dark : .light)
            .animation(.easeInOut(duration: animationDuration), value: darkMode)
        }
        .onAppear {
            // Set initial animation duration to 0 for the first load, then reset to normal
            // This prevents animation on initial view appearance
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                animationDuration = 0.7
            }
        }
    }
    
    // Format the notification time
    private var notificationTimeText: String {
        if notificationTime < 60 {
            return "\(Int(notificationTime)) minutes"
        } else if notificationTime == 60 {
            return "1 hour"
        } else if notificationTime.truncatingRemainder(dividingBy: 60) == 0 {
            return "\(Int(notificationTime / 60)) hours"
        } else {
            let hours = Int(notificationTime / 60)
            let minutes = Int(notificationTime.truncatingRemainder(dividingBy: 60))
            return "\(hours) hour\(hours > 1 ? "s" : "") \(minutes) minute\(minutes > 1 ? "s" : "")"
        }
    }
}
    
    // Send a test notification to demonstrate the functionality
    private func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Test Notification"
        content.body = "Your notifications are working properly!"
        content.sound = UNNotificationSound.default
        
        // Trigger the notification in 5 seconds
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "testNotification", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling test notification: \(error)")
            }
        }
    }


// MARK: - Main ContentView
struct ContentView: View {
    @StateObject private var viewModel = TaskViewModel()
    @StateObject private var categoryStore = CategoryStore()
    
    @State private var showingAddTask = false
    @State private var showingFilters = false
    @State private var showingSettings = false
    @AppStorage("darkMode") private var darkMode = false
    @AppStorage("username") private var username = ""
    
    // Filter selection states
    @State private var selectedFilter: FilterOption = .all
    @State private var selectedCategory: String? = nil
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    // Inside ContentView struct, add this computed property
    var groupedUpcomingTasks: [String: [Task]] {
        guard selectedFilter == .upcoming else { return [:] }
        
        var groupedTasks = [String: [Task]]()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        for task in filteredTasks {
            guard let dueDate = task.dueDate else { continue }
            let dateString = dateFormatter.string(from: dueDate)
            
            if groupedTasks[dateString] == nil {
                groupedTasks[dateString] = [task]
            } else {
                groupedTasks[dateString]!.append(task)
            }
        }
        
        return groupedTasks
    }
    
    // Helper function to get a readable date format
    func formatDateHeader(_ dateString: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        if let date = dateFormatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            return displayFormatter.string(from: date)
        }
        return dateString
    }
    
    // Compute filtered tasks - FIXED VERSION
    var filteredTasks: [Task] {
        var filtered = viewModel.filteredAndSortedTasks
        
        // First filter out deleted tasks for all filters except .deleted
        if selectedFilter != .deleted {
            filtered = filtered.filter { !$0.isDeleted }
        }
        
        // Filter by status
        switch selectedFilter {
        case .all:
            // Show all non-deleted tasks
            break
        case .active:
            filtered = filtered.filter { !$0.isCompleted }
        case .today:
            let today = Calendar.current.startOfDay(for: Date())
            filtered = filtered.filter {
                // Include tasks with today's date OR tasks with no due date
                if $0.isCompleted { return false }
                if $0.dueDate == nil { return true } // Tasks with no due date are for today
                return Calendar.current.isDate($0.dueDate!, inSameDayAs: today)
            }
        case .upcoming:
            let today = Calendar.current.startOfDay(for: Date())
            filtered = filtered.filter {
                guard let dueDate = $0.dueDate else { return false }
                return dueDate > today && !$0.isCompleted
            }
        case .completed:
            filtered = filtered.filter { $0.isCompleted }
        case .deleted:
            filtered = filtered.filter { $0.isDeleted }
        }
        
        // Filter by category if one is selected
        if let category = selectedCategory {
            filtered = filtered.filter { $0.category == category }
        }
        
        // Filter by search text
        if !viewModel.searchText.isEmpty {
            filtered = filtered.filter {
                $0.title.localizedCaseInsensitiveContains(viewModel.searchText) ||
                $0.notes.localizedCaseInsensitiveContains(viewModel.searchText)
            }
        }
        
        // Sort tasks by priority (high to low) and then by date
        return filtered.sorted { task1, task2 in
            // First sort by completion status (incomplete first)
            if task1.isCompleted != task2.isCompleted {
                return !task1.isCompleted
            }
            
            // Next sort by priority (high to low)
            if task1.priority != task2.priority {
                let priorities: [Task.Priority] = [.high, .medium, .low]
                if let index1 = priorities.firstIndex(of: task1.priority),
                   let index2 = priorities.firstIndex(of: task2.priority) {
                    return index1 < index2
                }
            }
            
            // Handle cases where one or both tasks might not have due dates
            if let date1 = task1.dueDate, let date2 = task2.dueDate {
                return date1 < date2
            } else if task1.dueDate != nil {
                return true
            } else if task2.dueDate != nil {
                return false
            }
            
            // If everything else is equal, sort by title
            return task1.title < task2.title
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search tasks...", text: $viewModel.searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .padding(.horizontal)
                .padding(.top)
                
                // Tasks List
                List {
                    if selectedFilter == .deleted {
                        ForEach(filteredTasks) { task in
                            VStack(alignment: .leading) {
                                TaskRow(task: task, viewModel: viewModel)
                                if let deletedDate = task.deletedDate {
                                    Text("Deleted: \(formatDate(deletedDate))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    viewModel.permanentlyDeleteTask(task)
                                } label: {
                                    Label("Permanently Delete", systemImage: "trash.fill")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    viewModel.restoreTask(task)
                                } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.blue)
                            }
                        }
                    } else {
                        // Regular list for other filters
                        ForEach(filteredTasks) { task in
                            NavigationLink(destination: TaskDetailView(task: task, viewModel: viewModel, categoryStore: categoryStore)) {
                                TaskRow(task: task, viewModel: viewModel)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    if let index = viewModel.tasks.firstIndex(where: { $0.id == task.id }) {
                                        viewModel.deleteTask(at: IndexSet(integer: index))
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    viewModel.toggleCompletion(for: task)
                                } label: {
                                    Label("Complete", systemImage: "checkmark")
                                }
                                .tint(.green)
                            }
                        }
                        .onDelete(perform: viewModel.deleteTask)
                    }
                    
                    if filteredTasks.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "checkmark.circle")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("No tasks found")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Add a new task to get started")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
            .navigationTitle(username.isEmpty ? "Welcome" : "Welcome, \(username)")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(darkMode ? .dark : .light)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingFilters = true }) {
                        Image(systemName: "line.horizontal.3.decrease.circle")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button(action: { showingAddTask = true }) {
                            Image(systemName: "plus")
                        }
                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gear")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddTask) {
                AddTaskView(viewModel: viewModel, categoryStore: categoryStore)
            }
            .sheet(isPresented: $showingFilters) {
                FiltersView(selectedFilter: $selectedFilter, selectedCategory: $selectedCategory, categoryStore: categoryStore)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .onAppear {
                // Check notification permissions on app appear
                UNUserNotificationCenter.current().getNotificationSettings { settings in
                    if settings.authorizationStatus != .authorized {
                        // Show alert to enable notifications
                        DispatchQueue.main.async {
                            let alert = UIAlertController(
                                title: "Enable Notifications",
                                message: "Please enable notifications to receive task reminders",
                                preferredStyle: .alert
                            )
                            alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            })
                            alert.addAction(UIAlertAction(title: "Later", style: .cancel))
                            
                            // Get the root view controller properly for iOS 15+
                            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let rootViewController = windowScene.windows.first?.rootViewController {
                                rootViewController.present(alert, animated: true)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - AddTaskView (A proper form to add tasks)
struct AddTaskView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: TaskViewModel
    @ObservedObject var categoryStore: CategoryStore
    
    @State private var title = ""
    @State private var notes = ""
    @State private var dueDate = Date()
    @State private var dueTime = Date()
    @State private var hasDueDate = false
    @State private var hasDueTime = false
    @State private var priority: Task.Priority = .medium
    @State private var selectedCategory: String = Task.defaultCategories.first ?? "Personal"
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Task Details")) {
                    TextField("Task Title", text: $title)
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(categoryStore.allCategories(), id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                    Picker("Priority", selection: $priority) {
                        ForEach(Task.Priority.allCases, id: \.self) { p in
                            HStack {
                                Circle()
                                    .fill(p.color)
                                    .frame(width: 12, height: 12)
                                Text(p.rawValue)
                            }
                            .tag(p)
                        }
                    }
                }
                Section(header: Text("Due Date & Time")) {
                    Toggle("Set Due Date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)
                        Toggle("Set Due Time", isOn: $hasDueTime)
                        if hasDueTime {
                            DatePicker("Due Time", selection: $dueTime, displayedComponents: .hourAndMinute)
                        }
                    }
                }
                Section(header: Text("Notes")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("New Task")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        let newTask = Task(title: title,
                                           isCompleted: false,
                                           dueDate: hasDueDate ? dueDate : nil,
                                           dueTime: hasDueTime ? dueTime : nil,
                                           priority: priority,
                                           category: selectedCategory,
                                           notes: notes)
                        viewModel.addTask(newTask)
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}


// MARK: - FiltersView (Uniform Buttons & Dynamic Categories)
struct FiltersView: View {
    @Binding var selectedFilter: FilterOption
    @Binding var selectedCategory: String?
    @ObservedObject var categoryStore: CategoryStore
    @Environment(\.dismiss) var dismissView
    
    @State private var showingAddCategoryAlert = false
    @State private var newCategoryName = ""
    
    private let buttonHeight: CGFloat = 80
    private let buttonPadding: CGFloat = 12
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Filter by Status Section
                    statusFiltersSection
                    
                    // Filter by Category Section
                    categoryFiltersSection
                    
                    Spacer()
                }
                .padding(.vertical)
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismissView() }
                }
            }
            .alert("New Category", isPresented: $showingAddCategoryAlert) {
                TextField("Category name", text: $newCategoryName)
                Button("Add") {
                    if !newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty {
                        categoryStore.addCategory(newCategoryName)
                    }
                    newCategoryName = ""
                    showingAddCategoryAlert = false
                }
                Button("Cancel", role: .cancel) {
                    newCategoryName = ""
                    showingAddCategoryAlert = false
                }
            } message: {
                Text("Enter a new category name")
            }
        }
    }
    
    // Breaking down complex view into smaller components
    private var statusFiltersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filter by Status")
                .font(.headline)
                .padding(.leading, 16)
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(FilterOption.allCases) { filter in
                    Button(action: {
                        selectedFilter = filter
                        selectedCategory = nil
                    }) {
                        VStack {
                            Image(systemName: filter.icon)
                                .font(.system(size: 18))
                            Text(filter.rawValue)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                        }
                        .frame(height: buttonHeight)
                        .frame(maxWidth: .infinity)
                        .padding(buttonPadding)
                        .background(selectedFilter == filter ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    private var categoryFiltersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filter by Category")
                .font(.headline)
                .padding(.leading, 16)
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(categoryStore.allCategories(), id: \.self) { category in
                    Button(action: {
                        selectedCategory = (selectedCategory == category ? nil : category)
                    }) {
                        Text(category)
                            .font(.caption)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .multilineTextAlignment(.center)
                            .frame(height: buttonHeight)
                            .frame(maxWidth: .infinity)
                            .padding(buttonPadding)
                            .background(selectedCategory == category ? Color.green.opacity(0.2) : Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                Button(action: {
                    showingAddCategoryAlert = true
                }) {
                    VStack {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 18))
                        Text("Add")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }
                    .frame(height: buttonHeight)
                    .frame(maxWidth: .infinity)
                    .padding(buttonPadding)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - TaskRow View
struct TaskRow: View {
    let task: Task
    @ObservedObject var viewModel: TaskViewModel
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Circle()
                    .fill(task.priority.color)
                    .frame(width: 12, height: 12)
                
                Text(task.title)
                    .strikethrough(task.isCompleted)
                    .foregroundColor(task.isCompleted ? .gray : .primary)
                
                Spacer()
                
                if task.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.gray)
                }
            }
            
            // Add completion date for completed tasks
            if task.isCompleted, let completedDate = task.completedDate {
                Text("Completed: \(formatDate(completedDate))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    // Helper function to format date
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - TaskDetailView
struct TaskDetailView: View {
    let task: Task
    @ObservedObject var viewModel: TaskViewModel
    @ObservedObject var categoryStore: CategoryStore
    @State private var isEditing = false
    @State private var editedTask: Task
    @Environment(\.presentationMode) var presentationMode
    
    init(task: Task, viewModel: TaskViewModel, categoryStore: CategoryStore) {
        self.task = task
        self.viewModel = viewModel
        self.categoryStore = categoryStore
        self._editedTask = State(initialValue: task)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isEditing {
                    editTaskView
                } else {
                    taskDetailsView
                }
            }
            .padding()
        }
        .navigationTitle(isEditing ? "Edit Task" : "Task Details")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isEditing ? "Save" : "Edit") {
                    if isEditing {
                        viewModel.updateTask(editedTask)
                        presentationMode.wrappedValue.dismiss()  // Keep using presentationMode
                    }
                    isEditing.toggle()
                }
            }
        }
    }
    
    private var taskDetailsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(task.title)
                    .font(.title)
                    .fontWeight(.bold)
                Spacer()
                
                Button(action: {
                    viewModel.toggleCompletion(for: task)
                }) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundColor(task.isCompleted ? .green : .gray)
                }
            }
            
            // Category & Priority information
            HStack {
                Label(task.category, systemImage: "folder")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(5)
                
                Spacer()
                
                HStack {
                    Circle()
                        .fill(task.priority.color)
                        .frame(width: 12, height: 12)
                    Text(task.priority.rawValue)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(5)
            }
            
            Divider()
            
            // Due date information
            if let dueDate = task.dueDate {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Due Date")
                        .font(.headline)
                    
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.blue)
                        Text(formatDate(dueDate))
                        
                        if let dueTime = task.dueTime {
                            Image(systemName: "clock")
                                .foregroundColor(.blue)
                                .padding(.leading, 10)
                            Text(formatTime(dueTime))
                        }
                    }
                }
                
                Divider()
            }
            
            // Notes section
            if !task.notes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes")
                        .font(.headline)
                    Text(task.notes)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
                
                Divider()
            }
            
            // Completion status
            if task.isCompleted, let completedDate = task.completedDate {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Status")
                        .font(.headline)
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Completed on \(formatDate(completedDate))")
                    }
                }
            }
            
            Spacer()
        }
    }
    
    private var editTaskView: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Task Title", text: $editedTask.title)
                .font(.title3)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            
            VStack(alignment: .leading) {
                Text("Category")
                    .font(.headline)
                Picker("Category", selection: $editedTask.category) {
                    ForEach(categoryStore.allCategories(), id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            
            VStack(alignment: .leading) {
                Text("Priority")
                    .font(.headline)
                Picker("Priority", selection: $editedTask.priority) {
                    ForEach(Task.Priority.allCases, id: \.self) { priority in
                        HStack {
                            Circle()
                                .fill(priority.color)
                                .frame(width: 12, height: 12)
                            Text(priority.rawValue)
                        }
                        .tag(priority)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            
            // Completely rewritten date section with simpler logic
            dateSection
            
            VStack(alignment: .leading) {
                Text("Notes")
                    .font(.headline)
                TextEditor(text: $editedTask.notes)
                    .padding(4)
                    .frame(minHeight: 100)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }
            
            Toggle("Mark as Completed", isOn: $editedTask.isCompleted)
                .toggleStyle(SwitchToggleStyle(tint: .green))
        }
    }
    
    private var dateSection: some View {
        VStack(alignment: .leading) {
            Text("Due Date & Time")
                .font(.headline)
            
            // Separate toggle for due date
            dueDateToggleView
            
            // Only show date picker if there's a due date
            if editedTask.dueDate != nil {
                dueDatePickerView
                
                // Separate toggle for due time
                dueTimeToggleView
                
                // Only show time picker if there's a due time
                if editedTask.dueTime != nil {
                    dueTimePickerView
                }
            }
        }
    }

    // Break up complex expressions into separate views
    private var dueDateToggleView: some View {
        Toggle("Set Due Date", isOn: Binding(
            get: {
                editedTask.dueDate != nil
            },
            set: { newValue in
                if newValue {
                    if editedTask.dueDate == nil {
                        editedTask.dueDate = Date()
                    }
                } else {
                    editedTask.dueDate = nil
                }
            }
        ))
    }

    private var dueDatePickerView: some View {
        DatePicker(
            "Due Date",
            selection: Binding(
                get: { editedTask.dueDate ?? Date() },
                set: { editedTask.dueDate = $0 }
            ),
            displayedComponents: .date
        )
    }

    private var dueTimeToggleView: some View {
        Toggle("Set Due Time", isOn: Binding(
            get: {
                editedTask.dueTime != nil
            },
            set: { newValue in
                if newValue {
                    if editedTask.dueTime == nil {
                        editedTask.dueTime = Date()
                    }
                } else {
                    editedTask.dueTime = nil
                }
            }
        ))
    }

    private var dueTimePickerView: some View {
        DatePicker(
            "Due Time",
            selection: Binding(
                get: { editedTask.dueTime ?? Date() },
                set: { editedTask.dueTime = $0 }
            ),
            displayedComponents: .hourAndMinute
        )
    }
    
    // Helper functions to format date and time
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
