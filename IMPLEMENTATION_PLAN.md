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
│   │   ├── PreferencesView.swift          ✅ NEW
│   │   └── Components/
│   ├── Core/
│   │   ├── Models/
│   │   │   ├── Intention.swift
│   │   │   ├── Session.swift
│   │   │   ├── ConversationTurn.swift
│   │   │   ├── URLClassification.swift
│   │   │   └── LLMConfig.swift
│   │   ├── Services/
│   │   │   ├── URLTracker.swift
│   │   │   ├── LLMProvider.swift
│   │   │   ├── ConversationEngine.swift
│   │   │   ├── NotificationManager.swift
│   │   │   └── SessionManager.swift
│   │   └── Store/
│   │       ├── LocalStore.swift           ✅ NEW
│   │       └── ObsidianSync.swift
│   ├── Resources/
│   │   ├── Assets.xcassets/
│   │   ├── Info.plist
│   │   └── Steady.entitlements
│   └── Utils/
│       ├── KeychainHelper.swift
│       └── AXHelpers.swift
├── SteadyTests/
└── README.md
```

## Core Models

### Intention.swift ✅
```swift
struct Intention: Codable, Identifiable, Equatable {
    let id: UUID
    let task: String
    let whyItMatters: String
    let plannedDuration: Int
    let scheduledDate: Date
    let strictness: StrictnessLevel
    let temptationBundle: String?
    var status: IntentionStatus          // var for status updates
}
enum StrictnessLevel: String, Codable, CaseIterable { case quiet, gentle, focused, accountable }
enum IntentionStatus: String, Codable   { case planned, active, completed, skipped }
```

### Session.swift ✅
```swift
struct Session: Codable, Identifiable, Equatable {
    let id: UUID; let intentionId: UUID; let startTime: Date
    var endTime: Date?; var interruptions: [DistractionLog]
    let preSessionEnergy: Int; var postSessionReflection: String?
    var urlClassifications: [URLClassification]
}
struct DistractionLog: Codable, Equatable { ... }
```

### ConversationTurn.swift ✅ (fixed)
- Added `id: UUID` for stable `Identifiable` conformance (was generating new UUID each render — broken scroll/diffing)

### URLClassification.swift ✅
### LLMConfig.swift ✅ — defaults to OpenRouter, `google/gemini-flash-2.0` + `anthropic/claude-haiku-4-5`

---

## Key Technical Requirements

| # | Requirement | Status | Notes |
|---|-------------|--------|-------|
| 1 | LSUIElement — menu bar only | ✅ | Set in build settings |
| 2 | Accessibility API — read browser URL | ✅ | AXHelpers + AppleScript fallback |
| 3 | LLM Integration — OpenRouter | ✅ | LLMProvider; API key via Keychain |
| 4 | Structured JSON classification | ✅ | LLMProvider.parseClassificationResponse |
| 5 | Local persistence | ✅ | LocalStore.swift (JSON, App Support) |
| 6 | Obsidian Sync | ✅ | ObsidianSync.swift; vault path via Preferences |
| 7 | Global Hotkeys ⌘⇧Space / ⌘⇧D / ⌘⇧I | ✅ | HotkeyManager (Carbon) |
| 8 | Notifications — quiet by default | ✅ | NotificationManager (UNUserNotificationCenter) |

---

## Gap Analysis & Fixes Applied (2025-04)

### Critical — Previously Broken

#### 1. No persistence layer ✅ FIXED
- **Problem**: All sessions/intentions held in memory only; lost on restart. `setupAppState()` was an empty stub.
- **Fix**: Created `LocalStore.swift` — `@MainActor` JSON persistence in `~/Library/Application Support/Steady/`. `AppState.startSession()` saves intentions; `endSession()` saves completed sessions.

#### 2. Services never initialized ✅ FIXED
- **Problem**: `AppDelegate` created `MenuBarController` but never wired `LLMProvider`, `SessionManager`, `ConversationEngine`, `HotkeyManager`, or `NotificationManager`.
- **Fix**: `AppDelegate.setupServices()` creates all services, calls `appState.configure(sessionManager:conversationEngine:)`, requests notification auth, and wires HotkeyManager callbacks.

#### 3. AppState not connected to services ✅ FIXED
- **Problem**: `AppState.sendUserMessage()` only logged locally — no LLM call. `startSession()` had no timer/URL-tracking side effects.
- **Fix**: `AppState.configure(sessionManager:conversationEngine:)` sets up Combine subscriptions to sync timer state. `startSession()` delegates to `SessionManager` + calls `ConversationEngine.startConversation()`. `sendUserMessage()` calls `ConversationEngine.continueConversation()` and appends the AI response.

#### 4. ConversationPanel had no session start UI ✅ FIXED
- **Problem**: Panel showed "No active session" with no way to start one. No IntentionCard visible.
- **Fix**: `ConversationPanel` now switches between an **idle view** (inline `NewIntentionForm` with task/duration/strictness fields + Start button) and an **active view** (SessionTimer + conversation + input area).

#### 5. ConversationTurn.id was unstable ✅ FIXED
- **Problem**: `extension ConversationTurn: Identifiable { var id: UUID { UUID() } }` created a new UUID on every render — scroll anchoring and list diffing were broken.
- **Fix**: Added `let id: UUID` to the struct itself with a memberwise `init(id: UUID = UUID(), ...)`.

#### 6. NotificationManager.getIntention() always returned nil ✅ FIXED
- **Problem**: `sendSessionComplete(session:)` and `scheduleSessionNudge(session:)` called an internal `getIntention()` stub that always returned `nil`, so these notifications never fired.
- **Fix**: Changed signatures to `sendSessionComplete(session:intention:)` and `scheduleSessionNudge(session:intention:)`. SessionManager passes `currentIntention` at callsite.

#### 7. URLTracker delegate never set ✅ FIXED
- **Problem**: `URLTracker.delegate` was `nil` — off-task events never reached `SessionManager`.
- **Fix**: Added `URLTracker.setDelegate(_:)`. `SessionManager` conforms to `URLTrackerDelegate` (nonisolated methods dispatch back to `@MainActor`) and sets itself as delegate before tracking starts.

#### 8. URLTracker timer unreliable ✅ FIXED
- **Problem**: `Timer.scheduledTimer` inside an actor ran on the actor's executor with no RunLoop — timer never fired.
- **Fix**: Timer is now scheduled on `@MainActor` (main RunLoop) and stored back into the actor.

#### 9. PreferencesView missing ✅ FIXED
- **Problem**: No UI to configure API key, provider URL, model names, or Obsidian vault path.
- **Fix**: Created `PreferencesView.swift` with three tabs: API (key + models), Notifications, Obsidian. Settings scene wired in `SteadyApp.swift`.

---

### Remaining Known Issues

| Issue | Severity | Notes |
|-------|----------|-------|
| `SessionManager.activeSession` and `AppState.activeSession` can drift if SessionManager-only operations happen | Medium | Both bound via Combine now; edge cases on pause/resume |
| HotkeyManager uses deprecated Carbon APIs | Low | Works on current macOS; replace with `NSEvent` monitor if Carbon breaks |
| `kAXTrustedCheckOptionPrompt.takeRetainedValue()` in HotkeyManager | Low | Should be `takeUnretainedValue()` (avoids over-release on constant) |
| Obsidian vault path defaults to hardcoded subdirectory | Low | User must set vault path in Preferences |
| LLM provider config changes require restart | Low | Documented in PreferencesView |
| No DashboardView for session history | Low | Recent sessions shown as "Repeat" list in idle view for now |

---

## Implementation Order (completed)

1. ✅ Project structure & Xcode setup
2. ✅ Core Data Models with stable IDs
3. ✅ Menu bar UI & NSPanel
4. ✅ LLM Provider & URL Classification
5. ✅ URL Tracker (Accessibility API + delegate wiring)
6. ✅ Conversation Engine
7. ✅ Session Management (wired to AppState)
8. ✅ Obsidian Sync
9. ✅ Notifications (fixed intent lookup)
10. ✅ Preferences UI
11. ✅ Local Persistence (LocalStore)
12. ⬜ Dashboard / History view
13. ⬜ CI/CD
