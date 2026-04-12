# filename: 07-quality-gaps-refactor-and-personalization.md

# Quality Assessment, Production Gaps, Refactor Blueprint, and Personalization Plan

---

## Section 9: Quality Assessment by Subsystem

| Subsystem | Score | Good | Weak | Risky | Change First |
|---|---|---|---|---|---|
| **Repo structure** | 4/10 | Flat directory is easy to navigate for a small project | No module boundaries, no separation of concerns in directory layout, single `LilAgents/` folder for everything | Cannot scale beyond ~15 files without becoming chaotic | Create `Sources/`, `Models/`, `Sessions/`, `UI/`, `Infrastructure/` subdirectories |
| **macOS app architecture** | 6/10 | Working accessory app with CVDisplayLink, correct Dock geometry, multi-display support | WalkerCharacter god object, hybrid SwiftUI/AppKit confusion, AppDelegate owns too much menu logic | State management is entirely ad hoc booleans — easy to create impossible states | Extract state machine from WalkerCharacter |
| **Provider/session abstraction** | 5/10 | Clean `AgentSession` protocol with good callback surface, `AgentProvider` factory pattern | Each session is a one-off implementation with no shared parsing infrastructure, no error typing, no versioning | CLI output format changes will break silently with no diagnostics | Add shared NDJSON parser, typed errors, provider version detection |
| **Shell environment handling** | 7/10 | Clever zsh env capture, proper `TERM=dumb`, `CLAUDECODE` removal, caching | Cached forever (never invalidated), hardcoded to zsh, no error handling if zsh probe fails | User installs new CLI after app start → not detected | Add cache invalidation or periodic refresh |
| **UI/terminal rendering** | 6/10 | Functional Markdown renderer, themed consistently, auto-scrolling, slash commands | No resize, no search, no accessibility, no image support, fixed popover size | Markdown parser is hand-rolled and incomplete (no tables, no numbered lists, no nested formatting) | Add resize support, accessibility labels |
| **Configurability** | 4/10 | Per-character provider/size, 4 themes, sounds toggle, display pinning | Most config not persisted (sounds, display pin), characters hardcoded, themes hardcoded, working directory always `~` | Adding a character or theme requires code changes | Extract character definitions to config/data |
| **Observability** | 1/10 | Debug line window exists (hidden) | No logging whatsoever, no crash reporting, no performance metrics, no error aggregation, stderr goes to `onError` but often ignored | CLI failures are silent. Process hangs are undetected. Memory leaks in long sessions are invisible. | Add OSLog or unified logging |
| **Reliability** | 3/10 | Graceful binary-not-found handling, fallback hit-testing, environment hide/show state restoration | No retry logic, no timeout, no heartbeat, no process supervision, force-unwrap on pipe write, no cleanup on crash | A hung CLI process blocks the character indefinitely with no user recourse except `/clear` | Add process timeout, watchdog, graceful degradation |
| **Extensibility** | 3/10 | AgentSession protocol allows new providers, theme struct allows new themes | Everything is hardcoded in code — no plugin architecture, no config files, no dynamic loading | Every extension requires recompilation | Move character/theme definitions to plist/JSON |
| **Production readiness** | 3/10 | Ships and works (v1.2.2 released), Sparkle updates, universal binary | No sandbox, no logging, no tests, no error recovery, no session persistence, no security review, private key in UserDefaults | The `--dangerously-skip-permissions` on Claude means the AI can do anything on the user's system with no confirmation | Add sandbox or at minimum permission UI, move keys to Keychain |

---

## Section 10: Production-Readiness Gap Analysis

### P0 — Must Fix Before Serious Use

| Gap | Impact | Affected Files |
|---|---|---|
| **All safety bypassed** — `--dangerously-skip-permissions`, `--full-auto`, `--allow-all`, `--yolo` | AI can execute arbitrary commands, read/write any file, no user confirmation | All session files |
| **No process supervision** — if a CLI process hangs, the character is stuck forever | User must `/clear` or quit app. No timeout, no watchdog. | `WalkerCharacter.swift`, all sessions |
| **No logging** — zero diagnostic output, no way to debug issues after the fact | Cannot diagnose user-reported issues. Cannot detect silent failures. | All files |
| **Private key in UserDefaults** — OpenClaw Ed25519 private key stored in plaintext | Any app reading UserDefaults can steal the identity | `OpenClawSession.swift` |
| **No session persistence** — all conversation history lost on quit | Users lose context on every restart | `WalkerCharacter.swift`, session files |
| **Force-unwrap on pipe write** — `line.data(using: .utf8)!` | Crash if message contains unencodable characters (extremely unlikely but possible) | `ClaudeSession.swift` |

