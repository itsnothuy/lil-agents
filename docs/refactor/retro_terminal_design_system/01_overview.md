# 01 — Overview: Retro Terminal Design System

**Date:** 2026-04-16  
**Branch:** `main` (itsnothuy/lil-agents)  
**Base commit:** `ab6c812`

## What This Is

A new visual theme ("Neon") for the lil-agents dock companion app, inspired by retro terminal / neon CRT / arcade interfaces. The theme integrates through the existing `PopoverTheme` design token system — no architectural changes required.

## Target Design Summary

| Token | Value | Purpose |
|-------|-------|---------|
| Surface dark | `#120F2D` | Popover background, input background |
| Surface | `#1C1840` | Title bar, bubble background |
| Cyan glow/border | `#4FF6E8` | Borders, separator, success, completion |
| Accent purple | `#8A6CFF` | Accent color, links, tool names |
| Alert red | `#FF3B5C` | Errors |
| Text primary | `#F2F4FF` | Main text |
| Text secondary | `#A7B0D6` | Dim text, bubble text |
| Corner radius | 2px | Square/rigid geometry |
| Fonts | SF Mono | Monospace terminal feel |
| Title format | UPPERCASE | Bracketed/rigid labels |

## Current Status

✅ **Implemented and building.** The "Neon" theme is available in the Style menu alongside existing themes (Peach, Midnight, Cloud, Moss). Users select it the same way they select any other theme. Zero behavioral changes.

## Documents in This Folder

| File | Description |
|------|-------------|
| `01_overview.md` | This file — index and summary |
| `02_repository_architecture_summary.md` | Codebase styling architecture |
| `03_migration_architecture_decision.md` | Why this approach was chosen |
| `04_migration_plan.md` | Staged rollout plan |
| `05_design_tokens_and_styling_foundation.md` | Token inventory and mapping |
| `06_component_and_view_mapping.md` | Which views consume which tokens |
| `07_validation_report.md` | Build/functional validation |
| `08_implementation_summary.md` | What changed and why |
| `09_rollback_and_toggle_plan.md` | How to enable/disable/remove |
| `10_open_questions_and_follow_ups.md` | Future improvements |

## Recommended Reading Order

1. `02_repository_architecture_summary.md` — understand why integration was trivial
2. `05_design_tokens_and_styling_foundation.md` — the token definitions
3. `08_implementation_summary.md` — what was changed (very small)
4. `09_rollback_and_toggle_plan.md` — how to disable/remove
5. `03_migration_architecture_decision.md` — architectural rationale
