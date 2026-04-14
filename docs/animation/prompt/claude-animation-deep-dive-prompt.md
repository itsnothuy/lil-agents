# Claude Prompt: Animation System Deep Dive + Customization Guide

> Copy everything below the horizontal rule and paste it directly to Claude Code or Claude.ai.
> Claude should be given full repo access (or the relevant files listed at the bottom of the prompt).

---

You are a senior macOS Swift engineer with deep expertise in AVFoundation, Core Animation, and AppKit window management. I need you to perform a complete, production-quality technical analysis of the animation system in this macOS application and then produce a step-by-step customization guide.

## Context

This is `lil-agents` — a macOS accessory app that displays two small animated characters (Bruce and Jazz) walking back and forth above the Dock. Characters are transparent HEVC `.mov` video files played inside borderless, transparent `NSWindow`s. Position is updated every display frame by a `CVDisplayLink`. The app has no SwiftUI at runtime — it is pure AppKit + AVFoundation.

## Scope of analysis

I want you to read, trace, and explain the following **exhaustively and precisely**. Do not summarize; explain every mechanism in full technical detail.

---

### Part 1 — Video asset pipeline (how the image gets on screen)

Trace the complete path from `.mov` file on disk to rendered pixels on screen:

1. How the video asset is loaded (`AVAsset`, `AVPlayerItem`, `AVQueuePlayer`, `AVPlayerLooper`) in `WalkerCharacter.setup()`.
2. How `AVPlayerLayer` is configured — `videoGravity`, `backgroundColor`, `frame`, and why `backgroundColor` must be `.clear.cgColor` for transparency to work.
3. How `playerLayer` is added to `CharacterContentView` (which is the `contentView` of a borderless `NSWindow`).
4. Why the `NSWindow` is configured with `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`, and `level = .statusBar` — what each property controls and what breaks if you change it.
5. How `CharacterContentView.hitTest(_:)` works: the `CGWindowListCreateImage` pixel-sampling approach, the coordinate-space flip (`primaryScreen.frame.height - screenPoint.y`), the alpha threshold of `>30`, and the centre-60% bounding-rect fallback. Explain exactly why GPU-rendered `AVPlayerLayer` content cannot be sampled via `layer.render(in:)`.
6. How the video is looped seamlessly — `AVPlayerLooper` mechanism vs. notification-based manual seeking, and what the `templateItem` parameter does.
7. What happens to the video when the character is paused (walked to a stop): `queuePlayer.pause()` + `queuePlayer.seek(to: .zero)` — why seeking to zero matters for the walk-sync logic.

---

### Part 2 — Motion system (how the character moves across the Dock)

Trace the complete motion pipeline from display refresh to pixel position:

1. **CVDisplayLink tick loop** (`LilAgentsController.startDisplayLink()` → `tick()`):
   - How `CVDisplayLink` is created with `CVDisplayLinkCreateWithActiveCGDisplays`.
   - Why the callback dispatches to `DispatchQueue.main` instead of running on the display-link thread.
   - How `tick()` calls `char.update(dockX:dockWidth:dockTopY:)` for each visible character every frame.

2. **Dock geometry calculation** (`getDockIconArea(screenWidth:)`):
   - How the Dock icon area width is derived from `com.apple.dock` `UserDefaults` (`tilesize`, `persistent-apps`, `persistent-others`, `recent-apps`, `show-recents`).
   - The `slotWidth = tileSize * 1.25` formula.
   - The `dockWidth *= 1.15` fudge factor.
   - How `dockTopY` is derived from `screen.visibleFrame.origin.y`.
   - Why `NSScreen.main` must NOT be used here and what `activeScreen` does instead.

3. **Walk state machine** (`WalkerCharacter` — `isPaused`, `isWalking`, `isIdleForPopover`):
   - All three states and their legal transitions. Draw the state diagram in ASCII.
   - `enterPause()`: what it resets, how the pause duration (`5...12` seconds) is chosen.
   - `startWalk()`: how direction (`goingRight`) is chosen, how `walkEndPos` is clamped to `0...1.0`, how sibling separation (`minSeparation = 0.12`) works, and the pixel-space walk distance calculation (`walkAmountRange * 500px reference`).

