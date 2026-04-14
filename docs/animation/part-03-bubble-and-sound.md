# Part 3 — Bubble and Sound System

> Thinking bubbles, completion notifications, and audio feedback.

---

## 3.1 Thinking Bubble Overview

The thinking bubble is a small floating window that appears above the character when the AI agent is processing a request. It displays rotating phrases like "thinking...", "on it!", "almost...".

### Window Setup

```swift
private func createThinkingBubble() {
    let t = resolvedTheme
    let w: CGFloat = 80
    let h = Self.bubbleH  // 26 points
    let win = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: w, height: h),
        styleMask: .borderless, backing: .buffered, defer: false
    )
    win.isOpaque = false
    win.backgroundColor = .clear
    win.hasShadow = true
    win.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 5)
    win.ignoresMouseEvents = true
    win.collectionBehavior = [.moveToActiveSpace, .stationary]

    let container = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
    container.wantsLayer = true
    container.layer?.backgroundColor = t.bubbleBg.cgColor
    container.layer?.cornerRadius = t.bubbleCornerRadius
    container.layer?.borderWidth = 1
    container.layer?.borderColor = t.bubbleBorder.cgColor

    let font = t.bubbleFont
    let lineH = ceil(("Xg" as NSString).size(withAttributes: [.font: font]).height)
    let labelY = round((h - lineH) / 2) - 1

    let label = NSTextField(labelWithString: "")
    label.font = font
    label.textColor = t.bubbleText
    label.alignment = .center
    label.drawsBackground = false
    label.isBordered = false
    label.isEditable = false
    label.frame = NSRect(x: 0, y: labelY, width: w, height: lineH + 2)
    label.tag = 100  // Tag for later retrieval
    container.addSubview(label)

    win.contentView = container
    thinkingBubbleWindow = win
}
```

### Key Properties

| Property | Value | Purpose |
|----------|-------|---------|
| `level` | `.statusBar + 5` | Above the character window (`.statusBar + 0-2`) but below the popover (`.statusBar + 10`) |
| `ignoresMouseEvents` | `true` | Clicks pass through to the character or desktop below |
| `tag = 100` | — | Allows retrieval of the label via `viewWithTag(100)` for text updates |

---

## 3.2 Bubble Positioning

```swift
func showBubble(text: String, isCompletion: Bool) {
    let t = resolvedTheme
    if thinkingBubbleWindow == nil {
        createThinkingBubble()
    }

    let h = Self.bubbleH  // 26
    let padding: CGFloat = 16
    let font = t.bubbleFont
    let textSize = (text as NSString).size(withAttributes: [.font: font])
    let bubbleW = max(ceil(textSize.width) + padding * 2, 48)

    let charFrame = window.frame
    let x = charFrame.midX - bubbleW / 2
    let y = charFrame.origin.y + charFrame.height * 0.88
    thinkingBubbleWindow?.setFrame(CGRect(x: x, y: y, width: bubbleW, height: h), display: false)
    
    // ... styling and display ...
}
```

### Position Calculation

| Coordinate | Formula | Result |
|------------|---------|--------|
| X (centre) | `charFrame.midX - bubbleW / 2` | Bubble centred horizontally over character |
| Y | `charFrame.origin.y + charFrame.height * 0.88` | 88% up the character window (near head level) |

For a 200-point tall character:
- `y = charFrame.origin.y + 176` — bubble appears near the character's "head"

### Dynamic Width

```swift
let textSize = (text as NSString).size(withAttributes: [.font: font])
let bubbleW = max(ceil(textSize.width) + padding * 2, 48)
```

The bubble width adapts to the text content:
- Measure text width with the theme's bubble font
- Add 32 points of padding (16 on each side)
- Minimum width: 48 points (prevents tiny bubbles for short phrases like "hi!")

---

## 3.3 Phrase Rotation

### Thinking Phrases

```swift
private static let thinkingPhrases = [
    "hmm...", "thinking...", "one sec...", "ok hold on",
    "let me check", "working on it", "almost...", "bear with me",
    "on it!", "gimme a sec", "brb", "processing...",
    "hang tight", "just a moment", "figuring it out",
    "crunching...", "reading...", "looking...",
    "cooking...", "vibing...", "digging in",
    "connecting dots", "give me a sec",
    "don't rush me", "calculating...", "assembling\u{2026}"
]
```

