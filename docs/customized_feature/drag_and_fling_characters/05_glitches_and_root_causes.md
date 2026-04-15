# 05 — Glitches and Root Causes

**Date:** 2026-04-15  
**Context:** The repo owner commented "This is fun, but a little glitchy in practice." This document analyzes the root causes of those glitches in the original PR and documents which were fixed in our re-implementation.

## Defect List (Original PR)

### 1. Velocity Noise → Unpredictable Fling Distance

**Severity:** UX Issue  
**Status:** Fixed in re-implementation  

**Root Cause:** PR uses raw instantaneous velocity: `dragVelocityX = (currentX - lastDragX) / CGFloat(dt)`. On frames where `dt` is tiny (e.g., 0.002s), a 1px mouse movement produces velocity of 500 px/s. On frames where `dt` is normal (0.016s), the same 1px gives 62 px/s.

**Effect:** Fling distance is highly dependent on the exact timing of the last few mouse events before release. The user experiences inconsistent fling behavior — sometimes a gentle drag produces a huge fling, sometimes a fast drag produces almost none.

**Fix:** Exponential smoothing with `dragVelocityX = dragVelocityX * 0.6 + instantVelocity * 0.4`. This weights recent history more than a single sample.

---

### 2. Screen-Edge Bounce → Character Flies Off Dock Area

**Severity:** Correctness Bug  
**Status:** Fixed in re-implementation  

**Root Cause:** PR bounces off full screen edges:
```swift
let minX = screen.frame.origin.x
let maxX = screen.frame.origin.x + screen.frame.width - displayWidth
```

Characters are supposed to walk on the dock. The dock occupies roughly the center ~70% of the screen. Bouncing off screen edges allows the character to slide far outside the dock area, appearing to "fly off" into corners.

**Fix:** Bounce off dock travel bounds:
```swift
let minX = dockX
let maxX = dockX + currentTravelDistance
```

---

### 3. Frozen Y Position During Slide

**Severity:** UX Issue  
**Status:** Fixed in re-implementation  

**Root Cause:** PR captures `slideY = window.frame.origin.y` at fling start and uses it throughout the slide:
```swift
window.setFrameOrigin(NSPoint(x: newX, y: slideY))
```

If the dock position changes during slide (e.g., dock auto-show/hide, screen resize), the character's Y position becomes stale and the character floats above or below the dock.

**Fix:** Compute Y from current `dockTopY` every frame:
```swift
let bottomPadding = displayHeight * 0.15
let y = dockTopY - bottomPadding + yOffset
window.setFrameOrigin(NSPoint(x: newX, y: y))
```

---

### 4. Video Not Paused on Drag Start

**Severity:** UX Issue  
**Status:** Fixed in re-implementation  

**Root Cause:** PR's `startDrag()` sets `isWalking = false` but does not call `queuePlayer.pause()`. The walking animation continues playing while the character is being dragged, which looks wrong — the character appears to be walking in place while being moved.

**Fix:** Added `queuePlayer.pause()` to `startDrag()`.

---

### 5. Type Name Mismatch → Compile Failure

**Severity:** Correctness Bug (would not compile)  
**Status:** N/A — ClaudeSession changes not ported (already implemented)  

**Root Cause:** PR uses `Message(role: .assistant, text:)` but the codebase uses `AgentMessage(role: .assistant, text:)`.

---

### 6. Duplicate Streaming Accumulator

**Severity:** Architectural Smell  
**Status:** N/A — ClaudeSession changes not ported  

**Root Cause:** PR adds `currentStreamingResponse` to ClaudeSession, but the current branch already has `currentResponseText` doing the same job. Porting would create two accumulators with different names, both appending in the same handler.

---

### 7. No Feature Flag / No Way to Disable

**Severity:** Maintainability Risk  
**Status:** Fixed in re-implementation  

**Root Cause:** PR's drag behavior is always active with no way to disable it without code changes. If drag introduces issues for some users, there's no kill switch.

**Fix:** Added `static var dragEnabled = true` on `WalkerCharacter`. `CharacterContentView` checks this flag — when false, falls back to original click-only behavior.

---

## Severity Summary

| # | Defect | Severity | Fixed? |
|---|--------|----------|--------|
| 1 | Velocity noise | UX Issue | ✅ Exponential smoothing |
| 2 | Screen-edge bounce | Correctness Bug | ✅ Dock-travel bounds |
| 3 | Frozen slideY | UX Issue | ✅ Dynamic Y calculation |
| 4 | Video not paused | UX Issue | ✅ Added `queuePlayer.pause()` |
| 5 | Type mismatch | Compile Error | N/A (not ported) |
| 6 | Duplicate accumulator | Architectural Smell | N/A (not ported) |
| 7 | No feature flag | Maintainability Risk | ✅ `dragEnabled` static flag |
