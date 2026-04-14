# Part 8 — Known Issues and Quirks

> Documented bugs, edge cases, and architectural oddities in the animation system.

---

## 8.1 The `"big"` Default Bug

### Description

In `LilAgentsApp.applicationDidFinishLaunching()`:

```swift
UserDefaults.standard.register(defaults: ["dockIconSize": "big"])
```

This registers `"big"` as the default value for `dockIconSize`. However, the value is never used — Dock icon detection relies on system APIs, not this setting.

### Impact

- No functional impact
- Dead code / misleading configuration
- `UserDefaults.standard.string(forKey: "dockIconSize")` would return `"big"` but isn't read anywhere

### Suggested Fix

Remove the unused default:

```swift
// Delete this line:
UserDefaults.standard.register(defaults: ["dockIconSize": "big"])
```

Or implement proper Dock size detection if this was intended for future use.

---

## 8.2 Sound Toggle Not Persisted

### Description

```swift
static var soundsEnabled = true
```

This is an in-memory static property. When the app quits, the value is lost.

### Reproduction

1. Launch app (sounds on by default)
2. Menu > Sounds > click to disable
3. Quit app
4. Relaunch
5. Sounds are on again ❌

### Suggested Fix

Use UserDefaults:

```swift
static var soundsEnabled: Bool {
    get { UserDefaults.standard.object(forKey: "soundsEnabled") as? Bool ?? true }
    set { UserDefaults.standard.set(newValue, forKey: "soundsEnabled") }
}
```

---

## 8.3 `flipXOffset = -9` Magic Number

### Description

Jazz's `flipXOffset` is set to `-9`:

```swift
char2.flipXOffset = -9
```

### Origin

This value was determined empirically by:
1. Positioning Jazz at Dock centre
2. Walking right, then left
3. Observing a 9-pixel shift when flipping
4. Adding `-9` compensation

### Issues

- **Not documented in code** — No comment explaining why -9
- **Tied to video asset** — If video is re-rendered with different centre, value breaks
- **Resolution-dependent?** — May need adjustment on different displays (untested)

### Suggested Fix

Add documentation:

```swift
// Jazz's video is offset ~9 pixels right of centre.
// When flipped via CATransform3D, this causes visible shift.
// -9 compensates to keep feet stationary during turn.
char2.flipXOffset = -9
```

Or calculate dynamically based on video frame analysis (complex).

---

## 8.4 CVDisplayLink Cleanup Race Condition

### Description

In `LilAgentsController`:

```swift
deinit {
    stopDisplayLink()
}
```

The CVDisplayLink callback runs on a background thread. If `deinit` fires while a callback is in progress:

1. `stopDisplayLink()` invalidates the display link
2. Callback may still be executing on another thread
3. Callback accesses `self` which is being deallocated
4. Potential crash (use-after-free)

### Current Mitigation

The `@objc` `tick` selector adds some safety, and `DispatchQueue.main.async` defers actual work. However, the pattern is fragile.

### Suggested Fix

Use proper synchronisation:

```swift
private let displayLinkLock = NSLock()
private var isShuttingDown = false

func stopDisplayLink() {
    displayLinkLock.lock()
    isShuttingDown = true
    if let link = displayLink {
        CVDisplayLinkStop(link)
    }
    displayLink = nil
    displayLinkLock.unlock()
}

@objc private func tick() {
    displayLinkLock.lock()
    guard !isShuttingDown else {
        displayLinkLock.unlock()
        return
    }
    displayLinkLock.unlock()
    
    DispatchQueue.main.async { [weak self] in
        self?.update()
    }
}
```

---

## 8.5 Hardcoded 10-Second Video Duration

### Description

```swift
let videoDuration: CFTimeInterval = 10.0
```

This assumes all videos are exactly 10 seconds.

### Issues

- If a video is 12 seconds, the last 2 seconds of animation are ignored
- If a video is 8 seconds, timing calculations are wrong for final 2 seconds
- No runtime validation

### Suggested Fix

Read duration from asset:

```swift
let videoDuration: CFTimeInterval

func setup() {
    guard let path = Bundle.main.path(forResource: videoName, ofType: "mov") else { return }
    let asset = AVAsset(url: URL(fileURLWithPath: path))
    
    // Load duration asynchronously
    Task {
        let duration = try await asset.load(.duration)
        await MainActor.run {
            self.videoDuration = CMTimeGetSeconds(duration)
        }
    }
}
```

---

## 8.6 Walk Collision Avoidance Limited to 2 Characters

### Description

`checkCharacterCollisions()` only compares characters pairwise and uses simple heuristics:

```swift
if char1.isWalkingToTarget && char2.isWalkingToTarget {
    // One yields...
}
```

### Issues

- With 3+ characters, collisions between non-adjacent pairs may be missed
- No spatial partitioning for efficiency
- Characters can still overlap during complex scenarios

### Suggested Fix

For 2 characters, current system is adequate. For 3+, implement:

1. Distance matrix between all character pairs
2. Priority queue for collision resolution
3. More sophisticated yielding logic

---

## 8.7 Popover Positioning Edge Cases

### Description

The popover is positioned relative to the character window:

```swift
let x = charFrame.maxX - 20
let y = charFrame.minY + charFrame.height * 0.35
```

### Issues

- **Right edge of screen**: Popover may be clipped or extend off-screen
- **Very small Dock**: Character may be positioned where popover overlaps Dock
- **Multiple monitors**: Popover may appear on wrong monitor

### Suggested Fix

Add bounds checking:

```swift
func positionPopover() {
    let screen = window.screen ?? NSScreen.main!
    let screenFrame = screen.visibleFrame
    
    var x = charFrame.maxX - 20
    var y = charFrame.minY + charFrame.height * 0.35
    
    // Prevent right overflow
    if x + popoverWidth > screenFrame.maxX {
        x = charFrame.minX - popoverWidth + 20  // Flip to left side
    }
    
    // Prevent bottom underflow
    if y < screenFrame.minY {
        y = screenFrame.minY + 10
    }
    
    popover.setFrame(CGRect(x: x, y: y, width: popoverWidth, height: popoverHeight), display: true)
}
```

---

## 8.8 Theme Not Persisted

### Description

```swift
static var current: PopoverTheme = .classic
```

Like `soundsEnabled`, theme selection is lost on app restart.

### Suggested Fix

```swift
static var current: PopoverTheme {
    get {
        let name = UserDefaults.standard.string(forKey: "popoverTheme") ?? "classic"
        switch name {
        case "modern": return .modern
        case "terminal": return .terminal
        case "peach": return .peach
        default: return .classic
        }
    }
    set {
        UserDefaults.standard.set(newValue.name, forKey: "popoverTheme")
    }
}
```

---

## 8.9 Asset Loading on Main Thread

### Description

In `WalkerCharacter.setup()`:

```swift
let asset = AVAsset(url: url)
let item = AVPlayerItem(asset: asset)
player = AVQueuePlayer(playerItem: item)
```

While `AVAsset` itself is lightweight, creating `AVPlayerItem` can trigger I/O.

### Issues

- On slow storage, may cause brief UI stutter at launch
- Blocking main thread is generally discouraged for I/O

### Suggested Fix

Load assets asynchronously:

```swift
func setup() async {
    let asset = AVAsset(url: url)
    let item = AVPlayerItem(asset: asset)
    
    await MainActor.run {
        self.player = AVQueuePlayer(playerItem: item)
        self.setupPlayerLayer()
    }
}
```

---

## 8.10 No Graceful Degradation for Missing Assets

### Description

```swift
guard let path = Bundle.main.path(forResource: videoName, ofType: "mov") else {
    return
}
```

If the video file is missing, setup silently fails.

### Issues

- Character window may be created but never show video
- No error message to user or logs
- Debugging is difficult

### Suggested Fix

```swift
guard let path = Bundle.main.path(forResource: videoName, ofType: "mov") else {
    NSLog("⚠️ WalkerCharacter: Video not found: \(videoName).mov")
    // Show placeholder or error state
    showErrorPlaceholder()
    return
}
```

---

## 8.11 Hit Testing Performance

### Description

`hitTest(_:)` in `CharacterContentView` captures a screen region on every click:

```swift
let img = CGWindowListCreateImage(captureRect, .optionIncludingWindow, CGWindowID(window.windowNumber), [])
```

### Issues

- Creates GPU → CPU readback for every click
- With many characters, this multiplies
- On high-DPI displays, capturing large regions is slow

### Current Mitigation

Only 1×1 pixel region is captured, minimising impact.

### Potential Improvement

Cache alpha mask from video frame (complex due to animation).

---

## 8.12 Memory: Video Looping Keeps Full Asset in Memory

### Description

`AVPlayerLooper` keeps the video asset buffered for seamless looping.

### Impact

- Each character's 10-second HEVC video is fully decoded and buffered
- ~10-50 MB per character depending on resolution and codec
- With many characters, memory adds up

### Mitigation

- Current 2 characters is fine (~20-100 MB total)
- For 5+ characters, consider:
  - Lower resolution videos
  - More aggressive compression
  - Lazy loading (only active characters in memory)

---

## Summary Table

| Issue | Severity | Status |
|-------|----------|--------|
| `"big"` default unused | Low | Cosmetic |
| Sound toggle not saved | Medium | Missing feature |
| `flipXOffset` magic number | Low | Documentation |
| CVDisplayLink race | Medium | Potential crash |
| Hardcoded 10s duration | Medium | Fragile |
| 2-character collision limit | Low | Design limitation |
| Popover edge positioning | Medium | UX issue |
| Theme not persisted | Medium | Missing feature |
| Main thread asset loading | Low | Performance |
| Silent asset failure | Medium | Debuggability |
| Hit testing performance | Low | Acceptable |
| Video memory footprint | Low | Scalability |

---

## Priority Fixes

If contributing to the project, prioritise:

1. **Sound toggle persistence** — Easy win, improves UX
2. **Theme persistence** — Easy win, improves UX
3. **CVDisplayLink race condition** — Prevents rare crashes
4. **Popover edge positioning** — Prevents clipping on edge cases
5. **Remove `"big"` default** — Code cleanliness
