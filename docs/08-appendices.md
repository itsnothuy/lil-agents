# filename: 08-appendices.md

# Appendices

---

## Appendix A: Observed Inconsistencies and Red Flags

### Code Smells

- **`WalkerCharacter` is 1007 lines** — a model, view, controller, session manager, sound player, and animation engine in one class. This is the single largest technical debt item in the repo.
- **`AppDelegate` is 264 lines of menu-building code** — every menu action is an `@objc` method directly mutating character properties. No separation between UI construction and business logic.
- **`AgentProvider.current` is defined but effectively unused** — the getter/setter pair exists but only `openGatewaySettings()` reads it. Per-character provider selection superseded this global setting but it was never cleaned up.
- **`bruce-hang.imageset`** exists in the asset catalog but is not referenced anywhere in code. Likely a legacy asset.
- **`CharacterSize` is defined in `WalkerCharacter.swift`** but used in `AgentSession.swift` (via `AgentProvider`) and `LilAgentsApp.swift`. Should be in its own file or in the session file.
- **Wait — `CharacterSize` is NOT in `AgentSession.swift`** — it's only in `WalkerCharacter.swift` and used in `LilAgentsApp.swift`. But `AgentSession.swift` defines `TitleFormat` which is used by `PopoverTheme`. Cross-file type definitions scattered without logic.

### Inconsistencies

- **README lists 4 providers, code has 6** — OpenCode and OpenClaw are in the code but not in the README's requirements or feature list.
- **`soundsEnabled` is not persisted** — it resets to `true` on every launch. The menu bar shows a toggle but it's not durable.
- **`pinnedScreenIndex` is not persisted** — resets to `-1` (auto) on every launch.
- **Sound file format inconsistency** — 8 files are `.mp3`, 1 is `.m4a` (`ping-jj.m4a`).
- **`size` default is `"big"` in getter but enum case is `.large`** — `WalkerCharacter.size` getter defaults to `"big"` which doesn't match any `CharacterSize` raw value (`"large"`, `"medium"`, `"small"`). This means the `?? .large` fallback always triggers for fresh installs, which works but the dead `"big"` string is confusing.
  
  ```swift
  let raw = UserDefaults.standard.string(forKey: "\(name)Size") ?? "big"
  return CharacterSize(rawValue: raw) ?? .large
  ```

- **Sparkle feed URL points to `ryanstephen/lil-agents`** but the current repo is `itsnothuy/lil-agents`. If this is a fork, auto-updates will pull from the upstream repo.
- **`OpenClawConfig` is defined inside `AgentSession.swift`** but `OpenClawSession.swift` is 426 lines of self-contained OpenClaw logic including `DeviceIdentity`. The config struct is in the wrong file.
- **`withCharacterColor()` only works for Peach theme** — the method returns `self` unchanged for all other themes. This is by design (per code comments) but is surprising behavior.
- **`currentDirectoryURL` is always `homeDirectoryForCurrentUser`** for all providers. The app has no concept of project context.
- **`ClaudeSession` uses `--dangerously-skip-permissions`** — this flag name literally contains "dangerously" and the code uses it silently.
- **`GeminiSession` handles 13+ event type strings** — `content`, `text`, `delta`, `message`, `tool_call`, `function_call`, `tool_use`, `tool_result`, `function_result`, `done`, `end`, `complete`, `turn_end`, `result`, `error`. This suggests the developer was reverse-engineering the CLI's protocol by trial and error, not working from documentation.
- **`CopilotSession` has runtime format detection** — `useJsonOutput` flips to `false` if the first JSON parse fails. This is a hack that will produce confusing behavior if the first line of output happens to be a log message.
- **`CodexSession` fakes multi-turn** by stuffing the entire conversation history into each prompt string. This will break or degrade as history grows (prompt length limits).
- **No `@Sendable` annotations, no `actor` usage** — the codebase relies on `DispatchQueue.main.async` for all thread safety but `CVDisplayLink` fires from a background thread. The callback itself dispatches to main, but the `Unmanaged.passUnretained(self)` pattern is a potential retain issue.

### Security Concerns

- **App sandbox disabled** — the app runs with full user permissions
- **All CLI safety mechanisms bypassed** — `--dangerously-skip-permissions`, `--full-auto`, `--allow-all`, `--yolo`
- **Ed25519 private key stored in UserDefaults** — should be in Keychain
- **Auth token stored in UserDefaults** — should be in Keychain
- **Shell environment capture via `zsh -l -i`** — if `~/.zshrc` has side effects, they execute on every app launch

### Missing Fundamentals

- No logging
- No crash reporting
- No error categorization
- No retry logic
- No timeout/watchdog
- No session persistence
- No test coverage (except 6 assertions for DockVisibility)
- No CI/CD
- No linting
- No accessibility
- No localization

---

## Appendix B: Reconstructed Architecture Snapshot

### One Paragraph

lil-agents is a macOS accessory app that renders transparent HEVC video characters walking on the Dock via `CVDisplayLink`-driven frame updates and `NSWindow` positioning calculated from `com.apple.dock` UserDefaults. Clicking a character opens a themed popover terminal backed by an `AgentSession` protocol, where concrete implementations spawn CLI subprocesses (`claude`, `codex`, `copilot`, `gemini`, `opencode`) or connect via WebSocket (`OpenClaw`), parse their NDJSON or plain-text output line by line, and stream results into an `NSTextView` with basic Markdown rendering. All state lives in mutable properties on a `WalkerCharacter` god-object with no formal state machine, persistence is limited to `UserDefaults` for provider/size/theme selection, and conversation history exists only in memory.

