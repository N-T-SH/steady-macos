# Steady — Architecture

## Diagram

```mermaid
flowchart TB
    classDef system    fill:#1e1e2e,stroke:#6c7086,color:#cdd6f4
    classDef actor     fill:#1e3a5f,stroke:#89b4fa,color:#cdd6f4
    classDef mainactor fill:#1e3a2f,stroke:#a6e3a1,color:#cdd6f4
    classDef ui        fill:#3a1e3a,stroke:#cba6f7,color:#cdd6f4
    classDef external  fill:#3a2a1e,stroke:#fab387,color:#cdd6f4

    %% ── External ──────────────────────────────────────────────────
    EXT["☁️ LLM API\nFireworks · OpenRouter\nOpenAI-compatible"]:::external

    %% ── macOS System ──────────────────────────────────────────────
    subgraph SYS["macOS System"]
        direction LR
        AW["ActivityWatch\nREST API :5600"]:::system
        KC["Keychain\nAPI key storage"]:::system
        NS["UNUserNotification\nmacOS notifications"]:::system
        MB["NSStatusItem\nmenu bar icon"]:::system
    end

    %% ── Service Actors ────────────────────────────────────────────
    subgraph ACT["Service Actors  (Swift actor — concurrent, awaited)"]
        direction TB
        UT["URLTracker\n─────────────────\n• polls AW web + window buckets\n• browser URL wins over app name\n• dedup by url / app+title\n• saved-rule fast path\n• grace period drift detection"]:::actor

        LP["LLMProvider\n─────────────────\n• classifyActivity(url/app, title)\n• generateConversationResponse()\n• extractIntent()\n• all known projects in prompt\n• TIMER / NUDGE tag emission"]:::actor

        CE["ConversationEngine\n─────────────────\n• multi-turn message history\n• system prompt with live activity\n• intent extraction from chat"]:::actor

        NM["NotificationManager\n─────────────────\n• session start / nudge\n• drift alert\n• session complete"]:::actor
    end

    %% ── State Layer ───────────────────────────────────────────────
    subgraph STATE["State Layer  (@MainActor — always on main thread)"]
        direction TB
        SM["SessionManager\n─────────────────\n@Published: sessionState · elapsedTime\nallActivityToday · urlClassifications\nactivityWatchConnected\n─────────────────\nstartContinuousTracking()\nreclassify(at:project:category:)"]:::mainactor

        AS["AppState\n─────────────────\n@Published: currentIntention\nactiveSession · conversations\nactiveTimers · isMenuBarIconActive\n─────────────────\nsendUserMessage()\nprocessTimerTag() → FocusTimer\ntickTimers() → expiry + flash"]:::mainactor

        LS["LocalStore\n─────────────────\nintentions.json\nsessions.json\nurl_rules.json\n─────────────────\nrenameProject() · deleteProject()\nallProjectNames"]:::mainactor
    end

    %% ── UI Layer ──────────────────────────────────────────────────
    subgraph UI["UI Layer  (SwiftUI + AppKit)"]
        direction TB
        MBC["MenuBarController\n─────────────────\nNSPanel (400×600 floating)\npositions below status icon\nflashOrange() on timer expiry\nglobal hotkey ⌘⇧Space"]:::ui

        CP["ConversationPanel\n─────────────────\nheader — live activity subtitle\nsessionControls — elapsed · pause · end\nmessagesList — chat bubbles\ntimerBar — TIMER countdown\n           NUDGE 'at 3:45 PM'\ninputArea — text field + send"]:::ui

        ALV["ActivityLogView\n─────────────────\nall events newest-first\nproject filter chips\nper-row tag → ProjectPickerPopover\ncreate · reassign project\n→ saves URLRule immediately"]:::ui

        ISV["InlineSettingsView\n─────────────────\nAPI key + provider URL\nclassification + conversation model\nProjects — rename · delete\nObsidian vault sync"]:::ui
    end

    %% ── Edges ─────────────────────────────────────────────────────
    AW      -->|"poll every 10 s"| UT
    UT      -->|"classifyActivity()"| LP
    LP      -->|"HTTP POST\nchat/completions"| EXT
    LP      -->|"load key"| KC
    UT      -->|"URLTrackerDelegate\ndidClassifyURL\ndidDetectOffTask\ndidDiscoverNewRule\ndidUpdateAWStatus"| SM
    SM      -->|"Combine @Published\nassign to AppState"| AS
    SM      -->|"sendDriftAlert\nscheduleNudge"| NM
    NM      -->|"schedule / deliver"| NS
    SM      -->|"saveURLRule"| LS
    AS      -->|"save session\nsave intention"| LS
    AS      -->|"sendUserMessage"| CE
    CE      -->|"generateConversationResponse()"| LP
    MB      -->|"click / hotkey"| MBC
    MBC     -->|"hosts SwiftUI view"| CP
    CP      -.->|"sheet"| ALV
    CP      -.->|"sheet"| ISV
    AS      -->|"focusTimerExpired\nNotification"| MBC
    AS      --->|"@ObservedObject"| CP
    LS      -->|"allProjectNames\nfor picker"| ALV
```

