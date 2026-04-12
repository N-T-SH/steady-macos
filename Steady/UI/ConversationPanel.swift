import SwiftUI

struct ConversationPanel: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var store = LocalStore.shared
    @State private var showingSettings = false
    @State private var showingActivityLog = false
    @State private var inputText = ""
    @State private var newTodoText = ""
    @State private var showDone = false
    @State private var showStashed = false
    @State private var todoProjectSuggestions: [String] = []
    @State private var selectedProjectFilter: String? = nil
    @State private var chatSuggestions: [String] = []
    @State private var chatSuggestionIndex = -1

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
            if appState.showTodoPanel {
                todoPanel
                Divider()
            }
            if !appState.activeTimers.isEmpty {
                timerBar
                Divider()
            }
            if !chatSuggestions.isEmpty {
                chatSuggestionsView
                Divider()
            }
            inputArea
        }
    }

    // MARK: - Todo Panel

    private var todoPanel: some View {
        let active = appState.activeTodos
        let done = appState.completedTodos
        let stashed = appState.stashedTodos
        let activeProjects: [String] = {
            var seen = Set<String>()
            return active.compactMap { $0.projectName }.filter { seen.insert($0).inserted }
        }()
        let filtered = selectedProjectFilter.map { proj in active.filter { $0.projectName == proj } } ?? active

        return ScrollView {
            VStack(spacing: 0) {
                // Project filter chips
                if activeProjects.count > 1 || (activeProjects.count == 1 && selectedProjectFilter != nil) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(activeProjects, id: \.self) { proj in
                                let isSelected = selectedProjectFilter == proj
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedProjectFilter = isSelected ? nil : proj
                                    }
                                }) {
                                    Text("#\(proj)")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(isSelected ? .white : .accentColor)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(isSelected ? Color.accentColor : Color.accentColor.opacity(0.12))
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                    }
                    Divider().padding(.horizontal, 14)
                }

                // Active items
                ForEach(filtered) { todo in
                    ActiveTodoRow(
                        todo: todo,
                        onToggle: { appState.toggleTodo(id: todo.id) },
                        onStash:  { appState.stashTodo(id: todo.id) },
                        onDelete: { appState.deleteTodo(id: todo.id) }
                    )
                }

                // Inline new-item row
                HStack(spacing: 8) {
                    Image(systemName: "circle")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.35))
                    TextField("New item… (use #project to tag)", text: $newTodoText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 12))
                        .onSubmit { commitNewTodo() }
                        .onChange(of: newTodoText) { text in
                            updateTodoProjectSuggestions(for: text)
                        }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 5)

                // Project tag autocomplete suggestions
                if !todoProjectSuggestions.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(todoProjectSuggestions, id: \.self) { project in
                            Button(action: { insertProjectTag(project) }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "number")
                                        .font(.system(size: 10))
                                        .foregroundColor(.accentColor)
                                    Text(project)
                                        .font(.system(size: 11))
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            .background(Color.accentColor.opacity(0.06))
                        }
                    }
                }

                // Done + Stashed section chips
                if !done.isEmpty || !stashed.isEmpty {
                    Divider()
                        .padding(.horizontal, 14)
                        .padding(.top, 2)
                        .padding(.bottom, 4)

                    HStack(spacing: 10) {
                        if !done.isEmpty {
                            collapsibleChip(
                                label: "Done", count: done.count,
                                isExpanded: showDone
                            ) {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    showDone.toggle()
                                }
                            }
                        }
                        if !stashed.isEmpty {
                            collapsibleChip(
                                label: "Stashed", count: stashed.count,
                                isExpanded: showStashed
                            ) {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    showStashed.toggle()
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)

                    if showDone {
                        ForEach(done) { todo in
                            DoneTodoRow(
                                todo: todo,
                                onRemove: { appState.deleteTodo(id: todo.id) }
                            )
                        }
                    }

                    if showStashed {
                        ForEach(stashed) { todo in
                            StashedTodoRow(
                                todo: todo,
                                onRestore: { appState.restoreTodo(id: todo.id) },
                                onDelete:  { appState.deleteTodo(id: todo.id) }
                            )
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .frame(maxHeight: 220)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.accentColor.opacity(0.04))
        .onAppear { appState.purgeOldDoneTodos() }
    }

    private func collapsibleChip(label: String, count: Int, isExpanded: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Capsule().fill(isExpanded ? Color.accentColor : Color.secondary.opacity(0.25)))
                    .foregroundColor(isExpanded ? .white : .secondary)
            }
            .foregroundColor(isExpanded ? .accentColor : .secondary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isExpanded ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func commitNewTodo() {
        let text = newTodoText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        appState.addTodo(text: text)
        newTodoText = ""
        todoProjectSuggestions = []
    }

    /// Extract the current unfinished #tag at the end of text (e.g., "fix bug #ste" → "ste").
    private func currentHashtagQuery(for text: String) -> String? {
        guard let lastHash = text.lastIndex(of: "#") else { return nil }
        let after = String(text[text.index(after: lastHash)...])
        // If there's a space after the #, the tag is already complete
        if after.contains(" ") { return nil }
        return after
    }

    private func updateTodoProjectSuggestions(for text: String) {
        guard let query = currentHashtagQuery(for: text) else {
            todoProjectSuggestions = []
            return
        }
        let all = store.allProjectNames
        todoProjectSuggestions = query.isEmpty
            ? Array(all.prefix(6))
            : all.filter { $0.lowercased().hasPrefix(query.lowercased()) }
    }

    private func insertProjectTag(_ project: String) {
        // Replace the partial #tag at the end with the selected project name
        if let lastHash = newTodoText.lastIndex(of: "#") {
            newTodoText = String(newTodoText[...lastHash]) + project
        } else {
            newTodoText += "#\(project)"
        }
        todoProjectSuggestions = []
    }

    // MARK: - Timer Bar

    private var timerBar: some View {
        VStack(spacing: 0) {
            ForEach(appState.activeTimers) { timer in
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.orange.opacity(timer.isNudge ? 0.5 : 1.0))
                        .frame(width: 5, height: 5)
                    Text(timer.label)
                        .font(.system(size: 12))
                        .foregroundColor(timer.isNudge ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer()
                    if timer.isNudge {
                        Text("checking in \(timer.formattedTargetTime)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.8))
                            .italic()
                    } else {
                        Text(timer.endsAt, style: .timer)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.orange)
                            .monospacedDigit()
                    }
                    Button(action: { appState.removeTimer(id: timer.id) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.45))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
            }
        }
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
            // Todo toggle button — always a radio circle
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.showTodoPanel.toggle()
                }
            }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "circle")
                        .font(.title2)
                        .foregroundColor(appState.showTodoPanel
                            ? .secondary.opacity(0.5)
                            : (appState.activeTodos.isEmpty ? .secondary.opacity(0.5) : .accentColor))
                    if !appState.showTodoPanel && !appState.activeTodos.isEmpty {
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

            TaggableTextField(
                placeholder: "Message Steady…",
                text: $inputText,
                onSubmit: sendMessageOrConfirmSuggestion,
                onArrowUp: chatArrowUp,
                onArrowDown: chatArrowDown
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(NSColor.controlBackgroundColor)))
            .onChange(of: inputText) { text in
                updateChatProjectSuggestions(for: text)
            }

            Button(action: sendMessageOrConfirmSuggestion) {
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
        chatSuggestions = []
        chatSuggestionIndex = -1
    }

    private func sendMessageOrConfirmSuggestion() {
        if chatSuggestionIndex >= 0, chatSuggestionIndex < chatSuggestions.count {
            insertChatProjectTag(chatSuggestions[chatSuggestionIndex])
        } else {
            sendMessage()
        }
    }

    private func updateChatProjectSuggestions(for text: String) {
        guard let query = currentHashtagQuery(for: text) else {
            chatSuggestions = []
            chatSuggestionIndex = -1
            return
        }
        let all = store.allProjectNames
        chatSuggestions = query.isEmpty
            ? Array(all.prefix(6))
            : all.filter { $0.lowercased().hasPrefix(query.lowercased()) }
        chatSuggestionIndex = -1
    }

    private func insertChatProjectTag(_ project: String) {
        if let lastHash = inputText.lastIndex(of: "#") {
            inputText = String(inputText[...lastHash]) + project
        } else {
            inputText += "#\(project)"
        }
        chatSuggestions = []
        chatSuggestionIndex = -1
    }

    private func chatArrowUp() {
        guard !chatSuggestions.isEmpty else { return }
        chatSuggestionIndex = chatSuggestionIndex <= 0 ? chatSuggestions.count - 1 : chatSuggestionIndex - 1
    }

    private func chatArrowDown() {
        guard !chatSuggestions.isEmpty else { return }
        chatSuggestionIndex = (chatSuggestionIndex + 1) % chatSuggestions.count
    }

    private var chatSuggestionsView: some View {
        VStack(spacing: 0) {
            ForEach(Array(chatSuggestions.enumerated()), id: \.element) { idx, project in
                Button(action: { insertChatProjectTag(project) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "number")
                            .font(.system(size: 10))
                            .foregroundColor(chatSuggestionIndex == idx ? .white : .accentColor)
                        Text(project)
                            .font(.system(size: 11))
                            .foregroundColor(chatSuggestionIndex == idx ? .white : .primary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .background(chatSuggestionIndex == idx ? Color.accentColor : Color.accentColor.opacity(0.06))
            }
        }
    }
}

// MARK: - Todo Rows

private struct ActiveTodoRow: View {
    let todo: TodoItem
    let onToggle: () -> Void
    let onStash: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Radio — marks done
            Button(action: onToggle) {
                Image(systemName: "circle")
                    .font(.system(size: 13))
                    .foregroundColor(.accentColor)
                    .frame(width: 28)
            }
            .buttonStyle(PlainButtonStyle())

            Text(formattedText(todo.text))
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Stash
            Button(action: onStash) {
                Image(systemName: "forward")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.4))
                    .frame(width: 24)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Stash for later")

            // Delete
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.4))
                    .frame(width: 24)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Delete")
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// Returns an AttributedString with #tags highlighted in accent colour.
    private func formattedText(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        let pattern = #"#[A-Za-z0-9][A-Za-z0-9\-_]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches.reversed() {
            guard let swiftRange = Range(match.range, in: text),
                  let lo = AttributedString.Index(swiftRange.lowerBound, within: result),
                  let hi = AttributedString.Index(swiftRange.upperBound, within: result) else { continue }
            result[lo..<hi].foregroundColor = Color.accentColor
        }
        return result
    }
}

