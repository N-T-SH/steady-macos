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
- **AI-powered activity classification** — LLM reads your active window/URL locally and detects off-task drift
- **Gentle check-ins** — a brief, non-blocking prompt when drift is detected
- **Focus timers & nudges** — set a countdown or ask the AI to check in at a specific time
- **Obsidian sync** — session summaries written as Markdown files into your vault
- **Todos** — lightweight task list integrated into the panel
- **Privacy-first** — all data stored locally; API key in macOS Keychain

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
- **API Key** — stored securely in macOS Keychain, never in files
- **Obsidian Vault** — optional path for session sync

Recommended defaults:
- Classification: `google/gemini-flash-2.0` via OpenRouter (fast, cheap)
- Conversation: `anthropic/claude-haiku-4-5` via OpenRouter

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
