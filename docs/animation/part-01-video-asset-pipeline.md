# Part 1 — Video Asset Pipeline

> How the image gets on screen: from `.mov` file on disk to rendered pixels.

---

## 1.1 Video Asset Loading

The video asset pipeline begins in `WalkerCharacter.setup()`:

```swift
guard let videoURL = Bundle.main.url(forResource: videoName, withExtension: "mov") else {
    print("Video \(videoName) not found")
    return
}

let asset = AVAsset(url: videoURL)
queuePlayer = AVQueuePlayer()
looper = AVPlayerLooper(player: queuePlayer, templateItem: AVPlayerItem(asset: asset))
```

### Component Breakdown

| Component | Role |
|-----------|------|
| `Bundle.main.url(forResource:withExtension:)` | Locates the `.mov` file inside the app bundle at runtime. Returns `nil` if the video is missing or not included in target membership. |
| `AVAsset(url:)` | Creates an immutable asset object representing the video file. Does not load frames — only metadata. Lightweight and thread-safe. |
| `AVPlayerItem(asset:)` | Wraps the asset into a playable item with its own timeline, status, and error tracking. |
| `AVQueuePlayer()` | A subclass of `AVPlayer` designed for sequential playback of multiple items. Here it plays a single item repeatedly via the looper. |
| `AVPlayerLooper(player:templateItem:)` | Manages seamless looping by pre-buffering the template item and inserting copies into the queue. Eliminates the seek-to-zero gap that occurs with manual notification-based looping. |

### Why AVPlayerLooper instead of manual looping?

The older approach was:
```swift
NotificationCenter.default.addObserver(
    forName: .AVPlayerItemDidPlayToEndTime,
    object: playerItem,
    queue: .main
) { _ in
    player.seek(to: .zero)
    player.play()
}
```

This produces a visible stutter (1–3 frames of freeze) at the loop point because:
1. The notification fires *after* the last frame displays
2. `seek(to: .zero)` invalidates the video decoder's buffer
3. The decoder must re-decode from the start before the first frame can render

`AVPlayerLooper` avoids this by keeping two `AVPlayerItem` copies in the queue. While one plays, the other pre-buffers from the start. When the playing item ends, playback switches instantly to the pre-buffered copy.

---

## 1.2 AVPlayerLayer Configuration

```swift
playerLayer = AVPlayerLayer(player: queuePlayer)
playerLayer.videoGravity = .resizeAspect
playerLayer.backgroundColor = NSColor.clear.cgColor
playerLayer.frame = CGRect(x: 0, y: 0, width: displayWidth, height: displayHeight)
```

### Property Analysis

| Property | Value | Purpose |
|----------|-------|---------|
| `videoGravity` | `.resizeAspect` | Scales video to fit the layer bounds while preserving aspect ratio. Black bars appear if ratios don't match. Alternative: `.resizeAspectFill` (crops to fill) or `.resize` (stretches, distorts). |
| `backgroundColor` | `.clear.cgColor` | **Critical for transparency.** If set to any opaque color, the alpha channel in the HEVC video is composited over that color, destroying transparency. Must be `.clear` for the window transparency chain to work. |
| `frame` | `(0, 0, displayWidth, displayHeight)` | Positions the layer at the origin of its superlayer with size derived from the character's `displayHeight` and the video's aspect ratio. |

### Display Dimensions Calculation

```swift
let videoWidth: CGFloat = 1080
let videoHeight: CGFloat = 1920
private(set) var displayHeight: CGFloat = 200
var displayWidth: CGFloat { displayHeight * (videoWidth / videoHeight) }
```

For a 1080×1920 video (9:16 portrait aspect ratio):
- `displayWidth = 200 * (1080 / 1920) = 200 * 0.5625 = 112.5` points

The character window is therefore 112.5 × 200 points for the default `.large` size.

---

## 1.3 Layer Hierarchy and Window Setup

```swift
let hostView = CharacterContentView(frame: CGRect(x: 0, y: 0, width: displayWidth, height: displayHeight))
hostView.character = self
hostView.wantsLayer = true
hostView.layer?.backgroundColor = NSColor.clear.cgColor
hostView.layer?.addSublayer(playerLayer)

window.contentView = hostView
```

### Layer Stack (bottom to top)

```
┌─────────────────────────────────────────┐
│  NSWindow (borderless, transparent)     │
│  ├── contentView: CharacterContentView  │
│  │   ├── layer (backing layer)          │
│  │   │   └── playerLayer (AVPlayerLayer)│
│  │   │       └── [video frames]         │
└─────────────────────────────────────────┘
```

