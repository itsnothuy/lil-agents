# Part 5 — Adding a New Character

> Step-by-step guide to creating a third walking character from scratch.

---

## 5.1 Overview

Adding a new character requires:

1. **Video asset** — A looping walk cycle with transparent background
2. **Xcode asset** — Added to the app bundle
3. **Parameter tuning** — Timing values matched to the video
4. **Swift instantiation** — Creating the `WalkerCharacter` in `LilAgentsController`
5. **Menu bar toggle** — Adding show/hide menu item
6. **Provider integration** — Associating with an AI backend

---

## 5.2 Video Requirements

### Format

| Aspect | Requirement | Example |
|--------|-------------|---------|
| Container | QuickTime `.mov` | `walk-pixel-01.mov` |
| Codec | HEVC with alpha (ProRes 4444 also works) | `hvc1` fourcc |
| Resolution | 1080 × 1920 (portrait) recommended | Matches existing assets |
| Frame rate | 25 fps recommended | Matches existing assets |
| Duration | 10 seconds exactly | Matches hardcoded default |
| Alpha channel | Required | Transparent background |
| Loop | Seamless start/end | Character pose identical at frame 1 and last frame |

### Walk Cycle Structure

The video must follow this structure:

```
Time: 0s              A           B           C           D         10s
      │               │           │           │           │          │
      │   PRE-WALK    │   ACCEL   │   WALK    │   DECEL   │ POST-WALK│
      │  (standing)   │  (start)  │  (full)   │  (slow)   │(standing)│
      └───────────────┴───────────┴───────────┴───────────┴──────────┘

Where:
A = accelStart    (e.g., 3.0s)
B = fullSpeedStart (e.g., 3.75s)
C = decelStart    (e.g., 8.0s)
D = walkStop      (e.g., 8.5s)
```

**Critical**: Note the exact frame numbers where:
- The character lifts their first foot to start walking → `accelStart`
- The character reaches full walking stride → `fullSpeedStart`
- The character begins slowing down → `decelStart`
- The character plants both feet and is fully stopped → `walkStop`

### Example: "Pixel" Character

Let's say your video (`walk-pixel-01.mov`) has:
- **Frame 80** (3.2s @ 25fps): Pixel starts lifting foot
- **Frame 100** (4.0s): Pixel at full stride
- **Frame 200** (8.0s): Pixel starts slowing
- **Frame 225** (9.0s): Pixel fully stopped

Your parameters would be:
```swift
accelStart: 3.2
fullSpeedStart: 4.0
decelStart: 8.0
walkStop: 9.0
```

---

## 5.3 Adding to Xcode

### Step 1: Add Video File

1. Open `LilAgents.xcodeproj` in Xcode
2. In the Project Navigator, select the `LilAgents` folder
3. Right-click → "Add Files to 'LilAgents'..."
4. Select your `walk-pixel-01.mov` file
5. Ensure "Copy items if needed" is checked
6. Ensure "Add to targets: LilAgents" is checked
7. Click "Add"

The video will appear in the project and be included in the app bundle.

### Step 2: (Optional) Add Icon

If you want a custom menu bar icon:

1. Create a 20×20 PNG with transparency
2. Create @2x (40×40) and @3x (60×60) versions
3. In `Assets.xcassets`, create new Image Set named `PixelIcon`
4. Drag PNG files to 1x, 2x, 3x slots

---

## 5.4 Swift Implementation

### Step 1: Create Character Instance

In `LilAgentsController.swift`, add to the `characters` array:

```swift
let char3 = WalkerCharacter(videoName: "walk-pixel-01", name: "Pixel")
char3.accelStart = 3.2
char3.fullSpeedStart = 4.0
char3.decelStart = 8.0
char3.walkStop = 9.0
char3.walkAmountRange = 0.35...0.55
char3.yOffset = -5
char3.flipXOffset = 0  // Adjust after testing
char3.positionProgress = 0.5  // Start in middle
char3.pauseEndTime = CACurrentMediaTime() + Double.random(in: 4.0...10.0)
char3.characterColor = NSColor(red: 0.5, green: 0.2, blue: 0.8, alpha: 1.0)  // Purple
```

### Step 2: Add to Characters Array

```swift
private func start() {
    // ... existing char1, char2 setup ...
    
    let char3 = WalkerCharacter(videoName: "walk-pixel-01", name: "Pixel")
    // ... parameter setup ...
    
    characters = [char1, char2, char3]
}
```

### Step 3: Associate Provider

In the provider switch, add a case for the new character:

```swift
switch provider {
case .openClaw:
    if let char = characters.first(where: { $0.name == "Bruce" }) {
        // Bruce handles OpenClaw
    }
case .copilot:
    if let char = characters.first(where: { $0.name == "Jazz" }) {
        // Jazz handles Copilot
    }
case .gemini:
    if let char = characters.first(where: { $0.name == "Pixel" }) {
        // Pixel handles Gemini
    }
// ... other cases ...
}
```

---

## 5.5 Menu Bar Integration

### Add Toggle Item

In `LilAgentsApp.swift`, inside `buildMenu()`:

