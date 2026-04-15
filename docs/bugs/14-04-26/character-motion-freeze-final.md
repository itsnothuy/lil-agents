# Post-Mortem: Character Motion Freeze — Session 4 (Final)

**Date**: 14 April 2026  
**Severity**: Critical — Primary feature (character walking) completely non-functional  
**Status**: ✅ Fixed  

| File | Change |
|------|--------|
| `LilAgents/LilAgentsController.swift` | Fixed `getDockIconArea()` — replaced `double(forKey:)` / `bool(forKey:)` with `object(forKey:)` to correctly detect missing keys |
| `LilAgents/LilAgentsController.swift` | Fixed `dockAutohideEnabled()` — same `object(forKey:)` pattern |
| `LilAgents/WalkerCharacter.swift` | Fixed `startWalk()` — recompute `walkEndPixel` after separation clamp |

---

## 1. Background

This is the **fourth** debugging session for the motion freeze bug. Each session found and fixed a genuine bug, but the freeze persisted because multiple independent bugs were stacked:

| Session | Bug found | Fix |
|---------|-----------|-----|
| Session 2 | `tick()` death loop — `anyWalking` guard pushed `pauseEndTime` forward every frame | Removed broken staggering block from `tick()`, moved stagger into `startWalk()` |
| Session 3 | `update()` fall-through — `startWalk()` deferral left `isPaused=true` with no position/return path | Restructured `isPaused` block to re-check after `startWalk()` |
| **Session 4** | **`getDockIconArea()` returns `dockWidth ≈ 13.8` → `travelDistance = 0` → all pixel-space movement collapses to zero** | **Replace `double(forKey:)` / `bool(forKey:)` with `object(forKey:)` for correct nil detection** |

Each prior fix was correct and necessary. But the motion was never tested in isolation from the dock geometry calculation, so the zero-travel-distance condition masked all motion — even after the scheduling logic was fixed perfectly.

### Why incremental fixes didn't catch this

Sessions 2 and 3 focused on the walk scheduling state machine (`isPaused` / `isWalking` transitions). The state machine was genuinely broken and the fixes were correct. But even with a perfect state machine, if `currentTravelDistance = 0`, the walk interpolation produces:

```
currentPixel = walkStartPixel + (walkEndPixel - walkStartPixel) × walkNorm
            = 0 + (0 - 0) × walkNorm
            = 0
```

`positionProgress` never changes. The character walks in place.

---

## 2. Runtime Log Triage

| # | Message | Origin | Actionable? | Conclusion |
|---|---------|--------|-------------|------------|
| 1 | `AddInstanceForFactory: No factory registered for id F8BB1C28...` | CoreAudio HAL | No | **Benign** — normal plugin lookup at AVFoundation audio init |
| 2 | `cannot open file ... DetachedSignatures` | Gatekeeper SQLite | No | **Benign** — DB absent on this machine config |
| 3 | `LoudnessManager Mac16,12 ... unknown value` | AVFoundation | No | **Benign** — hardware loudness table missing newer Mac model, falls back to default |

All three are identical to prior sessions. No new warnings. No action needed.

---

## 3. Build Warning Triage

### `sampleWindowAlpha(windowID:at:)` deprecation — Line 53:25

**What it is**: The Xcode warning fires at the **call site** in `hitTest(_:)` (line 53), not at the function definition (line 19). The function `sampleWindowAlpha` is already annotated with `@available(macOS, deprecated: 14.0, message: "...")` — this is working as designed.

**Why the call-site warning still appears**: Swift emits a deprecation warning at every call site of an `@available(deprecated:)` function. The caller (`hitTest`) is not itself deprecated, so the warning persists. This is by design — Swift wants you to know you're calling deprecated code.

**Can it be suppressed further?** The only clean approach would be to annotate `hitTest` itself as deprecated, which is semantically wrong. The current isolation (one annotated helper, one call site) is the correct architecture.

**Can ScreenCaptureKit replace it?** No. `SCScreenshotManager.captureSampleBuffer` is async-only. `hitTest(_:)` is a synchronous `NSView` override called by AppKit's event delivery machinery — it cannot `await`. The deprecated call must be retained until Apple provides a synchronous ScreenCaptureKit capture path.

