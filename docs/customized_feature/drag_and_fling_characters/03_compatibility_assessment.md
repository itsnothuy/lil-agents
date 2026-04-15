# 03 — Compatibility Assessment

**Date:** 2026-04-15  
**Comparing:** PR #9 (base: ryanstephen/main) → itsnothuy/main

## File-by-File Compatibility

### `CharacterContentView.swift`

| Aspect | PR Assumes | Current Branch | Status |
|--------|-----------|----------------|--------|
| `mouseDown` body | `character?.handleClick()` | Same | ✅ Direct port |
| `KeyableWindow` class | Not present | Present (our fix) | ✅ No conflict |
| `sampleWindowAlpha` helper | Not present | Present (our fix) | ✅ No conflict |
| `hitTest` complexity | Simple | Complex pixel-sampling | ✅ No conflict |

**Verdict: Directly portable.** The PR only touches `mouseDown` and adds new methods. No conflicts.

### `ClaudeSession.swift`

| Aspect | PR Assumes | Current Branch | Status |
|--------|-----------|----------------|--------|
| Variable name | `currentStreamingResponse` | `currentResponseText` | ⚠️ Already exists |
| Type name | `Message(role:text:)` | `AgentMessage(role:text:)` | ❌ Won't compile |
| History accumulation | Missing, needs adding | Already implemented | ✅ Already done |
| `result` case logic | Needs rewrite | Already correct | ✅ Already done |

**Verdict: Not portable — already implemented.** Our branch already has the equivalent fix with `currentResponseText`. The PR would introduce a duplicate variable with a different name and use a non-existent `Message` type.

### `WalkerCharacter.swift`

| Aspect | PR Assumes | Current Branch | Status |
|--------|-----------|----------------|--------|
| Insertion point (line 105) | After `window.orderFrontRegardless()` in `setup()` | Same structure | ✅ Clean insertion |
| `update()` signature | `(dockX:dockWidth:dockTopY:)` | Same | ✅ Match |
| `update()` first line | `currentTravelDistance = max(...)` | Same | ✅ Match |
| `update()` entry after travelDistance | `if isIdleForPopover {` | Same | ✅ Match |
| `displayWidth` | Accessible | Accessible (computed) | ✅ |
| `currentFlipCompensation` | Accessible | Accessible (computed) | ✅ |
| `walkEndPixel` recompute after clamp | Not present in PR base | Present (our bug fix) | ⚠️ Minor |
| `isPaused` re-check after `startWalk()` | Not present in PR base | Present (our bug fix) | ⚠️ Minor |

**Verdict: Portable with adaptation.** The drag/fling logic ports cleanly but must be adapted for our `update()` method which has additional robustness fixes.

## Stale Assumptions

1. **`Message` type** — PR uses `Message(role: .assistant, text:)` but our codebase uses `AgentMessage`. This is a compile-time failure.
2. **ClaudeSession missing accumulator** — PR assumes the variable doesn't exist. Our branch already has it.
3. **`slideY` frozen at drag-end** — PR stores `slideY = window.frame.origin.y` at fling start and uses it throughout. If dock geometry changes during slide (e.g. dock auto-hide), the Y position becomes stale.

## Hidden Merge Hazards

1. **State overlap**: `isBeingDragged` and `isSliding` overlap with `isWalking`/`isPaused` without clear state-machine rules. The PR sets `isWalking = false; isPaused = true` in `startDrag()` but doesn't restore `isPaused = true` explicitly after slide ends — it relies on `pauseEndTime` which implicitly keeps `isPaused = true`.
2. **Velocity noise**: PR uses instantaneous velocity `(dx / dt)` which can spike wildly on a single frame with tiny dt. This causes unpredictable fling distances.
3. **Screen-edge bounce vs dock-travel bounce**: PR bounces off full screen edges (`screen.frame.origin.x` to `screen.frame.maxX`). Characters should only travel within the dock area, not fly to screen corners.

## Classification Summary

| Component | Classification |
|-----------|---------------|
| `CharacterContentView` drag input | **Directly portable** |
| `WalkerCharacter` drag state/methods | **Portable with adaptation** |
| `WalkerCharacter` slide physics in `update()` | **Portable with adaptation** (Y positioning, bounce bounds) |
| `ClaudeSession` history fix | **Not portable — already implemented** |
