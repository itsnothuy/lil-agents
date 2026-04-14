# Part 6 — Alternative Character Formats

> Exploring PNG sequences, sprite sheets, GIF/APNG, and vector animation libraries as alternatives to HEVC video.

---

## 6.1 Current Architecture (HEVC Video)

The existing implementation uses **HEVC video with alpha channel**:

```
┌─────────────────────────────────────────────────────────────────┐
│                        HEVC Video Pipeline                       │
├─────────────────────────────────────────────────────────────────┤
│  .mov file → AVAsset → AVPlayerItem → AVQueuePlayer → AVPlayerLayer │
│                                            ↓                         │
│                                    AVPlayerLooper (seamless loop)    │
└─────────────────────────────────────────────────────────────────┘
```

### Pros
- Hardware-accelerated decoding (VideoToolbox)
- Excellent compression (10s video ≈ 2-5 MB)
- Seamless looping via `AVPlayerLooper`
- Native alpha channel support (HEVC with alpha)
- Frame-accurate timing via `AVPlayer.currentTime()`

### Cons
- Requires video editing software to create
- Hard to modify individual frames
- Binary format (not diffable in version control)
- Large file if exported at higher quality

---

## 6.2 Option A: PNG Sequence

### Concept

Replace the video with individual PNG frames:

```
Sounds/
walk-pixel/
  frame_001.png
  frame_002.png
  ...
  frame_250.png
```

### Implementation Sketch

```swift
class PNGAnimatedCharacter {
    private var frames: [NSImage] = []
    private var currentFrame: Int = 0
    private var imageLayer: CALayer!
    private var frameRate: Double = 25.0
    private var lastFrameTime: CFTimeInterval = 0
    
    func loadFrames(named prefix: String, count: Int) {
        for i in 1...count {
            let name = String(format: "%@_%03d", prefix, i)
            if let img = NSImage(named: name) {
                frames.append(img)
            }
        }
    }
    
    func update(at time: CFTimeInterval) {
        let frameDuration = 1.0 / frameRate
        if time - lastFrameTime >= frameDuration {
            currentFrame = (currentFrame + 1) % frames.count
            imageLayer.contents = frames[currentFrame]
            lastFrameTime = time
        }
    }
}
```

### Changes Required

| Component | Current | PNG Version |
|-----------|---------|-------------|
| Asset storage | Single `.mov` | 250 PNG files |
| Layer type | `AVPlayerLayer` | `CALayer` |
| Frame advance | Automatic (AVPlayer) | Manual in `update()` |
| Timing | `player.currentTime()` | `currentFrame / frameRate` |
| Loop | `AVPlayerLooper` | `% frames.count` |

### Pros
- Easy to edit individual frames
- Version control friendly (or use LFS)
- No video codec dependencies
- Works on all platforms

### Cons
- **Much larger file size** (250 PNGs ≈ 20-50 MB uncompressed)
- Manual frame timing
- Slower loading (many file handles)
- No hardware decode acceleration

---

## 6.3 Option B: Sprite Sheet

### Concept

All frames in a single PNG atlas:

```
walk-pixel-spritesheet.png (2500 × 1920 for 10 frames per row, 25 rows)
walk-pixel-spritesheet.json (frame metadata)
```

### Implementation Sketch

```swift
struct SpriteFrame {
    let rect: CGRect  // x, y, width, height in atlas
    let duration: CFTimeInterval
}

class SpriteSheetCharacter {
    private var atlas: NSImage!
    private var frames: [SpriteFrame] = []
    private var currentFrame: Int = 0
    private var croppedLayer: CALayer!
    
    func loadSpriteSheet(named name: String) {
        atlas = NSImage(named: name)
        // Parse JSON for frame rects
    }
    
    func update(at time: CFTimeInterval) {
        let frame = frames[currentFrame]
        let cropped = cropImage(atlas, to: frame.rect)
        croppedLayer.contents = cropped
        // Advance frame...
    }
}
```

### Atlas Layout Options

**Grid layout** (simple):
```
┌────┬────┬────┬────┬────┐
│ 1  │ 2  │ 3  │ 4  │ 5  │
├────┼────┼────┼────┼────┤
│ 6  │ 7  │ 8  │ 9  │ 10 │
├────┼────┼────┼────┼────┤
│...                      │
└─────────────────────────┘
```

**Packed layout** (smaller file, complex parsing):
- Tools like TexturePacker optimise frame positions
- Requires accompanying JSON/plist with coordinates

### Pros
- Single file to manage
- Smaller than individual PNGs (shared compression)
- Standard game development technique
- Many tools available (TexturePacker, Shoebox)

### Cons
- Atlas can get very large for long animations
- Need to crop/extract each frame at runtime
- More complex coordinate math
- Harder to edit individual frames

---

## 6.4 Option C: Animated GIF / APNG

### Concept

Use a single animated image file:

```
walk-pixel.apng  (APNG for alpha support)
walk-pixel.gif   (no alpha, limited to 256 colours)
```

### Implementation with CGImageSource