4. **Trapezoidal velocity curve** (`movementPosition(at:)`):
   - The four timing parameters: `accelStart`, `fullSpeedStart`, `decelStart`, `walkStop`.
   - The mathematical derivation of peak velocity `v = 1 / (dIn/2 + dLin + dOut/2)`.
   - The four phases — pre-walk flat, ease-in quadratic, linear, ease-out quadratic — and the formula for each.
   - How `movementPosition` returns a `CGFloat` in `0...1` representing progress from `walkStartPos` to `walkEndPos`.
   - The pixel-space interpolation in `update()`: why positions are stored in pixels (`walkStartPixel`, `walkEndPixel`) rather than progress fractions, and how this keeps walk speed consistent when the screen changes mid-walk.

5. **Frame update** (`update(dockX:dockWidth:dockTopY:)`):
   - How `window.setFrameOrigin` is called every frame.
   - The `bottomPadding = displayHeight * 0.15` formula and what `yOffset` does on top of it.
   - How `currentFlipCompensation` (`flipXOffset`) corrects pixel-drift when the layer is mirrored.
   - Window z-ordering: why `sorted { $0.positionProgress < $1.positionProgress }` is used and what `NSWindow.Level.statusBar + i` achieves.

6. **Horizontal mirroring** (`updateFlip()`):
   - How `CATransform3DMakeScale(-1, 1, 1)` mirrors the layer.
   - Why `CATransaction.setDisableActions(true)` is required (prevents implicit animation on the transform change).
   - How `flipXOffset` compensates for the pixel shift introduced by the scale transform.

7. **Multi-display handling** (`activeScreen`, `shouldShowCharacters`, `DockVisibility`):
   - How the app determines which screen has the Dock.
   - `hideForEnvironment()` / `showForEnvironmentIfNeeded()`: how hidden duration is tracked and all timing references (`walkStartTime`, `pauseEndTime`, bubble expiry) are adjusted.

---

### Part 3 — Bubble and sound system

1. **Thinking bubble** (`showBubble`, `createThinkingBubble`, `updateThinkingBubble`):
   - How the bubble window is positioned relative to the character (`charFrame.midX`, `charFrame.origin.y + charFrame.height * 0.88`).
   - Dynamic width calculation from text measurement (`NSString.size(withAttributes:)`).
   - The `animatePhraseChange` fade-out/fade-in via `NSAnimationContext`.
   - Phrase rotation timing (`3...5` second random intervals).
   - The completion bubble vs. thinking bubble distinction and the 3-second expiry.

2. **Sound system** (`playCompletionSound`):
   - How sounds are selected without repeating the last one.
   - The bundle subdirectory lookup (`Sounds/ping-*.mp3`).

---

### Part 4 — Character parameters (Bruce vs. Jazz comparison)

For each of the following parameters, explain what it controls, what its valid range is, and what visual effect changing it produces:

| Parameter | Bruce | Jazz |
|---|---|---|
| `accelStart` | 3.0 | 3.9 |
| `fullSpeedStart` | 3.75 | 4.5 |
| `decelStart` | 8.0 | 8.0 |
| `walkStop` | 8.5 | 8.75 |
| `walkAmountRange` | 0.4...0.65 | 0.35...0.6 |
| `yOffset` | -3 | -7 |
| `flipXOffset` | 0 | -9 |
| `positionProgress` (initial) | 0.3 | 0.7 |
| `pauseEndTime` (initial) | 0.5...2.0 s | 8.0...14.0 s |
| `characterColor` | green | orange |
| `videoDuration` | 10.0 (default) | 10.0 (default) |

Explain why Bruce and Jazz have **different** `accelStart`/`fullSpeedStart` values even if their videos are the same duration. What would happen if both had identical parameters?

---

### Part 5 — How to add a new character

Provide a complete, step-by-step guide to adding a third character (`Pixel`) from scratch. Cover:

1. **Video file requirements**:
   - Container format (`.mov`), codec (HEVC / H.265 with alpha), resolution (aspect ratio 1080×1920 or any portrait ratio), duration, frame rate.
   - Why the background must be fully transparent (alpha=0) in every frame — what happens to click detection if it is not.
   - How to export a character video correctly from After Effects / Motion / CapCut with alpha using HEVC with alpha (`hvc1` + alpha channel).
   - Naming convention: how the video name relates to the `WalkerCharacter` initialiser parameter.

2. **Adding the asset to Xcode**:
   - Where to drag the `.mov` file in the Xcode project navigator (the `LilAgents` group, not `Resources` at the top level).
   - How to confirm `Target Membership` is checked for the `LilAgents` target.
   - Verifying `Bundle.main.url(forResource:withExtension:)` will find it.

3. **Instantiating the character** in `LilAgentsController.start()`:
   - Full code to create a `WalkerCharacter(videoName: "walk-pixel-01", name: "Pixel")`.
   - Which parameters to set and sensible default values for a third character that starts at `positionProgress = 0.5` and launches after both others.
   - How to set `characterColor`, `yOffset`, `flipXOffset` for the new character.
   - Adding it to the `characters` array and setting `controller`.

4. **Menu bar toggle**:
   - How to add a `toggleChar3` action in `AppDelegate` (mirroring `toggleChar1`/`toggleChar2`).
   - Adding the `NSMenuItem` with key equivalent `"3"` to the menu.

5. **Collision avoidance**:
   - How `minSeparation = 0.12` in `startWalk()` handles two characters. Does it scale to three? If not, what adjustment is needed?

6. **Walk timing calibration**:
   - How to frame-analyse your video to find the correct `accelStart`, `fullSpeedStart`, `decelStart`, `walkStop` values. What to look for frame-by-frame (first foot lift, peak velocity, foot plant, full stop).
   - What happens if these values are wrong (video and position out of sync).

---

### Part 6 — How to use a different character type (non-humanoid)

Explain how the animation system would accommodate each of the following alternative character types, and what code changes are required for each:

1. **Static PNG sprite** (no video, just an image that bounces or jiggles):
   - Replace `AVQueuePlayer`/`AVPlayerLayer` with `CALayer` + `CGImage`.
   - How to implement a bounce animation using `CABasicAnimation` on `transform.translation.y` on the layer.
   - Remove calls to `queuePlayer.play()`, `queuePlayer.pause()`, `queuePlayer.seek(to:)`.

2. **Sprite sheet / frame animation** (e.g., a pixel-art cat with walk cycle as a PNG strip):
   - Using `CALayer` with `contents` and a `CADisplayLink`-driven frame index.
   - How to replace `AVPlayerLayer` with a `CALayer` and update `contents` to the current frame's `CGImage` each tick.
   - How to encode the sprite sheet dimensions into the character's properties.

3. **GIF / APNG**:
   - Loading with `NSImage` (which handles APNG natively) or `ImageIO` frame extraction for GIF.
   - Embedding in an `NSImageView` in place of `playerLayer`.
   - Hit-test implications: `NSImageView` renders via the CPU so `layer.render(in:)` would work, removing the need for `CGWindowListCreateImage` pixel-sampling.

4. **Lottie / Rive animation** (vector, code-driven):
   - Adding Lottie (`lottie-spm`) or Rive (`rive-ios` with macOS target) as an SPM dependency.
   - Replacing `AVPlayerLayer` with a `LottieAnimationView`/`RiveView` hosted in the character window.
   - Driving play/pause from the same `queuePlayer.play()`/`queuePlayer.pause()` call sites.

For each type, note which parts of `WalkerCharacter` remain unchanged (the walk state machine, position update, bubble, sound, flip, hit-test fallback) and which must be replaced.

---

### Part 7 — How to customise the existing animations

For each customisation listed below, provide: what property to change, where it lives in the code, the effect, and any constraints or gotchas.

