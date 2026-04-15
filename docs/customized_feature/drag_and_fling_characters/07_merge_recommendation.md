# 07 — Merge Recommendation

**Date:** 2026-04-15

## Decision: Re-implement Feature Cleanly (Option 3)

Not "merge as-is" (Option 1), not "cherry-pick" (Option 2), not "reject" (Option 4).

## Rationale

### Why not merge the PR as-is?

1. **ClaudeSession fix already exists** on our branch with a different variable name (`currentResponseText` vs `currentStreamingResponse`). Merging would introduce a duplicate or conflict.
2. **Type mismatch** (`Message` vs `AgentMessage`) would cause a compile failure.
3. **Four UX/correctness bugs** in the drag/fling implementation (velocity noise, screen-edge bounce, frozen slideY, no video pause).
4. **No feature flag** — no way to disable without code revert.

### Why not cherry-pick?

Cherry-picking commit `5c63fa7` (drag/fling only) would avoid the ClaudeSession conflict but still bring in the four glitch-causing bugs. Fixing them post-cherry-pick produces worse git history than a clean implementation.

### Why not reject?

The feature has genuine value:
- Characters **do** walk in front of important UI elements
- Drag-to-reposition is a natural interaction for desktop companions
- Fling physics adds personality consistent with the app's character
- The architecture fits cleanly into the existing code

### Why re-implement?

- Fixes all known glitches from the start
- Adapts to our branch's existing fixes (UserDefaults, walk state machine, etc.)
- Adds feature flag for safety
- Clean git history with no conflict resolution artifacts

## Specific Answers

### Is the drag/fling feature worth integrating now?

**Yes.** It solves a real problem (characters blocking UI), is low-risk with the feature flag, and easy to unplug.

### Is the ClaudeSession fix worth integrating separately?

**No — it's already implemented.** Our branch has `currentResponseText` in `ClaudeSession.swift` performing the same accumulation and history-append logic.

### Should these land as one change or two?

**One change** — only the drag/fling feature is being integrated. The ClaudeSession fix is already present and should not be touched.

### What is the smallest safe merge unit?

The drag/fling feature as implemented:
- `CharacterContentView.swift` — input handling (mouseDown/mouseDragged/mouseUp)
- `WalkerCharacter.swift` — drag state, methods, update() integration

These two files constitute one atomic feature. They cannot be meaningfully split further.