### P1 — High-Value Next

| Gap | Impact | Affected Files |
|---|---|---|
| **No error categorization** — all errors are strings | Cannot distinguish transient from permanent, cannot retry, cannot show appropriate UI | `AgentSession.swift`, all sessions |
| **No CLI version detection** — no way to know if installed CLI supports the expected protocol | Silent breakage when CLIs update their output format | All session files |
| **No retry/reconnect** — process dies, session is dead | User must manually reset. OpenClaw WS disconnect is permanent. | All sessions |
| **No testability** — only 6 assertions in the entire codebase | Cannot validate changes, cannot prevent regressions | All files |
| **Sounds/display pin not persisted** — reset on restart | User must reconfigure every launch | `WalkerCharacter.swift`, `LilAgentsController.swift` |
| **Working directory always `~`** — no project context | AI operates in home directory, not in user's project. Severely limits usefulness for coding tasks. | All session `launchProcess` methods |
| **No cancel/abort** — `terminate()` kills entire session | Cannot cancel a single turn, must restart session | `AgentSession.swift` protocol |

### P2 — Later Improvements

| Gap | Impact | Affected Files |
|---|---|---|
| **No concurrency safety** — `CVDisplayLink` dispatches to main, all state mutation on main | Currently safe but fragile. Adding any background work risks data races. | `LilAgentsController.swift`, `WalkerCharacter.swift` |
| **No memory management** — `history` array grows unbounded | Long sessions will consume increasing memory, and text view will slow down | `AgentSession.swift`, `TerminalView.swift` |
| **No accessibility** — no VoiceOver, no Dynamic Type, no keyboard navigation | Not usable by users with accessibility needs | All UI files |
| **No localization** — all strings hardcoded in English | Cannot be used by non-English speakers | All files |
| **Sandbox disabled** — app has full user permissions | Could be a vector for privilege escalation if CLI is compromised | `LilAgents.entitlements` |
| **Sparkle feed URL mismatch** — points to `ryanstephen/` not `itsnothuy/` | Fork may receive wrong updates | `Info.plist` |

---

## Section 11: Refactor Blueprint — V2 Architecture

### Proposed Folder Structure

```
LilAgents/
├── App/
│   ├── LilAgentsApp.swift          # @main, minimal
│   ├── AppDelegate.swift           # Menu bar only
│   └── AppConfig.swift             # Centralized config/defaults
├── Controller/
│   ├── AgentCoordinator.swift      # Replaces LilAgentsController
│   └── DockGeometry.swift          # Extracted from controller
├── Character/
│   ├── CharacterConfig.swift       # Data-driven character definitions
│   ├── CharacterStateMachine.swift # Walking/Paused/Idle/Busy states
│   ├── CharacterAnimator.swift     # AVPlayer + movement math
│   ├── CharacterWindow.swift       # NSWindow + hit-testing
│   └── CharacterManager.swift      # Coordinates state + animator + window
├── Session/
│   ├── AgentSession.swift          # Protocol + types
│   ├── SessionManager.swift        # Owns lifecycle, retry, timeout
│   ├── NDJSONParser.swift          # Shared line-buffered parser
│   ├── Providers/
│   │   ├── ClaudeSession.swift
│   │   ├── CodexSession.swift
│   │   ├── CopilotSession.swift
│   │   ├── GeminiSession.swift
│   │   ├── OpenCodeSession.swift
│   │   └── OpenClawSession.swift
│   └── ProviderRegistry.swift      # Replaces AgentProvider enum
├── UI/
│   ├── PopoverController.swift     # Popover window lifecycle
│   ├── TerminalView.swift          # Chat rendering
│   ├── MarkdownRenderer.swift      # Extracted from TerminalView
│   ├── ThinkingBubble.swift        # Extracted from WalkerCharacter
│   └── Theme/
│       ├── PopoverTheme.swift      # Theme struct
│       ├── ThemeRegistry.swift     # Theme discovery/loading
│       └── themes.json             # Theme definitions as data
├── Infrastructure/
│   ├── ShellEnvironment.swift
│   ├── DockVisibility.swift
│   ├── KeychainHelper.swift        # For OpenClaw keys
│   ├── Logging.swift               # OSLog wrapper
│   └── Persistence.swift           # UserDefaults + file-based storage
├── Resources/
│   ├── Assets.xcassets/
│   ├── Sounds/
│   ├── characters.json             # Character definitions
│   └── themes.json                 # Theme definitions
└── Tests/
    ├── DockVisibilityTests.swift
    ├── NDJSONParserTests.swift
    ├── CharacterStateMachineTests.swift
    ├── MarkdownRendererTests.swift
    └── SessionTests/
        └── ClaudeSessionTests.swift
```