private struct DoneTodoRow: View {
    let todo: TodoItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Delete (left of checkmark, matches original spec)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.4))
                    .frame(width: 28)
            }
            .buttonStyle(PlainButtonStyle())

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundColor(.secondary.opacity(0.45))
                .frame(width: 20)

            Text(todo.text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .strikethrough(true, color: .secondary)
                .lineLimit(2)

            Spacer()
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct StashedTodoRow: View {
    let todo: TodoItem
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Restore to active
            Button(action: onRestore) {
                Image(systemName: "arrow.uturn.left")
                    .font(.system(size: 10))
                    .foregroundColor(.accentColor.opacity(0.7))
                    .frame(width: 28)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Restore to active")

            Text(todo.text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Delete
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.4))
                    .frame(width: 24)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Delete")
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Taggable Text Field

/// NSTextField wrapper that intercepts up/down arrow keys for suggestion navigation.
private struct TaggableTextField: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void
    var onArrowUp: () -> Void
    var onArrowDown: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.isBordered = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 13)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TaggableTextField

        init(_ parent: TaggableTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onArrowUp()
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onArrowDown()
                return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            default:
                return false
            }
        }
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
        let activeProjects = Set(allActivity.compactMap { $0.project }.filter { !$0.isEmpty })
        return appState.localStore.projects.map { $0.name }
            .filter { activeProjects.contains($0) }
            .sorted()
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
                            knownProjects: appState.localStore.allProjectNames,
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
        // 1. Project → associated activity
        if let project = classification.project,
           let status = store.taskStatus(forProject: project) {
            return status
        }
        // 2. URLCategory → activity override
        if let activity = store.activities.first(where: { $0.urlCategoryRaw == classification.category.rawValue }) {
            return activity.status
        }
        // 3. Stored classification status
        return classification.taskStatus
    }

    private func dotColor(for status: TaskStatus) -> Color {
        switch status {
        case .onTask:     return .steadyProductive
        case .drift:      return .steadyDrift
        case .goofingOff: return .steadyGoof
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
        store.activity(forProject: project)?.name ?? ""
    }

    private func categoryColor(for project: String) -> Color? {
        guard let activity = store.activity(forProject: project) else { return nil }
        switch activity.status {
        case .onTask:     return .steadyProductive
        case .drift:      return .steadyDrift
        case .goofingOff: return .steadyGoof
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

// MARK: - Projects Section (unified Activities + Projects)

private struct ProjectsSection: View {
    @ObservedObject private var store = LocalStore.shared

    // Activity editing state
    @State private var newActivityName = ""
    @State private var newActivityStatus = TaskStatus.onTask
    @State private var editingActivity: Activity? = nil
    @State private var editActivityName = ""
    @State private var editActivityStatus = TaskStatus.onTask
    @State private var confirmingDeleteActivity: UUID? = nil

    // Project editing state
    @State private var newProjectName = ""
    @State private var editingProject: Project? = nil
    @State private var editProjectName = ""
    @State private var editProjectActivity = ""   // "" = none
    @State private var confirmingDeleteProject: UUID? = nil

    private func statusColor(_ s: TaskStatus) -> Color {
        switch s { case .onTask: return .steadyProductive; case .drift: return .steadyDrift; case .goofingOff: return .steadyGoof }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            activitiesSection
            Divider()
            projectsSection
        }
    }

    // MARK: - Activities

    private var activitiesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(
                "Activities",
                detail: "Rename, delete, or add activity types. Default types correspond to auto-detected categories."
            )

            VStack(spacing: 3) {
                ForEach(store.activities) { activity in
                    if editingActivity?.id == activity.id {
                        activityEditRow(activity)
                    } else {
                        activityDisplayRow(activity)
                    }
                }
            }

            // Add new activity row
            HStack(spacing: 6) {
                Circle().fill(statusColor(newActivityStatus)).frame(width: 8, height: 8)
                TextField("New activity…", text: $newActivityName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(size: 12))
                Picker("", selection: $newActivityStatus) {
                    ForEach(TaskStatus.allCases, id: \.self) { s in Text(s.displayName).tag(s) }
                }
                .labelsHidden().frame(width: 100)
                Button("Add") {
                    let name = newActivityName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    store.save(activity: Activity(name: name, status: newActivityStatus))
                    newActivityName = ""
                    newActivityStatus = .onTask
                }
                .buttonStyle(BorderedButtonStyle()).controlSize(.mini)
                .disabled(newActivityName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    @ViewBuilder
    private func activityEditRow(_ activity: Activity) -> some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor(editActivityStatus)).frame(width: 8, height: 8)
            TextField("Activity name", text: $editActivityName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.system(size: 12))
            Picker("", selection: $editActivityStatus) {
                ForEach(TaskStatus.allCases, id: \.self) { s in Text(s.displayName).tag(s) }
            }
            .labelsHidden().frame(width: 100)
            Button("Save") {
                let name = editActivityName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                var updated = activity
                updated.name   = name
                updated.status = editActivityStatus
                store.save(activity: updated)
                editingActivity = nil
            }
            .buttonStyle(BorderedProminentButtonStyle()).controlSize(.mini)
            .disabled(editActivityName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel") { editingActivity = nil }
                .buttonStyle(BorderedButtonStyle()).controlSize(.mini)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func activityDisplayRow(_ activity: Activity) -> some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor(activity.status)).frame(width: 8, height: 8)
            Text(activity.name).font(.system(size: 12)).lineLimit(1)
            if activity.isDefault {
                Text("built-in")
                    .font(.system(size: 9)).foregroundColor(.secondary.opacity(0.6))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(3)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { activity.status },
                set: { newStatus in
                    var updated = activity
                    updated.status = newStatus
                    store.save(activity: updated)
                }
            )) {
                ForEach(TaskStatus.allCases, id: \.self) { s in Text(s.displayName).tag(s) }
            }
            .labelsHidden().frame(width: 110)

            Button(action: {
                editActivityName   = activity.name
                editActivityStatus = activity.status
                editingActivity    = activity
            }) {
                Image(systemName: "pencil").font(.system(size: 11))
            }
            .buttonStyle(PlainButtonStyle()).foregroundColor(.secondary)

            if confirmingDeleteActivity == activity.id {
                Button("Delete?") {
                    store.deleteActivity(id: activity.id)
                    confirmingDeleteActivity = nil
                }
                .buttonStyle(BorderedButtonStyle()).controlSize(.mini).foregroundColor(.red)
                Button("No") { confirmingDeleteActivity = nil }
                    .buttonStyle(BorderedButtonStyle()).controlSize(.mini)
            } else {
                Button(action: { confirmingDeleteActivity = activity.id }) {
                    Image(systemName: "trash").font(.system(size: 11))
                }
                .buttonStyle(PlainButtonStyle()).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 1)
    }

    // MARK: - Projects

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(
                "Projects",
                detail: "Tag todos or chat with #project-name. Auto-detected from activity and added automatically."
            )

            // Default sentinel shown at top
            HStack(spacing: 6) {
                Circle().fill(Color.secondary.opacity(0.35)).frame(width: 8, height: 8)
                Text("No Project / Quest")
                    .font(.system(size: 12)).foregroundColor(.secondary)
                Text("default")
                    .font(.system(size: 9)).foregroundColor(.secondary.opacity(0.6))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(3)
                Spacer()
            }
            .padding(.vertical, 1)

            if !store.projects.isEmpty {
                VStack(spacing: 3) {
                    ForEach(store.projects) { project in
                        if editingProject?.id == project.id {
                            projectEditRow(project)
                        } else {
                            projectDisplayRow(project)
                        }
                    }
                }
            }

            // Add new project row
            HStack(spacing: 6) {
                Circle().fill(Color.secondary.opacity(0.35)).frame(width: 8, height: 8)
                TextField("New project…", text: $newProjectName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(size: 12))
                Button("Add") {
                    let name = newProjectName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    store.save(project: Project(name: name))
                    newProjectName = ""
                }
                .buttonStyle(BorderedButtonStyle()).controlSize(.mini)
                .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    @ViewBuilder
    private func projectEditRow(_ project: Project) -> some View {
        HStack(spacing: 6) {
            Circle().fill(projectColor(for: project)).frame(width: 8, height: 8)
            TextField("Project name", text: $editProjectName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.system(size: 12))
            activityPickerView(selection: $editProjectActivity)
            Button("Save") {
                let name = editProjectName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                var updated = project
                updated.name         = name
                updated.activityName = editProjectActivity.isEmpty ? nil : editProjectActivity
                store.save(project: updated)
                editingProject = nil
            }
            .buttonStyle(BorderedProminentButtonStyle()).controlSize(.mini)
            .disabled(editProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel") { editingProject = nil }
                .buttonStyle(BorderedButtonStyle()).controlSize(.mini)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func projectDisplayRow(_ project: Project) -> some View {
        HStack(spacing: 6) {
            Circle().fill(projectColor(for: project)).frame(width: 8, height: 8)
            Text(project.name).font(.system(size: 12)).lineLimit(1)
            if let actName = project.activityName {
                Text(actName)
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
            Spacer()
            Button(action: {
                editProjectName     = project.name
                editProjectActivity = project.activityName ?? ""
                editingProject      = project
            }) {
                Image(systemName: "pencil").font(.system(size: 11))
            }
            .buttonStyle(PlainButtonStyle()).foregroundColor(.secondary)

            if confirmingDeleteProject == project.id {
                Button("Delete?") {
                    store.deleteProject(id: project.id)
                    confirmingDeleteProject = nil
                }
                .buttonStyle(BorderedButtonStyle()).controlSize(.mini).foregroundColor(.red)
                Button("No") { confirmingDeleteProject = nil }
                    .buttonStyle(BorderedButtonStyle()).controlSize(.mini)
            } else {
                Button(action: { confirmingDeleteProject = project.id }) {
                    Image(systemName: "trash").font(.system(size: 11))
                }
                .buttonStyle(PlainButtonStyle()).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 1)
    }

    // MARK: - Helpers

    private func projectColor(for project: Project) -> Color {
        guard let actName = project.activityName,
              let activity = store.activities.first(where: { $0.name == actName }) else {
            return Color.secondary.opacity(0.35)
        }
        return statusColor(activity.status)
    }

    private func activityPickerView(selection: Binding<String>) -> some View {
        Picker("", selection: selection) {
            Text("(none)").tag("")
            ForEach(store.activities, id: \.name) { activity in
                HStack(spacing: 4) {
                    Circle().fill(statusColor(activity.status)).frame(width: 7, height: 7)
                    Text(activity.name)
                }
                .tag(activity.name)
            }
        }
        .labelsHidden()
        .frame(width: 120)
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
}

// MARK: - Steady Visual System Palette

/// Design tokens that mirror the menu-bar icon's visual language.
/// Productive = cyan glow pill · Drift = purple dot · Goofing = red glow pill
extension Color {
    static let steadyProductive = Color(red: 0.22, green: 0.80, blue: 0.98) // on-task → cyan
    static let steadyDrift      = Color(red: 0.65, green: 0.25, blue: 0.95) // drift → purple dot
    static let steadyGoof       = Color(red: 0.95, green: 0.28, blue: 0.28) // goofing off → red halo
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
                        let c = color(for: seg.color) ?? Color.gray
                        let isProductive = seg.color == "green" || seg.color == "blue"
                        RoundedRectangle(cornerRadius: 3)
                            .fill(c)
                            .frame(width: max(4, geo.size.width * CGFloat(seg.ratio) - 2))
                            .shadow(color: isProductive ? c.opacity(0.5) : .clear, radius: 3)
                    }
                }
            }
            .frame(height: 8)
            // Legend — use activity-dot shapes for consistency
            HStack(spacing: 10) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    HStack(spacing: 4) {
                        activityDot(for: seg.color)
                            .scaleEffect(0.7)
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
            HStack(spacing: 5) {
                ForEach(Array(dots.prefix(12).enumerated()), id: \.offset) { _, dot in
                    activityDot(for: dot)
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

    // MARK: Helper — colour name → Steady palette

    private func color(for name: String?) -> Color? {
        switch name {
        case "green":  return .steadyProductive // on-task → cyan glow
        case "blue":   return .steadyProductive // treated as productive
        case "purple": return .steadyDrift      // drift → purple dot
        case "yellow": return .steadyDrift      // legacy token for drift
        case "orange": return .steadyDrift      // legacy LLM name for drift
        case "red":    return .steadyGoof       // goofing off → vivid red
        case "gray":   return .gray
        default:       return nil
        }
    }

    // MARK: Activity dot — shape encodes meaning (mirrors menu-bar icon visual language)

    @ViewBuilder
    private func activityDot(for colorName: String) -> some View {
        switch colorName {
        case "green", "blue":
            // Productive: mini cyan pill with glow — mirrors the active menu-bar icon
            Capsule()
                .fill(Color.steadyProductive)
                .frame(width: 14, height: 6)
                .shadow(color: Color.steadyProductive.opacity(0.65), radius: 3)
        case "purple", "yellow", "orange":
            // Drift: small purple dot — present but not a full pill
            Circle()
                .fill(Color.steadyDrift)
                .frame(width: 6, height: 6)
        case "red":
            // Goofing off: vivid red pill with red halo
            Capsule()
                .fill(Color.steadyGoof)
                .frame(width: 14, height: 6)
                .shadow(color: Color.steadyGoof.opacity(0.55), radius: 3)
        default:
            // Unknown / inactive: small muted circle
            Circle()
                .fill(Color.gray.opacity(0.35))
                .frame(width: 6, height: 6)
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
