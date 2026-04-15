# Post-Mortem: Characters Frozen — Animation Plays but No Movement

**Date**: 14 April 2026  
**Severity**: Critical — Primary feature (character walking) completely non-functional  
**Status**: Fixed  
**Files affected**: `LilAgents/LilAgentsController.swift`, `LilAgents/WalkerCharacter.swift`

---

## 1. Summary

Characters displayed their walking video animation correctly (the HEVC video looped) but never moved from their initial spawn position. The motion system — `CVDisplayLink` → `tick()` → `update()` → `startWalk()` — was running, but a logic error in `tick()` permanently deferred every character's walk start, causing both characters to stay frozen forever.

The other three console log messages were unrelated system noise and required no action.

---

## 2. Log Triage

### Message 1 — CoreAudio Factory (Benign)
```
AddInstanceForFactory: No factory registered for id
<CFUUID 0x6000039b2540> F8BB1C28-BAE8-11D6-9C31-00039315CD46
```
**Origin**: macOS CoreAudio HAL plugin lookup during AVFoundation audio context init.  
**Impact**: None. Same as previously documented. System fallback handles it.  
**Action**: None.

---

### Message 2 — Gatekeeper DetachedSignatures (Benign)
```
cannot open file at line 49441 of [1b37c146ee]
os_unix.c:49441: (2) open(/private/var/db/DetachedSignatures) - No such file or directory
```
**Origin**: macOS Gatekeeper SQLite database absent on this machine configuration.  
**Impact**: None. Same as previously documented.  
**Action**: None.

---

### Message 3 — LoudnessManager Hardware Model (Benign)
```
LoudnessManager.mm:413  PlatformUtilities::CopyHardwareModelFullName()
returns unknown value: Mac16,12, defaulting hw platform key
```
**Origin**: AVFoundation audio normalisation lookup table doesn't include this newer Mac model ID yet.  
**Impact**: None. Same as previously documented. Falls back to default loudness profile.  
**Action**: None.

---

### Message 4 — ViewBridge Terminated (Benign)
```
ViewBridge to RemoteViewService Terminated:
Error Domain=com.apple.ViewBridge Code=18 "(null)"
UserInfo={com.apple.ViewBridge.error.hint=this process disconnected remote view controller
-- benign unless unexpected, ...NSViewBridgeErrorCanceled}
```
**Origin**: macOS `ViewBridge` / `RemoteViewService` XPC connection teardown. This is logged when a remote view controller (used internally by system UI components) is dismissed. It is commonly triggered when a menu, popover, or system panel closes — in this case, likely from the Sparkle update check UI or a system overlay.  
**Impact**: None. The error description itself says "benign unless unexpected."  
**Action**: None.

---

## 3. The Real Bug — Character Motion Freeze

### 3.1 Symptom

Both characters displayed their looping HEVC video animation correctly (walking in-place), but neither character moved horizontally from their initial spawn position. The characters stayed frozen at `positionProgress = 0.3` (Bruce) and `positionProgress = 0.7` (Jazz) indefinitely, regardless of how long the app ran.

### 3.2 Root Cause

The bug was in `LilAgentsController.tick()`:

```swift
// BUGGY CODE — LilAgentsController.swift
let now = CACurrentMediaTime()
let anyWalking = activeChars.contains { $0.isWalking }
for char in activeChars {
    if char.isIdleForPopover { continue }
    if char.isPaused && now >= char.pauseEndTime && anyWalking {
        // ← BUG: resets pauseEndTime into the future instead of letting startWalk() run
        char.pauseEndTime = now + Double.random(in: 5.0...10.0)
    }
}
```

#### Intent

The developer intended walk staggering: if one character is already walking, delay the other from starting so they don't walk simultaneously.

#### What actually happened

On first launch:
- Both characters are `isPaused = true`
- Both have `pauseEndTime` set a few seconds in the future
- Neither is walking → `anyWalking = false`

After the initial pause elapses:
- `now >= char.pauseEndTime` → **true** for the character whose pause expired first
- `anyWalking` → **false** (nobody is walking yet)
- Condition `isPaused && now >= pauseEndTime && anyWalking` = `true && true && false` = **false**
- `tick()` doesn't reset `pauseEndTime` — good so far
- `update()` is called → calls `startWalk()` → first character starts walking ✅

One tick later:
- First character is now `isWalking = true`
- `anyWalking` → **true**
- Second character still has `isPaused = true` and `now >= char.pauseEndTime` → **true**
- Condition = `true && true && true` → **resets `pauseEndTime` 5–10 seconds into the future** ❌

After 5–10 seconds, first walk finishes, character enters pause:
- `anyWalking` → briefly **false** for exactly one tick
- That tick, `update()` tries to call `startWalk()` for both characters
- The very next tick, one character is walking again → `anyWalking = true` again
- The other character's `pauseEndTime` gets pushed forward again ❌

#### The Death Loop

```
Tick N:   char2.pauseEndTime expired, char1.isWalking=true
          → tick() resets char2.pauseEndTime += 5-10s

Tick N+M: char2.pauseEndTime expired again, char1 just finished
          → char1 enters pause, char1.isWalking=false
          → ONE TICK where anyWalking=false

Tick N+M+1: char2 calls startWalk() ✅... but char1's pauseEndTime also elapsed
            → char1 also calls startWalk() ✅
            → anyWalking=true again
            → tick() resets char2 AGAIN if char2's pause timer happened to
               expire at the same moment as char1 started

In practice: the initial pauseEndTime values are staggered (Bruce: 0.5-2s, Jazz: 8-14s).
Jazz's pauseEndTime expires many seconds after Bruce's walk starts.
tick() pushes Jazz's pauseEndTime forward by 5-10s.
This cycle repeats continuously → Jazz NEVER moves.
Bruce similarly gets caught if Jazz happens to walk when Bruce's next pause expires.
```