### Module Boundaries

```
App Module:        App bootstrap, menu bar, no business logic
Controller Module: Coordination, tick loop, dock geometry
Character Module:  State machine, animation, window management
Session Module:    AI provider abstraction, parsing, lifecycle
UI Module:         Popover, terminal, themes, bubbles
Infra Module:      Shell, persistence, logging, keychain
```

### Interface Design: Provider Sessions

```swift
// Session protocol with typed errors and async/await
protocol AgentSession: AnyObject {
    var state: SessionState { get }  // .idle, .starting, .ready, .busy, .failed
    var history: [AgentMessage] { get }
    
    // Async streams instead of callbacks
    func start() async throws
    func send(message: String) -> AsyncThrowingStream<SessionEvent, Error>
    func cancel()   // Cancel current turn only
    func terminate() // Kill entire session
}

enum SessionEvent {
    case text(String)
    case toolUse(name: String, input: [String: Any])
    case toolResult(summary: String, isError: Bool)
    case turnComplete
    case error(SessionError)
}

enum SessionError: Error {
    case binaryNotFound(provider: String, installInstructions: String)
    case launchFailed(underlying: Error)
    case processExited(code: Int32)
    case parseError(line: String)
    case timeout
    case connectionLost
}
```

### Interface Design: UI/State Orchestration

```swift
// State machine with enforced transitions
enum CharacterState {
    case walking(direction: Direction, progress: CGFloat)
    case paused(resumeAt: CFTimeInterval)
    case idle(popoverOpen: Bool)
    case hidden(reason: HiddenReason)
}

protocol CharacterDelegate: AnyObject {
    func characterDidRequestPopover(_ character: CharacterManager)
    func characterDidClosePopover(_ character: CharacterManager)
    func characterSessionDidComplete(_ character: CharacterManager)
}
```

### Interface Design: Personalization

```swift
// Data-driven character configuration
struct CharacterConfig: Codable {
    let id: String
    let name: String
    let videoAsset: String
    let color: CodableColor
    let defaultProvider: String
    let animationTiming: AnimationTiming
    let persona: PersonaConfig?
}

struct PersonaConfig: Codable {
    let systemPrompt: String?
    let workingDirectory: String?
    let environmentOverrides: [String: String]?
    let claudeMdPath: String?
}
```

### Migration Plan

| Phase | What | Keep / Rewrite / Delete |
|---|---|---|
| **Phase 1: Extract** | Pull state machine, animator, popover, bubble out of WalkerCharacter | Rewrite WalkerCharacter as thin coordinator |
| **Phase 2: Session layer** | Add shared NDJSON parser, typed errors, timeout/retry wrapper | Keep protocol shape, rewrite implementations |
| **Phase 3: Data-driven config** | Move characters, themes to JSON/plist | Delete hardcoded definitions |
| **Phase 4: Persistence** | Add conversation persistence, preference completeness | New code |
| **Phase 5: Observability** | Add OSLog, structured diagnostics | New code |
| **Phase 6: Tests** | XCTest for parser, state machine, themes, markdown | New code |

### What to Keep
- `DockVisibility` — clean, tested, correct
- `ShellEnvironment` — solid design, needs minor improvements
- `AgentSession` protocol shape — good callback surface
- `PopoverTheme` struct — good data model, needs registry extraction
- `CharacterContentView.hitTest()` — clever pixel-sampling approach
- Dock geometry logic — works, needs minor refinements
- CVDisplayLink tick loop — correct pattern for this use case

### What to Rewrite
- `WalkerCharacter` → decompose into 4–5 classes
- All 6 session implementations → add shared parsing, typed errors
- `AppDelegate` menu code → extract to dedicated menu builder
- `TerminalView` markdown rendering → extract to `MarkdownRenderer`

