# Steady

> *A compassionate companion for intentional digital work.*

Steady is a macOS menu bar app that helps you stay aligned with your intentions while working on your computer. Unlike traditional "website blockers" that use shame and restriction, Steady acts as a thoughtful companion—bringing awareness to digital habits through gentle check-ins and AI-powered insights, not control.

## Philosophy

Steady is built on a fundamental belief: **self-compassion beats shame every time.**

Research consistently shows that harsh self-criticism undermines the very focus and productivity people seek. When we shame ourselves for getting distracted, we trigger stress responses that make it *harder* to return to focus. The "reward" for harsh blockers is often just a more anxious mind.

**Steady takes a different approach:**

- **Companion, not controller:** Steady doesn't block or restrict. It brings awareness and offers a moment for reflection.
- **Curiosity over judgment:** "I noticed you switched away from your intention. What's drawing your attention?"
- **Pattern recognition:** Over time, Steady helps you understand your unique distraction patterns—not to shame you, but to help you design better work environments.
- **Integration over isolation:** Your session data syncs to Obsidian, becoming part of your knowledge management system.

## Features

### Core Capabilities

- **Intention Setting:** Set clear intentions for your work sessions, including what you're doing and why it matters
- **Menu Bar Presence:** Lives quietly in your menu bar—always accessible, never intrusive
- **Global Hotkey:** Quick access via `Cmd+Shift+Space` (customizable)
- **LLM-Powered URL Classification:** AI analyzes the websites you visit during sessions to detect off-task behavior (with privacy-preserving local processing options)
- **Gentle Interruption Check-ins:** When potential distractions are detected, Steady shows a brief, compassionate prompt—not a blocker
- **Obsidian Integration:** Automatically syncs session summaries to your Obsidian vault for pattern analysis
- **Flexible Strictness Levels:** Choose your support style—from "quiet" (minimal prompts) to "accountable" (more frequent check-ins)

### Key Differentiators

| Traditional Blockers | Steady |
|---------------------|--------|
| Blocks websites | Brings awareness |
| Uses shame/punishment | Uses compassion/curiosity |
| External control | Self-directed reflection |
| Data locked in app | Syncs to your Obsidian vault |
| One-size-fits-all | Learns your patterns |
| Bypass = failure | Drift = data for understanding |

## Installation

### Download Pre-built Binary

