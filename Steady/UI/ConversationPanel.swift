import SwiftUI

struct ConversationPanel: View {
    @ObservedObject var appState: AppState
    @State private var showingSettings = false
    @State private var showingClassificationManager = false
    @State private var showingActivityLog = false
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            Divider()

            if showingSettings {
                InlineSettingsView(isPresented: $showingSettings)
            } else {
                chatView
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { appState.panelDidOpen() }
        .sheet(isPresented: $showingClassificationManager) {
            ClassificationManagerView(localStore: appState.localStore)
        }
        .sheet(isPresented: $showingActivityLog) {
            ActivityLogView(appState: appState)
        }
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.title2)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Steady")
                    .font(.headline)
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundColor(headerSubtitleColor)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: { showingActivityLog = true }) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.body)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Activity Log")

            Button(action: { showingClassificationManager = true }) {
                Image(systemName: "calendar")
                    .font(.body)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Site Classifications")

            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showingSettings.toggle() } }) {
                Image(systemName: showingSettings ? "xmark.circle" : "gear")
                    .font(.body)
            }
            .buttonStyle(PlainButtonStyle())
            .help(showingSettings ? "Close settings" : "Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var headerSubtitle: String {
        guard let sm = appState.sessionManager else { return "Ready to focus" }
        switch sm.sessionState {
        case .active:
            if let last = sm.allActivityToday.last {
                return last.onTask ? "Working — \(last.project ?? last.category.displayName)" : "Off track"
            }
            return "Working"
        case .paused:
            return "Paused"
        case .ending:
            return "Wrapping up…"
        case .idle:
            if let last = sm.allActivityToday.last {
                return last.category.isProductive
                    ? (last.project ?? last.category.displayName)
                    : "Goofing off"
            }
            return sm.activityWatchConnected == true ? "Tracking activity" : "ActivityWatch not connected"
        }
    }

    private var headerSubtitleColor: Color {
        guard let sm = appState.sessionManager else { return .secondary }
        switch sm.sessionState {
        case .active:
            if let last = sm.allActivityToday.last { return last.onTask ? .green : .orange }
            return .secondary
        case .paused:
            return .orange
        case .idle:
            if let last = sm.allActivityToday.last {
                return last.category.isProductive ? .green : .orange
            }
            return sm.activityWatchConnected == true ? .secondary : .orange
        default:
            return .secondary
        }
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
            if !appState.activeTimers.isEmpty {
                timerBar
                Divider()
            }
            inputArea
        }
    }

    // MARK: - Timer Bar

    private var timerBar: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let _ = appState.tickTimers()
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
                            Text(timer.formattedRemaining)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.orange)
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
    @Environment(\.dismiss) private var dismiss

    @State private var filterProject: String = "All"

    private var sm: SessionManager? { appState.sessionManager }

    private static let ts: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    private var allActivity: [URLClassification] {
        sm?.allActivityToday ?? []
    }

    private var knownProjects: [String] {
        let fromRules = appState.localStore.urlRules.map { $0.projectName }
        let fromIntentions = appState.localStore.intentions.map { $0.task }
        let fromActivity = allActivity.compactMap { $0.project }
        return Array(Set(fromRules + fromIntentions + fromActivity))
            .filter { !$0.isEmpty }.sorted()
    }

    private var filteredActivity: [URLClassification] {
        guard filterProject != "All" else { return allActivity }
        return allActivity.filter { $0.project == filterProject }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Activity Log")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle").font(.body)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider()

            // Status bar
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(sm?.activityWatchConnected == true ? Color.green : Color.orange)
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
                .background(Color.orange.opacity(0.07))
            }

            Divider()

            // Project filter
            if !knownProjects.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        FilterChip(label: "All", selected: filterProject == "All") {
                            filterProject = "All"
                        }
                        ForEach(knownProjects, id: \.self) { p in
                            FilterChip(label: p, selected: filterProject == p) {
                                filterProject = p
                            }
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                }
                Divider()
            }

            // Activity list
            if filteredActivity.isEmpty {
                VStack(spacing: 8) {
                    Text(allActivity.isEmpty ? "No activity captured yet" : "No activity for this project")
                        .font(.headline).foregroundColor(.secondary)
                    if allActivity.isEmpty {
                        Text("Browse in Chrome with ActivityWatch running\nand events will appear here within ~10s")
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
                                onReclassify: { project, category in
                                    sm?.reclassify(classificationAt: c.timestamp, project: project, category: category)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(width: 520, height: 580)
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
    let classification: URLClassification
    let knownProjects: [String]
    let onReclassify: (String, URLCategory) -> Void

    @State private var showingProjectPicker = false

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
                    .fill(classification.category.isProductive ? Color.green.opacity(0.8) : Color.orange.opacity(0.8))
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
                    currentCategory: classification.category,
                    knownProjects: knownProjects,
                    onSelect: { project, category in
                        onReclassify(project, category)
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
    let currentProject: String?
    let currentCategory: URLCategory
    let knownProjects: [String]
    let onSelect: (String, URLCategory) -> Void

    @State private var newProjectName: String = ""
    @State private var selectedCategory: URLCategory
    @FocusState private var newProjectFocused: Bool

    init(currentProject: String?, currentCategory: URLCategory, knownProjects: [String], onSelect: @escaping (String, URLCategory) -> Void) {
        self.currentProject = currentProject
        self.currentCategory = currentCategory
        self.knownProjects = knownProjects
        self.onSelect = onSelect
        _selectedCategory = State(initialValue: currentCategory)
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
                            Button(action: { onSelect(project, currentCategory) }) {
                                HStack {
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
                Picker("Category", selection: $selectedCategory) {
                    ForEach(URLCategory.allCases.filter { $0 != .unknown }, id: \.self) { cat in
                        Text(cat.displayName.isEmpty ? cat.rawValue : cat.displayName).tag(cat)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .font(.system(size: 12))
                Button("Create & Assign") {
                    guard !newProjectName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    onSelect(newProjectName.trimmingCharacters(in: .whitespaces), selectedCategory)
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

// MARK: - Project Manager Section

private struct ProjectManagerSection: View {
    @ObservedObject private var store = LocalStore.shared
    @State private var editingProject: String? = nil
    @State private var editText: String = ""
    @State private var confirmingDelete: String? = nil

    var body: some View {
        if store.allProjectNames.isEmpty {
            Text("No projects yet — they're created automatically as you work.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        } else {
            VStack(spacing: 2) {
                ForEach(store.allProjectNames, id: \.self) { project in
                    projectRow(project)
                }
            }
        }
    }

    @ViewBuilder
    private func projectRow(_ project: String) -> some View {
        HStack(spacing: 6) {
            if editingProject == project {
                TextField("Project name", text: $editText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(size: 12))
                    .onSubmit { commitRename(project) }
                Button("Save") { commitRename(project) }
                    .buttonStyle(BorderedProminentButtonStyle())
                    .controlSize(.mini)
                    .disabled(editText.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel") { editingProject = nil }
                    .buttonStyle(BorderedButtonStyle())
                    .controlSize(.mini)
            } else {
                Text(project)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer()
                // Rename
                Button(action: { startEditing(project) }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.secondary)
                .help("Rename project")
                // Delete
                if confirmingDelete == project {
                    Button("Delete?") {
                        store.deleteProject(project)
                        confirmingDelete = nil
                    }
                    .buttonStyle(BorderedButtonStyle())
                    .controlSize(.mini)
                    .foregroundColor(.red)
                    Button("No") { confirmingDelete = nil }
                        .buttonStyle(BorderedButtonStyle())
                        .controlSize(.mini)
                } else {
                    Button(action: { confirmingDelete = project }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.secondary)
                    .help("Delete project")
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func startEditing(_ project: String) {
        confirmingDelete = nil
        editText = project
        editingProject = project
    }

    private func commitRename(_ oldName: String) {
        let trimmed = editText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        store.renameProject(from: oldName, to: trimmed)
        editingProject = nil
    }
}

// MARK: - Inline Settings View

struct InlineSettingsView: View {
    @Binding var isPresented: Bool

    @State private var apiKey: String = ""
    @State private var apiKeySaved = false

    @AppStorage("llm.providerURL") private var providerURL = "https://openrouter.ai/api/v1"
    @AppStorage("llm.classificationModel") private var classificationModel = ""
    @AppStorage("llm.conversationModel") private var conversationModel = ""
    @AppStorage("obsidian.vaultPath") private var vaultPath = ""
    @AppStorage("obsidian.enabled") private var obsidianEnabled = false

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

                settingsSection("Projects") {
                    ProjectManagerSection()
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
            Text(title)
                .font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
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
