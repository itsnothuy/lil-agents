# 05 — Design Tokens and Styling Foundation

**Date:** 2026-04-16

## Neon Theme Token Inventory

### Popover Chrome

| Token | Value | Hex | Notes |
|-------|-------|-----|-------|
| `popoverBg` | `(0.07, 0.06, 0.18, 0.97)` | `#120F2D` | Dark indigo, slight transparency |
| `popoverBorder` | `(0.31, 0.96, 0.91, 0.75)` | `#4FF6E8` @ 75% | Neon cyan border |
| `popoverBorderWidth` | `1.5` | — | Thin, precise |
| `popoverCornerRadius` | `2` | — | Nearly square, rigid geometry |

### Title Bar

| Token | Value | Hex | Notes |
|-------|-------|-----|-------|
| `titleBarBg` | `(0.11, 0.09, 0.25, 1.0)` | `#1C1840` | Slightly lighter indigo |
| `titleText` | `(0.31, 0.96, 0.91, 1.0)` | `#4FF6E8` | Cyan, matching border |
| `titleFont` | SFMono-Bold 10pt | — | Monospace, small |
| `titleFormat` | `.uppercase` | — | `"CLAUDE"` not `"claude"` |
| `separatorColor` | `#4FF6E8` @ 20% | — | Faint cyan line |

### Terminal Text

| Token | Value | Hex | Notes |
|-------|-------|-----|-------|
| `font` | SFMono-Regular 11.5pt | — | Monospace body |
| `fontBold` | SFMono-Medium 11.5pt | — | Monospace emphasis |
| `textPrimary` | `(0.95, 0.96, 1.0, 1.0)` | `#F2F4FF` | Bright white-blue |
| `textDim` | `(0.65, 0.69, 0.84, 1.0)` | `#A7B0D6` | Soft lavender |
| `accentColor` | `(0.54, 0.42, 1.0, 1.0)` | `#8A6CFF` | Purple accent |

### Status Colors

| Token | Value | Hex | Notes |
|-------|-------|-----|-------|
| `errorColor` | `(1.0, 0.23, 0.36, 1.0)` | `#FF3B5C` | Neon red |
| `successColor` | `(0.31, 0.96, 0.91, 1.0)` | `#4FF6E8` | Cyan (matches border) |

### Input Field

| Token | Value | Hex | Notes |
|-------|-------|-----|-------|
| `inputBg` | `(0.07, 0.06, 0.18, 1.0)` | `#120F2D` | Same as popover bg |
| `inputCornerRadius` | `2` | — | Square |

### Thinking Bubble

| Token | Value | Hex | Notes |
|-------|-------|-----|-------|
| `bubbleBg` | `(0.11, 0.09, 0.25, 0.95)` | `#1C1840` | Indigo surface |
| `bubbleBorder` | `#4FF6E8` @ 50% | — | Cyan, softer |
| `bubbleText` | `#A7B0D6` | — | Dim lavender |
| `bubbleCompletionBorder` | `#4FF6E8` @ 70% | — | Brighter on completion |
| `bubbleCompletionText` | `#4FF6E8` | — | Full cyan on completion |
| `bubbleFont` | System Mono 10pt medium | — | |
| `bubbleCornerRadius` | `2` | — | Square |

## Design Language Rules

1. **Surfaces are dark indigo** — never pure black, never gray
2. **Borders are neon cyan** — varying alpha for hierarchy
3. **Text is cool-toned** — white-blue primary, lavender dim
4. **Accent is purple** — used for links, tool names, interactive elements
5. **Errors are hot red** — high contrast against indigo
6. **Success is cyan** — matches the structural border language
7. **Corners are square** — radius 2px everywhere
8. **Fonts are monospace** — SF Mono for everything, custom font override disabled

## Anti-Patterns

- Do NOT use warm colors (orange, peach, cream) in this theme
- Do NOT use large corner radii (>4px)
- Do NOT use proportional/rounded system fonts
- Do NOT tint per character color (this theme has a fixed palette)
- Do NOT add glow/shadow effects at the theme-token level (they require view-level changes)

## Legacy-to-New Mapping

The mapping is 1:1 — every existing `PopoverTheme` property has a Neon value. No new properties were added. No properties were removed. The token schema is unchanged.
