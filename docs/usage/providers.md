# AI Providers

lil agents wraps locally-installed AI CLI tools. The app itself is free and open-source. **You pay (or don't) based on which CLI you choose.**

---

## Provider comparison

| Provider | Free tier? | Cost model | Multi-turn? | Install |
|---|---|---|---|---|
| **Claude Code** | ✅ Free tier (5 hrs/mo on Pro) | Anthropic subscription or API credits | ✅ Yes | `curl` script |
| **OpenAI Codex** | ❌ No free tier | OpenAI API credits (pay-per-token) | ⚠️ Faked (history stuffed into prompt) | npm |
| **GitHub Copilot** | ✅ Free tier (limited) | GitHub subscription ($10–$19/mo) | ✅ Yes (via `--continue` flag) | Homebrew |
| **Gemini CLI** | ✅ Free tier (Gemini 2.5 Flash, generous limits) | Google AI credits above free tier | ✅ Yes (via `--resume latest`) | npm |
| **OpenCode** | Depends on backend | Configurable LLM backend | ❌ No (single-turn only) | Binary download |
| **OpenClaw** | Self-hosted | Your own server cost | ✅ Yes | WebSocket gateway (see [openclaw.md](openclaw.md)) |

> **Cheapest option to try right now:** Gemini CLI has the most generous free tier with no credit card required.
> **Most capable free option:** Claude Code if you have an Anthropic Pro subscription.

---

## Claude Code

**Cost:** Requires an [Anthropic account](https://console.anthropic.com). Anthropic Pro ($20/mo) includes 5 hours of Claude Code usage. API-key usage is pay-per-token.

### Install

```bash
curl -fsSL https://claude.ai/install.sh | sh
```

### Authenticate

```bash
claude auth
```

Follow the browser prompt to log in. After authentication the `claude` binary is ready.

### How lil agents uses it

Claude Code runs as a **single long-lived process** per character. The process stays alive for the entire session so conversation context is retained natively. It streams responses as newline-delimited JSON (`stream-json` mode).

**Safety flags used:** `--dangerously-skip-permissions` — this bypasses Claude's file-system permission prompts. The characters will execute file operations without asking.

---

## OpenAI Codex

**Cost:** Requires an [OpenAI account](https://platform.openai.com) with API credits. No meaningful free tier — expect ~$0.01–$0.10 per message depending on model.

### Install

```bash
npm install -g @openai/codex
```

### Authenticate

```bash
export OPENAI_API_KEY="sk-..."
```

Add to your shell profile (`~/.zshrc`) so lil agents picks it up automatically.

### How lil agents uses it

A **new process is spawned per message**. Multi-turn is simulated by serializing the conversation history into the CLI prompt — it is not true session continuity.

**Safety flags used:** `--full-auto` — runs without any human confirmation prompts.

---

## GitHub Copilot CLI

**Cost:** Requires a [GitHub Copilot subscription](https://github.com/features/copilot) ($10/mo individual, $19/mo business). There is a **free tier** with limited completions.

### Install

```bash
brew install gh
gh extension install github/gh-copilot
```

> The binary lil agents looks for is `copilot` (via `gh copilot`). Make sure `gh` is on your PATH.

### Authenticate

```bash
gh auth login
```

### How lil agents uses it

A new process per message. Subsequent messages use `--continue` to resume the session. lil agents auto-detects whether the CLI returns JSON or plain text and switches modes at runtime.

**Safety flags used:** `--allow-all` — skips confirmation prompts.

---

## Gemini CLI

**Cost:** Gemini CLI uses the [Google AI free tier](https://ai.google.dev/pricing) by default (Gemini 2.5 Flash). Generous limits — most users will not hit them. No credit card required to start.

### Install

```bash
npm install -g @google/gemini-cli
```

### Authenticate — option A: Google account (interactive, no credit card)

```bash
gemini auth login
# Opens a browser — sign in with your Google account.
# Free tier is activated automatically (Gemini 2.5 Flash, generous daily limits).
```

### Authenticate — option B: API key (robust, scriptable — recommended)

1. Get a free key at [aistudio.google.com/apikey](https://aistudio.google.com/apikey) (no credit card required on the free tier).

2. Store it securely in macOS Keychain (keeps it out of plaintext files):

```bash
security add-generic-password -a "$USER" -s "gemini_api_key" -w "YOUR_KEY_HERE" -U
```

3. Add a loader to `~/.zshrc` so every login shell (and lil agents) sees the key automatically. This only needs to be done once:

```bash
cat >> ~/.zshrc <<'EOF'
# >>> lil-agents: load Gemini API key from macOS Keychain >>>
if command -v security >/dev/null 2>&1; then
  export GEMINI_API_KEY="$(security find-generic-password -a "$USER" -s "gemini_api_key" -w 2>/dev/null || true)"
fi
# <<< lil-agents: end >>>
EOF
source ~/.zshrc
```

4. Verify the key is available to login shells (this is how lil agents reads your environment):

```bash
zsh -l -i -c 'echo "$GEMINI_API_KEY" | sed -E "s/(.{4}).+(.{4})/\1...\2/"'
# Expected: AIza...xxxx  (masked)
```

5. Quick headless test to confirm Google accepts the key:

```bash
gemini -p "Hello from lil agents test" --model "gemini-2.5-flash"
# Expected: Hello! How can I help you today?
```

### How lil agents uses it

A new process per message. Subsequent messages use `--resume latest` so Gemini picks up the existing conversation. The session is the most defensively coded — it filters out spinner characters, progress indicators, and keytar errors from the output before displaying text.

**Safety flags used:** `--yolo` — disables all confirmation prompts.

---

## OpenCode

**Cost:** Depends on which LLM backend you configure in OpenCode. Can be free (local model) or paid (cloud API).

### Install

Download the binary from the [OpenCode releases page](https://github.com/sst/opencode/releases) and place it somewhere on your PATH (e.g. `/usr/local/bin/opencode`).

### Configure

Run `opencode` once to set up your backend of choice.

### How lil agents uses it

A new process per message using `opencode run <message> --format json`. **No multi-turn support** — each message is independent.

---

## Verify Gemini is working (before launching the app)

Run this one command — it simulates exactly what lil agents does at startup (spawning `zsh -l -i -c env` to capture your login shell environment):

```bash
zsh -l -i -c 'which gemini; echo "GEMINI_API_KEY set: $([ -n "$GEMINI_API_KEY" ] && echo yes || echo NO)"'
```

Expected output:
```
/opt/homebrew/bin/gemini
GEMINI_API_KEY set: yes
```

If both lines look good, lil agents will detect Gemini as available and the provider will not be greyed out in the menu.

Also do a quick headless test to confirm the API key is accepted by Google:

```bash
gemini -p "Hello from lil agents test" --model "gemini-2.5-flash"
# Expected: a short text response like "Hello! How can I help you today?"
```

---

## Switching providers

From the **menu bar icon → Provider**, select the provider you want. Only providers whose CLI is detected on your PATH appear as enabled. Providers not found are shown greyed out.

The change takes effect for the **next conversation** — if a popover is open, close it first.

---

## Checking if a provider is detected

lil agents scans these paths on launch:

- Your login shell's `$PATH` (captured by spawning `zsh -l -i -c env`)
- `~/.local/bin/<binary>`
- `/usr/local/bin/<binary>`
- `/opt/homebrew/bin/<binary>`

If the CLI is installed but greyed out, make sure it's in one of those locations or on your `$PATH` in `~/.zshrc`.
