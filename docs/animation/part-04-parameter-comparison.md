# Part 4 — Character Parameters (Bruce vs. Jazz)

> Understanding what each parameter controls and why the characters have different values.

---

## 4.1 Parameter Reference Table

| Parameter | Bruce | Jazz | Unit |
|-----------|-------|------|------|
| `videoName` | `"walk-bruce-01"` | `"walk-jazz-01"` | — |
| `name` | `"Bruce"` | `"Jazz"` | — |
| `accelStart` | 3.0 | 3.9 | seconds |
| `fullSpeedStart` | 3.75 | 4.5 | seconds |
| `decelStart` | 8.0 | 8.0 | seconds |
| `walkStop` | 8.5 | 8.75 | seconds |
| `walkAmountRange` | 0.4...0.65 | 0.35...0.6 | fraction |
| `yOffset` | -3 | -7 | points |
| `flipXOffset` | 0 | -9 | points |
| `positionProgress` (initial) | 0.3 | 0.7 | fraction (0–1) |
| `pauseEndTime` (initial) | 0.5...2.0 | 8.0...14.0 | seconds |
| `characterColor` | green (0.4, 0.72, 0.55) | orange (1.0, 0.4, 0.0) | RGB |
| `videoDuration` | 10.0 (default) | 10.0 (default) | seconds |

---

## 4.2 Parameter Explanations

### `videoName`

The filename (without extension) of the `.mov` file in the app bundle.

```swift
let char1 = WalkerCharacter(videoName: "walk-bruce-01", name: "Bruce")
let char2 = WalkerCharacter(videoName: "walk-jazz-01", name: "Jazz")
```

The app loads `walk-bruce-01.mov` and `walk-jazz-01.mov` from `Bundle.main`.

---

### `accelStart` / `fullSpeedStart` / `decelStart` / `walkStop`

These four timing parameters define the **velocity curve** that synchronises the character's on-screen position with their walk animation in the video.

| Phase | Bruce | Jazz |
|-------|-------|------|
| **Pre-walk** (standing) | 0.0 → 3.0 s | 0.0 → 3.9 s |
| **Acceleration** (starting to walk) | 3.0 → 3.75 s (0.75 s) | 3.9 → 4.5 s (0.6 s) |
| **Constant speed** (walking) | 3.75 → 8.0 s (4.25 s) | 4.5 → 8.0 s (3.5 s) |
| **Deceleration** (slowing down) | 8.0 → 8.5 s (0.5 s) | 8.0 → 8.75 s (0.75 s) |
| **Post-walk** (standing) | 8.5 → 10.0 s | 8.75 → 10.0 s |

**Why different values?**

Each character video has a different animation. Bruce's walk cycle starts earlier in the video (frame ~75 at 25fps = 3.0s), while Jazz's starts later (frame ~97 = 3.9s). The timing parameters must match the actual frames where:
- The character lifts their foot to start walking (`accelStart`)
- The character reaches full stride (`fullSpeedStart`)
- The character begins to slow down (`decelStart`)
- The character plants both feet and stops (`walkStop`)

**What happens if identical?**