```swift
class APNGCharacter {
    private var imageSource: CGImageSource!
    private var frameCount: Int = 0
    private var currentFrame: Int = 0
    private var imageLayer: CALayer!
    
    func load(url: URL) {
        imageSource = CGImageSourceCreateWithURL(url as CFURL, nil)
        frameCount = CGImageSourceGetCount(imageSource)
    }
    
    func update(at time: CFTimeInterval) {
        let cgImage = CGImageSourceCreateImageAtIndex(imageSource, currentFrame, nil)
        imageLayer.contents = cgImage
        currentFrame = (currentFrame + 1) % frameCount
    }
    
    func frameDuration(at index: Int) -> CFTimeInterval {
        let props = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [CFString: Any]
        // Parse duration from GIF/PNG dictionary...
        return 0.04  // default 25fps
    }
}
```

### Format Comparison

| Feature | GIF | APNG |
|---------|-----|------|
| Alpha channel | 1-bit (on/off) | Full 8-bit |
| Colours | 256 max | Full 24-bit |
| File size | Smaller | Larger |
| Browser support | Universal | Modern browsers |
| Compression | LZW | Deflate |

### Pros
- Single self-contained file
- Built-in frame timing
- APNG supports full alpha
- Familiar format for artists

### Cons
- **GIF**: No partial transparency (jaggy edges)
- **APNG**: Larger file size than HEVC
- Decoding not hardware accelerated
- Limited tooling compared to video

---

## 6.5 Option D: Lottie / Rive

### Concept

Use vector-based animation with runtime rendering:

```
walk-pixel.json  (Lottie from After Effects)
walk-pixel.riv   (Rive native format)
```

### Lottie Implementation

```swift
import Lottie

class LottieCharacter {
    private var animationView: LottieAnimationView!
    
    func setup(named name: String) {
        let animation = LottieAnimation.named(name)
        animationView = LottieAnimationView(animation: animation)
        animationView.loopMode = .loop
        animationView.play()
    }
    
    func setProgress(_ progress: CGFloat) {
        // For synchronised movement
        animationView.currentProgress = progress
    }
}
```

### Rive Implementation

```swift
import RiveRuntime

class RiveCharacter {
    private var riveView: RiveView!
    
    func setup(url: URL) {
        riveView = RiveView(riveFile: RiveFile(url: url)!)
        riveView.autoPlay = true
    }
    
    func triggerState(_ stateName: String) {
        // Interactive state machines
        riveView.setInput(stateName, value: true)
    }
}
```

### Feature Comparison

| Feature | Lottie | Rive |
|---------|--------|------|
| Format origin | After Effects export | Native editor |
| File size | Very small (KB) | Very small (KB) |
| Runtime size | ~2 MB | ~1 MB |
| Interactivity | Limited | State machines |
| Raster support | Embedded images | Embedded images |
| macOS support | ✅ (lottie-ios) | ✅ (rive-ios) |

### Pros
- **Tiny file sizes** (10KB vs 5MB)
- Resolution independent (vector)
- Easy to tweak timing/colours
- Interactive states possible
- Popular in modern apps

### Cons
- Requires external dependency (pod/SPM)
- Complex animations need skilled artists
- Raster effects limited
- Performance depends on complexity
- New toolchain for artists to learn

---

## 6.6 Architecture Changes Summary

| Format | Asset Layer | Update Loop | Timing |
|--------|-------------|-------------|--------|
| HEVC (current) | `AVPlayerLayer` | Automatic | `player.currentTime()` |
| PNG sequence | `CALayer` | Manual `contents` swap | Frame counter ÷ fps |
| Sprite sheet | `CALayer` with crop | Manual crop + swap | Frame counter ÷ fps |
| APNG/GIF | `CALayer` | Manual via CGImageSource | Frame dictionary |
| Lottie | `LottieAnimationView` | Automatic | `currentProgress` |
| Rive | `RiveView` | Automatic | State machine |

---

## 6.7 Migration Path

To support multiple formats, create a protocol:

```swift
protocol AnimatedCharacter {
    var layer: CALayer { get }
    var currentTime: CFTimeInterval { get }
    var duration: CFTimeInterval { get }
    
    func setup(asset: String) throws
    func play()
    func pause()
    func seek(to time: CFTimeInterval)
}

class HEVCCharacter: AnimatedCharacter { /* existing implementation */ }
class PNGCharacter: AnimatedCharacter { /* new */ }
class LottieCharacter: AnimatedCharacter { /* new */ }
```

Then `WalkerCharacter` can use any `AnimatedCharacter` implementation:

```swift
class WalkerCharacter {
    var animatedCharacter: AnimatedCharacter
    
    init(type: CharacterType, asset: String) {
        switch type {
        case .hevc: animatedCharacter = HEVCCharacter()
        case .png:  animatedCharacter = PNGCharacter()
        case .lottie: animatedCharacter = LottieCharacter()
        }
        try? animatedCharacter.setup(asset: asset)
    }
}
```

---

## 6.8 Recommendation

| Use Case | Recommended Format |
|----------|-------------------|
| High-quality character (current) | HEVC video ✅ |
| Simple mascot | Lottie or Rive |
| Quick prototype | PNG sequence |
| Cross-platform (iOS/web) | Lottie |
| Interactive character | Rive |
| Minimal dependencies | APNG |

For **lil-agents**, HEVC remains the best choice because:
1. Characters are pre-rendered raster animations
2. Hardware decoding keeps CPU usage low
3. No additional dependencies needed
4. 10-second loop is reasonable file size

Consider Lottie/Rive only if adding **simple vector mascots** or **interactive emotes** in the future.