---

## How it works — for someone new to Mac development

### What kind of app is this?

Steady is a **menu bar app** — it lives as a small icon in the macOS menu bar rather than in the Dock. There is no traditional app window; instead a floating panel (`NSPanel`) drops down when you click the icon. This pattern is common for lightweight Mac utilities that run quietly in the background.

### The tracking pipeline

Every 10 seconds, `URLTracker` calls ActivityWatch's local REST API (`http://localhost:5600`). ActivityWatch is a separate open-source background process that captures which browser tab is open and which app is frontmost — Steady simply reads that data.

If the frontmost app is a browser, Steady uses the web watcher event (which has the actual URL). If it's a native app like Xcode or Figma, it synthesizes an `app://Xcode` identifier instead. Either way it ends up with a `(url, title)` pair.

That pair is classified by the LLM — unless a saved URL rule already covers it, in which case classification is skipped entirely (fast path). The result flows through a **delegate** back to `SessionManager`, which appends it to `allActivityToday`.

### Swift concurrency — actors vs `@MainActor`

Two isolation patterns appear throughout the codebase:

**`actor`** (`URLTracker`, `LLMProvider`, `ConversationEngine`) — Swift guarantees only one piece of code runs inside an actor at a time, preventing data races when multiple network responses arrive concurrently. You `await` to call into them from any thread.

**`@MainActor`** (`AppState`, `SessionManager`, `LocalStore`) — these classes are pinned to the main thread. This is required because SwiftUI reads `@Published` properties on the main thread. When an actor finishes work, it hops back to main with `Task { @MainActor in ... }` before updating state.

### The chat pipeline

When you type a message, `AppState.sendUserMessage` bundles the current intention, recent activity classifications, and conversation history into a `ConversationContext`, then calls `ConversationEngine`. The engine maintains the full message history and sends it to `LLMProvider`, which makes an HTTP POST to the configured endpoint using the OpenAI chat completions format — so it works with Fireworks, OpenRouter, or any compatible provider.

Before the response is displayed, `processTimerTag` scans it for embedded tags:

- `[TIMER:25m:label]` — user-requested; shows a live MM:SS countdown in orange
- `[NUDGE:20m:label]` — LLM-initiated; shows a calm "checking in at 3:45 PM" hint with no countdown

When a timer expires, a `Notification` is posted and `MenuBarController` responds by flashing the status item orange six times.

### Sessions vs. passive tracking

The two concepts are intentionally separate. **Passive tracking** runs constantly from app launch — `URLTracker` polls ActivityWatch and classifies activity regardless of whether a session is active. **Sessions** are an optional annotation layer: starting one adds an `Intention` context to the tracker (so the LLM can judge on-task vs. off-task) and starts an elapsed-time counter. Ending a session strips that context but leaves the tracker running.

### Persistence

Everything is stored locally — no cloud. `LocalStore` writes three JSON files to `~/Library/Application Support/Steady/`. The API key lives separately in the **macOS Keychain** (encrypted secure storage). The optional Obsidian sync writes markdown files directly into your vault folder via `ObsidianSync`.