If both characters had Bruce's timing but Jazz's video:
- Jazz would start moving on-screen before her video shows movement (she'd slide)
- She'd stop moving before her video shows her stopping (feet would still be mid-stride)

---

### `walkAmountRange`

A `ClosedRange<CGFloat>` specifying the minimum and maximum walk distance as a fraction of a 500-pixel reference width.

| Character | Range | Pixels walked per segment |
|-----------|-------|---------------------------|
| Bruce | 0.4...0.65 | 200–325 px |
| Jazz | 0.35...0.6 | 175–300 px |

```swift
let referenceWidth: CGFloat = 500.0
let walkPixels = CGFloat.random(in: walkAmountRange) * referenceWidth
```

**Effect**: Bruce walks slightly longer distances on average than Jazz. This, combined with different pause times, creates variety in their paths.

---

### `yOffset`

Vertical adjustment in points, applied after the base position calculation.

| Character | yOffset | Effect |
|-----------|---------|--------|
| Bruce | -3 | 3 points lower than default |
| Jazz | -7 | 7 points lower than default |

```swift
let bottomPadding = displayHeight * 0.15
let y = dockTopY - bottomPadding + yOffset
```

**Why different?**

The character videos may have different amounts of transparent padding at the bottom. `yOffset` compensates so both characters' feet appear at the same level relative to the Dock.

---

### `flipXOffset`

Horizontal correction in points, applied when the character is facing left.

| Character | flipXOffset | Effect when facing left |
|-----------|-------------|-------------------------|
| Bruce | 0 | No correction needed |
| Jazz | -9 | Character shifts 9 points left to compensate |

When a layer is mirrored via `CATransform3DMakeScale(-1, 1, 1)`, the content flips around the layer's centre. If the character's visual centre doesn't match the layer's geometric centre, the character appears to shift horizontally when turning.

```swift
var currentFlipCompensation: CGFloat {
    goingRight ? 0 : flipXOffset
}

let x = dockX + travelDistance * positionProgress + currentFlipCompensation
```

**Why Jazz needs -9?**

In Jazz's video, the character is not perfectly centred — she's offset a few pixels to the right. When mirrored, she'd appear to shift left. The `-9` offset adds 9 points to her position when facing left, keeping her feet in the same spot.

**How to determine this value for a new character:**
1. Position the character at the centre of the Dock
2. Make them walk right, then walk left
3. If they shift N pixels when turning, set `flipXOffset = -N` (or `+N` depending on direction)

---

### `positionProgress` (initial)

The starting horizontal position as a fraction from 0.0 (left edge) to 1.0 (right edge) of the Dock walking area.

| Character | Initial position | Location |
|-----------|------------------|----------|
| Bruce | 0.3 | 30% from left — left-centre area |
| Jazz | 0.7 | 70% from left — right-centre area |

This positions the characters apart at launch so they don't overlap immediately.

---

### `pauseEndTime` (initial)

The time after launch when the character will start their first walk.

| Character | Initial pause | Effect |
|-----------|---------------|--------|
| Bruce | 0.5–2.0 s | Starts walking almost immediately |
| Jazz | 8.0–14.0 s | Stands still for 8–14 seconds first |

This staggering ensures:
1. Both characters don't start walking at the exact same moment
2. The user sees movement quickly (Bruce) while Jazz provides visual stability
3. The characters naturally desynchronise over time

---

### `characterColor`

An `NSColor` used to tint the Peach theme's accents.

| Character | RGB | Visual |
|-----------|-----|--------|
| Bruce | (0.4, 0.72, 0.55) | Teal/green |
| Jazz | (1.0, 0.4, 0.0) | Orange |

When using the Peach theme, the popover border, title text, and bubble accents are tinted with this color:

```swift
func withCharacterColor(_ color: NSColor) -> PopoverTheme {
    guard name == "Peach" else { return self }
    // ... apply tinting ...
}
```

---

### `videoDuration`

The total length of the video in seconds.

```swift
let videoDuration: CFTimeInterval = 10.0
```

Both videos are 10 seconds long. This is a hardcoded default that should match the actual video duration. If a video is longer or shorter, this value must be updated.

**Used in**:
- `update()`: Determines when a walk cycle completes
- `movementPosition(at:)`: Normalises timing calculations

---

## 4.3 What Happens with Identical Parameters?

If both characters had exactly the same parameters:

### Same timing values
- Both would move in sync with their respective videos
- **But** if they have different videos, at least one would be misaligned

### Same `positionProgress`
- Both would start at the same horizontal position
- They'd overlap on launch

### Same `pauseEndTime`
- Both would start walking at the same time
- Movements would feel mechanical and synchronised

### Same `walkAmountRange`
- Both would walk similar distances
- Less variety in crossing paths

### Same `yOffset`
- If videos have different bottom padding, one character's feet would float or sink

### Same `flipXOffset`
- If videos have different centre alignments, one would visually shift when turning

---

## 4.4 Summary: Why Parameters Differ

| Parameter | Reason for difference |
|-----------|----------------------|
| Timing (`accelStart`, etc.) | Videos have different walk cycle timing |
| `walkAmountRange` | Creates variety in movement patterns |
| `yOffset` | Videos have different bottom padding |
| `flipXOffset` | Videos have different horizontal centre |
| `positionProgress` | Avoids overlap at launch |
| `pauseEndTime` | Staggers first movement |
| `characterColor` | Visual identity / brand |

The combination of different parameters makes Bruce and Jazz feel like distinct characters with their own personalities, even though they share the same underlying animation system.
