# 08 — Implementation Summary

**Date:** 2026-04-15  
**Branch:** `main` (itsnothuy/lil-agents)

## Files Changed

### 1. `LilAgents/CharacterContentView.swift`

**What changed:**
- Replaced `mouseDown(with:)` body (was `character?.handleClick()`) with drag-tracking initialization
- Added `mouseDragged(with:)` override with 5px threshold and window repositioning
- Added `mouseUp(with:)` override routing to `handleClick()` or `endDrag()`
- Added state properties: `dragStartPoint`, `windowStartOrigin`, `isDragging`, `dragThreshold`
- All new input handlers check `WalkerCharacter.dragEnabled` gate

**Why:**
- Input handling belongs in the NSView subclass where AppKit delivers mouse events
- Threshold prevents accidental drags from triggering on small cursor jitter
- Feature flag gate ensures zero behavior change when disabled

**Risk level:** Low — all additions, original click path preserved when flag is off

### 2. `LilAgents/WalkerCharacter.swift`

**What changed:**

#### Added `// MARK: - Drag & Fling Support` section (after `setup()`, before `handleClick()`)
- `static var dragEnabled = true` — master feature flag
- `isBeingDragged`, `isSliding`, `slideVelocity`, `dragVelocityX`, `lastDragX`, `lastDragTime` — drag/fling state
- `lastDockX`, `lastDockTopY` — cached dock geometry for position sync
- `startDrag()` — enters drag mode, pauses walk and video
- `trackDragVelocity()` — exponential-smoothed velocity from mouse deltas
- `endDrag()` — initiates slide or syncs position directly
- `syncPositionFromWindow()` — reverse-maps window.x to `positionProgress`

#### Modified `update(dockX:dockWidth:dockTopY:)` (Frame Update section)
- Added `lastDockX = dockX; lastDockTopY = dockTopY` at top
- Added early return `if isBeingDragged { return }` (don't fight user's drag)
- Added slide physics block `if isSliding { ... return }` with:
  - 0.92 friction per frame
  - Bounce off dock travel bounds (dockX to dockX + travelDistance)
  - Dynamic Y from current dockTopY
  - Terminates at velocity < 10

**Why each sub-change was necessary:**
- `lastDockX/Y` caching: `syncPositionFromWindow()` needs dock geometry but runs outside `update()` call
- `isBeingDragged` early return: prevents `update()` from snapping window back while user drags
- Slide physics: implements the fling deceleration and bounce behavior
- Dock-bound bounce (vs screen-edge): keeps character within the dock area where it belongs

**Risk level:** Low — all existing code paths unchanged; new code only activates when drag/slide flags are set

## What Was Intentionally NOT Changed

| File/Area | Reason |
|-----------|--------|
| `ClaudeSession.swift` | Chat-history fix already present as `currentResponseText` |
| `LilAgentsController.swift` | Tick loop, dock geometry, window level sorting — all unaffected |
| `AgentSession.swift` | Protocol unchanged |
| Walk state machine (`startWalk`, `enterPause`, `movementPosition`) | No modifications needed |
| Popover/bubble logic | Works correctly with drag — `isIdleForPopover` checked after drag/slide returns |
| Other session files | No touch needed |

## Improvements Over the Original PR

| Aspect | PR Behavior | Our Implementation |
|--------|-------------|-------------------|
| Velocity sampling | Raw instantaneous | Exponential smoothing (0.6/0.4) |
| Bounce bounds | Full screen edges | Dock travel bounds |
| Slide Y position | Frozen at fling start | Dynamic from current dockTopY |
| Video on drag | Keeps playing | Paused (`queuePlayer.pause()`) |
| Feature flag | None | `WalkerCharacter.dragEnabled` |
| ClaudeSession | Adds duplicate accumulator | Not touched (already fixed) |