`CharacterContentView` is the window's `contentView` and hosts the `AVPlayerLayer` as a sublayer of its backing layer. The view is layer-backed (`wantsLayer = true`) to enable Core Animation compositing.

---

## 1.4 NSWindow Transparency Configuration

```swift
window = NSWindow(
    contentRect: contentRect,
    styleMask: .borderless,
    backing: .buffered,
    defer: false
)
window.isOpaque = false
window.backgroundColor = .clear
window.hasShadow = false
window.level = .statusBar
window.ignoresMouseEvents = false
window.collectionBehavior = [.moveToActiveSpace, .stationary]
```

### Property-by-Property Breakdown

| Property | Value | What it does | What breaks if wrong |
|----------|-------|--------------|----------------------|
| `styleMask` | `.borderless` | No title bar, no close/minimize/zoom buttons, no resize handles. Window is a raw rectangle. | With `.titled`, you get a grey title bar above the character. |
| `backing` | `.buffered` | Window content is rendered into an off-screen buffer, then composited to screen. Required for transparency. | `.retained` is deprecated. `.nonretained` causes flicker. |
| `isOpaque` | `false` | Tells the window server this window has transparent regions. Enables per-pixel alpha compositing. | If `true`, the window server fills transparent areas with the window background color (even if `.clear`). |
| `backgroundColor` | `.clear` | The window's base fill color. Combined with `isOpaque = false`, this makes the window fully transparent except for its content. | Any other color shows as a solid rectangle behind the video. |
| `hasShadow` | `false` | Disables the macOS window drop shadow. | Shadows are computed from the window's bounding rect, not its alpha channel, so a shadow would appear as a rectangle around the character, not conforming to its silhouette. |
| `level` | `.statusBar` | Places the window above normal windows, below screen savers. Ensures characters float above the Dock and most app windows. | `.normal` causes characters to disappear behind other windows. `.floating` works but is lower than `.statusBar`. |
| `ignoresMouseEvents` | `false` | Window receives mouse events. Required for click detection to work. | If `true`, clicks pass through to windows beneath. |
| `collectionBehavior` | `[.moveToActiveSpace, .stationary]` | `.moveToActiveSpace`: window follows the user when switching Spaces. `.stationary`: window does not tile or participate in Mission Control. | Without `.moveToActiveSpace`, characters disappear when switching to another Space. Without `.stationary`, they might get swept into Mission Control thumbnails. |

---

## 1.5 Hit Testing with CGWindowListCreateImage

`CharacterContentView.hitTest(_:)` implements pixel-perfect click detection for GPU-rendered video:

```swift
override func hitTest(_ point: NSPoint) -> NSView? {
    let localPoint = convert(point, from: superview)
    guard bounds.contains(localPoint) else { return nil }

    let screenPoint = window?.convertPoint(toScreen: convert(localPoint, to: nil)) ?? .zero
    guard let primaryScreen = NSScreen.screens.first else { return nil }
    let flippedY = primaryScreen.frame.height - screenPoint.y

    let captureRect = CGRect(x: screenPoint.x - 0.5, y: flippedY - 0.5, width: 1, height: 1)
    guard let windowID = window?.windowNumber, windowID > 0 else { return nil }

    if let image = CGWindowListCreateImage(
        captureRect,
        .optionIncludingWindow,
        CGWindowID(windowID),
        [.boundsIgnoreFraming, .bestResolution]
    ) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel: [UInt8] = [0, 0, 0, 0]
        if let ctx = CGContext(
            data: &pixel, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            if pixel[3] > 30 {
                return self
            }
            return nil
        }
    }

    // Fallback: centre 60% bounding rect
    let insetX = bounds.width * 0.2
    let insetY = bounds.height * 0.15
    let hitRect = bounds.insetBy(dx: insetX, dy: insetY)
    return hitRect.contains(localPoint) ? self : nil
}
```

### Why `layer.render(in:)` Cannot Be Used

The standard approach to sample a layer's content is:

```swift
let context = CGContext(...)
layer.render(in: context)
// Read pixel from context
```

This **does not work** for `AVPlayerLayer` because:

1. **GPU-resident frames**: Video frames are decoded directly to GPU textures via VideoToolbox. They never exist in CPU-accessible memory unless explicitly requested.
2. **`render(in:)` only captures CPU-backed content**: It renders the layer's `contents` property and sublayers, but `AVPlayerLayer` does not expose its current frame as `contents`. The property is `nil`.
3. **Result**: `layer.render(in:)` produces a fully transparent image — the video frame is invisible.

### How `CGWindowListCreateImage` Solves This

`CGWindowListCreateImage` captures the *composited* window content directly from the window server. The window server has already received the GPU-rendered video frame and composited it into the window's backbuffer. This API captures that final composited result, including alpha.

### Coordinate Space Transformation

```swift
let flippedY = primaryScreen.frame.height - screenPoint.y
```

- **NSScreen coordinates**: Origin at bottom-left of the primary display, Y increases upward.
- **Core Graphics (Quartz) coordinates**: Origin at top-left, Y increases downward.

The flip is computed relative to `primaryScreen.frame.height` because all screen coordinates in macOS are relative to the primary display's origin, even on multi-monitor setups.

### Alpha Threshold

```swift
if pixel[3] > 30 {
    return self
}
```

The threshold of 30 (out of 255) allows clicks on semi-transparent pixels (e.g., anti-aliased edges, shadows, motion blur) while rejecting fully transparent areas. A threshold of 0 would make even 1% opacity clickable; a threshold of 128 would require >50% opacity.

### Fallback Bounding Rect

If `CGWindowListCreateImage` fails (e.g., on older macOS versions or in certain security contexts), the method falls back to accepting clicks within the centre 60% of the view bounds:

```swift
let insetX = bounds.width * 0.2   // 20% inset from each side
let insetY = bounds.height * 0.15 // 15% inset from top and bottom
```

This assumes the character is roughly centred in the video frame with transparent padding around the edges.

---

## 1.6 Seamless Looping via AVPlayerLooper

```swift
looper = AVPlayerLooper(player: queuePlayer, templateItem: AVPlayerItem(asset: asset))
```

`AVPlayerLooper` works by:

1. Creating internal copies of the `templateItem`
2. Inserting them into the `AVQueuePlayer`'s item queue
3. Pre-buffering the next copy while the current one plays
4. Switching to the pre-buffered copy at the exact end time with frame-accurate precision

The `templateItem` is the "template" — it is not modified. The looper creates its own internal copies.

### Checking Loop Status

```swift
looper.status // .ready, .failed, .cancelled, or .unknown
looper.loopCount // Number of completed loops
```

---

## 1.7 Pausing and Seeking

When the character stops walking:

```swift
func enterPause() {
    isWalking = false
    isPaused = true
    queuePlayer.pause()
    queuePlayer.seek(to: .zero)
    // ...
}
```

### Why `seek(to: .zero)`?

The walk animation in the video starts at frame 0 and ends at around frame 250 (at 25 fps, in a 10-second video). When the character pauses:

1. The video may be at frame 180 (mid-walk, one leg forward)
2. If we just `pause()`, the character freezes mid-stride
3. By seeking to `.zero`, the character returns to its neutral standing pose (frame 0)

This keeps the visual state consistent: paused characters always show the same idle pose.

### Seeking Accuracy

`seek(to: .zero)` uses the default tolerance, which is efficient but not frame-accurate. For frame-accurate seeking:

```swift
queuePlayer.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
```

In this app, frame-accuracy isn't critical because the idle pose spans multiple frames at the video's start.

---

## 1.8 Video Format Requirements Summary

For a video to work correctly in this system:

| Requirement | Value | Reason |
|-------------|-------|--------|
| Container | `.mov` (QuickTime) | `Bundle.main.url(forResource:withExtension:)` expects this extension. |
| Codec | HEVC with alpha (`hvc1` + alpha layer) | Only HEVC supports hardware-decoded alpha on macOS. ProRes 4444 also works but has much larger file size. |
| Alpha channel | Premultiplied or straight | Both work; premultiplied is more common in video. |
| Background | Fully transparent (alpha = 0) in all non-character pixels | Required for click detection to work. Any non-zero alpha in the background makes those pixels clickable. |
| Aspect ratio | Portrait (e.g., 1080×1920) | The `displayWidth` calculation assumes portrait. Landscape videos would appear squished. |
| Frame rate | 25–60 fps | Lower frame rates make animation choppy. Higher is fine but increases file size. |
| Duration | Should match `videoDuration` property (default 10.0 seconds) | The walk timing parameters are calibrated to this duration. |