### What to Delete
- `AgentProvider.current` (unused global provider key)
- Debug window code (or gate behind a build flag)
- The `bruce-hang` asset if unused

---

## Section 12: Personalization / Customization Plan

### Layer A — App-Level Personalization

#### Character Identity / Persona
- **Current**: Names are hardcoded strings ("Bruce", "Jazz"). Colors are hardcoded NSColor values. No persona concept exists.
- **How to customize**: 
  1. Create `characters.json` with name, color, video asset, default provider per character
  2. Add a `persona` field with system prompt text
  3. For Claude: prepend persona text to each session's first message, or use `CLAUDE.md`
  4. For others: prepend persona text to each prompt

#### Themes
- **Current**: 4 themes hardcoded as static properties on `PopoverTheme`
- **How to customize**: Add new `PopoverTheme` instances to `allThemes` array, or better, load from a `themes.json` file

#### Names
- **Current**: Change `"Bruce"` / `"Jazz"` strings in `LilAgentsController.start()`. UserDefaults keys are name-prefixed, so changing names creates fresh config.
- **Impact**: Changing a name orphans old UserDefaults keys

#### Animations
- **Current**: Replace `.mov` files in bundle. Must match 1080×1920 format with transparent background.
- **How to add new characters**: Add new video, create new `WalkerCharacter` in `start()`, add menu items

#### Sound Effects
- **Current**: 9 files in `Sounds/`. Add/remove `.mp3`/`.m4a` files and update the `completionSounds` array in `WalkerCharacter`.

#### Keyboard Shortcuts
- **Current**: ⌘1/⌘2 toggle characters, ESC closes popover. No other shortcuts.
- **How to add**: Add `keyEquivalent` to `NSMenuItem` in `setupMenuBar()`, or add local event monitors

#### Popover Layout
- **Current**: Fixed 420×310. Change constants in `createPopoverWindow()`.
- **How to make resizable**: Change `styleMask` from `.borderless` to include `.resizable`, add constraints

#### Default Provider Selection
- **Current**: `AgentProvider.firstAvailable` is used on first run. Per-character after that.
- **How to customize**: Set `char1.provider = .claude` directly in `start()`, or create a config file

#### Per-Character Behavior
- **Current**: Each character has independent `provider`, `size`, `session`, `history`
- **What's missing**: Per-character working directory, per-character system prompt, per-character theme

#### Local Persistence of Preferences
- **Current**: Provider and size persisted. Theme persisted globally. Sounds and display pin NOT persisted.
- **Fix**: Add `UserDefaults.standard.set()` for `soundsEnabled` and `pinnedScreenIndex`

### Layer B — Provider/CLI Behavior Personalization (Claude Code Focus)

#### `CLAUDE.md`
- **What it does**: Provides project-level instructions that Claude Code reads at session start
- **Where it goes**: Root of any directory Claude operates in (currently `~` since working directory is always home)
- **What changes**: Response style, coding conventions, domain knowledge, behavioral rules
- **Best for**: Stable instructions like "always use Swift 6 concurrency", "prefer composition over inheritance", "respond in a direct, blunt style"
- **Limitation in lil-agents**: Since working directory is `~`, a `CLAUDE.md` in `~` applies to ALL Claude sessions, not per-character

#### `.claude/` Directory (User-Level)
- **`~/.claude/settings.json`**: User-level settings (allowed tools, denied tools, model preferences)
- **`~/.claude/commands/`**: Custom slash commands available in all projects
- **What changes**: Behavior and available tooling

#### `.claude/` Directory (Project-Level)  
- **`.claude/settings.json`**: Project-specific tool permissions
- **`.claude/commands/`**: Project-specific slash commands
- **`.claude/skills/`**: Reusable workflow definitions
- **What changes**: Per-project behavior customization

#### Skills (`.claude/skills/`)
- **What they are**: Markdown files describing reusable workflows
- **Best for**: Recurring tasks like "do a repo teardown", "grade this Java interview", "generate an IELTS lesson"
- **Changes**: Reusable workflow behavior, not response style

#### Hooks
- **What they are**: Deterministic actions triggered before/after specific events
- **Best for**: Always running formatter after edits, always running tests, blocking dangerous file operations
- **Changes**: Guaranteed actions, not probabilistic behavior

