# filename: 03-request-lifecycle.md

# End-to-End Request Lifecycle

## Scenario: User clicks Bruce, types a question, receives a streamed answer (Claude provider)

### Step-by-Step Trace

#### 1. Click Interaction (Synchronous, Local)

```
User clicks on Bruce's transparent video window
    ↓
CharacterContentView.hitTest(_:) is called
    ├── Converts click point to screen coordinates
    ├── Flips Y for CG coordinate system (uses primary screen height)
    ├── Calls CGWindowListCreateImage() to capture 1×1 pixel at click point
    ├── Reads alpha channel of captured pixel
    ├── If alpha > 30 → return self (accept click)
    └── If alpha ≤ 30 → return nil (click passes through to app behind)
    ↓
CharacterContentView.mouseDown(with:) fires
    ↓
character.handleClick()
    ├── If isOnboarding → openOnboardingPopover() (first-run path)
    └── If not onboarding:
        ├── If isIdleForPopover → closePopover()
        └── If !isIdleForPopover → openPopover()  ← THIS PATH
```

#### 2. Popover/Session Creation (Asynchronous for session, Synchronous for UI)

```
openPopover()
    ├── Close any sibling's open popover (only one popover at a time)
    ├── Set state: isIdleForPopover=true, isWalking=false, isPaused=true
    ├── Pause and rewind AVQueuePlayer
    ├── Hide any thinking/completion bubble
    │
    ├── If session == nil (first open or after reset):
    │   ├── provider.createSession() → ClaudeSession()
    │   ├── wireSession(newSession) → attach all 7 callbacks
    │   └── newSession.start() → triggers CLI discovery + process launch
    │
    ├── If popoverWindow == nil:
    │   └── createPopoverWindow()
    │       ├── Create KeyableWindow (borderless, statusBar+10)
    │       ├── Create container NSView with theme colors/corners
    │       ├── Create title bar with:
    │       │   ├── Provider name label
    │       │   ├── Dropdown arrow button → showProviderMenu()
    │       │   ├── Refresh button → refreshSessionFromButton()
    │       │   └── Copy button → copyLastResponseFromButton()
    │       ├── Create TerminalView (scrollView + textView + inputField)
    │       └── Wire terminal.onSendMessage → session.send()
    │           Wire terminal.onClearRequested → resetSession()
    │
    ├── If session has history → terminal.replayHistory(session.history)
    ├── Position popover centered above character, clamped to screen
    ├── Order popover front, make key, focus input field
    │
    └── Install event monitors:
        ├── Global leftMouseDown/rightMouseDown → closePopover() if outside
        └── Local keyDown(ESC) → closePopover()
```

#### 3. Shell Environment Resolution (Asynchronous, One-time)

```
ClaudeSession.start()
    ├── If Self.binaryPath cached → launchProcess() immediately
    └── Else:
        ShellEnvironment.findBinary(name: "claude", fallbackPaths: [...])
            └── ShellEnvironment.resolve()
                ├── If cached environment → use immediately
                └── Else:
                    ├── Spawn: Process("/bin/zsh", ["-l", "-i", "-c", 
                    │       "echo '---ENV_START---' && env && echo '---ENV_END---'"])
                    ├── Read stdout → parse between markers
                    ├── Build [String: String] environment dict
                    ├── Cache as static property
                    └── completion(env)
                        ├── Search env["PATH"] directories for "claude" executable
                        └── Check fallback paths if not found
```

**Latency introduced here**: First call takes ~200–500ms for zsh to initialize and dump env. Subsequent calls are instant (cached).

#### 4. CLI Binary Selection & Subprocess Launch (Asynchronous)

