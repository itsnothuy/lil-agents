# 03 — Migration Architecture Decision

**Date:** 2026-04-16

## Chosen Architecture

**Add a new PopoverTheme preset.** No new abstractions, no new patterns, no adapters, no feature flags beyond the existing theme selection mechanism.

## Why This Approach

The codebase already has a production-quality theme system:

1. **Centralized tokens** — `PopoverTheme` struct with 32 semantic properties
2. **Multiple presets** — 4 existing themes prove the pattern works
3. **Runtime toggle** — users switch themes from the menu bar, persisted in UserDefaults
4. **Instant apply** — `switchTheme()` tears down and recreates styled windows
5. **No scattered literals** — all visual surfaces read from the theme struct

Adding yet another abstraction layer (adapter, strategy, environment provider, feature flag system) on top of this would be overengineering. The existing pattern is the correct pattern.

## Questions Answered

### Should this be a centralized token/theme refactor, a view-wrapper refactor, or a mixed strategy?

**Centralized token addition only.** The token system already exists. No views need wrapping — they already consume tokens.

### Is an adapter pattern appropriate here?

**No.** An adapter would add indirection with no benefit. `PopoverTheme` IS the adapter — it already adapts between design intent and AppKit rendering.

### Is a runtime toggle feasible?

**Yes, it already exists.** The Style menu in the menu bar is a runtime toggle. Selecting "Neon" enables the retro design. Selecting any other theme disables it. No additional toggle mechanism needed.

### What is the smallest safe rollout unit?

**One static constant and one array entry in `PopoverTheme.swift`.** That's it. The new theme definition + adding it to `allThemes`.

### How easy will this be to unplug later?

**Trivial.** Delete the `retroTerminal` static and remove it from `allThemes`. If any user had it selected, `PopoverTheme.current` falls back to `.playful` (first in `allThemes`).

## Reversibility Verdict

**Easy to unplug.**

Why: The theme is a self-contained data definition. It doesn't modify any view code, doesn't add new abstractions, doesn't change any method signatures, doesn't touch behavioral logic. It's a single struct value in an array.

## Tradeoffs

| Decision | Tradeoff | Justification |
|----------|---------|---------------|
| No separate glow/shadow layer | Subtle CRT glow effect not implemented | The existing `popoverBorder` with alpha handles the visual, adding NSShadow/CALayer glow would require view-level changes for one theme |
| No scanline texture | Phosphor texture not implemented | Would require custom drawing in TerminalView, not justified for a theme option |
| Square corners (radius=2 not 0) | Not perfectly square | radius=0 looks harsh on macOS; 2px provides the rigid feel without clipping artifacts |
| No custom bitmap font | Uses SF Mono instead of pixel font | Custom font requires bundling, licensing, fallback handling; SF Mono delivers the monospace terminal feel reliably |