### Completion Phrases

```swift
private static let completionPhrases = [
    "done!", "all set!", "ready!", "here you go", "got it!",
    "finished!", "ta-da!", "voila!",
    "boom!", "there ya go!", "check it out!"
]
```

### Update Logic

```swift
private func updateThinkingPhrase() {
    let now = CACurrentMediaTime()
    if currentPhrase.isEmpty || now - lastPhraseUpdate > Double.random(in: 3.0...5.0) {
        var next = Self.thinkingPhrases.randomElement() ?? "..."
        while next == currentPhrase && Self.thinkingPhrases.count > 1 {
            next = Self.thinkingPhrases.randomElement() ?? "..."
        }
        currentPhrase = next
        lastPhraseUpdate = now
    }
}
```

| Condition | Action |
|-----------|--------|
| `currentPhrase.isEmpty` | Pick a random phrase immediately |
| `now - lastPhraseUpdate > random(3.0...5.0)` | Pick a new phrase after 3–5 seconds |
| `next == currentPhrase` | Re-roll to avoid showing the same phrase twice in a row |

---

## 3.4 Phrase Animation

```swift
private func animatePhraseChange(to newText: String, isCompletion: Bool) {
    guard let win = thinkingBubbleWindow, win.isVisible,
          let label = win.contentView?.viewWithTag(100) as? NSTextField else {
        showBubble(text: newText, isCompletion: isCompletion)
        return
    }
    phraseAnimating = true

    // Fade out
    NSAnimationContext.runAnimationGroup({ ctx in
        ctx.duration = 0.2
        ctx.allowsImplicitAnimation = true
        label.animator().alphaValue = 0.0
    }, completionHandler: { [weak self] in
        // Update text while invisible
        self?.showBubble(text: newText, isCompletion: isCompletion)
        label.alphaValue = 0.0
        
        // Fade in
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.allowsImplicitAnimation = true
            label.animator().alphaValue = 1.0
        }, completionHandler: {
            self?.phraseAnimating = false
        })
    })
}
```

### Animation Timeline

```
Time  0.0s           0.2s                 0.45s
      │              │                    │
      ▼              ▼                    ▼
      ┌──────────────┬────────────────────┐
      │ Fade out     │ Fade in            │
      │ old text     │ new text           │
      │ alpha: 1→0   │ alpha: 0→1         │
      └──────────────┴────────────────────┘
                     ▲
                     │
              Text changes here
              (invisible, alpha=0)
```

The `phraseAnimating` flag prevents overlapping animations if `updateThinkingBubble` is called during the transition.

---

## 3.5 Thinking vs. Completion Bubbles

### State Management

```swift
var currentPhrase = ""
var completionBubbleExpiry: CFTimeInterval = 0
var showingCompletion = false
```

### Thinking Bubble Logic

```swift
func updateThinkingBubble() {
    let now = CACurrentMediaTime()

    if showingCompletion {
        // Handle completion bubble expiry
        if now >= completionBubbleExpiry {
            showingCompletion = false
            hideBubble()
            return
        }
        if isIdleForPopover {
            completionBubbleExpiry += 1.0 / 60.0  // Pause timer while popover open
            hideBubble()
        } else {
            showBubble(text: currentPhrase, isCompletion: true)
        }
        return
    }

    if isAgentBusy && !isIdleForPopover {
        // Show thinking bubble
        let oldPhrase = currentPhrase
        updateThinkingPhrase()
        if currentPhrase != oldPhrase && !oldPhrase.isEmpty && !phraseAnimating {
            animatePhraseChange(to: currentPhrase, isCompletion: false)
        } else if !phraseAnimating {
            showBubble(text: currentPhrase, isCompletion: false)
        }
    } else if !showingCompletion {
        hideBubble()
    }
}
```

### Completion Bubble Trigger

```swift
func showCompletionBubble() {
    currentPhrase = Self.completionPhrases.randomElement() ?? "done!"
    showingCompletion = true
    completionBubbleExpiry = CACurrentMediaTime() + 3.0  // 3-second display
    lastPhraseUpdate = 0
    phraseAnimating = false
    if !isIdleForPopover {
        showBubble(text: currentPhrase, isCompletion: true)
    }
}
```

Called from `onTurnComplete` when the AI agent finishes responding.

### Visual Differences