**Conclusion**: Expected warning. Current suppression approach is correct. No change needed.

---

## 4. Root Cause Analysis — The Freeze

### 4.1 Exact Root Cause

`getDockIconArea(screenWidth:)` reads `tilesize` from `com.apple.dock` UserDefaults:

```swift
// BEFORE (broken)
let tileSize = CGFloat(dockDefaults?.double(forKey: "tilesize") ?? 48)
```

On macOS, when the user has **never manually changed the Dock icon size**, the `tilesize` key **does not exist** in `com.apple.dock.plist`. The system uses its built-in default (48 points) without writing it to the plist.

The problem is a Swift `Optional` chain subtlety:

1. `dockDefaults` is `UserDefaults?` — it's non-nil (the suite exists)
2. `dockDefaults?.double(forKey: "tilesize")` — the optional chain unwraps `dockDefaults`, then calls `double(forKey:)`
3. `UserDefaults.double(forKey:)` returns `Double` (non-optional). When the key is missing, it returns `0.0`
4. The optional chain wraps this as `Optional(0.0)` — **not** `nil`
5. `?? 48` — the nil-coalescing operator sees `Optional(0.0)`, which is NOT nil
6. Result: `tileSize = 0.0`

The same bug affects `show-recents`:

```swift
// BEFORE (broken)
let showRecents = dockDefaults?.bool(forKey: "show-recents") ?? true
```

When the key is absent: `bool(forKey:)` returns `false` → `Optional(false)` → `?? true` doesn't fire → `showRecents = false`.

### 4.2 Execution Trace

```
CVDisplayLink fires on background thread
  → DispatchQueue.main.async { controller.tick() }
    → getDockIconArea(screenWidth: 1470)
      → tileSize = 0.0          ← BUG: should be 48
      → slotWidth = 0.0 × 1.25 = 0.0
      → totalIcons = 26         (25 apps + 1 other + 0 recent)
      → dockWidth = 0.0 × 26 + 1 × 12.0 = 12.0
      → dockWidth *= 1.15 = 13.8
    → char.update(dockX: 728.1, dockWidth: 13.8, dockTopY: 57.0)
      → currentTravelDistance = max(13.8 - 112.5, 0) = 0.0
      → [paused] → startWalk()
        → walkStartPixel = 0.3 × 0.0 = 0.0
        → walkEndPixel = 0.58 × 0.0 = 0.0
      → [walking]
        → walkNorm = 0.34 (correct, time is advancing)
        → currentPixel = 0.0 + (0.0 - 0.0) × 0.34 = 0.0
        → if travelDistance > 0 → FALSE → positionProgress NOT UPDATED
        → x = 728.1 + 0.0 × 0.3 = 728.1 (CONSTANT)
        → window.setFrameOrigin(728.1, ...) — same position every frame
```

**Debug output confirming the bug** (captured during investigation):

```
[tick] screenWidth=1470.0 dockX=728.1 dockWidth=13.8 dockTopY=57.0
[Bruce] startWalk: posProgress=0.3 travelDist=0.0
[Bruce] walk pixel range: 0.0 → 0.0, walkEndPos=0.0
[Bruce] walking: elapsed=3.50 walkNorm=0.0342 posProgress=0.3000 pixel=0.0 travelDist=0.0
[Bruce] walking: elapsed=6.00 walkNorm=0.5385 posProgress=0.3000 pixel=0.0 travelDist=0.0
[Bruce] enterPause: posProgress=0.3 nextWalkIn=10.7s
```

`walkNorm` advances correctly (0.03 → 0.54 → 1.0) — the timing curve works. But `pixel=0.0` and `travelDist=0.0` means all movement collapses to zero.

**Debug output after fix**:

```
[VERIFY] dockWidth=2042.4 travelDist≈1929.9
```

### 4.3 Why Previous Fixes Didn't Catch This

Sessions 2 and 3 diagnosed the **scheduling** bugs (when does `startWalk()` fire? does `update()` handle deferral?). Those bugs were real and were correctly fixed. But neither session checked whether the **geometry** input to the walk system was valid. The scheduling was broken AND the geometry was broken — two independent bug classes producing the same symptom.