1. Visit the [Releases](https://github.com/niteshp/steady-macos/releases) page
2. Download the latest `Steady.dmg`
3. Open the DMG and drag Steady to your Applications folder
4. Launch Steady from Applications

### Build from Source

Requirements:
- macOS 14.0+
- Xcode 15.0+
- Swift 5.9+

```bash
git clone https://github.com/niteshp/steady-macos.git
cd steady-macos
xcodebuild -project Steady.xcodeproj -scheme Steady -configuration Release
```

## Setup Guide

### First Launch

On first launch, Steady will guide you through setup:

1. **Accessibility Permissions:** Grant Steady access to read window titles (needed for URL tracking). This stays on your device—never sent to any server.
2. **LLM Provider:** Configure your preferred LLM provider (default: OpenRouter with open-source models)
3. **Obsidian Vault:** Select your Obsidian vault for session sync
4. **Hotkey Preference:** Customize your global hotkey (default: `Cmd+Shift+Space`)

### LLM Provider Configuration

Steady uses LLMs for URL classification and conversation generation. You can configure:

- **Provider:** OpenRouter (default), OpenAI, Anthropic, or any OpenAI-compatible API
- **Models:** Choose your preferred classification and conversation models
- **API Key:** Securely stored in macOS Keychain

**Default Setup (Recommended for Privacy):**
- Provider: OpenRouter
- Classification Model: `google/gemini-flash-1.5` (fast, capable, inexpensive)
- Conversation Model: `anthropic/claude-3.5-haiku` (quick, conversational)

### Obsidian Integration

Steady creates structured Markdown files in your Obsidian vault:

```
vault/
└── Steady/
    ├── 2025/
    │   └── 03/
    │       ├── 2025-03-31-afternoon-session.md
    │       └── 2025-03-31-morning-session.md
    └── weekly-summaries/
        └── 2025-W13.md
```

Each session file includes:
- Intention and context
- URL visit analysis
- Distraction patterns
- Energy levels (pre/post)
- Reflection prompts

### Strictness Levels

Choose your support style:

| Level | Behavior |
|-------|----------|
| **Quiet** | Minimal UI, logs only, rare prompts |
| **Gentle** | Occasional check-ins, soft tone |
| **Focused** | Proactive prompts, accountability questions |
| **Accountable** | Frequent check-ins, detailed logging |

## Usage Guide

### Starting a Session

1. Click the Steady menu bar icon (or use your hotkey)
2. Enter your intention: "What am I doing?"
3. Add context: "Why does this matter?"
4. Set planned duration (optional)
5. Click "Start Session"

### During a Session

Steady runs quietly in the background:
- Tracks active window titles (locally)
- Classifies URLs using your configured LLM
- Detects potential off-task behavior
- Shows gentle check-in prompts when drift is detected

### Responding to Check-ins

When Steady detects a potential distraction, you'll see a brief panel:

> *"I noticed you've been on Twitter for 3 minutes. You mentioned wanting to finish your report. What's drawing your attention right now?"*

Your options:
- **Acknowledge:** "Thanks, I'll get back to it" (resets the drift timer)
- **Explain:** Brief note about why you're here (logged for pattern analysis)
- **Adjust Intention:** Update your current task if plans changed
- **End Session:** Close the session with a brief reflection

### Ending a Session

1. Click menu bar icon or use hotkey
2. Select "End Session"
3. Quick reflection: How did it go? Energy level?
4. Session summary syncs to Obsidian

### Viewing Dashboard

Access your dashboard via the menu bar:
- Today's sessions
- This week's patterns
- Common distraction sites
- Focus quality trends
- Intention completion rate

## Development Setup

### Prerequisites

- macOS 14.0+
- Xcode 15.0+
- SwiftLint (optional, for linting)

### Project Structure

```
Steady/
├── Steady.xcodeproj/
├── Steady/
│   ├── Core/
│   │   ├── Models/          # Data models
│   │   └── Services/        # Business logic
│   ├── UI/                  # SwiftUI views
│   ├── App/                 # App entry point
│   ├── Resources/           # Assets, entitlements
│   └── Utils/               # Helpers
└── SteadyTests/             # Unit tests
```

### Building

```bash
# Open in Xcode
open Steady.xcodeproj

# Or build via command line
xcodebuild -project Steady.xcodeproj -scheme Steady
```

### Running Tests

```bash
xcodebuild test -project Steady.xcodeproj -scheme Steady -destination 'platform=macOS'
```

### Linting

```bash
swiftlint lint
```

## Architecture Overview

### Core Components

**URL Tracker:** Uses macOS Accessibility API to read window titles from browsers. Maps titles to domains, respects user privacy.

**LLM Provider:** OpenAI-compatible API client. Supports streaming responses, structured JSON output for classification, conversation generation.

**Conversation Engine:** Manages check-in dialogues. Context-aware (knows current intention, session history, drift patterns).

**Session Manager:** State machine for session lifecycle. Handles interruptions, resumption, data collection.

**Notification Manager:** macOS UNUserNotificationCenter integration. Quiet by default, respects Do Not Disturb.

**Obsidian Sync:** File-based sync to Markdown. Creates structured directories, handles duplicates, weekly summaries.

### Data Flow

```
User sets intention
       ↓
Session starts → URL Tracker monitors
       ↓
LLM classifies URLs → Pattern detection
       ↓
Drift detected → Conversation Engine prompts
       ↓
User responds → Session updates
       ↓
Session ends → Obsidian Sync creates Markdown
```

### Privacy Architecture

**Privacy-First Design:**
- All URL tracking happens locally on your Mac
- LLM calls are stateless (no conversation history stored server-side)
- API keys stored in macOS Keychain, never in code or logs
- Obsidian files stay in your vault—you control them
- No analytics, no tracking, no cloud service dependency

## Contributing

We welcome contributions! Steady is built with:
- Swift 5.9+
- SwiftUI for UI
- Combine for reactive patterns
- Core Data for local persistence

### Getting Started

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Make your changes
4. Run tests: `xcodebuild test -project Steady.xcodeproj -scheme Steady`
5. Commit with conventional commits: `git commit -m "feat: add amazing feature"`
6. Push to your fork: `git push origin feature/amazing-feature`
7. Open a Pull Request

### Development Guidelines

- **No blocking philosophy:** Any feature that blocks, restricts, or shames users will not be accepted
- **Privacy by default:** All data stays local unless explicitly synced by user
- **Compassionate UX:** Check-ins should be gentle, curious, never judgmental
- **Test coverage:** New features include unit tests
- **Accessibility:** Support for VoiceOver, reduced motion, high contrast

### Code Style

We use SwiftLint with custom rules (see `.swiftlint.yml`). Key points:
- 4 spaces indentation
- Max 120 characters per line
- Explicit self where required
- No force unwrapping

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

Steady draws inspiration from:
- [Centered](https://centered.app/) - for showing that gentle check-ins can work
- Obsidian - for the philosophy of local-first, user-controlled data
- Research on self-compassion by Kristin Neff and others
- The humane tech movement

## Support

- 🐛 [Report bugs](https://github.com/niteshp/steady-macos/issues)
- 💡 [Request features](https://github.com/niteshp/steady-macos/discussions)
- 💬 [Join discussions](https://github.com/niteshp/steady-macos/discussions)

---

**Remember:** Steady is a companion, not a controller. Be kind to yourself.