#### Memory
- **What it does**: Persists knowledge across sessions
- **Best for**: Remembering project context, user preferences, past decisions
- **Changes**: Long-term context, not per-session behavior

#### Output Styles
- **What they do**: Change response formatting and tone
- **Best for**: "Be concise", "use bullet points", "respond like a senior engineer"
- **Changes**: Response style only

#### Subagents
- **What they do**: Spawn specialized sub-tasks within a session
- **Best for**: Complex multi-step workflows where different subtasks need different capabilities
- **Changes**: Task orchestration

### Layer C — Architecture Changes for First-Class Personalization

#### Multiple Personas
```swift
// Add to CharacterConfig
struct PersonaConfig: Codable {
    let name: String              // "Senior Reviewer"
    let systemPrompt: String      // Prepended to first message
    let workingDirectory: String? // Override per-character
    let claudeMdPath: String?     // Per-persona CLAUDE.md
    let environmentOverrides: [String: String]?
}
```
**Files to change**: `WalkerCharacter.swift` (add persona config), all session `launchProcess` methods (support custom working directory, custom env vars)

#### Different Assistants Per Character
- **Already partially supported**: Each character has independent `provider` property
- **Missing**: Per-character system prompt, per-character working directory, per-character CLI flags
- **Implementation**: Add `characterConfig.cliExtraArgs: [String]` passed to session `start()`, add `characterConfig.workingDirectory: String` passed to `proc.currentDirectoryURL`

#### Project-Aware Behavior
- **Current**: Working directory is always `~`
- **Fix**: Add a `workingDirectory` property to `WalkerCharacter`, pass to session `launchProcess`
- **Better**: Let user set working directory per character via menu or drag-and-drop of a folder
- **Best**: Auto-detect from frontmost Xcode/VS Code window's project path

#### Persistent Memory Per Character
- **Current**: History lost on quit
- **Implementation**: 
  1. Serialize `session.history` to JSON file on `applicationWillTerminate`
  2. Key by character name + provider: `~/Library/Application Support/LilAgents/history/Bruce-claude.json`
  3. Reload on session creation
  4. For Claude: leverage Claude Code's built-in memory system via `~/.claude/memory/`

#### Different Prompt Stacks for Different Tasks
- Create multiple `CLAUDE.md` files in different project directories
- Point different characters at different working directories
- Each character gets different context and instructions

#### Safe Automation Actions
- Use Claude Code hooks to enforce safety: always run tests, always lint, block writes to certain directories
- Remove `--dangerously-skip-permissions` and let Claude Code handle its own permission model
- Add a confirmation UI in the popover before executing dangerous tool calls

#### Voice (Later)
- Add microphone permission, `AVAudioEngine` for speech-to-text
- Pipe transcribed text to `session.send()`
- For TTS: pipe `onText` output to `AVSpeechSynthesizer` or a better TTS engine

#### MCP Tool Use (Later)
- Claude Code already supports MCP servers natively
- Configure MCP servers in `.claude/settings.json`
- No app-level changes needed — the tools appear in Claude's context automatically

### Layer D — Recommended Personalization Strategy

**The layered approach:**

1. **App layer** (light touch):
   - Rename characters to meaningful personas ("Reviewer", "Writer")
   - Set per-character colors and default providers
   - Set per-character working directories
   - Persist all preferences

2. **`CLAUDE.md`** (core instructions):
   - One per working directory (one per "project context")
   - Contains stable behavioral instructions: coding style, review approach, response format
   - Example: `~/projects/java-prep/CLAUDE.md` for interview prep, `~/projects/blog/CLAUDE.md` for writing

3. **Skills** (reusable workflows):
   - `~/.claude/skills/repo-teardown.md` — full codebase analysis
   - `~/.claude/skills/interview-grader.md` — Java interview assessment
   - `~/.claude/skills/ielts-lesson.md` — IELTS teaching format

4. **Hooks** (guaranteed actions):
   - After file edit: run formatter
   - After code generation: run tests
   - Before file write: check against deny list

5. **Memory** (persistence):
   - Let Claude Code manage its own memory for cross-session context
   - Add app-level history persistence for UI replay

6. **Output styles** (tone):
   - "blunt senior reviewer" for code review character
   - "patient teacher" for writing/learning character