### ASCII Diagram

```
┌──────────────────── macOS ─────────────────────────────────────┐
│                                                                 │
│  ┌─ Menu Bar ──────────────────────────────────────────────┐   │
│  │ [🤖] Provider | Size | Style | Display | Quit           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─ Dock Screen ───────────────────────────────────────────┐   │
│  │                                                          │   │
│  │        ╔══════════╗        ╔══════════╗                  │   │
│  │        ║ "hmm..." ║        ║  done!   ║   ← Bubbles     │   │
│  │        ╚════╤═════╝        ╚════╤═════╝                  │   │
│  │             │                    │                        │   │
│  │    ┌────────┴────────┐  ┌───────┴────────┐               │   │
│  │    │   🧑 Bruce      │  │   🧑 Jazz       │  ← HEVC     │   │
│  │    │  (AVPlayerLayer)│  │  (AVPlayerLayer) │    video     │   │
│  │    └────────┬────────┘  └────────┬────────┘               │   │
│  │ ────────────┼─── Dock top line ──┼─────────────────────  │   │
│  │    ┌────────┴──────────────────────────────┐              │   │
│  │    │           macOS Dock                   │              │   │
│  │    └───────────────────────────────────────┘              │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─ Popover (on click) ─────────────────┐                      │
│  │ ┌─ Title: CLAUDE ▾ ──── ↻ ⧉ ──────┐ │                      │
│  │ ├─────────────────────────────────── │                      │
│  │ │ > How does Swift concurrency work? │ │ ← TerminalView    │
│  │ │                                     │ │                    │
│  │ │ Swift concurrency uses structured   │ │ ← Streamed text   │
│  │ │ async/await patterns...             │ │                    │
│  │ ├─────────────────────────────────── │                      │
│  │ │ [Ask Claude...]                     │ │ ← Input field     │
│  │ └───────────────────────────────────┘ │                      │
│  └───────────────────────────────────────┘                      │
│                                                                 │
│  ┌─ Subprocess ─────────────────────────────────────────────┐  │
│  │ claude -p --output-format stream-json --input-format ... │  │
│  │     stdin ← JSON messages                                 │  │
│  │     stdout → NDJSON events → parseLine() → onText()       │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
         │                                    ▲
         │ CLI makes API calls                │ API responses
         ▼                                    │
   ┌──────────────────────────────────────────┘
   │  Anthropic / OpenAI / Google / GitHub APIs
   └──────────────────────────────────────────
```

### One Sentence

**lil-agents is a charming but architecturally immature macOS Dock overlay that wraps external AI CLI tools in themed popover terminals, with real UX polish and genuine technical novelty in its transparent video rendering and Dock geometry calculation, but significant engineering debt in its god-object character class, ad hoc state management, absent observability, and fragile CLI protocol parsing.**

---

## Appendix C: Questions to Answer Before Building on This

1. **Do you need the sandbox disabled?** If so, what specific capabilities require it, and can you use targeted entitlements instead?

2. **Are you comfortable with `--dangerously-skip-permissions` on Claude?** This means the AI can execute any shell command and modify any file without confirmation. What safety model do you want?

3. **What is your working directory strategy?** Currently all CLIs run in `~`. Will each character have a fixed project directory? Will it follow the frontmost IDE's project? Will the user configure it?

4. **How will you handle CLI version changes?** Claude Code, Codex, Copilot, and Gemini CLIs are all rapidly evolving. Their output formats are undocumented and can change without notice. What is your compatibility strategy?

5. **Do you want conversation persistence?** If yes, where? Files? Core Data? SQLite? How much history? How will you handle history migration when the `AgentMessage` schema changes?

6. **Do you want more than two characters?** If yes, how many? The current architecture hardcodes two. Making it N-character requires extracting character config to data files.

7. **Do you want per-character personas?** If yes, how will they be implemented? System prompts? Separate `CLAUDE.md` files? Separate working directories?

8. **What is your update strategy?** The Sparkle feed points to `ryanstephen/lil-agents`. Will you maintain your own fork's feed? Will you diverge from upstream?

9. **Do you need offline functionality?** Currently the app is useless without a network connection (all CLIs need API access). Do you want local model support?

10. **What is your testing strategy?** The codebase has nearly zero tests. Will you add tests before refactoring, or refactor first and add tests to the new structure?

11. **How will you handle process lifecycle failures?** CLI crashes, hangs, OOM kills? Currently these are unhandled. Do you want auto-restart? Timeout? User notification?

12. **Do you want MCP tool support?** Claude Code supports MCP natively. Do you want the app to configure MCP servers, or will you manage that in `.claude/settings.json`?

13. **What is your multi-display strategy?** The current code handles multi-display but with some edge cases. Do you use an external monitor? Will characters need to move between screens?

14. **Do you want voice interaction?** If yes, at what priority? This would require microphone permissions, speech recognition, and TTS — a significant addition.

15. **What is your threat model?** The app runs unsandboxed, spawns subprocesses with full user permissions, and gives AI tools unrestricted system access. What are you willing to risk?
