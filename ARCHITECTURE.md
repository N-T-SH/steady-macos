# Architecture

```mermaid
flowchart TB
    classDef system    fill:#1e1e2e,stroke:#6c7086,color:#cdd6f4
    classDef actor     fill:#1e3a5f,stroke:#89b4fa,color:#cdd6f4
    classDef mainactor fill:#1e3a2f,stroke:#a6e3a1,color:#cdd6f4
    classDef ui        fill:#3a1e3a,stroke:#cba6f7,color:#cdd6f4
    classDef external  fill:#3a2a1e,stroke:#fab387,color:#cdd6f4

    EXT["☁️ LLM API\nFireworks · OpenRouter\nOpenAI-compatible"]:::external

    subgraph SYS["macOS System"]
        direction LR
        AW["ActivityWatch\nREST API :5600"]:::system
        KC["Keychain\nAPI key storage"]:::system
        NS["UNUserNotification\nmacOS notifications"]:::system
        MB["NSStatusItem\nmenu bar icon"]:::system
    end

    subgraph ACT["Service Actors  (Swift actor — concurrent, awaited)"]
        direction TB
        UT["URLTracker\n─────────────────\n• polls AW every 10 s\n• browser URL wins over app name\n• saved-rule fast path\n• grace period drift detection"]:::actor
        LP["LLMProvider\n─────────────────\n• classifyActivity(url/app, title)\n• generateConversationResponse()\n• extractIntent()\n• TIMER / NUDGE tag emission"]:::actor
        CE["ConversationEngine\n─────────────────\n• multi-turn message history\n• system prompt with live activity\n• intent extraction from chat"]:::actor
        NM["NotificationManager\n─────────────────\n• session start / nudge\n• drift alert\n• session complete"]:::actor
    end

    subgraph STATE["State Layer  (@MainActor — main thread)"]
        direction TB
        SM["SessionManager\n─────────────────\n@Published: sessionState · elapsedTime\nallActivityToday · urlClassifications\nactivityWatchConnected"]:::mainactor
        AS["AppState\n─────────────────\n@Published: currentIntention\nactiveSession · conversations\nactiveTimers · isMenuBarIconActive"]:::mainactor
        LS["LocalStore\n─────────────────\nintentions.json · sessions.json\nurl_rules.json"]:::mainactor
    end

    subgraph UI["UI Layer  (SwiftUI + AppKit)"]
        direction TB
        MBC["MenuBarController\n─────────────────\nNSPanel (400×600 floating)\npositions below status icon\nflashOrange() on timer expiry\nglobal hotkey ⌘⇧Space"]:::ui
        CP["ConversationPanel\n─────────────────\nheader — live activity subtitle\nsessionControls — elapsed · pause · end\nmessagesList — chat bubbles\ntimerBar — countdown / nudge hint\ninputArea — text field + send"]:::ui
        ALV["ActivityLogView\n─────────────────\nevents newest-first\nproject filter chips\nper-row tag → ProjectPickerPopover"]:::ui
        ISV["InlineSettingsView\n─────────────────\nAPI key + provider URL\nclassification + conversation model\nProjects — rename · delete\nObsidian vault sync"]:::ui
    end

    AW      -->|"poll every 10 s"| UT
    UT      -->|"classifyActivity()"| LP
    LP      -->|"HTTP POST\nchat/completions"| EXT
    LP      -->|"load key"| KC
    UT      -->|"URLTrackerDelegate"| SM
    SM      -->|"Combine @Published"| AS
    SM      -->|"sendDriftAlert\nscheduleNudge"| NM
    NM      -->|"schedule / deliver"| NS
    SM      -->|"saveURLRule"| LS
    AS      -->|"save session / intention"| LS
    AS      -->|"sendUserMessage"| CE
    CE      -->|"generateConversationResponse()"| LP
    MB      -->|"click / hotkey"| MBC
    MBC     -->|"hosts SwiftUI view"| CP
    CP      -.->|"sheet"| ALV
    CP      -.->|"sheet"| ISV
    AS      -->|"focusTimerExpired\nNotification"| MBC
    AS      --->|"@ObservedObject"| CP
    LS      -->|"allProjectNames"| ALV
```

---

## Key Concepts

### Concurrency model

- **`actor`** (`URLTracker`, `LLMProvider`, `ConversationEngine`) — isolated, awaitable; safe for concurrent network work
- **`@MainActor`** (`AppState`, `SessionManager`, `LocalStore`) — pinned to the main thread; required for `@Published` / SwiftUI reads

### Tracking pipeline

Every 10 seconds `URLTracker` polls ActivityWatch's local REST API (`http://localhost:5600`). If a browser is frontmost it uses the web-watcher URL; otherwise it synthesizes `app://AppName`. The `(url, title)` pair is classified by `LLMProvider` — unless a saved URL rule already covers it (fast path). Results flow via `URLTrackerDelegate` to `SessionManager`.

### Chat pipeline

`AppState.sendUserMessage` bundles the current intention, recent classifications, and conversation history into a `ConversationContext`. `ConversationEngine` maintains the full message history and sends it to `LLMProvider` as an OpenAI-compatible `chat/completions` request. Before display, the response is scanned for embedded tags:

- `[TIMER:25m:label]` — shows a live MM:SS countdown in the panel
- `[NUDGE:20m:label]` — shows a calm "checking in at 3:45 PM" hint

### Sessions vs. passive tracking

Passive tracking runs constantly from launch. A session is an optional annotation layer: it adds an `Intention` context (so the LLM can judge on/off-task) and starts an elapsed-time counter. Ending a session strips the context but leaves the tracker running.

### Persistence

All data is stored locally in `~/Library/Application Support/Steady/` as JSON. The API key lives in the macOS Keychain. Obsidian sync writes Markdown files directly into the configured vault folder.