```
launchProcess(binaryPath: "/Users/you/.local/bin/claude")
    ├── Create Process()
    ├── Set executableURL, arguments:
    │   ["-p", "--output-format", "stream-json", 
    │    "--input-format", "stream-json", "--verbose",
    │    "--dangerously-skip-permissions"]
    ├── Set currentDirectoryURL = home directory
    ├── Set environment = ShellEnvironment.processEnvironment()
    │   ├── Start with cached shell env (or ProcessInfo fallback)
    │   ├── Prepend essential paths to PATH
    │   ├── Set TERM=dumb
    │   └── Remove CLAUDECODE, CLAUDE_CODE_ENTRYPOINT
    ├── Create stdin/stdout/stderr Pipes
    ├── Set terminationHandler → mark !isRunning, fire onProcessExit
    ├── Set stdout readabilityHandler → processOutput()
    ├── Set stderr readabilityHandler → onError()
    ├── proc.run()
    ├── isRunning = true
    └── Send any pendingMessages
```

**Latency**: Claude CLI startup takes 1–5 seconds depending on network authentication. During this time, the user sees an empty terminal with cursor.

#### 5. Prompt/Input Handoff (Synchronous)

```
User types "How does the Swift type system work?" and presses Enter
    ↓
TerminalView.inputSubmitted()
    ├── Trim input, check non-empty
    ├── Check for slash commands (/clear, /copy, /help) → none
    ├── If showingSessionMessage: clear "✦ new session" text
    ├── appendUser(text) → render "> How does the Swift type system work?"
    ├── Set isStreaming=true, currentAssistantText=""
    └── onSendMessage?(text) → WalkerCharacter callback
        ↓
session.send(message: "How does the Swift type system work?")
    ↓
ClaudeSession.writeMessage(message, to: inputPipe)
    ├── Set isBusy=true, currentResponseText=""
    ├── Append AgentMessage(.user, text) to history
    ├── Build JSON payload:
    │   {"type": "user", "message": {"role": "user", "content": "..."}}
    ├── Serialize to JSON string + newline
    └── Write to pipe.fileHandleForWriting
```

#### 6. Streaming Output Parsing (Asynchronous)

```
Claude CLI process writes to stdout
    ↓
outPipe.fileHandleForReading.readabilityHandler fires
    ├── Read availableData → decode as UTF-8
    └── DispatchQueue.main.async { processOutput(text) }
        ↓
processOutput(text)
    ├── Append to lineBuffer
    └── While lineBuffer contains "\n":
        ├── Extract line up to newline
        └── parseLine(line)
            ├── JSON parse → [String: Any]
            ├── Switch on json["type"]:
            │
            │   "system" (subtype: "init"):
            │       → onSessionReady?()
            │
            │   "assistant":
            │       → Extract content blocks
            │       → For "text" blocks: 
            │           currentResponseText += text
            │           onText?(text) → wireSession callback
            │       → For "tool_use" blocks:
            │           onToolUse?(toolName, input)
            │
            │   "user" (tool_result content):
            │       → onToolResult?(summary, isError)
            │
            │   "result":
            │       → isBusy = false
            │       → Append final text to history
            │       → onTurnComplete?()
```

#### 7. Terminal Rendering (Synchronous on main thread)

