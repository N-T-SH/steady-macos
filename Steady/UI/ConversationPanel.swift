import SwiftUI

struct ConversationPanel: View {
    @ObservedObject var appState: AppState
    @State private var showingSettings = false
    @State private var showingActivityLog = false
    @State private var inputText = ""
    @State private var newTodoText = ""
    @State private var showingTodoAdd = false

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            Divider()

            if showingSettings {
                InlineSettingsView(isPresented: $showingSettings)
            } else if showingActivityLog {
                ActivityLogView(appState: appState, isPresented: $showingActivityLog)
            } else {
                chatView
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { appState.panelDidOpen() }
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack(spacing: 10) {
            InfographicCardView(spec: appState.currentInfographic, appState: appState)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingActivityLog.toggle()
                    if showingActivityLog { showingSettings = false }
                }
            }) {
                Image(systemName: showingActivityLog ? "xmark.circle" : "list.bullet.rectangle").font(.body)
            }
            .buttonStyle(PlainButtonStyle())
            .help(showingActivityLog ? "Close activity log" : "Activity Log")

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingSettings.toggle()
                    if showingSettings { showingActivityLog = false }
                }
            }) {
                Image(systemName: showingSettings ? "xmark.circle" : "gear").font(.body)
            }
            .buttonStyle(PlainButtonStyle())
            .help(showingSettings ? "Close settings" : "Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Chat View

    private var chatView: some View {
        VStack(spacing: 0) {
            if appState.activeSession != nil {
                sessionControls
                Divider()
            }
            messagesList
            Divider()
            if appState.showTodoPanel || !appState.localStore.todos.isEmpty {
                todoPanel
                Divider()
            }
            if !appState.activeTimers.isEmpty {
                timerBar
                Divider()
            }
            inputArea
        }
    }

    // MARK: - Todo Panel

    private var todoPanel: some View {
        VStack(spacing: 0) {
            // Add button — no title, flush right
            HStack {
                Spacer()
                Button(action: { withAnimation(.easeInOut(duration: 0.15)) { showingTodoAdd.toggle() } }) {
                    Image(systemName: showingTodoAdd ? "xmark" : "plus")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help(showingTodoAdd ? "Cancel" : "Add intention")
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 2)

            // Quick-add field
            if showingTodoAdd {
                HStack(spacing: 6) {
                    TextField("Add intention…", text: $newTodoText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 12))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
                        .onSubmit { commitNewTodo() }
                    Button(action: commitNewTodo) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(newTodoText.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .accentColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(newTodoText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 5)
            }

            // Todo list with drag reorder
            if !appState.localStore.todos.isEmpty {
                List {
                    ForEach(appState.localStore.todos) { todo in
                        TodoRow(
                            todo: todo,
                            onToggle: { appState.toggleTodo(id: todo.id) },
                            onDelete: { appState.deleteTodo(id: todo.id) }
                        )
                        .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .onMove { appState.reorderTodos(from: $0, to: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(height: min(CGFloat(appState.localStore.todos.count) * 28 + 4, 148))
            }
        }
        .background(Color.accentColor.opacity(0.04))
        .padding(.bottom, 4)
    }

    private func commitNewTodo() {
        let text = newTodoText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        appState.addTodo(text: text)
        newTodoText = ""
        showingTodoAdd = false
    }

    // MARK: - Timer Bar

    private var timerBar: some View {
        VStack(spacing: 3) {
            ForEach(appState.activeTimers) { timer in
                HStack(spacing: 7) {
                    Circle()
                        .fill(Color.orange.opacity(timer.isNudge ? 0.5 : 1.0))
                        .frame(width: 5, height: 5)
                    Text(timer.label)
                        .font(.system(size: 11))
                        .foregroundColor(timer.isNudge ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer()
                    if timer.isNudge {
                        // No countdown — just a calm target time
                        Text("checking in \(timer.formattedTargetTime)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.8))
                            .italic()
                    } else {
                        Text(timer.endsAt, style: .timer)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.orange)
                            .monospacedDigit()
                    }
                    Button(action: { appState.removeTimer(id: timer.id) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Color.orange.opacity(0.05))
    }

    // MARK: - Session Controls

    private var sessionControls: some View {
        HStack {
            if let sm = appState.sessionManager {
                Text(sm.formattedElapsedTime())
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                if let intention = appState.currentIntention {
                    Text("· \(intention.task)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(sm.isPaused ? "Resume" : "Pause") {
                    Task {
                        if sm.isPaused { await sm.resumeSession() }
                        else { await sm.pauseSession() }
                    }
                }
                .buttonStyle(BorderedButtonStyle())
                .controlSize(.mini)
            }
            Button("End") { appState.endSession(reflection: nil) }
                .buttonStyle(BorderedButtonStyle())
                .controlSize(.mini)
                .foregroundColor(.red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Messages List

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(appState.conversations) { turn in
                        MessageBubble(turn: turn).id(turn.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: appState.conversations.count) { _ in scrollToBottom(proxy: proxy) }
            .onAppear { scrollToBottom(proxy: proxy) }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let last = appState.conversations.last {
            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(spacing: 8) {
            // Todo toggle button — left edge
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.showTodoPanel.toggle()
                    if !appState.showTodoPanel { showingTodoAdd = false }
                }
            }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: appState.showTodoPanel ? "checklist" : "circle")
                        .font(.title2)
                        .foregroundColor(appState.showTodoPanel ? .accentColor : (appState.activeTodos.isEmpty ? .gray : .accentColor))
                    if !appState.activeTodos.isEmpty {
                        Text("\(appState.activeTodos.count)")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 12, height: 12)
                            .background(Circle().fill(Color.accentColor))
                            .offset(x: 4, y: -4)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .help(appState.showTodoPanel ? "Hide intentions" : "Show intentions")

            TextField("Message Steady…", text: $inputText)
                .textFieldStyle(PlainTextFieldStyle())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color(NSColor.controlBackgroundColor)))
                .onSubmit { sendMessage() }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(inputText.isEmpty ? .gray : .accentColor)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(inputText.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func sendMessage() {
        guard !inputText.isEmpty else { return }
        appState.sendUserMessage(inputText)
        inputText = ""
    }
}

// MARK: - Todo Row

private struct TodoRow: View {
    let todo: TodoItem
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Button(action: onToggle) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundColor(todo.isCompleted ? .secondary : .accentColor)
            }
            .buttonStyle(PlainButtonStyle())

            Text(todo.text)
                .font(.system(size: 12))
                .foregroundColor(todo.isCompleted ? .secondary : .primary)
                .strikethrough(todo.isCompleted, color: .secondary)
                .lineLimit(2)

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.4))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let turn: ConversationTurn
    private var isUser: Bool { turn.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(turn.content)
                    .font(.body)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 16)
                        .fill(isUser ? Color.accentColor : Color(NSColor.controlBackgroundColor)))
                    .foregroundColor(isUser ? .white : .primary)
                Text(turn.timestamp, style: .time)
                    .font(.caption2).foregroundColor(.secondary)
            }
            if !isUser { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Activity Log View

struct ActivityLogView: View {
    @ObservedObject var appState: AppState
    @Binding var isPresented: Bool

    @State private var filterProject: String = "All"

    private var sm: SessionManager? { appState.sessionManager }

    private var allActivity: [URLClassification] { sm?.allActivityToday ?? [] }

    private var knownProjects: [String] {
        let fromIntentions = appState.localStore.intentions.map { $0.task }
        let fromActivity   = allActivity.compactMap { $0.project }
        return Array(Set(fromIntentions + fromActivity))
            .filter { !$0.isEmpty }.sorted()
    }

    private var filteredActivity: [URLClassification] {
        guard filterProject != "All" else { return allActivity }
        return allActivity.filter { $0.project == filterProject }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(sm?.activityWatchConnected == true ? Color.green : Color.yellow)
                        .frame(width: 7, height: 7)
                    Text(sm?.activityWatchConnected == true ? "ActivityWatch connected" : "ActivityWatch not connected")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("\(allActivity.count) events today")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            if sm?.activityWatchConnected != true {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Install ActivityWatch to start tracking:")
                        .font(.system(size: 11, weight: .medium))
                    Text("1. Download from activitywatch.net\n2. Install the browser extension for Chrome\n3. Launch ActivityWatch — Steady connects automatically (~10s)")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color.yellow.opacity(0.07))
            }

            Divider()
            activityTab
        }
    }

    // MARK: - Activity Tab

    @ViewBuilder
    private var activityTab: some View {
        // Project filter chips
        if !knownProjects.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    FilterChip(label: "All", selected: filterProject == "All") { filterProject = "All" }
                    ForEach(knownProjects, id: \.self) { p in
                        FilterChip(label: p, selected: filterProject == p) { filterProject = p }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
            }
            Divider()
        }

        if filteredActivity.isEmpty {
            VStack(spacing: 8) {
                Text(allActivity.isEmpty ? "No activity captured yet" : "No activity for this project")
                    .font(.headline).foregroundColor(.secondary)
                if allActivity.isEmpty {
                    Text("Browse with ActivityWatch running\nand events will appear here within ~10s")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(filteredActivity.reversed().enumerated()), id: \.offset) { _, c in
                        ActivityLogRow(
                            classification: c,
                            knownProjects: knownProjects,
                            onReclassify: { project in
                                sm?.reclassify(classificationAt: c.timestamp, project: project)
                            }
                        )
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

}

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(selected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                .foregroundColor(selected ? .white : .primary)
                .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Activity Log Row

private struct ActivityLogRow: View {
    @ObservedObject private var store = LocalStore.shared
    let classification: URLClassification
    let knownProjects: [String]
    let onReclassify: (String) -> Void

    @State private var showingProjectPicker = false

    /// Effective status mirrors URLTracker's 3-level priority chain.
    private var displayStatus: TaskStatus {
        if let project = classification.project,
           let catName = store.projectAssignments[project],
           let cat = store.projectCategories.first(where: { $0.name == catName }) {
            return cat.status
        }
        return store.urlCategoryOverrides[classification.category.rawValue] ?? classification.taskStatus
    }

    private func dotColor(for status: TaskStatus) -> Color {
        switch status {
        case .onTask:     return .green
        case .drift:      return .yellow
        case .goofingOff: return .red
        }
    }

    private static let ts: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    private var displayLabel: String {
        if classification.url.hasPrefix("app://") {
            return classification.url
                .replacingOccurrences(of: "app://", with: "")
                .removingPercentEncoding ?? classification.url
        }
        return URL(string: classification.url)?.host ?? classification.url
    }

    private var subtitle: String {
        if classification.pageTitle.isEmpty { return classification.url }
        return classification.pageTitle
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Time + dot
            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.ts.string(from: classification.timestamp))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                Circle()
                    .fill(dotColor(for: displayStatus).opacity(0.85))
                    .frame(width: 6, height: 6)
                    .padding(.top, 2)
            }
            .frame(width: 56, alignment: .trailing)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(displayLabel)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(classification.category.displayName.isEmpty ? classification.category.rawValue : classification.category.displayName)
                        .font(.system(size: 10))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.12))
                        .cornerRadius(3)
                        .foregroundColor(.secondary)
                }
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if let project = classification.project, !project.isEmpty {
                    Text(project)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.accentColor)
                }
            }

            Spacer()

            // Project assignment button
            Button(action: { showingProjectPicker = true }) {
                Image(systemName: "tag")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .popover(isPresented: $showingProjectPicker, arrowEdge: .trailing) {
                ProjectPickerPopover(
                    currentProject: classification.project,
                    knownProjects: knownProjects,
                    onSelect: { project in
                        onReclassify(project)
                        showingProjectPicker = false
                    }
                )
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(4)
        .padding(.horizontal, 8)
    }
}

// MARK: - Project Picker Popover

private struct ProjectPickerPopover: View {
    @ObservedObject private var store = LocalStore.shared
    let currentProject: String?
    let knownProjects: [String]
    let onSelect: (String) -> Void

    @State private var newProjectName: String = ""
    @FocusState private var newProjectFocused: Bool

    private func categoryLabel(for project: String) -> String {
        guard let catName = store.projectAssignments[project],
              let cat = store.projectCategories.first(where: { $0.name == catName }) else { return "" }
        return cat.name
    }

    private func categoryColor(for project: String) -> Color? {
        guard let catName = store.projectAssignments[project],
              let cat = store.projectCategories.first(where: { $0.name == catName }) else { return nil }
        switch cat.status {
        case .onTask:     return .green
        case .drift:      return .yellow
        case .goofingOff: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Assign to Project")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)

            if !knownProjects.isEmpty {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(knownProjects, id: \.self) { project in
                            Button(action: { onSelect(project) }) {
                                HStack(spacing: 6) {
                                    if let color = categoryColor(for: project) {
                                        Circle().fill(color).frame(width: 6, height: 6)
                                    }
                                    Text(project)
                                        .font(.system(size: 12))
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if project == currentProject {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10))
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .padding(.horizontal, 12).padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            .background(project == currentProject ? Color.accentColor.opacity(0.08) : Color.clear)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("New Project")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                TextField("Project name", text: $newProjectName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(size: 12))
                    .focused($newProjectFocused)
                Text("Assign a category in Settings → Projects")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Button("Create & Assign") {
                    let name = newProjectName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    onSelect(name)
                }
                .buttonStyle(BorderedProminentButtonStyle())
                .controlSize(.small)
                .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
        }
        .frame(width: 240)
        .onAppear { newProjectFocused = knownProjects.isEmpty }
    }
}

// MARK: - Projects Section (URL category overrides + user categories + project→category assignments)

private struct ProjectsSection: View {
    @ObservedObject private var store = LocalStore.shared
    @State private var newCategoryName = ""
    @State private var newCategoryStatus = TaskStatus.onTask
    @State private var editingCategory: ProjectCategory? = nil
    @State private var editCategoryName = ""
    @State private var editCategoryStatus = TaskStatus.onTask
    @State private var confirmingDeleteCategory: UUID? = nil

    private func statusColor(_ s: TaskStatus) -> Color {
        switch s { case .onTask: return .green; case .drift: return .yellow; case .goofingOff: return .red }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            activityTypesSection
            Divider()
            categoriesSection
            if !store.allProjectNames.isEmpty {
                Divider()
                assignmentsSection
            }
        }
    }

    // MARK: Activity Types (auto-generated URLCategory overrides)

    private var activityTypesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Activity Types", detail: "Override the default status for auto-detected categories.")

            VStack(spacing: 3) {
                ForEach(URLCategory.allCases.filter { $0 != .unknown }, id: \.self) { urlCat in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor(store.effectiveStatus(for: urlCat)))
                            .frame(width: 8, height: 8)
                        Text(urlCat.displayName)
                            .font(.system(size: 12)).lineLimit(1)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { store.effectiveStatus(for: urlCat) },
                            set: { store.setURLCategoryOverride(urlCat, status: $0) }
                        )) {
                            ForEach(TaskStatus.allCases, id: \.self) { s in
                                Text(s.displayName).tag(s)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
                .textCase(.uppercase).tracking(0.4)
            if let detail = detail {
                Text(detail).font(.system(size: 10)).foregroundColor(.secondary.opacity(0.8))
            }
        }
    }

    // MARK: User Categories

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Custom Categories", detail: "Group projects into named categories with a status.")

            if store.projectCategories.isEmpty {
                Text("No categories yet. Add one below.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            } else {
                VStack(spacing: 3) {
                    ForEach(store.projectCategories) { cat in
                        if editingCategory?.id == cat.id {
                            // Inline edit row
                            HStack(spacing: 6) {
                                Circle().fill(statusColor(editCategoryStatus)).frame(width: 8, height: 8)
                                TextField("Category name", text: $editCategoryName)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .font(.system(size: 12))
                                Picker("", selection: $editCategoryStatus) {
                                    ForEach(TaskStatus.allCases, id: \.self) { s in
                                        Text(s.displayName).tag(s)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 100)
                                Button("Save") {
                                    let name = editCategoryName.trimmingCharacters(in: .whitespaces)
                                    guard !name.isEmpty else { return }
                                    var updated = cat
                                    updated.name   = name
                                    updated.status = editCategoryStatus
                                    store.save(projectCategory: updated)
                                    editingCategory = nil
                                }
                                .buttonStyle(BorderedProminentButtonStyle()).controlSize(.mini)
                                .disabled(editCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                                Button("Cancel") { editingCategory = nil }
                                    .buttonStyle(BorderedButtonStyle()).controlSize(.mini)
                            }
                            .padding(.vertical, 2)
                        } else {
                            HStack(spacing: 6) {
                                Circle().fill(statusColor(cat.status)).frame(width: 8, height: 8)
                                Text(cat.name).font(.system(size: 12)).lineLimit(1)
                                Text(cat.status.displayName)
                                    .font(.system(size: 10)).foregroundColor(.secondary)
                                Spacer()
                                Button(action: {
                                    editCategoryName   = cat.name
                                    editCategoryStatus = cat.status
                                    editingCategory    = cat
                                }) {
                                    Image(systemName: "pencil").font(.system(size: 11))
                                }
                                .buttonStyle(PlainButtonStyle()).foregroundColor(.secondary)
                                if confirmingDeleteCategory == cat.id {
                                    Button("Delete?") {
                                        store.deleteProjectCategory(id: cat.id)
                                        confirmingDeleteCategory = nil
                                    }
                                    .buttonStyle(BorderedButtonStyle()).controlSize(.mini).foregroundColor(.red)
                                    Button("No") { confirmingDeleteCategory = nil }
                                        .buttonStyle(BorderedButtonStyle()).controlSize(.mini)
                                } else {
                                    Button(action: { confirmingDeleteCategory = cat.id }) {
                                        Image(systemName: "trash").font(.system(size: 11))
                                    }
                                    .buttonStyle(PlainButtonStyle()).foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }

            // Add new category
            HStack(spacing: 6) {
                Circle().fill(statusColor(newCategoryStatus)).frame(width: 8, height: 8)
                TextField("New category…", text: $newCategoryName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(size: 12))
                Picker("", selection: $newCategoryStatus) {
                    ForEach(TaskStatus.allCases, id: \.self) { s in
                        Text(s.displayName).tag(s)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
                Button("Add") {
                    let name = newCategoryName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    store.save(projectCategory: ProjectCategory(name: name, status: newCategoryStatus))
                    newCategoryName = ""
                    newCategoryStatus = .onTask
                }
                .buttonStyle(BorderedButtonStyle()).controlSize(.mini)
                .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: Project → Category Assignments

    private var assignmentsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Project → Category", detail: "Applies to all projects — auto-detected and manual.")

            VStack(spacing: 3) {
                ForEach(store.allProjectNames, id: \.self) { project in
                    HStack(spacing: 6) {
                        Text(project)
                            .font(.system(size: 12)).lineLimit(1)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { store.projectAssignments[project] ?? "" },
                            set: { store.assignCategory(toProject: project, categoryName: $0.isEmpty ? nil : $0) }
                        )) {
                            Text("(none)").tag("")
                            if !store.projectCategories.isEmpty {
                                Divider()
                                ForEach(store.projectCategories, id: \.name) { cat in
                                    Label {
                                        Text(cat.name)
                                    } icon: {
                                        Image(systemName: "circle.fill")
                                            .foregroundColor(statusColor(cat.status))
                                            .font(.system(size: 8))
                                    }
                                    .tag(cat.name)
                                }
                            }
                            Divider()
                            ForEach(URLCategory.allCases.filter { $0 != .unknown }, id: \.self) { urlCat in
                                Label {
                                    Text(urlCat.displayName)
                                } icon: {
                                    Image(systemName: "circle.fill")
                                        .foregroundColor(statusColor(store.effectiveStatus(for: urlCat)))
                                        .font(.system(size: 8))
                                }
                                .tag(urlCat.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }
}

// MARK: - Infographic Card View

struct InfographicCardView: View {
    let spec: InfographicSpec?
    let appState: AppState

    var body: some View {
        if let spec = spec {
            cardWithLink(spec)
        } else {
            // Shown only during the brief moment before configure() fires (app cold start)
            Text("Steady")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func cardWithLink(_ spec: InfographicSpec) -> some View {
        if let urlString = spec.linkURL, let url = URL(string: urlString) {
            renderedCard(spec)
                .underline(false)
                .overlay(alignment: .bottomLeading) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary.opacity(0.5))
                        .offset(y: 2)
                }
                .onTapGesture { NSWorkspace.shared.open(url) }
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
        } else {
            renderedCard(spec)
        }
    }

    // MARK: Card dispatch

    @ViewBuilder
    private func renderedCard(_ spec: InfographicSpec) -> some View {
        switch spec.cardType {
        case .stat:       statCard(spec)
        case .multiStat:  multiStatCard(spec)
        case .barSplit:   barSplitCard(spec)
        case .dotRow:     dotRowCard(spec)
        case .labelValue: labelValueCard(spec)
        }
    }

    // MARK: stat

    private func statCard(_ spec: InfographicSpec) -> some View {
        let accentColor = color(for: spec.accent)
        return VStack(alignment: .leading, spacing: 1) {
            if let label = spec.label {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(spec.value ?? "—")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(accentColor ?? .primary)
                    .lineLimit(1)
                if let subtitle = spec.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: multiStat

    private func multiStatCard(_ spec: InfographicSpec) -> some View {
        let items = Array((spec.items ?? []).prefix(3))
        return HStack(alignment: .center, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.value)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text(item.label)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                if idx < items.count - 1 {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1, height: 24)
                        .padding(.horizontal, 12)
                }
            }
        }
    }

    // MARK: barSplit

    private func barSplitCard(_ spec: InfographicSpec) -> some View {
        let segments = spec.segments ?? []
        return VStack(alignment: .leading, spacing: 4) {
            if let title = spec.barTitle {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color(for: seg.color) ?? .gray)
                            .frame(width: max(4, geo.size.width * CGFloat(seg.ratio) - 2))
                    }
                }
            }
            .frame(height: 8)
            // Legend
            HStack(spacing: 10) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(color(for: seg.color) ?? .gray)
                            .frame(width: 5, height: 5)
                        Text(seg.label)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: dotRow

    private func dotRowCard(_ spec: InfographicSpec) -> some View {
        let dots = spec.dots ?? []
        return VStack(alignment: .leading, spacing: 4) {
            if let title = spec.dotTitle {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
            HStack(spacing: 4) {
                ForEach(Array(dots.prefix(12).enumerated()), id: \.offset) { _, dot in
                    Circle()
                        .fill(color(for: dot) ?? .gray)
                        .frame(width: 8, height: 8)
                }
            }
        }
    }

    // MARK: labelValue

    private func labelValueCard(_ spec: InfographicSpec) -> some View {
        let rows = spec.rows ?? []
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(rows.prefix(2).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    Text(row.label)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Text(row.value)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: Helper

    private func color(for name: String?) -> Color? {
        switch name {
        case "green":  return .green
        case "yellow": return .yellow
        case "red":    return .red
        case "orange": return .orange   // legacy LLM responses
        case "blue":   return .blue
        case "gray":   return .gray
        default:       return nil
        }
    }
}

// MARK: - Inline Settings View

struct InlineSettingsView: View {
    @Binding var isPresented: Bool
    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab { case general, projects }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                tabButton("General",  tab: .general,  icon: "key")
                tabButton("Projects", tab: .projects, icon: "folder")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            switch selectedTab {
            case .general:  GeneralSettingsTab()
            case .projects: ProjectsSettingsTab()
            }
        }
    }

    private func tabButton(_ label: String, tab: SettingsTab, icon: String) -> some View {
        Button(action: { selectedTab = tab }) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 11))
                Text(label).font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(selectedTab == tab ? Color.accentColor.opacity(0.12) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
    }
}

// MARK: - General Settings Tab

private struct GeneralSettingsTab: View {
    @State private var apiKey: String = ""
    @State private var apiKeySaved = false

    @AppStorage("llm.providerURL") private var providerURL = "https://openrouter.ai/api/v1"
    @AppStorage("llm.classificationModel") private var classificationModel = ""
    @AppStorage("llm.conversationModel") private var conversationModel = ""
    @AppStorage("obsidian.vaultPath") private var vaultPath = ""
    @AppStorage("obsidian.enabled") private var obsidianEnabled = false
    @AppStorage("content.feedURL") private var contentFeedURL = "https://bookmarkgarden.vercel.app/?item=tweet-2036000729173987338"

    enum TestState { case idle, testing, success(String), failure(String) }
    @State private var testState: TestState = .idle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                settingsSection("API Key") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            SecureField("sk-or-…", text: $apiKey)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            Button(apiKeySaved ? "Saved ✓" : "Save") { saveAPIKey() }
                                .disabled(apiKey.isEmpty)
                        }
                        HStack(spacing: 8) {
                            Button(action: testConnection) {
                                HStack(spacing: 4) {
                                    if case .testing = testState { ProgressView().controlSize(.mini) }
                                    Text(testButtonLabel)
                                }
                            }
                            .disabled(apiKey.isEmpty || conversationModel.isEmpty || { if case .testing = testState { return true }; return false }())
                            switch testState {
                            case .success(let msg):
                                Label(msg, systemImage: "checkmark.circle.fill").font(.caption).foregroundColor(.green)
                            case .failure(let msg):
                                Label(msg, systemImage: "xmark.circle.fill").font(.caption).foregroundColor(.red)
                            default: EmptyView()
                            }
                        }
                        Text("OpenRouter or OpenAI-compatible key")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                settingsSection("Provider") {
                    TextField("https://openrouter.ai/api/v1", text: $providerURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }

                settingsSection("Models") {
                    VStack(spacing: 6) {
                        HStack {
                            Text("Classification")
                                .font(.system(size: 12)).foregroundColor(.secondary).frame(width: 100, alignment: .leading)
                            TextField("required", text: $classificationModel)
                                .textFieldStyle(RoundedBorderTextFieldStyle()).font(.system(size: 12))
                        }
                        HStack {
                            Text("Conversation")
                                .font(.system(size: 12)).foregroundColor(.secondary).frame(width: 100, alignment: .leading)
                            TextField("required", text: $conversationModel)
                                .textFieldStyle(RoundedBorderTextFieldStyle()).font(.system(size: 12))
                        }
                    }
                }

                settingsSection("Obsidian") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Sync sessions to vault", isOn: $obsidianEnabled).font(.system(size: 13))
                        if obsidianEnabled {
                            HStack(spacing: 8) {
                                TextField("/Users/you/Obsidian/MyVault", text: $vaultPath)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                Button("Browse…") { browseForVault() }
                            }
                        }
                    }
                }

                settingsSection("Content Feed") {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("https://…", text: $contentFeedURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Text("Shown in the header when there's no activity yet. Point it at any page — its title becomes a clickable link.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                Text("Changes take effect immediately. Restart app to reload models.")
                    .font(.caption).foregroundColor(.secondary).padding(.top, 4)
            }
            .padding(16)
        }
        .onAppear { loadAPIKey() }
    }

    @ViewBuilder
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                .textCase(.uppercase).tracking(0.5)
            content()
        }
    }

    private var testButtonLabel: String {
        if case .testing = testState { return "Testing…" }
        return "Test Connection"
    }

    private func loadAPIKey() {
        apiKey = (try? KeychainHelper.load(key: LLMConfig.default.apiKeyIdentifier)) ?? ""
        apiKeySaved = !apiKey.isEmpty
    }

    private func saveAPIKey() {
        try? KeychainHelper.save(key: LLMConfig.default.apiKeyIdentifier, data: apiKey)
        withAnimation { apiKeySaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { apiKeySaved = false }
    }

    private func testConnection() {
        guard !conversationModel.isEmpty else { testState = .failure("Set a conversation model first"); return }
        testState = .testing
        let key = apiKey; let url = providerURL; let model = conversationModel
        Task {
            do {
                let base = url.hasSuffix("/") ? String(url.dropLast()) : url
                guard let endpoint = URL(string: "\(base)/chat/completions") else {
                    await MainActor.run { testState = .failure("Invalid URL") }; return
                }
                let body: [String: Any] = ["model": model, "messages": [["role": "user", "content": "ping"]], "max_tokens": 5]
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)
                request.timeoutInterval = 15
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200...299).contains(status) {
                    await MainActor.run { testState = .success("Connected") }
                } else {
                    let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                        .flatMap { ($0["error"] as? [String: Any])?["message"] as? String } ?? "HTTP \(status)"
                    await MainActor.run { testState = .failure(msg) }
                }
            } catch { await MainActor.run { testState = .failure(error.localizedDescription) } }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run { if case .success = testState { testState = .idle } }
        }
    }

    private func browseForVault() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.prompt = "Select Vault"
        if panel.runModal() == .OK, let url = panel.url { vaultPath = url.path }
    }
}

// MARK: - Projects Settings Tab

private struct ProjectsSettingsTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ProjectsSection()
            }
            .padding(16)
        }
    }
}
