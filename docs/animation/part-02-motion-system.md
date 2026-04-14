# Part 2 — Motion System

> How the character moves across the Dock: from display refresh to pixel position.

---

## 2.1 CVDisplayLink Tick Loop

### Creating the Display Link

```swift
private func startDisplayLink() {
    CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
    guard let displayLink = displayLink else { return }

    let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
        let controller = Unmanaged<LilAgentsController>.fromOpaque(userInfo!).takeUnretainedValue()
        DispatchQueue.main.async {
            controller.tick()
        }
        return kCVReturnSuccess
    }

    CVDisplayLinkSetOutputCallback(displayLink, callback,
                                   Unmanaged.passUnretained(self).toOpaque())
    CVDisplayLinkStart(displayLink)
}
```

### How CVDisplayLink Works

`CVDisplayLink` is a Core Video API that synchronises callbacks to the display's vertical sync (VSync) signal. On a 60 Hz display, the callback fires approximately every 16.67 ms; on a 120 Hz ProMotion display, every 8.33 ms.

| Function | Purpose |
|----------|---------|
| `CVDisplayLinkCreateWithActiveCGDisplays` | Creates a display link that fires on whichever display is currently active (has the mouse cursor or keyboard focus). |
| `CVDisplayLinkSetOutputCallback` | Registers the callback function to be invoked each frame. |
| `CVDisplayLinkStart` | Begins the callback loop. |

### Why Dispatch to Main Queue?

```swift
DispatchQueue.main.async {
    controller.tick()
}
```

The `CVDisplayLinkOutputCallback` runs on a **high-priority background thread** managed by Core Video. However:

1. **All AppKit/UIKit operations must happen on the main thread.** This includes `window.setFrameOrigin`, `window.orderFrontRegardless`, and any layer modifications.
2. **Dispatching to main is the only safe way** to update UI from the callback.

### Frame Drop Risk

If the main thread is busy (e.g., during popover rendering), `DispatchQueue.main.async` queues the `tick()` call. If multiple frames pile up:

- The queue grows (memory pressure)
- When the main thread becomes free, it executes all queued ticks rapidly (animation speeds up briefly then normalises)

This is generally acceptable for this app because:
- The main thread is rarely blocked for more than 1–2 frames
- The walk animation is slow enough that a few dropped frames are imperceptible

---

## 2.2 Dock Geometry Calculation

```swift
private func getDockIconArea(screenWidth: CGFloat) -> (x: CGFloat, width: CGFloat) {
    let dockDefaults = UserDefaults(suiteName: "com.apple.dock")
    let tileSize = CGFloat(dockDefaults?.double(forKey: "tilesize") ?? 48)
    let slotWidth = tileSize * 1.25

    var persistentApps = dockDefaults?.array(forKey: "persistent-apps")?.count ?? 0
    var persistentOthers = dockDefaults?.array(forKey: "persistent-others")?.count ?? 0

    if persistentApps == 0 && persistentOthers == 0 {
        persistentApps = 5
        persistentOthers = 3
    }

    let showRecents = dockDefaults?.bool(forKey: "show-recents") ?? true
    let recentApps = showRecents ? (dockDefaults?.array(forKey: "recent-apps")?.count ?? 0) : 0
    let totalIcons = persistentApps + persistentOthers + recentApps

    var dividers = 0
    if persistentApps > 0 && (persistentOthers > 0 || recentApps > 0) { dividers += 1 }
    if persistentOthers > 0 && recentApps > 0 { dividers += 1 }
    if showRecents && recentApps > 0 { dividers += 1 }

    let dividerWidth: CGFloat = 12.0
    var dockWidth = slotWidth * CGFloat(totalIcons) + CGFloat(dividers) * dividerWidth

    dockWidth *= 1.15  // Fudge factor for edge padding
    let dockX = (screenWidth - dockWidth) / 2.0
    return (dockX, dockWidth)
}
```

### Reading Dock Preferences

The Dock stores its configuration in `com.apple.dock.plist`. Key values:

| Key | Type | Meaning |
|-----|------|---------|
| `tilesize` | Double | Icon size in points (default 48, range 16–128) |
| `persistent-apps` | Array | Apps pinned to the left side of the Dock |
| `persistent-others` | Array | Files/folders pinned to the right side |
| `recent-apps` | Array | Recently used apps (shown if `show-recents` is true) |
| `show-recents` | Bool | Whether to show recent apps section |
| `autohide` | Bool | Whether Dock auto-hides |

### Slot Width Formula

```swift
let slotWidth = tileSize * 1.25
```

