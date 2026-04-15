# 04 — Functional Validation

**Date:** 2026-04-15  
**Method:** Static code analysis + architecture trace (runtime blocked: Xcode GUI needed for interactive testing)

## Validation Approach

Full interactive testing requires running the app in the GUI and physically dragging characters. This was validated through:
- Complete code path tracing through CVDisplayLink → tick() → update() → drag/slide states
- State machine analysis of all flag combinations
- Coordinate math verification
- Edge case reasoning

## A. Click Behavior

| Test | Status | Evidence |
|------|--------|----------|
| Short click opens popover | ✅ PASS | `mouseUp` calls `handleClick()` when `!isDragging` |
| No duplicate open on mouseDown | ✅ PASS | `mouseDown` only sets tracking state, never calls `handleClick()` |
| Drag does not trigger click on release | ✅ PASS | `mouseUp` checks `isDragging` before routing to `handleClick()` vs `endDrag()` |
| Tiny/shaky cursor movement | ✅ PASS | 5px threshold prevents sub-threshold movement from triggering drag |
| Feature flag off → old behavior | ✅ PASS | `mouseDown` has `guard WalkerCharacter.dragEnabled else { handleClick(); return }` |

## B. Drag Behavior

| Test | Status | Evidence |
|------|--------|----------|
| Drag begins only after threshold | ✅ PASS | `abs(dx) > 5 \|\| abs(dy) > 5` check in `mouseDragged` |
| Drag moves smoothly | ✅ PASS | `window.setFrameOrigin(startOrigin + delta)` — direct offset from start, no accumulation drift |
| No jitter/teleport | ✅ PASS | Uses `NSEvent.mouseLocation` (global coords), not relative deltas that can accumulate errors |
| Vertical movement allowed | ✅ PASS | Both dx and dy applied to window origin during drag |
| Hit testing preserved | ✅ PASS | `hitTest` is on `CharacterContentView`, unaffected by drag state |

## C. Fling Behavior

| Test | Status | Evidence |
|------|--------|----------|
| Velocity sampling reliable | ✅ PASS (improved) | Exponential smoothing (0.6/0.4 blend) reduces noise vs PR's raw instantaneous velocity |
| Slide decelerates naturally | ✅ PASS | `friction = 0.92` per frame, ~60fps → smooth exponential decay |
| Bounce at edges correct | ✅ PASS (improved) | Bounces off dock travel bounds (`dockX` to `dockX + travelDistance`), not screen edges |
| No oscillation trap | ✅ PASS | Velocity halved on bounce (`*0.5`), terminates when `abs(velocity) < 10` |
| Slide ends deterministically | ✅ PASS | `abs(slideVelocity) < 10` → `isSliding = false`, `syncPositionFromWindow()`, `pauseEndTime` set |
| Walking resumes correctly | ✅ PASS | `syncPositionFromWindow()` updates all position state, `pauseEndTime = now + 2.0` → `startWalk()` fires |

## D. Position/State Coherence

| Test | Status | Evidence |
|------|--------|----------|
| No teleport after drag | ✅ PASS | `syncPositionFromWindow()` converts window.x → `positionProgress` before walk resumes |
| Walk progress synchronized | ✅ PASS | `walkStartPixel = walkEndPixel = currentTravelDistance * positionProgress` |
| Pause/resume coherent | ✅ PASS | `isPaused = true` set in `startDrag()`, `pauseEndTime` set after slide/drop |
| No drift from repeated drags | ✅ PASS | Each drag uses absolute start position (`windowStartOrigin + delta`), not relative accumulation |

## E. Regression Checks

| Test | Status | Evidence |
|------|--------|----------|
| Normal idle walking | ✅ PASS | Drag state vars default to `false`; `update()` only enters drag/slide paths when flags are set |
| Popover/chat interactions | ✅ PASS | `handleClick()` path unchanged; drag only adds a code path before it |
| Multi-character behavior | ✅ PASS | Each `WalkerCharacter` has its own drag state; no shared mutable state |
| Dock geometry handling | ✅ PASS | `lastDockX`/`lastDockTopY` updated every `update()` call before drag check |
| ClaudeSession history | ✅ PASS | Not touched — our existing `currentResponseText` logic preserved |

## F. Edge Cases

| Test | Status | Evidence |
|------|--------|----------|
| Fling near screen edge | ✅ PASS | Clamped to `dockX` / `dockX + travelDistance`, velocity reversed |
| Drag while mid-walk | ✅ PASS | `startDrag()` sets `isWalking = false; isPaused = true; queuePlayer.pause()` |
| Drag during popover open | ⚠️ PARTIAL | If popover is open (`isIdleForPopover=true`), `update()` takes the idle path before reaching drag check. Dragging while popover is open would move window but `update()` would snap it back on next tick. **Mitigated:** `isBeingDragged` early return is before `isIdleForPopover` check. |
| Rapid click-drag-click | ✅ PASS | `mouseUp` always resets `isDragging`, `dragStartPoint`, `windowStartOrigin` |
| Low-velocity release | ✅ PASS | `abs(velocity) <= 50` → no slide, direct `syncPositionFromWindow()` |
| Repeated drags quickly | ✅ PASS | Each `mouseDown` resets all drag state cleanly |
| Multi-monitor | ⚠️ NOTE | `lastDockX` is relative to current screen from `getDockIconArea()`. Characters are constrained to the dock screen by the controller. Drag allows moving off-dock-screen temporarily but slide bounces back to dock bounds. |

## Runtime Validation Limitations

The following could not be tested without interactive GUI:
- Actual feel of drag responsiveness and smoothness
- Visual quality of fling deceleration curve
- Exact behavior of bounce at extreme velocities
- Multi-monitor drag behavior with different display scales
- Interaction with macOS Dock auto-hide animation

These should be tested manually before shipping (see `10_follow_up_test_plan.md`).
