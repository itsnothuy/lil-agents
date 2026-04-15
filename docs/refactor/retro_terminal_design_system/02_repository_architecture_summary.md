# 02 — Repository Architecture Summary

**Date:** 2026-04-16

## UI Framework

**100% AppKit.** SwiftUI is imported only for the `@main` app entry point shell (`Settings { EmptyView() }`). All views, windows, panels, and controls are NSView/NSWindow/NSTextField/NSTextView.

## Styling Architecture

The codebase has a **centralized design token system** in `PopoverTheme.swift`:

### `PopoverTheme` Struct (32 properties)

| Category | Properties |
|----------|-----------|
| Popover chrome | `popoverBg`, `popoverBorder`, `popoverBorderWidth`, `popoverCornerRadius` |
| Title bar | `titleBarBg`, `titleText`, `titleFont`, `titleFormat`, `separatorColor` |
| Terminal text | `font`, `fontBold`, `textPrimary`, `textDim`, `accentColor` |
| Status colors | `errorColor`, `successColor` |
| Input field | `inputBg`, `inputCornerRadius` |
| Thinking bubble | `bubbleBg`, `bubbleBorder`, `bubbleText`, `bubbleCompletionBorder`, `bubbleCompletionText`, `bubbleFont`, `bubbleCornerRadius` |

### Theme Presets (Pre-existing)

| Static Name | Display Name | Character |
|-------------|-------------|-----------|
| `.playful` | "Peach" | Light, warm, rounded |
| `.teenageEngineering` | "Midnight" | Dark, orange, mono |
| `.wii` | "Cloud" | Light, blue, clean |
| `.iPod` | "Moss" | Green LCD, retro Mac |

### Theme Selection Flow

1. User selects from menu bar → Style → [theme name]
2. `AppDelegate.switchTheme()` → `PopoverTheme.current = allThemes[idx]`
3. Persisted to UserDefaults via `selectedThemeName` key
4. Theme consumed via `WalkerCharacter.resolvedTheme` / `TerminalView.theme` computed properties
5. Popover/bubble windows are torn down and recreated to apply new theme

### Theme Modifiers

- `withCharacterColor(_:)` — only applies to "Peach" theme, tints border/accent per character
- `withCustomFont()` — applies system rounded font to non-mono themes (skips "Midnight")

## Visual Surfaces (Where Tokens Are Consumed)

| Surface | File | Tokens Used |
|---------|------|-------------|
| Popover window | `WalkerCharacter.createPopoverWindow()` | All popover + title bar tokens |
| Terminal text area | `TerminalView` | font, colors, accentColor, inputBg, etc. |
| Input field | `TerminalView.setupViews()` + `PaddedTextFieldCell` | font, textPrimary, inputBg, inputCornerRadius |
| Thinking bubble | `WalkerCharacter.showBubble()` + `createThinkingBubble()` | All bubble tokens |
| Markdown rendering | `TerminalView.renderMarkdown()` | font, fontBold, textPrimary, textDim, accentColor, inputBg |
| Tool use/result | `TerminalView.appendToolUse/Result()` | fontBold, font, accentColor, textDim, errorColor, successColor |
| OpenClaw settings | `OpenClawSession.showSettingsPanel()` | None (uses system NSAlert) |
| Character window | `WalkerCharacter.setup()` | None (transparent, video layer) |
| Debug line | `LilAgentsController.setupDebugLine()` | None (hardcoded red, hidden) |

## Key Finding

**The entire visual language is already token-based.** Every styled surface reads from `PopoverTheme`. Adding a new theme is a matter of defining a new static preset and registering it in `allThemes`. No architectural changes, no view modifications, no new abstractions needed.

## Migration Seams

The migration seam is a single point: `PopoverTheme.allThemes`. Adding or removing a theme from this array is the only integration/removal step.

## Risks

| Risk | Severity | Assessment |
|------|----------|-----------|
| Token miss (some surface not themed) | Low | Grep confirms all color/font usage goes through `theme`/`resolvedTheme` |
| Dark appearance mismatch | Low | `createPopoverWindow()` uses brightness check → auto `.darkAqua` |
| Custom font override | Low | `withCustomFont()` now skips "Neon" (same as "Midnight") |
| Accessibility contrast | Medium | Must verify manually — dark indigo + dim text could be low contrast |
