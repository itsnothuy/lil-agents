# filename: 05-ui-state-and-session-architecture.md

# UI, State, and Session Architecture Deep Dive

## App Lifecycle: SwiftUI Shell → Pure AppKit

The app uses SwiftUI's `@main` attribute and `App` protocol, but **only as a bootstrap**:

```swift
@main
struct LilAgentsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}
```

The `body` is an empty `Settings` scene. All actual UI is pure AppKit, created programmatically by `AppDelegate` and `LilAgentsController`. This is a **hybrid-driven** app in name only — it is effectively a **100% AppKit app** that uses SwiftUI only for the `@main` entrypoint.

## Central Coordinator: `LilAgentsController`

### Responsibilities
1. Instantiates and configures characters (hardcoded Bruce + Jazz)
2. Owns and runs the `CVDisplayLink` tick loop
3. Calculates Dock geometry from `com.apple.dock` defaults
4. Determines active screen and character visibility
5. Orchestrates per-frame updates for all characters
6. Manages z-order (window levels) based on position
7. Handles onboarding flow

### What it does NOT do (but should)
- Does not manage session lifecycle (that's in `WalkerCharacter`)
- Does not handle theme changes (that's in `AppDelegate`)
- Does not manage popover state (that's in `WalkerCharacter`)
- Does not persist any state except the onboarding flag

### Control Flow: App Startup

```
1. applicationDidFinishLaunching
2. NSApp.setActivationPolicy(.accessory)  — hide from Dock
3. controller = LilAgentsController()
4. controller.start()
   a. Create Bruce & Jazz WalkerCharacter instances
   b. Set per-character animation parameters (hardcoded)
   c. detectAvailableProviders (async, shells out to zsh)
   d. Set first-run provider defaults if !onboarding
   e. char.setup() for each → create NSWindow + AVPlayerLayer
   f. characters = [char1, char2]; set controller backref
   g. setupDebugLine() → hidden red 2px window
   h. startDisplayLink() → CVDisplayLink at display refresh rate
   i. If !onboarding → triggerOnboarding() after 2s
5. setupMenuBar()
   a. Create NSStatusItem with MenuBarIcon
   b. Build NSMenu with: Bruce, Jazz toggles, Sounds toggle,
      Provider submenu, Size submenu, Theme submenu,
      Display submenu, Check for Updates, Quit
```

### Control Flow: Central Controller Tick

```
tick() — called at display refresh rate (60–120 Hz)
    1. Get activeScreen
       - If pinnedScreenIndex set → use that screen
       - Else find screen where screenHasDock() is true
       - Else fallback: primary screen (menu bar visible)
       - Else: first screen
    2. updateEnvironmentVisibility(for: screen)
       - shouldShowCharacters() → check dock presence
       - If visibility changed:
         - Hide: orderOut all windows, pause players
         - Show: orderFront, resume walking if needed,
                 restore popover/bubble state
    3. getDockIconArea() → compute dockX, dockWidth
    4. dockTopY = screen.visibleFrame.origin.y
    5. updateDebugLine (if visible)
    6. Filter to active (visible + manually visible) characters
    7. Pause management: if paused and timer expired → allow walk
    8. For each character: char.update(dockX, dockWidth, dockTopY)
    9. Sort by positionProgress → assign window levels
```

## Character Model / Lifecycle: `WalkerCharacter`

### The God Object Problem

`WalkerCharacter` is 1007 lines and owns:

| Concern | Properties/Methods |
|---|---|
| **Identity** | `name`, `videoName`, `characterColor` |
| **Config** | `provider`, `size`, animation timing constants |
| **Video** | `queuePlayer`, `looper`, `playerLayer` |
| **Window** | `window`, `displayWidth`, `displayHeight` |
| **Walk state** | `isWalking`, `isPaused`, `goingRight`, `positionProgress`, `walkStart/EndPos`, `walkStart/EndPixel`, `pauseEndTime`, `currentTravelDistance` |
| **Popover** | `popoverWindow`, `terminalView`, `isIdleForPopover`, `createPopoverWindow()` |
| **Session** | `session`, `currentStreamingText`, `wireSession()`, `resetSession()` |
| **Events** | `clickOutsideMonitor`, `escapeKeyMonitor` |
| **Bubble** | `thinkingBubbleWindow`, `currentPhrase`, `showingCompletion`, `completionBubbleExpiry` |
| **Sounds** | `playCompletionSound()`, `soundsEnabled` |
| **Onboarding** | `isOnboarding`, `openOnboardingPopover()` |
| **Visibility** | `isManuallyVisible`, `environmentHiddenAt`, restore state |

This class needs to be decomposed into at least 4–5 separate types.

### Control Flow: Character Session Lifecycle

```
1. User clicks character → handleClick()
2. openPopover()
   a. Close any sibling's popover
   b. Stop walking, pause video
   c. If no session: provider.createSession() + wireSession() + start()
   d. If no popover window: createPopoverWindow()
   e. Replay history if session has messages
   f. Position and show popover, focus input
   g. Install click-outside and ESC monitors
3. User types and sends message
   a. TerminalView.inputSubmitted() → onSendMessage → session.send()
   b. Session writes to CLI stdin / launches process
   c. Streaming responses arrive via readabilityHandler
   d. wireSession callbacks: onText → appendStreamingText,
      onToolUse → appendToolUse, onTurnComplete → endStreaming + sound + bubble
4. User closes popover (click outside or ESC)
   a. Hide popover window (don't destroy)
   b. Remove event monitors
   c. Show bubble if busy or just completed
   d. Schedule walk resume
5. Session persists across popover open/close cycles
6. resetSession() — via /clear or refresh button
   a. Terminate old session, create new one
   b. Clear terminal, show "✦ new session"
7. Provider switch — via menu or popover dropdown
   a. Terminate session, nil out
   b. Destroy popover + terminal + bubble windows
   c. openPopover() creates fresh everything
```

## Animation / Rendering Strategy

### Video Rendering
- Characters are rendered as **transparent HEVC `.mov` videos** via `AVPlayerLayer`
- `AVQueuePlayer` + `AVPlayerLooper` for seamless looping
- Video dimensions: 1080×1920 (portrait), scaled to display height (100/150/200px)
- Walk animation is in the video itself; code just positions the window

### Movement Model
- `movementPosition(at:)` implements a **trapezoidal velocity profile**:
  - Idle → accelerate → constant speed → decelerate → idle
  - Parameters match the video's walk keyframes
- Walk direction: random, biased away from edges, avoids overlapping siblings
- Walk distance: random pixels (200–325px range), stored in pixels for consistency across screen changes
- Walk cycle: 10-second video duration, then 5–12 second pause

### Flip Handling
- `goingRight = false` → `CATransform3DMakeScale(-1, 1, 1)` on player layer
- `flipXOffset` compensates for asymmetric character sprites

## Terminal / Popup Rendering

### `TerminalView` (522 lines)
- `NSScrollView` containing `NSTextView` (output) + `NSTextField` (input)
- Custom `PaddedTextFieldCell` for input field styling
- Markdown renderer handles: headings, bold, inline code, code blocks, bullet lists, links, bare URLs
- Slash commands: `/clear`, `/copy`, `/help`
- Auto-scrolls to bottom on each append

### Popover Window
- `KeyableWindow` (can become key/main) at `statusBar + 10`
- Fixed size: 420×310 px
- Title bar: 28px with provider name, dropdown, refresh, copy buttons
- Appearance auto-detected from theme background brightness

### Limitations
- No resizing
- No search/find in chat
- No scrollbar customization
- No accessibility (VoiceOver, Dynamic Type)
- No image rendering (only text/markdown)
- No code syntax highlighting (just monospaced font + background)

## Theme / Styling System

### `PopoverTheme` (struct, ~30 properties)

Four presets:
| Name | Internal ID | Character | Visual Style |
|---|---|---|---|
| Peach | `.playful` | Warm, rounded | System font, rounded corners, pink accent |
| Midnight | `.teenageEngineering` | Dark, technical | SFMono, sharp, orange accent |
| Cloud | `.wii` | Light, clean | System font, blue accent |
| Moss | `.iPod` | Retro, green-gray | Geneva/Chicago fonts, minimal accent |

### Theme Modifiers
- `withCharacterColor()` — **only applies to Peach theme**. Tints border, title bar, accent, and bubble colors based on character's color. Other themes ignore it.
- `withCustomFont()` — replaces font with `.AppleSystemUIFontRounded` at size 13. **Skipped for Midnight** (keeps SFMono).
- `customFontName` and `customFontSize` are **static vars** on `PopoverTheme` — effectively globals.

### Theme Persistence
- Stored via `UserDefaults["selectedThemeName"]`
- Theme switching rebuilds all open popover windows to apply new colors/fonts

## Dock Geometry Logic

### `getDockIconArea(screenWidth:)`
Reads from `UserDefaults(suiteName: "com.apple.dock")`:
- `tilesize` (default 48)
- `persistent-apps` array count
- `persistent-others` array count  
- `show-recents` bool
- `recent-apps` array count

Calculates slot width, divider count, total width, applies 1.15× fudge factor, centers on screen.

### Known Issues
- Fallback if `persistent-apps == 0 && persistent-others == 0`: assumes 5 + 3 icons
- Does not handle Dock `orientation` (left/right positioning)
- Does not handle Dock magnification
- The 1.15× fudge factor is empirical, not derived from Dock rendering math

### `DockVisibility`
Pure functions comparing `screen.frame` vs `screen.visibleFrame`:
- Dock visible if `visibleFrame` is smaller than `frame` on any edge
- Auto-hide: show on main screen if menu bar is visible

## Window Layering / Z-Order

```
Level                  Window                          When visible
statusBar + 10         Debug line, Popover window      Debug: manual toggle. Popover: when character clicked.
statusBar + 5          Thinking bubble                 When agent is busy and popover is closed
statusBar + 0..N       Character windows               Always (sorted by x-position each frame)
```

**Concern**: The bubble at `statusBar + 5` will render behind the popover at `statusBar + 10`, which is correct. But if two characters both have visible bubbles, they share the same level and may z-fight.

## Session Ownership and Cleanup

| Event | Session | Popover Window | Terminal | Bubble |
|---|---|---|---|---|
| Popover close | **Kept alive** | Hidden (not destroyed) | Kept | May show |
| Provider switch | Terminated + nil'd | Destroyed | Destroyed | Destroyed |
| `/clear` or refresh | Terminated, new one created | Kept | Reset | Hidden |
| App quit | Terminated | — | — | — |
| Character hidden | Kept alive | Hidden | — | Hidden |

**Key observation**: Sessions survive popover close. This means the CLI process keeps running (and potentially using resources) even when the popover is hidden. For Claude (persistent process), this is a background process consuming memory. For per-turn providers, the session just holds history.

## Where State Lives

| State | Location | Persistence |
|---|---|---|
| Character position/walk state | `WalkerCharacter` mutable properties | **None** — reset on app restart |
| Provider selection | `UserDefaults["{name}Provider"]` | Persisted |
| Character size | `UserDefaults["{name}Size"]` | Persisted |
| Theme | `UserDefaults["selectedThemeName"]` | Persisted |
| Onboarding flag | `UserDefaults["hasCompletedOnboarding"]` | Persisted |
| Conversation history | `session.history: [AgentMessage]` | **Memory only** — lost on quit |
| Streaming text | `WalkerCharacter.currentStreamingText` | Memory only |
| Provider availability | `AgentProvider.availability` static dict | Memory only |
| Shell environment | `ShellEnvironment.cachedEnvironment` static dict | Memory only |
| Binary paths | Static vars on each Session class | Memory only |
| Sounds enabled | `WalkerCharacter.soundsEnabled` static var | **Memory only** — resets to true |
| Display pin | `LilAgentsController.pinnedScreenIndex` | **Memory only** — resets to -1 |

**Critical gap**: Sounds enabled and display pinning are not persisted. They reset every app launch.

## Brittleness / Hardcoding Inventory

1. **Two characters hardcoded** in `LilAgentsController.start()` — names, video files, animation timings, colors, offsets all inline
2. **Character toggle menu items** hardcoded as `toggleChar1`/`toggleChar2` with array index access
3. **Popover size** fixed at 420×310
4. **Title bar height** fixed at 28px
5. **Bubble height** fixed at 26px
6. **Sound file list** hardcoded in `WalkerCharacter`
7. **Custom font** hardcoded as `.AppleSystemUIFontRounded`
8. **Theme list** hardcoded as `[.playful, .teenageEngineering, .wii, .iPod]`
9. **Working directory** always `~` for all CLI processes
10. **Fudge factor** 1.15× for Dock width calculation
