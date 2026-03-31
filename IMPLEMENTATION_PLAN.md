# Steady macOS Implementation Plan

## Project Structure

```
Steady/
├── Steady.xcodeproj/          
├── Steady/
│   ├── App/
│   │   ├── SteadyApp.swift
│   │   ├── AppDelegate.swift
│   │   └── AppState.swift
│   ├── UI/
│   │   ├── MenuBarController.swift
│   │   ├── ConversationPanel.swift
│   │   ├── PreferencesView.swift
│   │   ├── DashboardView.swift
│   │   └── Components/
│   ├── Core/
│   │   ├── Models/
│   │   │   ├── Intention.swift
│   │   │   ├── Session.swift
│   │   │   ├── ConversationTurn.swift
│   │   │   ├── URLClassification.swift
│  │   │   └── LLMConfig.swift
│   │   ├── Services/
│   │   │   ├── URLTracker.swift
│   │   │   ├── LLMProvider.swift
│   │   │   ├── ConversationEngine.swift
│   │   │   ├── NotificationManager.swift
│   │   │   └── SessionManager.swift
│   │   └── Store/
│   │       ├── LocalStore.swift
│   │       └── ObsidianSync.swift
│   ├── Resources/
│   │   ├── Assets.xcassets/
│   │   ├── Info.plist
│   │   └── Steady.entitlements
│   └── Utils/
│       ├── KeychainHelper.swift
│       └── AXHelpers.swift
├── SteadyTests/
│   ├── ModelTests.swift
│   ├── LLMProviderTests.swift
│   ├── URLTrackerTests.swift
│   └── ObsidianSyncTests.swift
└── README.md
```

## Core Models

### Intention.swift
```swift
struct Intention: Codable, Identifiable {
    let id: UUID
    let task: String
    let whyItMatters: String
    let plannedDuration: Int
    let scheduledDate: Date
    let strictness: StrictnessLevel
    let temptationBundle: String?
    let status: IntentionStatus
}

enum StrictnessLevel: String, Codable {
    case quiet, gentle, focused, accountable
}

enum IntentionStatus: String, Codable {
    case planned, active, completed, skipped
}
```

### Session.swift
```swift
struct Session: Codable, Identifiable {
    let id: UUID
    let intentionId: UUID
    let startTime: Date
    let endTime: Date?
    let interruptions: [DistractionLog]
    let preSessionEnergy: Int
    let postSessionReflection: String?
    let urlClassifications: [URLClassification]
}

struct DistractionLog: Codable {
    let timestamp: Date
    let url: String?
    let category: String
    let duration: TimeInterval
    let acknowledged: Bool
}
```

### ConversationTurn.swift
```swift
struct ConversationTurn: Codable {
    let timestamp: Date
    let role: MessageRole
    let content: String
    let context: ConversationContext?
}

enum MessageRole: String, Codable {
    case system, user, assistant
}

struct ConversationContext: Codable {
    let intention: Intention?
    let session: Session?
    let driftDuration: TimeInterval?
    let classification: URLClassification?
}
```

### URLClassification.swift
```swift
struct URLClassification: Codable {
    let url: String
    let pageTitle: String
    let onTask: Bool
    let project: String?
    let category: URLCategory
    let confidence: Double
    let reasoning: String
    let timestamp: Date
}

enum URLCategory: String, Codable {
    case coding, design, research, communication
    case socialMedia, news, entertainment, otherWork, unknown
}
```

### LLMConfig.swift
```swift
struct LLMConfig: Codable {
    let providerURL: String
    let apiKeyIdentifier: String
    let classificationModel: String
    let conversationModel: String
    let maxTokens: Int
    let temperature: Double
}
```

## Key Technical Requirements

1. **LSUIElement**: Menu bar only, no dock icon
2. **Accessibility API**: Read browser URL/title from frontmost app
3. **LLM Integration**: OpenAI-compatible API (OpenRouter default)
4. **Structured JSON**: URL classification returns {onTask, project, category, confidence, reasoning}
5. **Core Data**: Local persistence
6. **Obsidian Sync**: Markdown file generation
7. **Global Hotkeys**: Cmd+Shift+Space default
8. **Notifications**: UNUserNotificationCenter, quiet by default

## Testing Strategy

**Unit Tests:**
- Model encoding/decoding
- LLM request/response parsing
- URL parsing and classification logic
- Obsidian file format generation
- Session state machine

**Integration Tests:**
- End-to-end session flow
- LLM API integration (with mock)
- Obsidian file writing

## Implementation Order

1. Project structure & Xcode setup
2. Core Data Models with tests
3. Menu bar UI & NSPanel
4. LLM Provider & URL Classification
5. URL Tracker (Accessibility API)
6. Conversation Engine
7. Session Management
8. Obsidian Sync
9. Notifications
10. Preferences
11. Dashboard
12. Integration & Onboarding
13. CI/CD
