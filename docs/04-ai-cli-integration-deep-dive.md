# filename: 04-ai-cli-integration-deep-dive.md

# AI CLI Integration Deep Dive

## Provider Abstraction Architecture

### The `AgentSession` Protocol

Defined in `AgentSession.swift`, this is the central contract between the UI layer and AI backends:

```swift
protocol AgentSession: AnyObject {
    var isRunning: Bool { get }
    var isBusy: Bool { get }
    var history: [AgentMessage] { get set }

    var onText: ((String) -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    var onToolUse: ((String, [String: Any]) -> Void)? { get set }
    var onToolResult: ((String, Bool) -> Void)? { get set }
    var onSessionReady: (() -> Void)? { get set }
    var onTurnComplete: (() -> Void)? { get set }
    var onProcessExit: (() -> Void)? { get set }

    func start()
    func send(message: String)
    func terminate()
}
```

**Design observations:**

- **Callback-based, not async/await or Combine** — every event is a closure. This is simple but leads to retain cycle risks and makes composition hard.
- **`history` is `get set`** on the protocol — the UI can mutate session history directly, breaking encapsulation.
- **No error typing** — `onError` takes a raw `String`, not a typed error. No way to distinguish network errors from parse errors from CLI crashes.
- **No `onThinking` or `onProgress`** — the UI infers thinking state from `isBusy` being true.
- **No cancel/abort** — `terminate()` kills the entire session. There is no way to cancel a single turn.

### The `AgentProvider` Enum

Also in `AgentSession.swift`, this enum is the provider registry:

```swift
enum AgentProvider: String, CaseIterable {
    case claude, codex, copilot, gemini, opencode, openclaw
}
```

It owns:
- `displayName`, `binaryName`, `inputPlaceholder`, `installInstructions`
- `createSession() -> any AgentSession` — factory method
- `detectAvailableProviders(completion:)` — scans PATH for all binaries
- `availability: [AgentProvider: Bool]` — cached availability map
- `isAvailable: Bool` — per-provider check
- `firstAvailable: AgentProvider` — fallback selection

**Provider-specific logic leak**: OpenClaw's availability check (`OpenClawConfig.load().authToken.isEmpty == false`) is directly in the enum, not behind a uniform interface.

### CLI Discovery

All CLI-based providers follow this pattern:

```swift
ShellEnvironment.findBinary(name: provider.binaryName, fallbackPaths: [
    "~/.local/bin/<name>",
    "/usr/local/bin/<name>",
    "/opt/homebrew/bin/<name>"
]) { path in ... }
```

Additional fallback paths vary by provider:
- **Claude**: `~/.claude/local/bin/claude`
- **Codex/Copilot/Gemini**: `~/.npm-global/bin/<name>`

### Environment Variables

`ShellEnvironment.processEnvironment()` builds the environment dict for spawned processes:

```swift
var env = cachedEnvironment ?? ProcessInfo.processInfo.environment
// Prepend essential paths
env["TERM"] = "dumb"
env.removeValue(forKey: "CLAUDECODE")
env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
```

The `TERM=dumb` setting prevents CLI tools from emitting ANSI escape codes. The `CLAUDECODE`/`CLAUDE_CODE_ENTRYPOINT` removal prevents Claude Code from detecting it's inside another Claude session and refusing to start.

### Streaming Output Parsing

Every CLI session uses the same NDJSON buffer pattern:

```swift
private func processOutput(_ text: String) {
    lineBuffer += text
    while let newlineRange = lineBuffer.range(of: "\n") {
        let line = String(lineBuffer[...newlineRange.lowerBound])
        lineBuffer = String(lineBuffer[newlineRange.upperBound...])
        if !line.isEmpty { parseLine(line) }
    }
}
```

This is correct for NDJSON but has no:
- Maximum line length protection (memory safety)
- Timeout for incomplete lines
- UTF-8 validation beyond `String(data:encoding:)`

### Error Surfacing

Errors reach the UI through two paths:
1. **`onError?(string)`** — displayed by `TerminalView.appendError()` in red text
2. **`onProcessExit?()`** — displayed as "{Provider} session ended."

There is no:
- Error categorization (transient vs permanent)
- Retry logic
- Structured error reporting
- User-actionable error messages beyond install instructions

### Public Contract: UI ↔ Session Layer

```
WalkerCharacter (UI owner)
    │
    ├── provider.createSession() → session instance
    ├── wireSession(session) → attach 7 callbacks
    ├── session.start() → discover binary, launch process
    ├── session.send(message:) → send user input
    ├── session.terminate() → kill process/connection
    ├── session.isBusy → used for thinking bubble state
    ├── session.history → replayed on popover reopen
    └── session.isRunning → not actually checked anywhere in UI
```

### Where Provider-Specific Logic Leaks

