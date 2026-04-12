# Chat Interface

Everything you can do once a character's popover is open.

---

## Opening and closing

- **Click a character** to open its chat popover
- **Click anywhere outside** the popover to close it
- The underlying AI session keeps running after you close — re-opening the same character resumes the conversation

---

## Sending messages

1. Click in the input field at the bottom of the popover (it auto-focuses on open)
2. Type your message
3. Press **Return** to send

There is no Shift+Return for newlines — the input is single-line. For multi-line prompts, write them as one long line or use a slash command to clear and re-ask.

---

## Slash commands

Type these in the input field and press Return:

| Command | What it does |
|---|---|
| `/clear` | Clears the visible chat history and resets the session |
| `/copy` | Copies the last AI response to the clipboard |
| `/help` | Shows a short help message listing available commands |

---

## Title bar buttons

The popover title bar (top strip) has one button:

- **Copy icon** — copies the most recent AI response to the clipboard (same as `/copy`)

---

## Themes (Style)

Switch from **menu bar → Style**. The theme affects the popover colors, font, and title formatting. It applies to both characters.

| Theme name | Vibe | Background | Accent |
|---|---|---|---|
| **Peach** | Warm / playful | Soft peach | Coral |
| **Midnight** | Dark / minimal | Deep navy | Ice blue |
| **Cloud** | Light / clean (Wii-inspired) | Off-white | Mid-grey |
| **Moss** | Muted / earthy (iPod-inspired) | Warm beige | Olive |

> Theme selection is saved and persists across relaunches.

---

## Character size

Switch from **menu bar → Size**:

| Size | Description |
|---|---|
| **Small** | Compact characters, less screen real estate |
| **Large** | Default — bigger, more expressive animations |

Size applies to both characters simultaneously.

---

## Thinking bubbles

While the AI is processing, a speech bubble appears above the character with a playful phrase (e.g. "thinking…", "on it…"). The bubble disappears when the response arrives.

---

## Completion sounds

A short sound plays when the AI finishes responding. Toggle from **menu bar → Sounds**.

> Sound state is **not** saved across relaunches — it resets to enabled every time the app starts. (Known limitation.)

---

## Markdown rendering

The chat terminal renders a subset of Markdown:

| Syntax | Rendered as |
|---|---|
| `# Heading` | Larger bold text |
| `**bold**` | Bold |
| `` `inline code` `` | Monospace highlight |
| ` ```code block``` ` | Indented monospace block |
| `- bullet` | Bullet list item |
| `[text](url)` | Clickable link |

Full Markdown (tables, images, nested lists, etc.) is **not** supported.

---

## Multi-display

If you have multiple monitors, pin the characters to a specific screen from **menu bar → Display**. The default is **Auto (Main Display)**, which follows whichever screen has the Dock.

---

## Keyboard shortcuts (menu bar)

| Shortcut | Action |
|---|---|
| `1` | Toggle Bruce |
| `2` | Toggle Jazz |

These only work when the menu is open (standard macOS menu key equivalents).