```
session.onText callback fires
    ↓
WalkerCharacter.wireSession closure:
    currentStreamingText += text
    terminalView?.appendStreamingText(text)
        ↓
TerminalView.appendStreamingText(text)
    ├── Strip leading newlines if first chunk
    ├── currentAssistantText += cleaned
    ├── Render through renderMarkdown(cleaned)
    │   ├── Split into lines
    │   ├── Handle code blocks (``` fences)
    │   ├── Handle headings (#, ##, ###)
    │   ├── Handle bullet lists (-, *)
    │   └── renderInlineMarkdown for each line:
    │       ├── Inline code (`...`)
    │       ├── Bold (**...**)
    │       ├── Links ([text](url))
    │       └── Bare URLs (https://...)
    ├── Append NSAttributedString to textView.textStorage
    └── scrollToBottom()
```

#### 8. Thinking State / Bubble State (during streaming)

```
CVDisplayLink tick() → character.update()
    ├── Character is isIdleForPopover → updateThinkingBubble()
    │   ├── If isAgentBusy && isIdleForPopover:
    │   │   → hide bubble (popover is open, no need for bubble)
    │   └── If isAgentBusy && !isIdleForPopover:
    │       → updateThinkingPhrase() → pick random phrase every 3-5s
    │       → showBubble(text, isCompletion: false)
    │
    └── (In this scenario, popover IS open, so bubble stays hidden)
```

#### 9. Completion State (Synchronous)

```
session.onTurnComplete fires
    ↓
wireSession closure:
    terminalView?.endStreaming()
        ├── Set isStreaming=false
        └── Save currentAssistantText as lastAssistantText (for /copy)
    
    playCompletionSound()
        ├── If soundsEnabled:
        │   ├── Pick random sound file (avoiding repeat)
        │   └── NSSound(contentsOf: url).play()
    
    showCompletionBubble()
        ├── Pick random completion phrase ("done!", "all set!", etc.)
        ├── Set showingCompletion=true
        ├── Set completionBubbleExpiry = now + 3.0 seconds
        └── If !isIdleForPopover → showBubble (if popover closed)
            (if popover open, bubble deferred until popover closes)
```

#### 10. Cleanup / Session Persistence

```
When user clicks outside popover or presses ESC:
    closePopover()
        ├── popoverWindow?.orderOut(nil) — hide, don't destroy
        ├── Remove global/local event monitors
        ├── isIdleForPopover = false
        ├── If showingCompletion → show completion bubble with fresh 3s timer
        ├── If isAgentBusy → show thinking bubble
        └── pauseEndTime = now + random(2...5) — resume walking
    
    NOTE: session is NOT terminated on popover close
    NOTE: popoverWindow is NOT destroyed on popover close (reused)
    NOTE: conversation history stays in session.history (in memory only)
    NOTE: if app is quit → applicationWillTerminate calls session.terminate()
              → all Process instances are killed
              → all history is lost (no disk persistence)
```

### Synchronous vs Asynchronous Parts

| Step | Sync/Async | Thread |
|---|---|---|
| Click hit-testing | Sync | Main |
| Popover UI creation | Sync | Main |
| Shell env resolution | **Async** | Background → Main callback |
| Binary discovery | **Async** | Uses resolved env, then Main callback |
| Process launch | Sync (after binary found) | Main |
| Writing to stdin pipe | Sync | Main |
| Reading stdout | **Async** | Background readabilityHandler → Main dispatch |
| NDJSON parsing | Sync (on Main) | Main |
| Terminal rendering | Sync | Main |
| CVDisplayLink tick | **Async** | CVDisplayLink thread → Main dispatch |

### Where Latency Is Introduced

1. **Shell environment resolution** (~200–500ms first time, cached after)
2. **CLI process startup** (1–5s for Claude, varies by provider)
3. **AI inference** (1–30s depending on query complexity, model, network)
4. **Main thread dispatch** (negligible, but all UI + parsing runs on main)

### Where Failures Can Occur

1. **Binary not found** → `onError` with install instructions (graceful)
2. **Process launch fails** → `onError` with error description (graceful)
3. **Process crashes mid-stream** → `terminationHandler` fires, `onProcessExit` callback (partial — no retry)
4. **Malformed JSON in stream** → `parseLine` silently ignores unparseable lines (silent data loss)
5. **Pipe write fails** → unhandled force-unwrap on `line.data(using: .utf8)!` (potential crash)
6. **Shell env probe fails** → returns `nil`, falls back to `ProcessInfo.processInfo.environment` (may miss user PATH entries)
7. **CGWindowListCreateImage fails** → falls back to center-60% hit rect (graceful degradation)

### Which Parts Are Local vs Remote

| Part | Location |
|---|---|
| Hit testing, window management, animation | 100% local |
| Dock geometry calculation | 100% local (reads local defaults) |
| Theme rendering, Markdown parsing | 100% local |
| Shell PATH resolution | 100% local |
| CLI binary execution | Local process, but CLI makes remote API calls |
| AI inference | **Remote** (via CLI's own network stack) |
| Sparkle update check | **Remote** (HTTP to GitHub) |
| OpenClaw | **Remote** (WebSocket to gateway) |