1. **`AgentProvider.isAvailable`** — OpenClaw checks `OpenClawConfig.load()` directly in the enum
2. **`AgentProvider.installInstructions`** — provider-specific install commands hardcoded in the enum
3. **`ShellEnvironment.processEnvironment()`** — the `CLAUDECODE` removal is Claude-specific but applied to all providers
4. **`WalkerCharacter.wireSession()`** — identical for all providers (good! no leakage here)
5. **`TerminalView`** — has a `provider` property used only for the input placeholder text

---

## Provider / Session Catalog

### 1. ClaudeSession

| Attribute | Value |
|---|---|
| **Source file** | `ClaudeSession.swift` (269 lines) |
| **CLI dependency** | `claude` (Claude Code CLI) |
| **Launch pattern** | Single long-lived `Process` with stdin/stdout/stderr pipes |
| **CLI arguments** | `["-p", "--output-format", "stream-json", "--input-format", "stream-json", "--verbose", "--dangerously-skip-permissions"]` |
| **Input method** | JSON messages written to stdin: `{"type": "user", "message": {"role": "user", "content": "..."}}` |
| **Stream format** | NDJSON with event types: `system`, `assistant`, `user`, `result` |
| **Multi-turn** | Native — single persistent process handles all turns |
| **Tool use display** | Parses `tool_use` blocks with specialized summaries for Bash, Read, Edit, Write, Glob, Grep |
| **Tool result display** | Parses `tool_result` content blocks from `user` type events |
| **Session ready** | Detected via `system` event with `subtype: "init"` |
| **Turn complete** | Detected via `result` event type |
| **Binary caching** | Static `binaryPath` on class |
| **Pending message queue** | Yes — messages sent before process is ready are queued |
| **Observed behavior** | Best-tested, most fully featured session. Handles streaming text, tool use, tool results, and completion correctly. |
| **Production readiness** | **Partial** — works well but uses `--dangerously-skip-permissions` (bypasses all safety), no error recovery, no reconnection if process dies |

### 2. CodexSession

| Attribute | Value |
|---|---|
| **Source file** | `CodexSession.swift` (244 lines) |
| **CLI dependency** | `codex` (OpenAI Codex CLI) |
| **Launch pattern** | New `Process` per `send()` call |
| **CLI arguments** | `["exec", "--json", "--full-auto", "--skip-git-repo-check", <prompt>]` |
| **Input method** | Full conversation history baked into prompt string as CLI argument |
| **Stream format** | NDJSON with event types: `thread.started`, `item.started`, `item.completed`, `turn.completed`, `turn.failed`, `error` |
| **Multi-turn** | **Faked** — entire conversation history is serialized into each prompt via `execPrompt()` |
| **Tool use display** | `item.started` with `command_execution` type |
| **Tool result display** | `item.completed` with `command_execution` status |
| **Session ready** | Immediately on binary discovery (no process launched at start) |
| **Turn complete** | `turn.completed` event or process termination |
| **Observed behavior** | Spawns a fresh process per message. Multi-turn context degrades as history grows (prompt gets very long). |
| **Production readiness** | **Thin wrapper** — the multi-turn hack is fragile, `--full-auto` bypasses safety, per-process overhead is high |

### 3. CopilotSession

| Attribute | Value |
|---|---|
| **Source file** | `CopilotSession.swift` (260 lines) |
| **CLI dependency** | `copilot` (GitHub Copilot CLI) |
| **Launch pattern** | New `Process` per `send()` call |
| **CLI arguments** | `["-p", <message>, "--output-format", "json", "--allow-all"]` + `--continue` for subsequent turns |
| **Input method** | Message as `-p` argument |
| **Stream format** | JSON events or plain text (runtime detection) |
| **Multi-turn** | Via `--continue` flag on subsequent calls |
| **Format detection** | `useJsonOutput` flag flips to `false` if first JSON parse fails — adapts at runtime |
| **Streaming delta** | Handles `assistant.message_delta` events marked as `ephemeral` |
| **Tool use display** | `assistant.tool_call` events |
| **Tool result display** | `assistant.tool_result` events |
| **Observed behavior** | Most adaptive session — handles both JSON and plain text output. The format detection is clever but fragile. |
| **Production readiness** | **Partial** — format auto-detection is a risk, `--allow-all` bypasses safety |

### 4. GeminiSession

| Attribute | Value |
|---|---|
| **Source file** | `GeminiSession.swift` (296 lines) |
| **CLI dependency** | `gemini` (Google Gemini CLI) |
| **Launch pattern** | New `Process` per `send()` call |
| **CLI arguments** | `["--yolo", "-p", <message>]` + `["--resume", "latest"]` for subsequent turns |
| **Input method** | Message as `-p` argument |
| **Stream format** | JSONL or plain text (dual-mode, detected at runtime) |
| **Multi-turn** | Via `--resume latest` flag |
| **Stderr filtering** | Extensive — filters spinner characters (`⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`), `✓`, `→`, `◆`, and keytar errors |
| **JSON event types** | Handles 13+ type strings: `content`, `text`, `delta`, `message`, `tool_call`, `function_call`, `tool_use`, `tool_result`, `function_result`, `done`, `end`, `complete`, `turn_end`, `result`, `error` |
| **Observed behavior** | Most defensively coded session. The huge number of event type strings suggests the author was guessing at the Gemini CLI's undocumented protocol across versions. |
| **Production readiness** | **Thin wrapper / exploratory** — the protocol handling is speculative, `--yolo` bypasses safety |

