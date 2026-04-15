# Post-Mortem: Compiler Warnings, makeKeyWindow Runtime Warning & Motion Freeze Follow-up

**Date**: 2025-04-26 (Session 3)  
**Severity**: Medium (compiler warnings + runtime log noise), High (motion freeze, still present after session 2)  
**Status**: ✅ All issues resolved  
**Files changed**:
- `LilAgents/WalkerCharacter.swift`
- `LilAgents/CharacterContentView.swift`
- `LilAgents/CodexSession.swift`
- `LilAgents/OpenClawSession.swift`
- `LilAgents/TerminalView.swift`

---

## Background

Session 2 fixed the initial cause of the motion freeze: a bad stagger block in `LilAgentsController.tick()` was pushing `pauseEndTime` forward on every frame whenever any character was walking, creating a death loop where characters could never resume walking. That block was removed and the stagger logic was moved into `WalkerCharacter.startWalk()`.

This session was prompted by two observations:

1. The motion freeze was **still happening** despite session 2's fix.
2. There were **4 Xcode compiler warnings** in the build log and a new **runtime log warning** (`makeKeyWindow`) that hadn't been investigated.

---

## Issue 1: Motion Freeze — Second Root Cause

### Symptom

Characters would eventually freeze in place after the first few walk cycles. This was identical to the session 2 symptom and was confirmed still reproducible after session 2's fix was applied.

### Investigation

Session 2 fixed the `tick()` death loop correctly. But the freeze was still occurring, pointing to a second independent bug. The focus turned to `WalkerCharacter.update()` and the new stagger guard in `startWalk()`.

The session 2 stagger guard looked like:

```swift
// In startWalk()
let anyWalking = siblings.contains { $0.isWalking }
if anyWalking {
    pauseEndTime = now + Double.random(in: 1.5...4.0)
    return   // <-- defer: stays in isPaused state
}
// ... proceeds to actually start the walk
```

This is correct in isolation. But `update()` had a structural flaw in its `isPaused` branch:

```swift
// BEFORE (buggy)
if isPaused {
    if now >= pauseEndTime {
        startWalk()         // (A) if startWalk() returned early, isPaused is still true
    } else {
        // position the window
        return              // (B) only this path returned
    }
}
// Falls through to here when (A) happened:
if isWalking { ... }        // false, since we're still paused
// updateThinkingBubble() runs — but the window was never repositioned this frame
```

When `startWalk()` deferred (returned early), path **(A)** was taken. The `else` branch was skipped, so the window was never repositioned. Code then fell through to `if isWalking` (false) — meaning **no position update and no `return`** for that entire frame. The character was stuck, `isPaused` was permanently `true` (because `startWalk()` kept deferring), and the window was orphaned at whatever position it was last set.

The visual result was identical to the death-loop freeze from session 2: the character just stopped.

### Root Cause

`update()`'s `isPaused` block assumed `startWalk()` would always transition `isPaused → false`. After the session 2 stagger guard was added, `startWalk()` could now return early while leaving `isPaused = true`. The `update()` code had no fallback path that handled this new state.

### Fix

Restructured the `isPaused` block to re-check `isPaused` after calling `startWalk()`, ensuring every code path in the paused state writes a position and returns cleanly:

```swift
// AFTER (fixed)
if isPaused {
    if now >= pauseEndTime {
        startWalk()
    }
    // Re-check isPaused: startWalk() may have returned early (sibling walking)
    if isPaused {
        let x = dockX + travelDistance * positionProgress + currentFlipCompensation
        let y = dockTopY - bottomPadding + yOffset
        window.setFrameOrigin(NSPoint(x: x, y: y))
        return
    }
}
if isWalking { ... }
```

Both paths — "deferred by stagger guard" and "truly paused, timer not yet elapsed" — now converge on the same position-and-return block.

### Lesson

When a callee can now fail silently (return without performing its primary effect), every caller that assumed it always succeeded must be audited. The session 2 fix was correct but introduced a new precondition on `update()` that `update()` itself was not aware of.

---

## Issue 2: `makeKeyWindow` Runtime Warning (3×)

### Symptom

Runtime log emitted the following three times at launch:

```
[Window] Warning: Window NSWindow 0x... is being asked to become the key window before it has a valid key view loop. [...]
```

### Investigation

Searched for all `makeKey` / `makeFirstResponder` call sites:

```
LilAgentsController.swift: popoverWindow?.makeKey()
WalkerCharacter.swift:     char.popoverWindow?.makeKey()
```

Both calls target `popoverWindow`, which is already `KeyableWindow` — the custom subclass that overrides `canBecomeKey = true`. That was not the source.

The warning is emitted for the window that is being made key, but the AppKit key-window machinery also touches *other* windows during its loop. Specifically, when AppKit scans the window list to find a valid key window, any `NSWindow` that doesn't override `canBecomeKey` can trigger this warning.

The character window (`self.window` inside `WalkerCharacter`) was created as:

```swift
// BEFORE
let win = NSWindow(
    contentRect: ...,
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
```

Plain `NSWindow` does not override `canBecomeKey`, so its default returns `false` and AppKit emits the warning when it is encountered during key-window resolution.

### Fix

Changed the character window to `KeyableWindow` — the same subclass already used for popup windows:

```swift
// AFTER
let win = KeyableWindow(
    contentRect: ...,
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
```

`KeyableWindow` is defined in `CharacterContentView.swift`:

```swift
class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
```

### Lesson

Any `NSWindow` visible on screen that might be touched by AppKit's key-window machinery should override `canBecomeKey`. Always use the project's `KeyableWindow` for borderless/transparent windows.

---

## Issue 3: `CGWindowListCreateImage` Deprecation Warning

