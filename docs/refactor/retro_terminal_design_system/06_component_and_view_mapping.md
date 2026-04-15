# 06 — Component and View Mapping

**Date:** 2026-04-16

## How Each Visual Surface Consumes the Theme

### Popover Window (`WalkerCharacter.createPopoverWindow()`)

| UI Element | Token(s) | Neon Result |
|-----------|----------|-------------|
| Window background | `popoverBg` → `container.layer.backgroundColor` | Dark indigo |
| Window border | `popoverBorder` → `container.layer.borderColor` | Cyan glow |
| Border width | `popoverBorderWidth` → `container.layer.borderWidth` | 1.5pt |
| Corner radius | `popoverCornerRadius` → `container.layer.cornerRadius` | 2px (square) |
| Window appearance | Brightness auto-detect → `.darkAqua` | Dark mode scrollbars/selection |
| Title bar bg | `titleBarBg` → `titleBar.layer.backgroundColor` | Lighter indigo |
| Title text | `titleText` + `titleFont` + `titleFormat` | Cyan SF Mono UPPERCASE |
| Separator | `separatorColor` → `sep.layer.backgroundColor` | Faint cyan line |
| Title bar buttons | `titleText.withAlphaComponent(0.75)` | Dim cyan |

### Terminal Text Area (`TerminalView`)

| UI Element | Token(s) | Neon Result |
|-----------|----------|-------------|
| Body text | `textPrimary` + `font` | White-blue SF Mono |
| User message prompt `>` | `accentColor` + `fontBold` | Purple bold mono |
| Streaming assistant text | `textPrimary` + `font` | White-blue mono |
| Tool use label | `accentColor` + `fontBold` | Purple `BASH`, `READ`, etc. |
| Tool use detail | `textDim` + `font` | Lavender |
| Tool result success | `successColor` + `fontBold` | Cyan `DONE` |
| Tool result error | `errorColor` + `fontBold` | Red `FAIL` |
| Error text | `errorColor` + `font` | Red |
| Inline code | `accentColor` + `inputBg` (background) | Purple on dark indigo |
| Code blocks | `textPrimary` + `inputBg` (background) | White on dark indigo |
| Links | `accentColor` + underline | Purple underlined |
| Session marker `✦ new session` | `accentColor` + `font` | Purple |
| Slash command success | `successColor` + `font` | Cyan |
| Slash command error | `errorColor` + `font` | Red |
| Help text headers | `accentColor` + `fontBold` | Purple bold |

### Input Field (`TerminalView.setupViews()` + `PaddedTextFieldCell`)

| UI Element | Token(s) | Neon Result |
|-----------|----------|-------------|
| Text color | `textPrimary` | White-blue |
| Background | `inputBg` via `PaddedTextFieldCell.fieldBackgroundColor` | Dark indigo |
| Corner radius | `inputCornerRadius` via `PaddedTextFieldCell.fieldCornerRadius` | 2px |
| Placeholder | `textDim` + `font` | Lavender "Ask Claude..." |
| Insertion point | `textPrimary` (via `insertionPointColor`) | White-blue cursor |

### Thinking Bubble (`WalkerCharacter.showBubble()` + `createThinkingBubble()`)

| UI Element | Token(s) | Neon Result |
|-----------|----------|-------------|
| Background | `bubbleBg` → `container.layer.backgroundColor` | Indigo |
| Border (thinking) | `bubbleBorder` → `container.layer.borderColor` | Cyan @ 50% |
| Border (completion) | `bubbleCompletionBorder` | Cyan @ 70% |
| Text (thinking) | `bubbleText` + `bubbleFont` | Lavender |
| Text (completion) | `bubbleCompletionText` | Full cyan |
| Corner radius | `bubbleCornerRadius` → `container.layer.cornerRadius` | 2px |

### Surfaces NOT Themed (Correct)

| Surface | Why |
|---------|-----|
| Character window | Transparent — video layer only |
| Debug line | Hidden in production, hardcoded red |
| Menu bar icon | System icon asset |
| OpenClaw settings panel | Uses `NSAlert` — system-styled, not theme-aware |
| Menu bar dropdown | System `NSMenu` — not customizable |

## Deferred Items

| Item | Why Deferred |
|------|-------------|
| OpenClaw settings panel | Uses `NSAlert` which is system-styled; theming would require replacing with custom `NSWindow` |
| Neon glow/shadow on borders | Requires `CALayer.shadowColor`/`shadowRadius` — view-level, not token-level |
| Scanline overlay | Would require custom `CALayer` subclass in `TerminalView` |
| Bracketed status labels | Would require format changes in `TerminalView.appendToolUse()` etc. |
