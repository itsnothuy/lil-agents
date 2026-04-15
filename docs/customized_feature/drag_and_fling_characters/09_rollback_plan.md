# 09 — Rollback Plan

**Date:** 2026-04-15

## Quick Disable (No Code Removal)

Set the feature flag to `false` anywhere during app initialization:

```swift
WalkerCharacter.dragEnabled = false
```

**Effect:** All drag/fling behavior becomes inert. Click behavior reverts to original (mouseDown → handleClick directly). No state changes, no physics, no position overrides. The dead code remains but has zero runtime impact.

## Full Removal

### Step 1: Revert `CharacterContentView.swift`

Delete everything from `// MARK: - Drag-to-reposition support` to the end of the file and replace with:

```swift
    override func mouseDown(with event: NSEvent) {
        character?.handleClick()
    }
}
```

### Step 2: Revert `WalkerCharacter.swift` — Drag Section

Delete the entire `// MARK: - Drag & Fling Support` section (approximately lines 235–297 in the current file). This includes:
- `static var dragEnabled`
- `isBeingDragged`, `isSliding`, `slideVelocity`, `dragVelocityX`, `lastDragX`, `lastDragTime`
- `lastDockX`, `lastDockTopY`
- `startDrag()`, `trackDragVelocity()`, `endDrag()`, `syncPositionFromWindow()`

### Step 3: Revert `WalkerCharacter.swift` — `update()` Method

In `func update(dockX:dockWidth:dockTopY:)`, remove:

1. The two lines after `currentTravelDistance = max(...)`:
   ```swift
   lastDockX = dockX
   lastDockTopY = dockTopY
   ```

2. The drag early-return block:
   ```swift
   if isBeingDragged { return }
   ```

3. The entire slide physics block:
   ```swift
   if isSliding {
       ... (entire block through closing brace and `return`)
   }
   ```

### Step 4: Build and Verify

```bash
xcodebuild -project lil-agents.xcodeproj -scheme LilAgents build
```

Expected: `BUILD SUCCEEDED` with no new warnings.

## Risk Assessment

| Rollback Step | Risk |
|--------------|------|
| Quick disable (flag) | Zero — no code changes |
| Remove CharacterContentView changes | Zero — restores one-line method |
| Remove WalkerCharacter drag section | Zero — pure deletion of additions |
| Remove update() additions | Low — must not accidentally delete existing code |

## Git Revert Alternative

If the changes were committed as a single commit, `git revert <sha>` would cleanly undo everything since the changes are additive (no complex modifications to existing logic).
