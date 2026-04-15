# 06 — Architecture and Reversibility

**Date:** 2026-04-15

## Can This Feature Be Unplugged Cleanly?

**Answer: Easy to unplug.**

## Invasiveness Assessment

The drag/fling feature touches exactly two files:

| File | Change Type | Invasiveness |
|------|------------|-------------|
| `CharacterContentView.swift` | Replace `mouseDown` with drag-tracking trio | **Low** — replaces one method, adds two |
| `WalkerCharacter.swift` | Add drag state + methods, add early returns in `update()` | **Low** — all additions, minimal modification to existing code |

### What Existing Code Was Modified

1. **`CharacterContentView.mouseDown`** — replaced body. Original was one line: `character?.handleClick()`.
2. **`WalkerCharacter.update()`** — added three early-return blocks at the top (drag, slide) before existing logic. Existing logic unchanged.

### What Was Added (Not Modified)

1. `WalkerCharacter` drag state variables (8 properties)
2. `WalkerCharacter.startDrag()`, `trackDragVelocity()`, `endDrag()`, `syncPositionFromWindow()` (4 methods)
3. `WalkerCharacter.dragEnabled` static flag
4. `CharacterContentView` drag state variables (3 properties) + `mouseDragged()` + `mouseUp()` + threshold constant

## Feature Flag

```swift
// WalkerCharacter.swift
static var dragEnabled = true
```

When `dragEnabled = false`:
- `CharacterContentView.mouseDown` → calls `handleClick()` directly (original behavior)
- `CharacterContentView.mouseDragged` → early return (no-op)
- `CharacterContentView.mouseUp` → early return (no-op)
- `WalkerCharacter.isBeingDragged` and `isSliding` remain `false` → `update()` drag/slide blocks never execute

**The feature is completely inert when the flag is off.** No state changes, no physics, no position overrides.

## How to Disable at Runtime

```swift
WalkerCharacter.dragEnabled = false
```

This can be wired to a menu toggle, UserDefaults preference, or compile-time flag.

## How to Remove Completely

1. In `CharacterContentView.swift`: Delete lines from `// MARK: - Drag-to-reposition support` to end of file. Restore original `mouseDown`:
   ```swift
   override func mouseDown(with event: NSEvent) {
       character?.handleClick()
   }
   }
   ```
2. In `WalkerCharacter.swift`: Delete the `// MARK: - Drag & Fling Support` section (all properties and 4 methods, plus `dragEnabled`).
3. In `WalkerCharacter.update()`: Remove the `lastDockX = dockX`, `lastDockTopY = dockTopY`, drag early-return block, and slide physics block.

**Estimated effort:** 5 minutes, no risk to other functionality.

## Architecture Pattern

This implementation follows a **guarded inline pattern** — the simplest reversible approach for a small feature:

- Feature state lives on the model object (`WalkerCharacter`) where it's naturally accessed during `update()`
- Input handling lives on the view (`CharacterContentView`) where AppKit expects it
- A single static boolean gates all behavior
- No new classes, protocols, or abstractions needed

### Why Not a Separate `DragInteractionController`?

A separate controller would add:
- A new class (~80 lines)
- Delegation/callback wiring
- Lifecycle management
- Testing surface

For a feature this small (4 methods, 8 state vars, ~60 lines of logic), the overhead exceeds the benefit. The guarded inline pattern provides the same reversibility with less code.

### When to Upgrade to a Separate Controller

If any of these become true:
- A third interaction mode is added (e.g., double-tap, long-press)
- Drag behavior needs per-character customization
- Physics tuning needs runtime configuration
- The feature grows beyond ~100 lines of logic

Then extract to `CharacterInteractionController` with a `MovementStrategy` enum.

## Blunt Verdict

**Easy to unplug.** One static flag disables everything. Full removal is a 5-minute delete with no side effects.
