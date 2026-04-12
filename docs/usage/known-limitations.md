# Known Limitations & Gotchas

Things that currently don't work the way you might expect.

---

## Behavior quirks

### Sound state resets on every launch
"Sounds" is toggled on by default every time lil agents starts. If you always want sounds off, you'll need to toggle it each launch. This is a known bug — the preference is not saved.

### Sessions keep running in the background
Closing the chat popover does **not** stop the AI process. If you asked a long question and close the popover, the CLI is still running. Re-open the same character to see the result. To stop it: **menu bar → Quit** (restarts everything) or use `/clear` before closing.

### Provider switch doesn't apply mid-session
Changing the provider from the menu bar resets the session for the *next* conversation. If a popover is open when you switch, close and reopen it.

### Size default may appear as "Large" even if you didn't set it
The size preference defaults to Large on every launch if it has never been explicitly saved. This is expected.

### Characters may not appear if the Dock is hidden
If your macOS Dock is set to "automatically hide and show", the characters anchor to the Dock's resting position and may appear at the bottom edge of the screen. They walk fine but can look a bit cramped.

---

## Provider-specific limitations

### Codex — multi-turn is simulated
Codex CLI doesn't have native session continuity. lil agents fakes it by bundling the full conversation history into each new prompt. This means very long conversations will eventually hit CLI argument length limits or become slow.

### OpenCode — single turn only
Each message you send to OpenCode is independent. The assistant has no memory of the previous message. Use it for one-shot questions only.

### Gemini — heavy stderr filtering
The Gemini CLI emits a lot of terminal UI noise (spinners, progress dots, keytar errors). lil agents filters most of it, but occasionally a stray character or line may appear in the chat output.

### Copilot — format auto-detection
Copilot CLI may output JSON or plain text depending on version. lil agents detects which mode at runtime and switches automatically. If the first message comes back garbled, try `/clear` and re-ask — this resets the format detection.

---

## What it cannot do (yet)

- **No file/project context** — you can't drag a file in or point it at a directory from the UI. To give a file as context, reference its path in your message and rely on the AI CLI's own file-reading abilities.
- **No image input** — text only.
- **No conversation history persistence** — closing and reopening the character starts a fresh session every time (except Claude Code, which retains context within a single long-lived process).
- **No custom system prompt from the UI** — you can't set a persistent system prompt through the app. Some CLIs accept one as a flag; that would need to be done at the CLI level.
- **No resize** — the popover is fixed at 420×310 px.
- **No search in chat history** — you can scroll, that's it.
- **No copy of individual messages** — only the last response can be copied (via `/copy` or the title bar button).

---

## If a provider is greyed out

The provider's CLI was not found on your PATH at launch time. Check:

1. Is the CLI installed? Run `which claude` (or `codex`, `copilot`, `gemini`, `opencode`) in Terminal.
2. Is it on your PATH in `~/.zshrc`? lil agents reads your login shell environment.
3. Did you install it after launching lil agents? Restart lil agents — it only scans PATH once on startup.