**Do NOT**:
- Jam everything into one mega system prompt
- Try to replicate Claude Code's built-in features at the app layer
- Build a custom MCP integration when Claude Code has it natively
- Store sensitive config in UserDefaults

---

## Section 13: Future Extension Path

### Right Abstraction Boundaries Now

| Future Feature | Boundary to Establish Now |
|---|---|
| **Richer local memory** | Persist `AgentMessage` history to disk. Keep history separate from session logic. |
| **MCP tools** | Don't build custom tool integration — Claude Code already supports MCP. Just ensure working directory is correct so `.claude/settings.json` is found. |
| **Local/hosted tool execution** | The `AgentSession` protocol already supports `onToolUse`/`onToolResult`. The UI can display tool activity without knowing whether tools run locally or remotely. |
| **Voice input/output** | Add `AudioInputManager` and `AudioOutputManager` as siblings to `TerminalView`, not children. The session layer should not know about audio. |
| **Project-aware companions** | Add `workingDirectory` to character config. The session layer already passes `currentDirectoryURL` to `Process`. |
| **Multiple agent backends** | The `AgentSession` protocol already supports this. `AgentProvider` enum is the registry. Just keep the protocol clean. |
| **Optional robotics tie-ins** | Add a `PhysicalOutputAdapter` protocol alongside the UI output. The session layer emits events; any adapter can consume them. |

---

## Section 14: Concrete Next Steps

If your goal is to use lil-agents as a personalized AI companion base, do these next:

### 1. Add OSLog Logging
- **Why**: You cannot debug or improve what you cannot observe
- **Files**: Create `Infrastructure/Logging.swift`, add `os_log` calls to all session `parseLine()`, `launchProcess()`, and error paths
- **Outcome**: Every CLI launch, parse error, and completion is logged to Console.app

### 2. Extract WalkerCharacter Into 4 Classes
- **Why**: The god object prevents all other improvements
- **Files**: Split `WalkerCharacter.swift` into `CharacterStateMachine.swift`, `CharacterAnimator.swift`, `PopoverController.swift`, `ThinkingBubble.swift`
- **Outcome**: Each concern is testable and modifiable independently

### 3. Add Per-Character Working Directory
- **Why**: Without project context, the AI is nearly useless for coding tasks
- **Files**: Add `workingDirectory: String` to `WalkerCharacter`, pass to each session's `proc.currentDirectoryURL`
- **Outcome**: Each character can operate in a different project

### 4. Persist Conversation History
- **Why**: Losing all context on quit destroys session continuity
- **Files**: Add serialization in `WalkerCharacter.resetSession()` and `AppDelegate.applicationWillTerminate()`, load in `openPopover()`
- **Outcome**: Conversations survive app restarts

### 5. Remove `--dangerously-skip-permissions` (Claude) and Equivalents
- **Why**: Full auto mode is a security liability for a desktop app
- **Files**: `ClaudeSession.swift` (remove flag), all other sessions (remove equivalent flags)
- **Outcome**: AI requests permission before executing dangerous operations

### 6. Add Shared NDJSON Parser with Tests
- **Why**: Every session has the same line-buffer + JSON parse pattern, duplicated 6 times
- **Files**: Create `Session/NDJSONParser.swift` + `Tests/NDJSONParserTests.swift`
- **Outcome**: One tested parser used by all sessions

### 7. Create `characters.json` Configuration File
- **Why**: Characters are hardcoded with magic numbers scattered through `start()`
- **Files**: Create `Resources/characters.json`, load in `LilAgentsController.start()`
- **Outcome**: Add/modify characters without code changes

### 8. Set Up `CLAUDE.md` and Skills for Your Personas
- **Why**: This is where the real personalization happens
- **Files**: `~/CLAUDE.md` or per-project `CLAUDE.md`, `~/.claude/skills/*.md`
- **Outcome**: Each character behaves according to its persona

### 9. Persist Sounds/Display Pin Settings
- **Why**: These reset every launch, which is annoying
- **Files**: `WalkerCharacter.swift` (soundsEnabled), `LilAgentsController.swift` (pinnedScreenIndex)
- **Outcome**: Settings survive restart

### 10. Add XCTest Suite for Critical Paths
- **Why**: You cannot refactor safely without tests
- **Files**: Create test targets for NDJSON parsing, Markdown rendering, DockVisibility (migrate existing), theme construction
- **Outcome**: Confidence to make changes without breaking things
