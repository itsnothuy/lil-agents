# filename: 00-executive-summary.md

# Executive Summary — lil-agents Technical Dossier

## What This Project Actually Is

**lil-agents** is a macOS menu-bar (accessory) application that renders two animated characters — **Bruce** and **Jazz** — walking back and forth above the system Dock. Clicking a character opens a themed popover terminal that proxies user input to one of six supported AI CLI tools (Claude Code, OpenAI Codex, GitHub Copilot, Google Gemini CLI, OpenCode, OpenClaw) via `Process`/`Pipe` subprocess management. It is, at its core, **a charming UI shell around external CLI binaries**.

## Core Architectural Pattern

| Layer | Pattern |
|---|---|
| App lifecycle | SwiftUI `@main` + `NSApplicationDelegateAdaptor` → pure AppKit |
| Animation loop | `CVDisplayLink` tick at display refresh rate |
| Dock positioning | Reads `com.apple.dock` UserDefaults for tile geometry |
| AI integration | `AgentSession` protocol → one concrete class per CLI provider → `Process` + `Pipe` + NDJSON/plain-text streaming |
| State | Mutable properties on `WalkerCharacter` objects; no formal state machine |
| Persistence | `UserDefaults` only (per-character provider, size, theme, onboarding flag) |
| Updates | Sparkle framework via `appcast.xml` |

## Is It a Good Base for a Personalized AI Companion App?

**Yes, conditionally.** The repo provides a working, delightful macOS companion UX that would take weeks to build from scratch — transparent HEVC video rendering, Dock geometry calculation, thinking bubbles, themed popover terminals, multi-provider switching. That is genuinely valuable.

However, it is **demo-shaped, not system-shaped**. The session abstraction is thin, state management is ad hoc, there is no persistence beyond UserDefaults, no logging, no error recovery, no testable architecture, and the provider sessions are brittle one-off implementations of undocumented CLI protocols. Building on it seriously requires refactoring the session layer, adding a proper state machine, and isolating provider-specific parsing.

## Biggest Strengths

1. **Working, polished Dock companion UX** — the hardest part (transparent video overlay, Dock geometry, popover positioning, click-through hit-testing) is done and works on both Apple Silicon and Intel.
2. **Six-provider architecture** — Claude, Codex, Copilot, Gemini, OpenCode, and OpenClaw are all wired with binary discovery, streaming output parsing, and tool-use display.
3. **Theme system** — four complete visual themes with character-color tinting, custom font support, and runtime switching with live popover rebuild.
4. **Per-character provider switching** — each character persists its own provider and size via name-prefixed UserDefaults keys.
5. **Clean `AgentSession` protocol** — the callback-based protocol (`onText`, `onToolUse`, `onTurnComplete`, etc.) is a solid foundation for a richer session abstraction.

## Biggest Weaknesses

1. **No formal state machine** — character state (walking/paused/idle/onboarding) is tracked via scattered booleans and timestamps with no transitions enforced.
2. **Fragile CLI integration** — every provider session parses undocumented, version-dependent NDJSON/text formats with no versioning, no schema validation, and no fallback contract.
3. **Zero observability** — no logging, no crash reporting, no diagnostics. If a CLI binary fails silently, the user sees nothing.
4. **No session persistence** — conversation history lives only in memory. Kill the app, lose everything.
5. **Hardcoded two-character model** — Bruce and Jazz are instantiated by name in `start()` with per-character animation constants hardcoded inline.
6. **Sandbox disabled** — `com.apple.security.app-sandbox` is `false`, meaning the app runs with full user permissions.
7. **No tests for anything except `DockVisibility`** — the test suite is a single file with 6 assertions.

## Blunt Verdict

lil-agents is an **excellent prototype and a charming product** but an **immature engineering base**. It has real UX polish and a working multi-provider architecture that would be painful to recreate. But it has the internal structure of a hackathon project: mutable god-objects, no separation of concerns between UI and session logic, no persistence, no error handling, no tests, and provider integrations that will break whenever the upstream CLIs change their output format.

**If you want to use it as a base**, the right strategy is: keep the Dock overlay engine, the theme system, and the `AgentSession` protocol shape; rewrite the session implementations behind a proper adapter layer with schema validation; add a state machine to `WalkerCharacter`; extract character configuration into data; and add persistence. That is 2–3 weeks of focused refactoring to get to a solid V2 foundation. The alternative — starting from scratch — would take longer because the Dock geometry, transparent video, and hit-testing code is genuinely non-trivial.
