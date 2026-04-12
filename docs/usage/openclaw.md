# OpenClaw Gateway (Advanced / Optional)

OpenClaw is a **self-hosted WebSocket gateway** that lets you plug in your own AI backend. It is entirely optional — if you are happy with Claude, Codex, Copilot, Gemini, or OpenCode, you do not need this.

---

## What it is

Instead of wrapping a local CLI binary, the OpenClaw provider connects to a WebSocket server you run yourself. That server can be backed by any model you want. It uses Ed25519 cryptographic authentication so the gateway can verify which device is connecting.

**Use it if:**
- You want to run a local model (e.g. Ollama, llama.cpp) and expose it to lil agents
- You want to use a model not supported by the other providers
- You want full control over the backend

**Skip it if:**
- You just want Claude / Gemini / Copilot — those work out of the box with their CLIs

---

## Cost

The OpenClaw provider itself is free and open-source. **You pay for whatever backend your gateway uses** — that could be $0 (local model) or whatever your cloud API costs.

---

## How it works (briefly)

1. lil agents generates an Ed25519 keypair on first use and stores it in UserDefaults (the device ID is the SHA-256 fingerprint of the public key)
2. On connection, the gateway issues a nonce challenge
3. lil agents signs the challenge with its private key and sends back a signed auth payload
4. If the signature is valid and the auth token matches, the gateway accepts the connection
5. Messages flow over WebSocket as JSON RPC calls (`chat.send`)

---

## Setup

### Step 1 — Run an OpenClaw gateway

You need a compatible WebSocket server. The protocol is the OpenClaw v3 gateway protocol. You can find a reference implementation or build your own.

At minimum the gateway must:
- Accept WebSocket connections
- Implement the nonce challenge handshake (v2 auth)
- Handle `chat.send` RPC calls
- Stream responses back as text deltas

### Step 2 — Configure lil agents

Open **menu bar → Provider → Advanced Settings…**

Fill in the four fields:

| Field | Description | Default |
|---|---|---|
| **Gateway URL** | WebSocket URL of your gateway | `ws://localhost:3001` |
| **Auth Token** | Shared secret token your gateway expects | *(empty)* |
| **Session Prefix** | Prefix for session keys (scoping) | `lil-agents` |
| **Agent ID** | Optional specific agent to target on the gateway | *(empty)* |

Click **Save**. Then switch to the **OpenClaw** provider from **menu bar → Provider → OpenClaw**.

### Step 3 — Verify

Click Bruce or Jazz. If the connection succeeds, you'll see the chat popover open normally. If it fails, you'll see an error message in the popover.

---

## Environment variable fallbacks

Instead of using the settings UI, you can set these environment variables in your shell profile (`~/.zshrc`):

```bash
export OPENCLAW_GATEWAY_URL="ws://your-server:3001"
export OPENCLAW_GATEWAY_TOKEN="your-secret-token"
```

lil agents reads these on launch and uses them as fallbacks if the UI fields are empty.

---

## Security notes

> ⚠️ **Known limitation:** The Ed25519 private key and auth token are stored in **UserDefaults**, not the macOS Keychain. This means they are accessible to any process running as your user. For a local development setup this is fine. For a production setup with a real auth token, treat it as you would any other credential in a config file.

The device ID (public key fingerprint) is safe to share — it identifies your device to the gateway but cannot be used to impersonate you.

---

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| OpenClaw greyed out in menu | Auth token field is empty — add one even if it's a placeholder |
| Connection refused | Gateway not running, or wrong URL/port |
| Auth failed | Token mismatch, or gateway not accepting the device ID |
| No response | Gateway connected but not sending text delta events |