| Aspect | Thinking | Completion |
|--------|----------|------------|
| Border color | `t.bubbleBorder` (theme accent) | `t.bubbleCompletionBorder` (green) |
| Text color | `t.bubbleText` (muted) | `t.bubbleCompletionText` (bright green) |
| Duration | While `isAgentBusy` | Fixed 3 seconds |
| Phrases | 26 thinking phrases | 11 completion phrases |

---

## 3.6 Bubble Visibility Rules

| State | Bubble Shown? |
|-------|---------------|
| Character idle, no agent activity | ❌ No |
| Agent busy, popover closed | ✅ Thinking bubble |
| Agent busy, popover open | ❌ No (popover shows response) |
| Response complete, popover closed | ✅ Completion bubble (3s) |
| Response complete, popover open | ❌ No (expiry paused) |
| Character hidden (environment change) | ❌ No (timing paused) |

---

## 3.7 Sound System

### Sound List

```swift
private static let completionSounds: [(name: String, ext: String)] = [
    ("ping-aa", "mp3"), ("ping-bb", "mp3"), ("ping-cc", "mp3"),
    ("ping-dd", "mp3"), ("ping-ee", "mp3"), ("ping-ff", "mp3"),
    ("ping-gg", "mp3"), ("ping-hh", "mp3"), ("ping-jj", "m4a")
]
```

Nine different completion sounds provide variety. The last sound is `.m4a` format.

### Sound Selection (No Repeats)

```swift
private static var lastSoundIndex: Int = -1

func playCompletionSound() {
    guard Self.soundsEnabled else { return }
    var idx: Int
    repeat {
        idx = Int.random(in: 0..<Self.completionSounds.count)
    } while idx == Self.lastSoundIndex && Self.completionSounds.count > 1
    Self.lastSoundIndex = idx

    let s = Self.completionSounds[idx]
    if let url = Bundle.main.url(forResource: s.name, withExtension: s.ext, subdirectory: "Sounds"),
       let sound = NSSound(contentsOf: url, byReference: true) {
        sound.play()
    }
}
```

### Key Details

| Aspect | Implementation |
|--------|----------------|
| No repeat | `repeat-while` loop ensures different sound each time |
| Bundle location | Sounds are in `LilAgents/Sounds/` subdirectory |
| Loading | `NSSound(contentsOf:byReference:)` streams from disk (efficient for short clips) |
| Global toggle | `WalkerCharacter.soundsEnabled` static property |

### Sound Toggle (Menu Bar)

```swift
@objc func toggleSounds(_ sender: NSMenuItem) {
    WalkerCharacter.soundsEnabled.toggle()
    sender.state = WalkerCharacter.soundsEnabled ? .on : .off
}
```

**Note**: `soundsEnabled` is not persisted to `UserDefaults`, so it resets to `true` on every app launch. This is a known limitation (see Part 8).

---

## 3.8 Theme Integration

The bubble's appearance is controlled by the current `PopoverTheme`:

```swift
var resolvedTheme: PopoverTheme {
    (themeOverride ?? PopoverTheme.current).withCharacterColor(characterColor).withCustomFont()
}
```

### Theme Properties Used

| Property | Purpose |
|----------|---------|
| `bubbleBg` | Background color |
| `bubbleBorder` | Border color (thinking) |
| `bubbleText` | Text color (thinking) |
| `bubbleCompletionBorder` | Border color (completion) |
| `bubbleCompletionText` | Text color (completion) |
| `bubbleFont` | Font for bubble text |
| `bubbleCornerRadius` | Corner rounding |

### Example: Peach Theme

```swift
bubbleBg: NSColor(red: 1.0, green: 0.95, blue: 0.90, alpha: 0.95),
bubbleBorder: NSColor(red: 0.95, green: 0.55, blue: 0.65, alpha: 0.6),
bubbleText: NSColor(red: 0.55, green: 0.5, blue: 0.52, alpha: 1.0),
bubbleCompletionBorder: NSColor(red: 0.3, green: 0.75, blue: 0.5, alpha: 0.7),
bubbleCompletionText: NSColor(red: 0.2, green: 0.6, blue: 0.4, alpha: 1.0),
bubbleFont: .systemFont(ofSize: 11, weight: .semibold),
bubbleCornerRadius: 14
```

This gives a warm peachy bubble with coral accents for thinking and green accents for completion.
