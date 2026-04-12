# Getting Started with lil agents

lil agents puts two tiny animated characters — **Bruce** and **Jazz** — on top of your macOS Dock. Click either one to open an AI chat terminal. That's it.

---

## What it currently does

| Feature | Status |
|---|---|
| Two animated characters above the Dock | ✅ |
| Click to open a chat popover | ✅ |
| Chat with Claude Code, Codex, Copilot, Gemini, OpenCode, or OpenClaw | ✅ |
| Switch AI provider from the menu bar | ✅ |
| Four visual themes | ✅ |
| Two character sizes (Small / Large) | ✅ |
| Multi-display support | ✅ |
| Sound effects on AI response completion | ✅ |
| Thinking bubbles while AI is working | ✅ |
| Slash commands in chat (`/clear`, `/copy`, `/help`) | ✅ |
| Copy last response button in the title bar | ✅ |
| Auto-updates via Sparkle | ✅ |
| Show/hide individual characters | ✅ |
| Multi-turn conversation (Claude, Copilot, Gemini) | ✅ |
| Multi-turn conversation (OpenCode) | ❌ (single-turn only) |

---

## System requirements

- **macOS Sonoma 14.0+** (including Sequoia 15.x)
- Apple Silicon or Intel — Universal binary
- **At least one** AI CLI installed (see [providers.md](providers.md))

---

## Installation

### Option A — Download the app (easiest)

1. Download the latest `.dmg` from [lilagents.xyz](https://lilagents.xyz)
2. Drag **lil agents** to `/Applications`
3. Open it — the characters will appear above your Dock

### Option B — Build from source

1. Clone the repo
2. Open `lil-agents.xcodeproj` in Xcode
3. Hit **Run** (⌘R)

> **Gatekeeper note:** Because the app is not notarized on this fork, macOS may block the first launch. Right-click the app → **Open** → **Open** to bypass the warning once.

---

## First launch

On first run you'll see a short onboarding dialog welcoming you and explaining the basics. After that, Bruce and Jazz start walking on the Dock immediately.

If no AI provider is found, the characters still appear and walk — they just can't answer questions until you install a provider CLI (see [providers.md](providers.md)).

---

## Basic usage

1. **Click Bruce or Jazz** — a chat popover opens
2. **Type your question** and press **Return**
3. Watch the thinking bubble while the AI works
4. Read the response in the popover terminal
5. Press **Return** again to ask a follow-up (most providers support multi-turn)
6. Click anywhere outside to close the popover — **the session keeps running in the background**

---

## Menu bar icon

The lil agents menu bar icon gives you access to all settings.

| Menu item | What it does |
|---|---|
| Bruce / Jazz | Toggle that character on or off (keyboard: `1` / `2`) |
| Sounds | Toggle completion sound effects |
| Provider → | Switch the active AI provider for both characters |
| Provider → Advanced Settings… | Configure OpenClaw gateway credentials |
| Size → | Switch between Small and Large characters |
| Style → | Switch between the four visual themes |
| Display → | Pin characters to a specific monitor |
| Check for Updates | Manually trigger a Sparkle update check |
| Quit | Quit the app |

---

## Next steps

- [providers.md](providers.md) — which AI providers are free, which cost money, and how to install each one
- [chat-interface.md](chat-interface.md) — slash commands, keyboard shortcuts, copy button, theme details
- [openclaw.md](openclaw.md) — how to set up the self-hosted OpenClaw gateway (advanced / optional)