Each Dock icon occupies more space than its rendered size due to:
- Padding between icons
- Hover magnification headroom

The `1.25` multiplier is empirically derived. It's an approximation — the actual Dock layout is more complex and includes animation-dependent spacing.

### Fudge Factor

```swift
dockWidth *= 1.15
```

This adds 15% extra width to account for:
- Edge padding at the Dock's left and right ends
- The Dock's rounded end caps
- Running app indicators (dots below icons)

### Dock Position (dockTopY)

```swift
dockTopY = screen.visibleFrame.origin.y
```

`NSScreen.visibleFrame` excludes the menu bar and Dock. Its `origin.y` is the Y-coordinate just above the Dock. This is where character windows should sit.

### Why Not Use NSScreen.main?

```swift
// WRONG:
let screen = NSScreen.main
```

`NSScreen.main` returns the screen with keyboard focus, which changes when clicking on different displays. If a user clicks on a secondary monitor, `NSScreen.main` switches to that monitor — but the Dock may still be on the primary monitor. Using `NSScreen.main` would cause characters to jump between screens or disappear.

Instead, `activeScreen` finds the screen that actually has the Dock:

```swift
var activeScreen: NSScreen? {
    if pinnedScreenIndex >= 0, pinnedScreenIndex < NSScreen.screens.count {
        return NSScreen.screens[pinnedScreenIndex]
    }
    if let dockScreen = NSScreen.screens.first(where: { screenHasDock($0) }) {
        return dockScreen
    }
    // Fallback to primary screen
    if let primaryScreen = NSScreen.screens.first(where: { $0.visibleFrame.maxY < $0.frame.maxY }) {
        return primaryScreen
    }
    return NSScreen.screens.first
}
```

---

## 2.3 Walk State Machine

### States

| State | `isPaused` | `isWalking` | `isIdleForPopover` | Description |
|-------|-----------|-------------|-------------------|-------------|
| **Paused** | `true` | `false` | `false` | Character standing still, video paused at frame 0 |
| **Walking** | `false` | `true` | `false` | Character moving, video playing |
| **Idle for Popover** | `true` | `false` | `true` | Character stopped with popover open |

### State Diagram (ASCII)

```
                    ┌─────────────────────────────────────┐
                    │                                     │
                    ▼                                     │
              ┌──────────┐    pauseEndTime elapsed   ┌────┴─────┐
    ──────────│  PAUSED  │ ─────────────────────────▶│ WALKING  │
    (initial) └──────────┘                           └────┬─────┘
                    ▲                                     │
                    │         videoDuration elapsed       │
                    └─────────────────────────────────────┘
                    
                    │                                     ▲
              click │                                     │ click or
                    ▼                                     │ outside click
              ┌───────────────┐                           │
              │ IDLE_FOR_     │───────────────────────────┘
              │ POPOVER       │
              └───────────────┘
```

### Transition Details

**Paused → Walking** (`startWalk()`):
- Triggered when `CACurrentMediaTime() >= pauseEndTime`
- Sets `isPaused = false`, `isWalking = true`
- Chooses walk direction and endpoint
- Starts video playback: `queuePlayer.play()`

**Walking → Paused** (`enterPause()`):
- Triggered when `elapsed >= videoDuration`
- Sets `isWalking = false`, `isPaused = true`
- Pauses video: `queuePlayer.pause()`, `queuePlayer.seek(to: .zero)`
- Schedules next walk: `pauseEndTime = CACurrentMediaTime() + Double.random(in: 5.0...12.0)`

**Any → Idle for Popover** (`openPopover()`):
- Triggered by user click on character
- Sets `isIdleForPopover = true`, `isWalking = false`, `isPaused = true`
- Pauses video: `queuePlayer.pause()`, `queuePlayer.seek(to: .zero)`
- Opens popover window

**Idle for Popover → Paused** (`closePopover()`):
- Triggered by clicking outside or pressing Escape
- Sets `isIdleForPopover = false`
- Schedules next walk: `pauseEndTime = CACurrentMediaTime() + Double.random(in: 2.0...5.0)`

---

## 2.4 Trapezoidal Velocity Curve

The `movementPosition(at:)` function maps video time to walk progress using a trapezoidal velocity profile:

```swift
func movementPosition(at videoTime: CFTimeInterval) -> CGFloat {
    let dIn = fullSpeedStart - accelStart       // Acceleration duration
    let dLin = decelStart - fullSpeedStart      // Constant speed duration
    let dOut = walkStop - decelStart            // Deceleration duration
    let v = 1.0 / (dIn / 2.0 + dLin + dOut / 2.0)  // Peak velocity

    if videoTime <= accelStart {
        return 0.0
    } else if videoTime <= fullSpeedStart {
        let t = videoTime - accelStart
        return CGFloat(v * t * t / (2.0 * dIn))
    } else if videoTime <= decelStart {
        let easeInDist = v * dIn / 2.0
        let t = videoTime - fullSpeedStart
        return CGFloat(easeInDist + v * t)
    } else if videoTime <= walkStop {
        let easeInDist = v * dIn / 2.0
        let linearDist = v * dLin
        let t = videoTime - decelStart
        return CGFloat(easeInDist + linearDist + v * (t - t * t / (2.0 * dOut)))
    } else {
        return 1.0
    }
}
```

### Timing Parameters

| Parameter | Bruce | Jazz | Meaning |
|-----------|-------|------|---------|
| `accelStart` | 3.0 | 3.9 | Video time (seconds) when character starts moving |
| `fullSpeedStart` | 3.75 | 4.5 | Video time when acceleration ends, constant speed begins |
| `decelStart` | 8.0 | 8.0 | Video time when deceleration begins |
| `walkStop` | 8.5 | 8.75 | Video time when character stops completely |

### Velocity Derivation

The total distance travelled must equal 1.0 (normalised). The distance under a trapezoidal velocity curve is:

$$
\text{Distance} = \frac{d_{in}}{2} \cdot v + d_{lin} \cdot v + \frac{d_{out}}{2} \cdot v = v \left( \frac{d_{in}}{2} + d_{lin} + \frac{d_{out}}{2} \right)
$$

Setting Distance = 1 and solving for $v$:

$$
v = \frac{1}{\frac{d_{in}}{2} + d_{lin} + \frac{d_{out}}{2}}
$$

### Four Phases

**Phase 1: Pre-walk (0 to `accelStart`)**
- Position: 0.0
- Character is standing still, video shows idle frames

**Phase 2: Acceleration (`accelStart` to `fullSpeedStart`)**
- Quadratic ease-in: $p(t) = \frac{v \cdot t^2}{2 \cdot d_{in}}$
- Character accelerates from 0 to peak velocity $v$

**Phase 3: Linear (`fullSpeedStart` to `decelStart`)**
- Constant velocity: $p(t) = \text{easeInDist} + v \cdot t$
- Character moves at constant speed

**Phase 4: Deceleration (`decelStart` to `walkStop`)**
- Quadratic ease-out: $p(t) = \text{easeInDist} + \text{linearDist} + v \cdot (t - \frac{t^2}{2 \cdot d_{out}})$
- Character decelerates from $v$ to 0

**Phase 5: Post-walk (`walkStop` to `videoDuration`)**
- Position: 1.0
- Character is standing still again

### Velocity Profile Visualisation

```
Velocity
    ▲
  v │    ┌──────────────────────┐
    │   ╱                        ╲
    │  ╱                          ╲
    │ ╱                            ╲
  0 └──────────────────────────────────▶ Time
    0   accelStart  fullSpeedStart  decelStart  walkStop
        ├─── dIn ───┼───── dLin ────┼─── dOut ──┤
```

---

## 2.5 Frame Update

```swift
func update(dockX: CGFloat, dockWidth: CGFloat, dockTopY: CGFloat) {
    currentTravelDistance = max(dockWidth - displayWidth, 0)
    
    // ... state handling ...

    if isWalking {
        let elapsed = now - walkStartTime
        let videoTime = min(elapsed, videoDuration)
        let travelDistance = currentTravelDistance

        let walkNorm = elapsed >= videoDuration ? 1.0 : movementPosition(at: videoTime)
        let currentPixel = walkStartPixel + (walkEndPixel - walkStartPixel) * walkNorm

        if travelDistance > 0 {
            positionProgress = min(max(currentPixel / travelDistance, 0), 1)
        }

        let x = dockX + travelDistance * positionProgress + currentFlipCompensation
        let bottomPadding = displayHeight * 0.15
        let y = dockTopY - bottomPadding + yOffset
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
```

### Pixel-Space Interpolation

Walk distance is stored in pixels, not progress fractions:

```swift
walkStartPixel = walkStartPos * currentTravelDistance
walkEndPixel = walkEndPos * currentTravelDistance
```

This ensures consistent walk speed when the screen changes mid-walk. If the user moves a window that triggers a Dock resize, or switches to a different display:

- **Progress-based**: Walk speed would suddenly change (wider Dock = faster perceived speed)
- **Pixel-based**: Walk speed stays constant, progress is recalculated from pixel position

### Position Calculation

