import SwiftUI

struct ConversationPanel: View {
    @ObservedObject var appState: AppState
    @State private var inputText: String = ""
    @State private var isInputFocused: Bool = false
    @Namespace private var scrollNamespace
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            panelHeader
            
            Divider()
            
            // Messages scroll view
            messagesList
            
            Divider()
            
            // Input area
            inputArea
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Header
    
    private var panelHeader: some View {
        HStack {
            // Logo/Icon
            Image(systemName: "waveform")
                .font(.title2)
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Steady")
                    .font(.headline)
                
                if let intention = appState.currentIntention {
                    Text(intention.task)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text("No active session")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Settings button
            Button(action: {
                // Open settings
            }) {
                Image(systemName: "gear")
                    .font(.body)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - Messages List
    
    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(appState.conversations) { turn in
                        MessageBubble(turn: turn)
                            .id(turn.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: appState.conversations.count) { _ in
                scrollToBottom(proxy: proxy)
            }
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastMessage = appState.conversations.last {
            withAnimation {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
    
    // MARK: - Input Area
    
    private var inputArea: some View {
        HStack(spacing: 8) {
            TextField("Message Steady...", text: $inputText)
                .textFieldStyle(PlainTextFieldStyle())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .onSubmit {
                    sendMessage()
                }
            
            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(inputText.isEmpty ? .gray : .accentColor)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(inputText.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
    
    private var isUser: Bool {
        turn.role == .user
    }
    
    var body: some View {
        HStack {
            if isUser {
                Spacer(minLength: 40)
            }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(turn.content)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isUser ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                    )
                    .foregroundColor(isUser ? .white : .primary)
                
                Text(formattedTime(turn.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if !isUser {
                Spacer(minLength: 40)
            }
        }
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - ConversationTurn Extension

extension ConversationTurn: Identifiable {
    var id: UUID {
        // Use timestamp as unique identifier
        UUID()
    }
}