```swift
// Find where Bruce and Jazz toggles are defined
let togglePixel = NSMenuItem(title: "Pixel", action: #selector(togglePixel(_:)), keyEquivalent: "")
togglePixel.target = self
togglePixel.state = LilAgentsController.shared.characters.first(where: { $0.name == "Pixel" })?.isHidden == false ? .on : .off
characterMenu.addItem(togglePixel)
```

### Add Action Handler

```swift
@objc func togglePixel(_ sender: NSMenuItem) {
    if let c = LilAgentsController.shared.characters.first(where: { $0.name == "Pixel" }) {
        let willHide = !c.isHidden
        c.isHidden = willHide
        sender.state = willHide ? .off : .on
        UserDefaults.standard.set(willHide, forKey: "pixelHidden")
    }
}
```

### Persist State

In `applicationDidFinishLaunching`:

```swift
if UserDefaults.standard.bool(forKey: "pixelHidden"),
   let c = LilAgentsController.shared.characters.first(where: { $0.name == "Pixel" }) {
    c.isHidden = true
}
```

---

## 5.6 Parameter Tuning

### Step 1: Initial Test

Build and run. Watch Pixel walk. Note any issues:
- Does the video start walking before/after the on-screen movement? → Adjust `accelStart`
- Does the character slide at constant speed? → Adjust `fullSpeedStart`/`decelStart`
- Does the video show movement after Pixel stops? → Adjust `walkStop`

### Step 2: Flip Test

1. Position Pixel at Dock centre
2. Walk right, then walk left
3. Note if Pixel shifts horizontally when turning
4. If shifting right → set `flipXOffset` to positive value
5. If shifting left → set `flipXOffset` to negative value
6. Iterate until turn looks seamless

### Step 3: Vertical Alignment

1. Compare Pixel's feet to Bruce and Jazz
2. If Pixel appears higher → decrease `yOffset` (more negative)
3. If Pixel appears lower → increase `yOffset` (less negative or positive)

### Step 4: Walk Distance

1. Watch Pixel walk several times
2. If walks feel too short → increase `walkAmountRange` upper bound
3. If walks feel too long → decrease `walkAmountRange` upper bound
4. If walks all feel similar → widen the range

---

## 5.7 Collision Avoidance (Multi-Character)

The current collision system only handles 2 characters. For 3+, you'll need to enhance `checkCharacterCollisions()`:

```swift
private func checkCharacterCollisions() {
    let tolerance: CGFloat = 70
    let visibleChars = characters.filter { !$0.isHidden && !$0.isIdleForPopover }
    
    for i in 0..<visibleChars.count {
        for j in (i+1)..<visibleChars.count {
            let char1 = visibleChars[i]
            let char2 = visibleChars[j]
            
            if char1.isWalkingToTarget && char2.isWalkingToTarget {
                // Both walking - check if on collision course
                let approaching = (char1.walkTarget > char1.positionProgress && char2.walkTarget < char2.positionProgress) ||
                                 (char1.walkTarget < char1.positionProgress && char2.walkTarget > char2.positionProgress)
                
                let distance = abs(char1.positionProgress - char2.positionProgress) * 500
                if distance < tolerance && approaching {
                    // Too close and approaching - one should wait
                    char2.waitingForOther = true
                }
            }
        }
    }
}
```

---

## 5.8 Checklist

Before shipping a new character:

- [ ] Video plays correctly (no codec errors)
- [ ] Video loops seamlessly (no jump at loop point)
- [ ] Alpha channel works (transparent background visible)
- [ ] Timing parameters match video walk cycle
- [ ] Character stays on screen (doesn't walk off edges)
- [ ] Flip looks natural (no horizontal shifting)
- [ ] Vertical position matches other characters
- [ ] Menu bar toggle works
- [ ] State persists across app restart
- [ ] Associated provider triggers this character's popover
- [ ] Bubble appears above character's head correctly
- [ ] No collisions/overlap with existing characters

---

## 5.9 Minimal Code Diff

Here's the minimal code changes for adding "Pixel":

**LilAgentsController.swift** — `start()`:
```swift
let char3 = WalkerCharacter(videoName: "walk-pixel-01", name: "Pixel")
char3.accelStart = 3.2
char3.fullSpeedStart = 4.0
char3.decelStart = 8.0
char3.walkStop = 9.0
char3.walkAmountRange = 0.35...0.55
char3.yOffset = -5
char3.flipXOffset = 0
char3.positionProgress = 0.5
char3.pauseEndTime = CACurrentMediaTime() + Double.random(in: 4.0...10.0)
char3.characterColor = NSColor(red: 0.5, green: 0.2, blue: 0.8, alpha: 1.0)
characters = [char1, char2, char3]
```

**LilAgentsApp.swift** — `buildMenu()`:
```swift
let togglePixel = NSMenuItem(title: "Pixel", action: #selector(togglePixel(_:)), keyEquivalent: "")
togglePixel.target = self
characterMenu.addItem(togglePixel)
```

**LilAgentsApp.swift** — new method:
```swift
@objc func togglePixel(_ sender: NSMenuItem) {
    // Toggle logic
}
```

That's it — approximately 20 lines of code plus a video file.