### 5. OpenCodeSession

| Attribute | Value |
|---|---|
| **Source file** | `OpenCodeSession.swift` (196 lines) |
| **CLI dependency** | `opencode` (OpenCode CLI) |
| **Launch pattern** | New `Process` per `send()` call |
| **CLI arguments** | `["run", <message>, "--format", "json"]` |
| **Input method** | Message as positional argument |
| **Stream format** | JSONL with event types: `text`, `step_start`, `step_finish`, `result`, `assistant.tool_call`, `assistant.tool_result` |
| **Multi-turn** | **No multi-turn support** — no `--resume` or `--continue` flag |
| **Observed behavior** | Simplest and most straightforward session. No multi-turn context. |
| **Production readiness** | **Minimal** — no multi-turn, basic parsing |

### 6. OpenClawSession

| Attribute | Value |
|---|---|
| **Source file** | `OpenClawSession.swift` (426 lines) |
| **CLI dependency** | None (network-based) |
| **Launch pattern** | `URLSessionWebSocketTask` to gateway |
| **Protocol** | Custom WebSocket JSON-RPC v3 with Ed25519 device auth |
| **Input method** | `chat.send` RPC with message, sessionKey, idempotencyKey |
| **Stream format** | WebSocket frames with `type: "event"` / `type: "res"` |
| **Chat events** | `delta` (streaming), `final` (completion), `error`, `aborted` |
| **Authentication** | Ed25519 keypair generated and persisted in UserDefaults, nonce challenge handshake |
| **Configuration** | `OpenClawConfig` with gateway URL, auth token, session prefix, agent ID |
| **Settings UI** | `showSettingsPanel()` — NSAlert with 4 text fields |
| **Observed behavior** | Most architecturally distinct session. Completely different transport (WebSocket vs Process). |
| **Production readiness** | **Partial** — functional but stores private key in UserDefaults (should use Keychain), no reconnection logic, no heartbeat |

---

## Provider Comparison Matrix

| Feature | Claude | Codex | Copilot | Gemini | OpenCode | OpenClaw |
|---|---|---|---|---|---|---|
| Process model | Persistent | Per-turn | Per-turn | Per-turn | Per-turn | WebSocket |
| Native multi-turn | ✅ | ❌ (faked) | ✅ (`--continue`) | ✅ (`--resume`) | ❌ | ✅ |
| JSON streaming | ✅ NDJSON | ✅ NDJSON | ✅/plain | ✅/plain | ✅ NDJSON | ✅ WebSocket |
| Tool use display | ✅ Rich | ✅ | ✅ | ✅ | ✅ | ✅ |
| Tool result display | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Error handling | Basic | Basic | Basic + format fallback | Defensive stderr filter | Basic | Auth error handling |
| Safety bypass | `--dangerously-skip-permissions` | `--full-auto --skip-git-repo-check` | `--allow-all` | `--yolo` | None visible | N/A |
| Binary caching | Static var | Static var | Static var | Static var | Static var | N/A |
| Message queuing | ✅ pendingMessages | ❌ | ❌ | ❌ | ❌ | ❌ |
| Production quality | ⭐⭐⭐ | ⭐⭐ | ⭐⭐½ | ⭐⭐ | ⭐½ | ⭐⭐½ |

---

## Critical Observations

### 1. All Safety Mechanisms Are Bypassed

Every CLI-based session uses a "full auto" flag:
- Claude: `--dangerously-skip-permissions`
- Codex: `--full-auto`
- Copilot: `--allow-all`
- Gemini: `--yolo`

This means the AI can execute arbitrary shell commands, read/write any file, and make network requests **without user confirmation**. This is a significant security concern for a desktop app.

### 2. No Schema Validation

Every session parses JSON with `try? JSONSerialization` and `as?` optional casting. If any CLI changes its output format, the session will silently drop data or break. There are no version checks, no schema assertions, and no compatibility tests.

### 3. The Multi-Turn Problem

Only Claude has true persistent multi-turn (single process with stdin/stdout). Codex fakes it by stuffing history into the prompt. Copilot and Gemini use `--continue`/`--resume` flags that depend on the CLI maintaining its own session state. OpenCode has no multi-turn at all.

### 4. Working Directory Is Always Home

Every process is launched with `currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser`. This means the AI CLI operates in `~/`, not in any project directory. For project-aware behavior, the working directory would need to be configurable per-character.
