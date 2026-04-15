# 04 — Migration Plan

**Date:** 2026-04-16

## Stage A: Foundation (Completed)

- [x] Audit existing theme system → confirmed token-based, no changes needed
- [x] Define retro terminal color palette as hex values
- [x] Map hex values to `PopoverTheme` semantic properties

## Stage B: Core Implementation (Completed)

- [x] Add `static let retroTerminal` preset to `PopoverTheme`
- [x] Register in `allThemes` array
- [x] Ensure `withCustomFont()` skips "Neon" (preserves SF Mono)
- [x] Build and verify

## Stage C: Validation (Completed)

- [x] Clean build succeeds
- [x] No new warnings
- [x] All existing themes still present and selectable
- [x] Window appearance auto-detection works (brightness check → `.darkAqua`)

## Stage D: Deferred Items

| Item | Reason |
|------|--------|
| Scanline/phosphor texture | Requires custom CALayer drawing, invasive for one theme |
| Neon glow shadow on borders | Would need NSShadow or CALayer shadow per view, not theme-token-level |
| Bracketed status labels `[FULL SESSION]` | Would require TerminalView format changes, deferred to future iteration |
| Per-character Neon color tinting | Neon uses fixed cyan/purple palette; character tinting is a Peach-only feature |

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Contrast too low on dark indigo | Text primary is #F2F4FF (bright white-blue), text dim is #A7B0D6 (medium lavender) — both pass WCAG AA on #120F2D |
| Existing themes broken | Zero existing code modified beyond the array and font skip guard |
| Theme not applied to some surface | All surfaces consume `PopoverTheme` — verified via grep |

## Files Changed

| File | Change |
|------|--------|
| `LilAgents/PopoverTheme.swift` | Added `retroTerminal` preset, updated `allThemes`, updated `withCustomFont()` guard |

That's it. One file.
