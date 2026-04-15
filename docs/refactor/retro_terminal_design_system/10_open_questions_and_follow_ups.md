# 10 — Open Questions and Follow-Ups

**Date:** 2026-04-16

## Deferred Visual Enhancements

These items were mentioned in the original specification but are not part of the current "add a preset" implementation. Each would require modifying view code and/or adding new token properties.

### 1. Scanline Texture Overlay

**Description:** A subtle CRT scanline effect drawn over the terminal body for extra retro feel.

**What's Needed:**
- New `PopoverTheme` property: `scanlineOpacity: CGFloat` (default 0 for all other themes)
- CALayer overlay in `WalkerCharacter.createPopoverWindow()` or `TerminalView` with horizontal stripe pattern
- Or: A tiling image asset (1px tall, 2px repeating: one transparent, one black at low alpha)

**Risk:** Low — purely decorative. No input/output logic affected.

### 2. Neon Glow / Outer Shadows

**Description:** Subtle neon glow around the popover window border, simulating CRT phosphor bloom.

**What's Needed:**
- New `PopoverTheme` property: `borderGlowColor: NSColor?` and `borderGlowRadius: CGFloat`
- `NSShadow` applied to the popover window's content view layer
- Care needed: borderless windows may clip outer shadows

**Risk:** Medium — shadow rendering on transparent windows can behave unexpectedly on different macOS versions.

### 3. Bracketed Status Labels

**Description:** Tool-use and status labels rendered as `[ RUNNING ]` instead of "Running", with monospaced padding.

**What's Needed:**
- New `PopoverTheme` property: `statusLabelFormat: enum { plain, bracketed }`
- Modify `TerminalView` tool-use label rendering to format strings based on theme
- Approximately 5–10 lines of view code

**Risk:** Very low.

### 4. Per-Character Tinting for Neon

**Description:** Each character (Bruce, Claude, etc.) gets a unique neon hue applied to their popover.

**What's Needed:**
- `withCharacterColor()` already exists and modifies border/accent colors, but its guard restricts it to Peach only
- Relax the guard: `name == "Peach" || name == "Neon"`
- Define character-specific neon hue mappings

**Risk:** Low — the mechanism exists. Needs color palette design.

### 5. OpenClaw Settings Panel Theming

**Description:** The `OpenClawSession` settings panel (`createSettingsPanel()`) uses some hardcoded colors that don't fully respect theme tokens.

**What's Needed:**
- Audit `OpenClawSession.createSettingsPanel()` for hardcoded `NSColor` usage
- Replace with `PopoverTheme.current` token references
- May need 1–2 new token properties for form-specific styling

**Risk:** Low. Contained to one method.

## Manual QA Checklist

The following should be verified by a human tester:

- [ ] Select Neon from Style menu → popover and terminal update immediately
- [ ] Type in the input field → cursor and text are visible
- [ ] Trigger an agent response → streaming text is readable
- [ ] Verify code blocks render with adequate contrast
- [ ] Verify tool-use labels (e.g., "Read file") are visible
- [ ] Switch from Neon to another theme → clean transition, no artifacts
- [ ] Switch back to Neon → theme restores correctly
- [ ] Quit and relaunch → Neon persists as selected theme
- [ ] Thinking bubbles are visible and readable in Neon
- [ ] Resize popover (if supported) → theme elements scale correctly
- [ ] Test on external display → colors render correctly

## Architecture Observations for Future Themes

### Strengths of Current System
- Memberwise init enforces completeness for every new theme
- Runtime switching with full window teardown guarantees clean state
- Brightness-based dark/light appearance auto-detection is elegant
- Zero view-code changes needed for new themes

### Potential Improvements
- **Theme categories**: Group themes by mood (light/dark/vibrant) in the Style menu
- **Custom theme editor**: Let users create their own themes (would need serialization)
- **Theme preview**: Show a small swatch or preview before selecting
- **Animated transitions**: Crossfade between themes instead of hard teardown/rebuild
- **Token validation**: Runtime assertion that contrast ratios meet WCAG AA

## Questions for Project Owner

1. Should Neon be the default theme for new installations, or remain opt-in?
2. Is per-character neon tinting desired? (mechanism exists, needs palette)
3. Should the scanline overlay be a separate toggle or bundled into the theme?
4. Any plans for user-customizable themes beyond the preset system?
5. Should the Neon theme have a different popover size or layout, or strictly same geometry?