1. **Walk speed** — change how fast the character moves across the Dock without changing the video.
2. **Walk distance** — make characters walk shorter or longer steps.
3. **Pause duration** — make characters pause longer or shorter between walks.
4. **Starting position** — place a character at a specific spot on the Dock at launch.
5. **Vertical offset** — raise or lower a character relative to the Dock top edge.
6. **Character size** — add a new `CharacterSize` case (e.g. `.xlarge` with `height = 280`).
7. **Flip drift correction** — fix a character that shifts a few pixels horizontally when it turns.
8. **Walk timing parameters** — re-calibrate `accelStart`/`fullSpeedStart`/`decelStart`/`walkStop` for a new video whose walk cycle starts at a different frame.
9. **Add a new thinking phrase** — add to `WalkerCharacter.thinkingPhrases`.
10. **Add a new completion sound** — add a sound file to `LilAgents/Sounds/`, register it in `completionSounds`.
11. **Change bubble position** — move the thinking bubble from above the head to the side.
12. **Make a character idle (never walk)** — how to keep a character permanently stationary at a fixed position (useful for a "desk pet" variant).

---

### Part 8 — Known issues and engineering questions

For each issue below, diagnose the root cause from the code and propose a fix:

1. The `size` UserDefaults key stores raw value `"big"` as default, but `CharacterSize` has no case with raw value `"big"`. What does `CharacterSize(rawValue: "big") ?? .large` return, and is this a bug or intentional?
2. `soundsEnabled` is a `static var` on `WalkerCharacter` but is never written to `UserDefaults`. What is the consequence and how do you fix it?
3. `flipXOffset` for Jazz is `-9`. Where does this value come from, and how would you determine the correct value for a new video?
4. The `CVDisplayLink` callback dispatches every frame to `DispatchQueue.main`. What happens if the main thread is busy (e.g. during a popover open)? Is there a risk of frame drops or queue buildup?
5. If a user has 40 apps in their Dock, will `getDockIconArea` produce an accurate width? What breaks if the computed width is too wide or too narrow?

---

## Files to read (give Claude access to these)

```
LilAgents/WalkerCharacter.swift       (1007 lines — god object, animation core)
LilAgents/LilAgentsController.swift   (257 lines — CVDisplayLink, dock geometry, tick loop)
LilAgents/CharacterContentView.swift  (67 lines — hit testing, pixel sampling)
LilAgents/AgentSession.swift          (for CharacterSize enum context)
LilAgents/DockVisibility.swift        (multi-display logic)
LilAgents/LilAgentsApp.swift          (menu bar toggles, AppDelegate)
LilAgents/PopoverTheme.swift          (theme colours referenced in bubble/popover)
```

## Output format

- Use level-2 (`##`) headers matching the Part numbers above.
- For code references, quote the exact function or property name in backticks.
- For mathematical derivations (velocity curve), use inline LaTeX or plain algebraic notation — be precise.
- For the new-character guide (Part 5) and alternative character types (Part 6), provide runnable Swift code snippets.
- For the customisation table (Part 7), use a two-column format: **what to change** | **where and how**.
- Do not skip any sub-question. If something is ambiguous in the code, say so and propose the most likely intended behaviour.

Additionally, the final result MUST be produced as separate Markdown files (one file per Part) placed under `docs/animation/` in this repository. Use the following filenames and ensure each file contains the full content for that Part using the headers and formats requested above:

- `docs/animation/part-01-video-asset-pipeline.md`
- `docs/animation/part-02-motion-system.md`
- `docs/animation/part-03-bubble-and-sound.md`
- `docs/animation/part-04-parameter-comparison.md`
- `docs/animation/part-05-add-new-character.md`
- `docs/animation/part-06-alternative-character-types.md`
- `docs/animation/part-07-customisation-cookbook.md`
- `docs/animation/part-08-known-issues-and-questions.md`

Each Markdown file should be self-contained, include code blocks where requested, and be formatted for readability (headings, code fences, tables). Do not return a single monolithic reply — write the files directly into the `docs/animation/` folder so they can be reviewed in the repo.
