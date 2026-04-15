# Debug Prompt: Character Motion Freeze — lil-agents

## Model
Claude Opus 4.5

---

## Your Role

You are a senior Swift/macOS engineer doing a **production-quality bug investigation** on a macOS AppKit application called **lil-agents**. You have full access to the codebase via `#codebase`. You will triage every item in both the runtime log and the Xcode build log, fix every real bug you find, and then produce a **fully detailed post-mortem** Markdown file at `docs/bugs/[dd-mm-yy]/` (use today's actual date in the filename).

---

## Bug Report

### Symptom

The characters' **walking animation plays** (the HEVC video loops correctly), but the characters **do not move from their position** — they stay frozen in place at their initial `positionProgress` coordinates for the entire session. This is a regression that has survived **two previous fix attempts**; treat all prior fixes as potentially incomplete or partially correct.

### Runtime Log (full, unedited)

```
AddInstanceForFactory: No factory registered for id <CFUUID 0x600002e3b160> F8BB1C28-BAE8-11D6-9C31-00039315CD46
cannot open file at line 49441 of [1b37c146ee]
os_unix.c:49441: (2) open(/private/var/db/DetachedSignatures) - No such file or directory
LoudnessManager.mm:413  PlatformUtilities::CopyHardwareModelFullName() returns unknown value: Mac16,12, defaulting hw platform key
```

### Xcode Build Log Warning (full, unedited)

```
LilAgents
/Users/tranhuy/Desktop/Code/lil-agents/LilAgents/CharacterContentView.swift
/Users/tranhuy/Desktop/Code/lil-agents/LilAgents/CharacterContentView.swift:53:25
'sampleWindowAlpha(windowID:at:)' was deprecated in macOS 14.0:
Replace with ScreenCaptureKit when a sync API is available.
```

---

## Required Investigation Steps

Work through these in order. **Do not skip any step.**

### Step 1 — Read all relevant source files

Read the following files in their entirety before forming any hypothesis:

- `#codebase` — use semantic search or direct file reads
- `LilAgents/WalkerCharacter.swift` — focus on:
  - `func update(dockX:dockWidth:dockTopY:)` — the per-frame state machine
  - `func startWalk()` — walk initiation and sibling-stagger guard
  - `func enterPause()` — pause entry
  - All state variables: `isWalking`, `isPaused`, `pauseEndTime`, `positionProgress`, `walkStartPixel`, `walkEndPixel`, `walkStartPos`, `walkEndPos`, `currentTravelDistance`
- `LilAgents/LilAgentsController.swift` — focus on:
  - `func tick()` — the CVDisplayLink callback, how `update()` is dispatched
  - `func start()` — initial `positionProgress` and `pauseEndTime` assignments
  - `getDockIconArea(screenWidth:)` — how `dockX` and `dockWidth` are calculated
- `LilAgents/CharacterContentView.swift` — the `sampleWindowAlpha` deprecation warning site
- `docs/animation/part-02-motion-system.md` — motion system architecture reference
- `docs/animation/part-08-known-issues.md` — known bugs that may be relevant
- `docs/bugs/14-04-26/character-motion-freeze.md` — previous post-mortem (session 2 fix)
- `docs/bugs/14-04-26/compiler-warnings-and-freeze-followup.md` — previous post-mortem (session 3 fix)

### Step 2 — Triage the runtime log

For each of the four runtime log lines:

1. State its origin (which Apple framework/subsystem emits it)
2. State whether it is actionable from application code
3. State your conclusion: **benign** / **needs fix** / **needs investigation**
4. If "needs fix" or "needs investigation", proceed to diagnose

### Step 3 — Triage the build warning

For the `sampleWindowAlpha` deprecation warning:

1. Confirm whether the current call site is properly isolated (check if `@available(macOS, deprecated:)` annotation is present on the function itself vs. the call site)
2. Check whether the warning is the *function definition* warning or a *call site* warning — the line number `53:25` is key
3. If the warning is genuinely suppressed correctly and the line number refers to the call site calling an annotated function, that is still a Xcode diagnostic. Determine if any additional suppression is needed, or if this is correct and expected
4. Confirm whether `SCScreenshotManager` (ScreenCaptureKit) can replace the deprecated call given that `hitTest(_:)` is a synchronous `NSView` override. Document your reasoning.

### Step 4 — Deep-dive the motion freeze

This is the primary bug. The animation plays but the characters do not move. Trace the complete execution path:

```
CVDisplayLink fires
  → DispatchQueue.main.async { controller.tick() }
    → char.update(dockX:dockWidth:dockTopY:)
      → isPaused block
        → startWalk() if timer elapsed
      → isWalking block
        → movementPosition(at:)
        → positionProgress update
        → window.setFrameOrigin()
```

For each function in this chain, verify:

1. **`tick()`**: Is `activeChars` non-empty? What filters could exclude characters? (`$0.window.isVisible && $0.isManuallyVisible`)
2. **`getDockIconArea(screenWidth:)`**: What is the actual computed `dockWidth`? What is `currentTravelDistance`? If `currentTravelDistance` is 0 or very small, `positionProgress` changes cannot produce visible movement. Trace the math: `tileSize`, `slotWidth`, `persistentApps`, `persistentOthers`, `totalIcons`, `dockWidth`. Ask: can `dockWidth` be wider than `screenWidth - displayWidth`, making `currentTravelDistance = max(dockWidth - displayWidth, 0) = 0`?
3. **`update()`**: Walk through all branches. In particular:
   - When `isPaused = true` and `now >= pauseEndTime`, does `startWalk()` actually get called?
   - After `startWalk()`, is `isPaused` actually set to `false`? Is `isWalking` set to `true`?
   - Does the re-check `if isPaused { ... return }` block ever trap a character that should be walking?
   - In the `isWalking` block: is `elapsed` computed correctly? Is `walkStartPixel` / `walkEndPixel` correctly set? Is `walkNorm` ever stuck at 0?
4. **`startWalk()` sibling guard**: The guard reads `siblings.contains { $0 !== self && $0.isWalking }`. If `controller` is `nil` (the `weak var controller` was never set, or was deallocated), the guard is skipped. But if `controller` is present, does the sibling check ever permanently prevent both characters from walking? Specifically: can character A defer because B is walking, and B defer because A is walking, creating a mutual-deferral deadlock?
5. **`movementPosition(at:)`**: Are the walk timing parameters (`accelStart`, `fullSpeedStart`, `decelStart`, `walkStop`) set to values where `movementPosition` returns meaningful non-zero deltas? Verify by tracing `char1` parameters through the piecewise function.
6. **`positionProgress` update in pixel space**: `currentPixel = walkStartPixel + (walkEndPixel - walkStartPixel) * walkNorm`. If `walkStartPixel == walkEndPixel` (walk distance collapsed to zero), `positionProgress` never changes. When can `walkEndPos == walkStartPos`? Check the sibling separation clamp at the bottom of `startWalk()`.
7. **`window.setFrameOrigin`**: Is this called on the main thread? (It is, since `tick()` dispatches to `DispatchQueue.main.async`.) But: is the window's frame ever being overwritten by another code path (e.g., `updateDimensions()` which also calls `setFrame` on a `DispatchQueue.main.async`)?

### Step 5 — Check for secondary causes

After identifying the primary freeze cause, check for secondary causes that could re-introduce the freeze:

1. Does `enterPause()` use `CACurrentMediaTime()` correctly for `pauseEndTime`? Could there be a clock source mismatch (e.g., `Date().timeIntervalSinceReferenceDate` vs `CACurrentMediaTime()`)?
2. Is `queuePlayer.seek(to: .zero)` in `enterPause()` followed by `queuePlayer.pause()` blocking frame delivery in a way that stalls the video before `startWalk()` can call `queuePlayer.play()`?
3. The `isIdleForPopover` early return at the top of `update()` — is this ever stuck `true` after a popover closes? Check `closePopover()` for whether it resets `isIdleForPopover` before or after the pause timer is set.
4. Are there any `DispatchQueue.main.async` calls in `updateDimensions()` or elsewhere that set `positionProgress` or call `window.setFrame` and could race with the display link path?

---

## Fix Requirements

### For the motion freeze (if found)

- Fix must be **minimal and surgical** — change only the lines that are wrong
- Do not restructure working code
- Do not introduce new state variables unless strictly necessary
- All scheduling logic must stay **inside `WalkerCharacter`** — the controller must only call `update()`
- After the fix, both characters must:
  - Start walking within 10 seconds of launch
  - Walk multiple times per session (pause → walk → pause cycle)
  - Never walk simultaneously (stagger must be preserved)
  - Never permanently freeze

### For the build warning

- If the warning is a call-site warning for an already-`@available`-annotated function, add `#if compiler(>=5.9)` or use a `withoutActuallyEscaping`-style trick only if genuinely needed. Prefer keeping the isolation clean.
- If the function definition is not annotated, add the `@available(macOS, deprecated: 14.0, message: "...")` annotation to the function definition, not the call site.
- Do **not** replace `CGWindowListCreateImage` with an async ScreenCaptureKit call — `hitTest(_:)` is synchronous and cannot `await`.

### For runtime log items

- Fix only items that are genuinely actionable from application code
- Do not add workarounds for system-level logs (CoreAudio, Gatekeeper, AVFoundation hardware table)

---

## Post-Mortem Requirements

After all fixes are applied, write a **fully detailed production-quality post-mortem** at:

```
docs/bugs/[dd-mm-yy]/character-motion-freeze-final.md
```

Use today's actual date (format: `DD-MM-YY`, e.g. `14-04-26`). If a `docs/bugs/[dd-mm-yy]/` directory already exists, use the same directory.

### The post-mortem must include all of the following sections:

#### 1. Header
- Date, severity, status, files changed (table)

#### 2. Background
- Brief history: session 2 fixed `tick()` death loop; session 3 restructured `update()` `isPaused` fall-through. This is session 4. Freeze persists.
- Explanation of why incremental fixes can leave latent bugs: each fix may be correct but expose the next bug in the chain.

#### 3. Runtime Log Triage
- A row-by-row table for all four log lines: message, origin framework, actionable?, conclusion.

#### 4. Build Warning Triage
- The `sampleWindowAlpha` warning: what it is, why it appears (call site vs. definition), what the correct suppression approach is, why the deprecated API cannot be replaced synchronously.

#### 5. Root Cause Analysis (the freeze)
- **Exact root cause** — the specific condition or code path that keeps `positionProgress` from changing
- **Execution trace** — step by step from `CVDisplayLink` callback through to `window.setFrameOrigin` showing where the bug manifests
- **Why previous fixes didn't catch this** — each prior fix was correct but didn't cover this specific path
- Before/after code diff (fenced Swift blocks) for every changed line

#### 6. Secondary Causes (if any found)
- Same format: root cause, execution trace, diff

#### 7. Fix Validation
- What to observe at runtime to confirm the fix works (specific, concrete observable behaviour)
- What the `positionProgress` value should do over a 30-second window

#### 8. Prevention
- Specific, actionable rules (not generic advice) derived directly from this bug
- At minimum: cover the encapsulation rule, pixel-space math validation, and mutual-deferral deadlock detection

#### 9. Summary Table
All issues found in this session: issue name, severity (Critical/High/Medium/Low), file, line(s), fix applied, status.

#### 10. Full Fix History (all sessions)
A table referencing all four post-mortems (sessions 2, 3, 4, and this one) with a one-line description of what each session fixed.

---

## Constraints

- **Read before writing**: Do not hypothesise fixes before reading the actual current source. The code may differ from what prior post-mortems describe.
- **No speculative fixes**: Only fix bugs you have confirmed by tracing the actual code.
- **No cosmetic changes**: Do not reformat, rename, or reorganise code that is not part of the bug fix.
- **No new files except the post-mortem**: Do not create documentation, READMEs, or summaries beyond the single post-mortem file requested.
- **Preserve existing post-mortems**: Do not edit `docs/bugs/14-04-26/character-motion-freeze.md` or `docs/bugs/14-04-26/compiler-warnings-and-freeze-followup.md`.
- **Swift idioms**: All fixes must be idiomatic Swift 5.9+ / macOS 14+ code.
- **Main thread safety**: Any `NSWindow` or `CALayer` mutation must remain on the main thread.

---

## Definition of Done

- [ ] All four runtime log lines triaged with documented conclusions
- [ ] Build warning triaged and handled correctly
- [ ] Motion freeze root cause identified and fixed
- [ ] Characters visibly move across the dock during a test run
- [ ] Stagger (no simultaneous walking) still works after fix
- [ ] Post-mortem written at `docs/bugs/[dd-mm-yy]/character-motion-freeze-final.md`
- [ ] Post-mortem contains all 10 required sections
- [ ] No unrelated code was modified
