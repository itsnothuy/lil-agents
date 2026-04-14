# Part 7 — Customisation Cookbook

> 12 common tweaks with exact property names, values, and file locations.

---

## Recipe 1: Change Walk Speed (Visually Faster)

**Goal**: Make a character walk faster without re-rendering the video.

**File**: `WalkerCharacter.swift`

**Properties**:
```swift
// Current values (Bruce)
walkAmountRange = 0.4...0.65

// Faster walking (covers more ground per cycle)
walkAmountRange = 0.6...0.85
```

**Effect**: Character travels further during the same video duration, appearing to walk faster.

**Caveat**: If too fast, the feet will "slide" because the video animation can't match the on-screen speed.

---

## Recipe 2: Change Pause Duration

**Goal**: Make character walk more/less frequently.

**File**: `WalkerCharacter.swift`

**Property**: `pauseRange` (in `startIdlePhase()`)

```swift
// Current (after first walk)
pauseEndTime = now + Double.random(in: 2.0...5.0)

// More frequent walks
pauseEndTime = now + Double.random(in: 0.5...2.0)

// Less frequent walks
pauseEndTime = now + Double.random(in: 8.0...15.0)
```

**Effect**: Shorter pause = character moves around more. Longer pause = character stands still more.

---

## Recipe 3: Change Character Scale

**Goal**: Make character bigger or smaller.

**File**: `WalkerCharacter.swift`

**Property**: `displayHeight` (in `setup()`)

```swift
// Current
displayHeight = screenSize.height * 0.12

// 50% larger
displayHeight = screenSize.height * 0.18

// 50% smaller
displayHeight = screenSize.height * 0.06
```

**Effect**: Character window and video scale proportionally.

**Note**: May need to adjust `yOffset` after scaling to keep feet aligned with Dock.

---

## Recipe 4: Change Popover Theme

**Goal**: Switch between Classic, Modern, Terminal, Peach themes.

**File**: `PopoverTheme.swift`

**Property**: `PopoverTheme.current`

```swift
// Set programmatically
PopoverTheme.current = PopoverTheme.peach

// Or via menu (already implemented)
// Menu > Theme > [Classic | Modern | Terminal | Peach]
```

**Available Themes**:
- `PopoverTheme.classic` — Blue system style
- `PopoverTheme.modern` — Dark with subtle borders
- `PopoverTheme.terminal` — Green-on-black hacker style
- `PopoverTheme.peach` — Warm peachy tones with character-colour tinting

---

## Recipe 5: Create a Custom Theme

**Goal**: Define your own popover/bubble appearance.

**File**: `PopoverTheme.swift`

```swift
static let myTheme = PopoverTheme(
    name: "Custom",
    
    // Popover styling
    popoverBg: NSColor(white: 0.95, alpha: 0.98),
    popoverBorder: NSColor.systemBlue.withAlphaComponent(0.5),
    popoverCornerRadius: 20,
    popoverPadding: 16,
    popoverShadowColor: NSColor.black.withAlphaComponent(0.2),
    popoverShadowRadius: 10,
    
    // Title
    titleText: NSColor.labelColor,
    titleFont: .systemFont(ofSize: 12, weight: .bold),
    
    // Body text
    bodyText: NSColor.secondaryLabelColor,
    bodyFont: .systemFont(ofSize: 12, weight: .regular),
    
    // Code blocks
    codeBlockBg: NSColor(white: 0.9, alpha: 1.0),
    codeBlockBorder: NSColor(white: 0.8, alpha: 1.0),
    codeBlockCornerRadius: 6,
    codeText: NSColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1.0),
    codeFont: .monospacedSystemFont(ofSize: 11, weight: .regular),
    
    // Bubble
    bubbleBg: NSColor.white.withAlphaComponent(0.95),
    bubbleBorder: NSColor.systemBlue.withAlphaComponent(0.4),
    bubbleText: NSColor.secondaryLabelColor,
    bubbleCompletionBorder: NSColor.systemGreen.withAlphaComponent(0.6),
    bubbleCompletionText: NSColor.systemGreen,
    bubbleFont: .systemFont(ofSize: 11, weight: .medium),
    bubbleCornerRadius: 13
)
```

Then set:
```swift
PopoverTheme.current = PopoverTheme.myTheme
```

---

## Recipe 6: Disable Sounds Permanently

**Goal**: Launch with sounds disabled by default.

**File**: `WalkerCharacter.swift`

```swift
// Current
static var soundsEnabled = true

// Disabled by default
static var soundsEnabled = false
```

**To persist across launches**, add UserDefaults (see Recipe 12).

---

## Recipe 7: Add New Completion Sound

**Goal**: Add a custom notification sound.

**Steps**:

1. Add audio file to `LilAgents/Sounds/` (e.g., `ping-kk.mp3`)

2. Add to Xcode project (drag into Sounds folder in Project Navigator)

3. Update `WalkerCharacter.swift`:
```swift
private static let completionSounds: [(name: String, ext: String)] = [
    ("ping-aa", "mp3"), ("ping-bb", "mp3"), ("ping-cc", "mp3"),
    ("ping-dd", "mp3"), ("ping-ee", "mp3"), ("ping-ff", "mp3"),
    ("ping-gg", "mp3"), ("ping-hh", "mp3"), ("ping-jj", "m4a"),
    ("ping-kk", "mp3")  // NEW
]
```

---

## Recipe 8: Change Thinking Phrases

**Goal**: Customise what the bubble says while agent is thinking.

**File**: `WalkerCharacter.swift`

```swift
private static let thinkingPhrases = [
    // Replace or extend this array
    "computing...", "analyzing...", "searching...",
    "please wait", "loading brain", "neural nets firing",
    "asking the hive", "consulting oracle"
]
```

**Per-character phrases**: Currently shared. To make per-character, change from `static` to instance property.

---

## Recipe 9: Change Bubble Position

**Goal**: Move bubble higher/lower/sideways.

**File**: `WalkerCharacter.swift` — `showBubble()`

```swift
// Current (88% up character height)
let y = charFrame.origin.y + charFrame.height * 0.88

// Higher (near top of window)
let y = charFrame.origin.y + charFrame.height * 0.95

// Offset to the right
let x = charFrame.midX - bubbleW / 2 + 20
```

---

## Recipe 10: Change Walk Boundaries

**Goal**: Keep character within a smaller area of the Dock.

**File**: `WalkerCharacter.swift` — `startWalk()`

```swift
// Current (full Dock width)
let fraction = CGFloat.random(in: walkAmountRange)
walkTarget = positionProgress + (goingRight ? fraction : -fraction)
walkTarget = max(0.05, min(0.95, walkTarget))

// Restrict to middle 50%
walkTarget = max(0.25, min(0.75, walkTarget))
```

---

## Recipe 11: Change Character Z-Order

**Goal**: Make one character always appear in front.

**File**: `LilAgentsController.swift` — `tick()`

The current code sorts by `positionProgress` (lower X = higher Z):

```swift
let sortedChars = visibleChars.sorted { c1, c2 in
    c1.positionProgress < c2.positionProgress
}
for (idx, char) in sortedChars.enumerated() {
    char.window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + idx)
}
```

**To make Bruce always in front**:
```swift
for (idx, char) in sortedChars.enumerated() {
    let bonus = char.name == "Bruce" ? 10 : 0
    char.window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + idx + bonus)
}
```

---

## Recipe 12: Persist Sound Setting

**Goal**: Remember `soundsEnabled` across app launches.

**File**: `WalkerCharacter.swift`

```swift
// Replace static property with computed property
static var soundsEnabled: Bool {
    get { UserDefaults.standard.bool(forKey: "soundsEnabled") }
    set { UserDefaults.standard.set(newValue, forKey: "soundsEnabled") }
}
```

**Note**: Add default value in `LilAgentsApp.applicationDidFinishLaunching`:
```swift
UserDefaults.standard.register(defaults: ["soundsEnabled": true])
```

---

## Quick Reference Table

| Recipe | File | Key Property |
|--------|------|--------------|
| 1. Walk speed | WalkerCharacter.swift | `walkAmountRange` |
| 2. Pause duration | WalkerCharacter.swift | `pauseEndTime` |
| 3. Character scale | WalkerCharacter.swift | `displayHeight` |
| 4. Popover theme | PopoverTheme.swift | `PopoverTheme.current` |
| 5. Custom theme | PopoverTheme.swift | `PopoverTheme(...)` |
| 6. Disable sounds | WalkerCharacter.swift | `soundsEnabled` |
| 7. New sound | WalkerCharacter.swift | `completionSounds` |
| 8. Thinking phrases | WalkerCharacter.swift | `thinkingPhrases` |
| 9. Bubble position | WalkerCharacter.swift | `showBubble()` |
| 10. Walk boundaries | WalkerCharacter.swift | `startWalk()` |
| 11. Z-order | LilAgentsController.swift | `tick()` |
| 12. Persist sounds | WalkerCharacter.swift | UserDefaults |

---

## Testing Your Changes

After any customisation:

1. **Build** (⌘B) to check for compile errors
2. **Run** (⌘R) to see changes live
3. **Watch** the character for at least 30 seconds to see walking/pausing
4. **Trigger** agent activity to test bubbles
5. **Toggle** sounds to test audio
6. **Quit and relaunch** to test persistence