With `travelDistance = 0`:
- The scheduling bugs were invisible (whether `startWalk()` fires or not, movement is zero)
- Fixing the scheduling made it correct but still produced zero movement
- Only fixing the geometry reveals whether the scheduling is actually working

This is a classic **stacked-bug** scenario where fixing the top bug exposes (or in this case, is masked by) a lower bug.

---

## 5. Secondary Bug — `walkEndPixel` Not Recomputed After Separation Clamp

### Root Cause

In `startWalk()`, the pixel endpoints were computed **before** the separation clamp:

```swift
// BEFORE
walkStartPixel = walkStartPos * currentTravelDistance
walkEndPixel = walkEndPos * currentTravelDistance    // uses PRE-clamp walkEndPos

// Separation clamp modifies walkEndPos here...
for sibling in siblings where sibling !== self {
    if abs(walkEndPos - sibPos) < minSeparation {
        walkEndPos = max(walkStartPos, sibPos - minSeparation)  // walkEndPos changed!
    }
}
// walkEndPixel is NEVER recomputed — uses stale value
```

### Impact

When the separation clamp activates (characters walking toward each other):
- `walkEndPos` is clamped to avoid overlap
- But `walkEndPixel` still has the original, larger value
- The character walks to the **original** unclamped destination in pixel space
- Characters can overlap despite the clamp logic

Conversely, `walkEndPos` is stored for future reference (used when entering pause), so the stored progress and actual pixel position diverge.

### Fix

Added `walkEndPixel = walkEndPos * currentTravelDistance` after the clamp loop:

```swift
// AFTER
walkStartPixel = walkStartPos * currentTravelDistance
walkEndPixel = walkEndPos * currentTravelDistance    // initial computation

// Separation clamp
for sibling in siblings where sibling !== self { ... }

// Recompute pixel endpoint after separation clamp may have changed walkEndPos
walkEndPixel = walkEndPos * currentTravelDistance
```

---

## 6. Fix Details

### Primary Fix — `getDockIconArea()` (LilAgentsController.swift)

**Before**:
```swift
let tileSize = CGFloat(dockDefaults?.double(forKey: "tilesize") ?? 48)
// ...
let showRecents = dockDefaults?.bool(forKey: "show-recents") ?? true
```

**After**:
```swift
let tileSize: CGFloat = {
    if let val = dockDefaults?.object(forKey: "tilesize") as? Double, val > 0 {
        return CGFloat(val)
    }
    return 48
}()
// ...
let showRecents: Bool = {
    if let val = dockDefaults?.object(forKey: "show-recents") as? Bool {
        return val
    }
    return true  // macOS default: show recents
}()
```

`object(forKey:)` returns `Any?` — it returns **actual `nil`** when the key is missing, unlike `double(forKey:)` which returns `0.0` wrapped in `Optional`.

### Secondary Fix — `dockAutohideEnabled()` (LilAgentsController.swift)

Same pattern. Previously correct by accident (`false` is the right default for `autohide`), but fixed for consistency:

**Before**:
```swift
return dockDefaults?.bool(forKey: "autohide") ?? false
```

**After**:
```swift
return dockDefaults?.object(forKey: "autohide") as? Bool ?? false
```

### Tertiary Fix — `walkEndPixel` recomputation (WalkerCharacter.swift)

**Before** (after separation clamp loop):
```swift
        }
    }

    updateFlip()
```

**After**:
```swift
        }
    }

    // Recompute pixel endpoint after separation clamp may have changed walkEndPos
    walkEndPixel = walkEndPos * currentTravelDistance

    updateFlip()
```

---

## 7. Fix Validation

### What to observe at runtime

1. **Both characters move** — within 10 seconds of launch, Bruce begins walking horizontally across the Dock. Jazz follows after 8-14 seconds.
2. **Walk distance is visible** — characters traverse a significant portion of the Dock width (200-325 pixels per walk).
3. **Stagger works** — characters never walk simultaneously. When one finishes, the other starts 1.5-4 seconds later.
4. **Multiple cycles** — over 60 seconds, each character should complete at least 2 walk cycles.
5. **Separation maintained** — characters should not walk through each other (the clamp fix ensures pixel endpoints match the clamped progress).

