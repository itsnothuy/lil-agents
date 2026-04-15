# 09 — Rollback and Toggle Plan

**Date:** 2026-04-16

## How to Enable the Neon Theme

1. Launch Lil Agents.
2. Click the menu bar icon.
3. Go to **Style** submenu.
4. Select **"Neon"**.

The theme is applied immediately (windows are torn down and recreated). The selection persists across app launches via the UserDefaults key `selectedThemeName`.

## How to Disable the Neon Theme

Select any other theme from the Style submenu (Peach, Midnight, Cloud, or Moss). The app falls back to Peach if the stored theme name doesn't match any preset.

## How to Remove the Neon Theme Entirely

A three-line change in `PopoverTheme.swift`:

### Step 1 — Remove the preset

Delete the entire `static let retroTerminal = PopoverTheme(...)` block (approximately lines 145–178).

### Step 2 — Remove from allThemes

```swift
// Change this:
static let allThemes: [PopoverTheme] = [.playful, .teenageEngineering, .wii, .iPod, .retroTerminal]

// To this:
static let allThemes: [PopoverTheme] = [.playful, .teenageEngineering, .wii, .iPod]
```

### Step 3 — Revert the font guard

```swift
// Change this:
guard name != "Midnight" && name != "Neon" else { return self }

// To this:
guard name != "Midnight" else { return self }
```

### Step 4 — Verify

Build. Run. If a user previously had "Neon" selected, the app will fall back to `allThemes.first` (Peach) because the stored name won't match any preset.

## User Data Safety

- **UserDefaults key `selectedThemeName`**: Will contain `"Neon"` if the user had it selected. After removal, this orphaned string is harmlessly ignored — the fallback logic in `PopoverTheme.current` resolves to `allThemes.first`.
- **No migration needed**: No data files, no database, no config files to clean up.
- **No per-character impact**: Theme applies globally, not per-character. No per-character UserDefaults keys reference theme.

## Feature-Flag Alternative

If you want to keep the code but hide Neon from the UI:

```swift
// Change allThemes to exclude retroTerminal:
static let allThemes: [PopoverTheme] = [.playful, .teenageEngineering, .wii, .iPod]
```

This leaves the `static let retroTerminal` definition in place for future use but removes it from the Style menu and prevents selection. One-line change, fully reversible.

## Branching Strategy

The Neon theme was implemented directly on `main`. If isolation is desired for review:

```bash
# Create a branch from the commit before Neon was added
git checkout -b remove-neon HEAD~1

# Or cherry-pick the revert
git revert <neon-commit-sha>
```

## Summary

| Action | Lines Changed | Files | Risk |
|--------|:---:|:---:|:---:|
| Enable | 0 (menu selection) | 0 | None |
| Disable | 0 (menu selection) | 0 | None |
| Hide from UI | 1 | 1 | None |
| Full removal | ~35 deleted | 1 | None |