```swift
let x = dockX + travelDistance * positionProgress + currentFlipCompensation
let y = dockTopY - bottomPadding + yOffset
```

| Component | Purpose |
|-----------|---------|
| `dockX` | Left edge of Dock icon area |
| `travelDistance * positionProgress` | Horizontal offset within Dock |
| `currentFlipCompensation` | Corrects for mirroring pixel shift (see §2.6) |
| `dockTopY` | Y-coordinate at top of Dock |
| `bottomPadding` | 15% of character height, sinks character into Dock slightly |
| `yOffset` | Per-character vertical adjustment |

### Window Z-Ordering

```swift
let sorted = activeChars.sorted { $0.positionProgress < $1.positionProgress }
for (i, char) in sorted.enumerated() {
    char.window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + i)
}
```

Characters are z-ordered by horizontal position: the leftmost character is at the back, the rightmost at the front. This creates a subtle 2.5D depth effect where characters can walk "in front of" or "behind" each other.

---

## 2.6 Horizontal Mirroring

```swift
func updateFlip() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    if goingRight {
        playerLayer.transform = CATransform3DIdentity
    } else {
        playerLayer.transform = CATransform3DMakeScale(-1, 1, 1)
    }
    playerLayer.frame = CGRect(x: 0, y: 0, width: displayWidth, height: displayHeight)
    CATransaction.commit()
}
```

### Transform Explanation

`CATransform3DMakeScale(-1, 1, 1)` mirrors the layer horizontally:
- X-axis scale: -1 (flip horizontally)
- Y-axis scale: 1 (no change)
- Z-axis scale: 1 (no change)

This makes the character face left when walking left.

### Why `CATransaction.setDisableActions(true)`?

Core Animation implicitly animates property changes. Without disabling actions, the transform change would animate over 0.25 seconds, causing the character to "spin" when changing direction. `setDisableActions(true)` makes the change instantaneous.

### Flip Offset Compensation

```swift
var flipXOffset: CGFloat = 0  // Bruce
var flipXOffset: CGFloat = -9 // Jazz

var currentFlipCompensation: CGFloat {
    goingRight ? 0 : flipXOffset
}
```

When a layer is mirrored around its centre, the rendered content shifts slightly if the visual centre of the character doesn't align with the layer centre. `flipXOffset` compensates for this shift.

For Jazz, `flipXOffset = -9` means the character shifts 9 points to the left when mirrored. The compensation adds those 9 points back to keep the character's feet in the same position.

---

## 2.7 Multi-Display Handling

### Finding the Active Screen

```swift
var activeScreen: NSScreen? {
    if pinnedScreenIndex >= 0, pinnedScreenIndex < NSScreen.screens.count {
        return NSScreen.screens[pinnedScreenIndex]
    }
    if let dockScreen = NSScreen.screens.first(where: { screenHasDock($0) }) {
        return dockScreen
    }
    if let primaryScreen = NSScreen.screens.first(where: { $0.visibleFrame.maxY < $0.frame.maxY }) {
        return primaryScreen
    }
    return NSScreen.screens.first
}
```

Priority order:
1. **User-pinned screen**: If `pinnedScreenIndex >= 0`, always use that screen
2. **Dock screen**: Find the screen whose `visibleFrame` indicates Dock presence
3. **Primary screen**: The screen with the menu bar (identified by `visibleFrame.maxY < frame.maxY`)
4. **First screen**: Fallback

### Hiding During Environment Changes

```swift
func hideForEnvironment() {
    guard environmentHiddenAt == nil else { return }

    environmentHiddenAt = CACurrentMediaTime()
    wasPopoverVisibleBeforeEnvironmentHide = popoverWindow?.isVisible ?? false
    wasBubbleVisibleBeforeEnvironmentHide = thinkingBubbleWindow?.isVisible ?? false

    queuePlayer.pause()
    window.orderOut(nil)
    popoverWindow?.orderOut(nil)
    thinkingBubbleWindow?.orderOut(nil)
}

func showForEnvironmentIfNeeded() {
    guard let hiddenAt = environmentHiddenAt else { return }

    let hiddenDuration = CACurrentMediaTime() - hiddenAt
    environmentHiddenAt = nil
    walkStartTime += hiddenDuration
    pauseEndTime += hiddenDuration
    completionBubbleExpiry += hiddenDuration
    lastPhraseUpdate += hiddenDuration

    // ... restore windows ...
}
```

When hiding (e.g., Dock auto-hides or screen changes), all timing references are adjusted by the hidden duration. This prevents:
- Walk animations skipping ahead
- Pause timers expiring prematurely
- Bubbles disappearing too early