### Expected `positionProgress` over 30 seconds

```
T+0s:   Bruce=0.30, Jazz=0.70                    (initial positions)
T+1s:   Bruce=0.30  (paused, waiting)             Jazz=0.70
T+2s:   Bruce starts walking                      Jazz=0.70
T+5s:   Bruce≈0.45  (mid-walk)                    Jazz=0.70
T+12s:  Bruce≈0.58  (walk done, enters pause)     Jazz=0.70
T+14s:  Bruce=0.58  (paused)                      Jazz starts walking
T+19s:  Bruce=0.58                                Jazz≈0.50
T+24s:  Bruce=0.58                                Jazz≈0.42
T+25s:  Bruce=0.58                                Jazz enters pause
T+30s:  Bruce starts second walk                  Jazz=0.42
```

---

## 8. Prevention

1. **Never use `double(forKey:)` / `bool(forKey:)` / `integer(forKey:)` through an optional chain when nil-coalescing with `??`.** These methods return non-optional values (0, false, 0). Through an optional chain, they become `Optional(0)` / `Optional(false)` — never `nil` — defeating the `??` fallback. Always use `object(forKey:) as? Type` when the key might not exist.

2. **Validate geometry inputs before using them in motion calculations.** Add an assertion or floor: `assert(currentTravelDistance > 0, "Zero travel distance — Dock geometry invalid")`. A zero or negative `travelDistance` makes all pixel-space math degenerate.

3. **Test with default macOS settings.** The bug was invisible to anyone who had manually set their Dock icon size (which writes `tilesize` to the plist). It only affected users with a fresh or unmodified Dock config — ironically, the most common case.

4. **Separation clamp must update pixel endpoints.** Any code that modifies `walkEndPos` must also update `walkEndPixel`. These two values are derived from the same source and must stay in sync.

---

## 9. Summary Table

| # | Issue | Severity | File | Lines | Fix | Status |
|---|-------|----------|------|-------|-----|--------|
| 1 | `getDockIconArea` returns `tileSize=0` due to `double(forKey:)` through optional chain | **Critical** | `LilAgentsController.swift` | 104-135 | Use `object(forKey:) as? Double` | ✅ Fixed |
| 2 | `show-recents` same `bool(forKey:)` bug → `false` instead of `true` | **High** | `LilAgentsController.swift` | 129-134 | Use `object(forKey:) as? Bool` | ✅ Fixed |
| 3 | `dockAutohideEnabled` same pattern (correct by accident) | **Low** | `LilAgentsController.swift` | 153 | Use `object(forKey:) as? Bool` for consistency | ✅ Fixed |
| 4 | `walkEndPixel` not recomputed after separation clamp | **Medium** | `WalkerCharacter.swift` | 904-906 | Added recomputation line | ✅ Fixed |
| 5 | `sampleWindowAlpha` deprecation warning | **Cosmetic** | `CharacterContentView.swift` | 53 | Expected call-site warning; no change needed | ✅ No action |
| 6-8 | Runtime log lines (CoreAudio, Gatekeeper, AVFoundation) | **Benign** | — | — | System noise, not actionable | ✅ No action |

---

## 10. Full Fix History

| Session | Date | Post-Mortem File | Primary Fix |
|---------|------|------------------|-------------|
| 2 | 14 Apr 2026 | `character-motion-freeze.md` | Removed `anyWalking` death loop from `tick()`, moved stagger into `startWalk()` |
| 3 | 14 Apr 2026 | `compiler-warnings-and-freeze-followup.md` | Restructured `update()` `isPaused` block to handle `startWalk()` deferral; fixed 4 compiler warnings; fixed `makeKeyWindow` |
| **4** | **14 Apr 2026** | **`character-motion-freeze-final.md`** | **Fixed `getDockIconArea()` UserDefaults `Optional` chain bug → `tileSize=0` → `travelDistance=0`; fixed `walkEndPixel` clamp desync** |
