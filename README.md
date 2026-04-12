# Steady

> A compassionate companion for intentional digital work.

Steady is a macOS menu bar app that brings gentle awareness to your digital habits — no blocking, no shaming. Just a quiet check-in when you drift from what you set out to do.

## Why Steady?

Most focus tools rely on restriction. Steady takes the opposite approach: it helps you notice when you wander and invites you back with curiosity, not judgment. Your session data stays entirely on your Mac.

| Traditional Blockers | Steady |
|---|---|
| Blocks websites | Brings awareness |
| Shame / punishment | Compassion / curiosity |
| External control | Self-directed reflection |
| Data locked in app | Syncs to your Obsidian vault |

## Features

- **Menu bar presence** — lives quietly in the background, accessible via `Cmd+Shift+Space`
- **Intention setting** — define what you're doing and why it matters before each session
- **AI-powered activity classification** — LLM reads your active window/URL and detects off-task drift
- **Gentle check-ins** — a brief, non-blocking prompt when drift is detected
- **Focus timers & nudges** — set a countdown or ask the AI to check in at a specific time
- **Obsidian sync** — session summaries written as Markdown files into your vault
- **Todos** — lightweight task list integrated into the panel

## ActivityWatch Integration

Steady uses [ActivityWatch](https://activitywatch.net) — a free, open-source, privacy-first time tracker — to read your active browser URLs and app window titles. ActivityWatch runs entirely on your machine; no data is sent to any server. Steady polls its local REST API (`http://localhost:5600`) every 10 seconds.

### Setup

1. **Download and install ActivityWatch** from [activitywatch.net](https://activitywatch.net)
2. **Install the browser extension** for [Chrome](https://chrome.google.com/webstore/detail/activitywatch-web-watcher/nglaklhklhcoonedhgnpgddginnjdadi) or [Firefox](https://addons.mozilla.org/en-US/firefox/addon/aw-watcher-web/) — this is what gives Steady visibility into browser URLs
3. **Launch ActivityWatch** — it runs as a menu bar app and starts its local server automatically
4. **Open Steady** — it will connect to ActivityWatch automatically within ~10 seconds. You'll see "ActivityWatch connected" in the panel when it's working.

No configuration is needed inside Steady itself. If ActivityWatch is not running, Steady will show a prompt with setup instructions.

> **Credit:** Activity tracking in Steady is powered by [ActivityWatch](https://activitywatch.net) ([GitHub](https://github.com/ActivityWatch/activitywatch)), created by Erik Bjäreholt and contributors. ActivityWatch is MIT licensed.

## Installation

**Requirements:** macOS 14.0+, Xcode 15.0+

```bash
git clone https://github.com/niteshp/steady-macos.git
cd steady-macos
open Steady.xcodeproj
```

Build and run the `Steady` scheme. On first launch, grant Accessibility permission when prompted — needed to read window titles, nothing leaves your device.

## Configuration

Open the inline settings panel (gear icon) to configure:

- **LLM Provider** — OpenRouter (default), OpenAI, Anthropic, or any OpenAI-compatible endpoint
- **Models** — separate models for classification and conversation
- **API Key** — stored securely in macOS Keychain
- **Obsidian Vault** — optional path for session sync

## Project Structure

```
Steady/
├── App/              # Entry point, AppState, AppDelegate
├── Core/
│   ├── Models/       # Data types (Intention, Session, URLClassification, …)
│   ├── Services/     # URLTracker, LLMProvider, ConversationEngine, …
│   └── Store/        # LocalStore (JSON persistence), ObsidianSync
├── UI/               # SwiftUI views, MenuBarController
└── Utils/            # KeychainHelper, AXHelpers, MarkdownFormatter
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for a full component diagram and data-flow walkthrough.

## Contributing

1. Fork and create a feature branch
2. Follow the existing Swift concurrency patterns (`actor` for services, `@MainActor` for state)
3. Run tests: `xcodebuild test -project Steady.xcodeproj -scheme Steady -destination 'platform=macOS'`
4. Open a pull request

Core principle: **no blocking, no shaming.** Features that restrict or punish won't be accepted.

## License

MIT — see [LICENSE](LICENSE) for details.