**Net effect**: Characters are effectively frozen at their initial positions. The video plays (the player is running), but `startWalk()` is never called so `isWalking` stays `false`, `positionProgress` never changes, and `window.setFrameOrigin()` always gets the same coordinates.

### 3.3 Why This Was Not Caught by Part 08 Known Issues

The known issues document (`part-08-known-issues.md`) covered race conditions, missing persistence, and edge-case positioning bugs — but not this logic error in the walk scheduling loop. The collision avoidance section (8.6) discussed `checkCharacterCollisions()` for 3+ characters, not the broken staggering guard in `tick()` for 2 characters. This bug would not have been visible during initial development if only one character existed at a time during testing.

---

## 4. Impact

| Area | Impact |
|------|--------|
| Core feature | 100% broken — primary character animation (movement) completely non-functional |
| Users affected | All users — both characters frozen on every launch |
| Workaround | None available to users |
| Visual confusion | Characters animate in-place (video plays), making it appear like a minor visual glitch rather than a fundamental logic failure |

---

## 5. Fix

### 5.1 `LilAgentsController.swift` — Remove the broken staggering block

The entire `anyWalking` deferral block was removed from `tick()`. It was mutating character state from outside `WalkerCharacter`, violating encapsulation and introducing the freeze bug.

**Before**:
```swift
let now = CACurrentMediaTime()
let anyWalking = activeChars.contains { $0.isWalking }
for char in activeChars {
    if char.isIdleForPopover { continue }
    if char.isPaused && now >= char.pauseEndTime && anyWalking {
        char.pauseEndTime = now + Double.random(in: 5.0...10.0)
    }
}
for char in activeChars {
    char.update(dockX: dockX, dockWidth: dockWidth, dockTopY: dockTopY)
}
```

**After**:
```swift
for char in activeChars {
    char.update(dockX: dockX, dockWidth: dockWidth, dockTopY: dockTopY)
}
```

### 5.2 `WalkerCharacter.swift` — Move staggering guard into `startWalk()`

Walk staggering (don't start if sibling is already walking) is re-implemented correctly inside `WalkerCharacter.startWalk()`. This keeps all scheduling logic inside the character itself, and — critically — performs a short **random defer** rather than replacing `pauseEndTime` with a long fixed window:

```swift
func startWalk() {
    // Don't start if a sibling is already mid-walk — stagger characters naturally.
    // We defer by a short random interval rather than mutating pauseEndTime from the
    // outside, keeping all walk-scheduling logic inside WalkerCharacter.
    if let siblings = controller?.characters {
        let siblingWalking = siblings.contains { $0 !== self && $0.isWalking }
        if siblingWalking {
            pauseEndTime = CACurrentMediaTime() + Double.random(in: 1.5...4.0)
            return
        }
    }

    isPaused = false
    isWalking = true
    // ... rest unchanged ...
}
```

### 5.3 Why this fix is correct

| Aspect | Old (broken) | New (fixed) |
|--------|--------------|-------------|
| Where staggering lives | `LilAgentsController.tick()` (external) | `WalkerCharacter.startWalk()` (internal) |
| What gets deferred | `pauseEndTime` pushed 5–10s on every tick | Deferred once by 1.5–4s at the moment of conflict |
| Re-check | Every tick → timer never expires | Next time `update()` calls `startWalk()`, sibling may have finished |
| Can it dead-loop? | Yes — repeats every tick | No — defers once, then checks fresh next time |
| Encapsulation | Breaks — controller mutates character timers | Correct — character manages its own state |

---

## 6. Testing

1. **Build and run** — both characters should begin walking within 2 seconds of launch
2. **Observe staggering** — characters should not walk simultaneously (1.5–4s gap)
3. **Long observation** — after 60+ seconds, both characters should have walked multiple times
4. **Single character** — hide Jazz via menu, confirm Bruce walks normally
5. **Popover** — click a character to open popover, other should continue walking

---

## 7. Timeline

| Time | Event |
|------|-------|
| T+0s | App launches, both characters spawn at initial positions |
| T+0.5–2s | Bruce's initial pause expires, `startWalk()` called, Bruce starts walking |
| T+1 tick | Jazz's pause timer also expired; old code resets it → Jazz frozen forever |
| T+8–14s | Jazz's initial pause expires (old code: reset again; new code: defers 1.5–4s) |
| T+12–18s | *(new code only)* Jazz's short defer expires, sibling check passes, Jazz walks |

---

## 8. Prevention

- **Encapsulation rule**: Never mutate `WalkerCharacter` timing state from `LilAgentsController`. The controller dispatches `update()` — all internal decisions (when to walk, when to pause) belong inside `WalkerCharacter`.
- **Condition audit**: Any `if A && B && C { mutate state }` pattern where one branch is `anyXxx` (global aggregate) should be carefully reviewed — it creates implicit coupling between characters that is hard to reason about.
- **Integration test**: Add a test that runs the tick loop for 30 simulated seconds and asserts that each character's `positionProgress` changes at least once.

---

## 9. Related Issues

| Issue | File | Status |
|-------|------|--------|
| This bug | `LilAgentsController.swift`, `WalkerCharacter.swift` | ✅ Fixed |
| Sound toggle not persisted | `WalkerCharacter.swift` | Open |
| Theme not persisted | `PopoverTheme.swift` | Open |
| Sparkle gentle reminders | `LilAgentsApp.swift` | ✅ Fixed (14-04-26) |