### Symptom

Xcode build warning:

```
'CGWindowListCreateImage' was deprecated in macOS 14.0: 
Use ScreenCaptureKit instead.
```

### Context

The call lives in `CharacterContentView.hitTest()`, which must be synchronous. The replacement API, `SCScreenshotManager`, is entirely async and cannot be used in a synchronous `NSView` override. The deprecated call must be intentionally retained.

### Fix

Extracted the deprecated call into a standalone private helper function annotated with `@available`:

```swift
@available(macOS, deprecated: 14.0, message: "Replace with ScreenCaptureKit when a sync API is available.")
private func sampleWindowAlpha(windowID: CGWindowID, at cgPoint: CGPoint) -> UInt8 {
    guard let image = CGWindowListCreateImage(
        CGRect(x: cgPoint.x - 1, y: cgPoint.y - 1, width: 3, height: 3),
        .optionIncludingWindow,
        windowID,
        [.boundsIgnoreFraming, .bestResolution]
    ) else { return 0 }
    // ... pixel sampling ...
}
```

The `hitTest()` call site is clean:

```swift
override func hitTest(_ point: NSPoint) -> NSView? {
    // ...
    let alpha = sampleWindowAlpha(windowID: CGWindowID(windowID), at: cgPoint)
    return alpha > 30 ? self : nil
}
```

The warning is now isolated to one documented location. The annotation serves as both a compiler suppressor and a TODO marker for when a sync ScreenCaptureKit API becomes available.

### Lesson

Never scatter `@available` suppressions across call sites. Isolate deprecated usage into a single helper so the intent is documented in exactly one place.

---

## Issue 4: Unused Variable Binding in `CodexSession.swift`

### Symptom

Xcode warning: *`'cached' was defined but never used`*

### Location

`CodexSession.swift`, binary-path check:

```swift
// BEFORE
if let cached = Self.binaryPath {
    return cached    // ← wait, was this even returning cached?
}
```

Actually the branch just fell through — `cached` was bound but its value was never used in the branch body.

### Fix

```swift
// AFTER
if Self.binaryPath != nil {
    // branch body (early return)
}
```

---

## Issue 5: Never-Mutated Variable in `OpenClawSession.swift`

### Symptom

Xcode warning: *`Variable 'c' was never mutated; consider changing to 'let' constant`*

### Location

`OpenClawSession.swift`, config creation:

```swift
// BEFORE
var c = OpenClawConfig(...)
c.save()
```

`c` is created, `save()` is called, and then `c` is never modified.

### Fix

```swift
// AFTER
let c = OpenClawConfig(...)
c.save()
```

---

## Issue 6: Unused Write to `codeBlockLang` in `TerminalView.swift`

### Symptom

Xcode warning: *`Immutable value 'codeBlockLang' was never used`* (or similar write-only variable warning)

### Location

`TerminalView.swift`, markdown code-fence parser:

```swift
// BEFORE
var codeBlockLang = ""
// ...
} else {
    codeBlockLang = String(line.dropFirst(3))
}
```

`codeBlockLang` is assigned but never read. It was originally intended for syntax highlighting but was never wired up.

### Fix

```swift
// AFTER
// Language tag captured here; reserved for future syntax highlighting
_ = String(line.dropFirst(3))
```

The `_ =` pattern explicitly discards the value while preserving the intent comment.

---

## Benign Runtime Logs (No Action Taken)

The following logs appeared in every session and were confirmed non-actionable:

| Log fragment | Source | Why benign |
|---|---|---|
| `AddInstanceForFactory: F8BB1C28` | CoreAudio HAL | Normal plugin registration at launch |
| `DetachedSignatures` in `os_unix.c` | Gatekeeper SQLite | Normal code-signature DB query |
| `LoudnessManager Mac16,12` | AVFoundation | Hardware loudness table lookup |
| `ViewBridge Terminated Code=18` | XPC | Normal XPC session teardown |

These are system-level logs emitted by Apple frameworks and are not actionable from application code.

---

## Summary Table

| # | Issue | Severity | File | Fix |
|---|---|---|---|---|
| 1 | Motion freeze (update fall-through) | High | `WalkerCharacter.swift` | Re-check `isPaused` after `startWalk()` call |
| 2 | `makeKeyWindow` warning (3×) | Medium | `WalkerCharacter.swift` | Character window → `KeyableWindow` |
| 3 | `CGWindowListCreateImage` deprecation | Low | `CharacterContentView.swift` | Isolated into `@available`-annotated helper |
| 4 | Unused binding `cached` | Low | `CodexSession.swift` | `if let` → `if != nil` |
| 5 | `var c` never mutated | Low | `OpenClawSession.swift` | `var` → `let` |
| 6 | `codeBlockLang` unused write | Low | `TerminalView.swift` | `_ =` with comment |

---

## Prevention

1. **Callee contract changes require caller audit.** When `startWalk()` gained a new early-return path (session 2), `update()` should have been checked immediately for all callers that assumed `startWalk()` always committed.

2. **Use project window type consistently.** `KeyableWindow` exists precisely for borderless windows. The project should have a lint rule or comment in `setup()` that makes this expectation explicit.

3. **Deprecation isolation.** Deprecated API usage should live in a single annotated helper, never scattered inline. This makes future migration easier and suppression intentional.

4. **Write-only variables.** Variables assigned but never read should either be removed or replaced with `_ =` plus a comment explaining future intent. Do not let them accumulate.

---

## Related Post-Mortems

- [Session 1 — Sparkle Gentle Reminders](./sparkle-gentle-reminders.md)
- Session 2 — Motion Freeze (initial `tick()` death loop) — no separate file; covered in the session 1 post-mortem notes
