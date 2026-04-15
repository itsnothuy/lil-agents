# 10 — Follow-Up Test Plan

**Date:** 2026-04-15

## Manual QA Checklist

These tests require running the app interactively in Xcode and physically interacting with the characters.

### Click Behavior

- [ ] Short click on character opens popover
- [ ] Short click on character with popover open closes popover
- [ ] Click + tiny movement (< 5px) still opens popover
- [ ] Click does not produce visual glitch or flash
- [ ] Repeated rapid clicks work correctly (open/close/open)
- [ ] Click on character during onboarding opens onboarding popover

### Drag Behavior

- [ ] Click and hold, then drag > 5px — character follows cursor
- [ ] Drag feels smooth with no jitter or lag
- [ ] Character walking animation stops when drag begins
- [ ] Can drag character vertically (above/below dock)
- [ ] Can drag character horizontally to any position
- [ ] Releasing after drag does NOT open popover
- [ ] After drop, character stays at drop position
- [ ] After drop, walking resumes after ~2 seconds from new position
- [ ] Character does not teleport back to pre-drag position

### Fling Behavior

- [ ] Fast drag + release produces visible fling slide
- [ ] Slide decelerates smoothly (no sudden stop)
- [ ] Slide bounces off left dock boundary
- [ ] Slide bounces off right dock boundary
- [ ] Bounce does not cause infinite oscillation
- [ ] Slide always comes to a stop (no permanent sliding)
- [ ] After slide stops, walking resumes from final position
- [ ] Slow drag + release does NOT produce fling (velocity < 50)

### Multi-Character Interaction

- [ ] Dragging one character does not affect the other
- [ ] Flinging one character while the other walks — both behave correctly
- [ ] Dragging to where the other character is — no crash or weird overlap

### Edge Cases

- [ ] Drag character, then Cmd+Tab away — app doesn't crash
- [ ] Fling near edge of dock area — bounces cleanly
- [ ] Drag during active Claude/Gemini response — thinking bubble hides properly
- [ ] Open popover, then try to drag — verify interaction model is correct
- [ ] Dock auto-hide triggers during drag — character doesn't break

### Feature Flag Verification

- [ ] Set `WalkerCharacter.dragEnabled = false` — click opens popover directly
- [ ] With flag off, no drag or fling behavior occurs
- [ ] With flag off, no visual or behavioral difference from pre-feature state

### Regression Checklist

- [ ] Normal walking works (characters move left/right on dock)
- [ ] Popover opens and closes correctly
- [ ] Chat input works (send message, receive response)
- [ ] Thinking bubble appears during agent processing
- [ ] Completion bubble appears after agent finishes
- [ ] Sounds play on completion
- [ ] Provider switching works
- [ ] Session refresh works
- [ ] Hide/show characters from menu bar works
- [ ] Theme changes work
- [ ] Size changes work
- [ ] Multiple screens — characters appear on correct screen

## Automated Test Ideas (Future)

If the project adds unit tests:

1. `syncPositionFromWindow()` — verify progress calculation with known inputs
2. Velocity smoothing — verify smoothing reduces noise vs raw sampling
3. State machine — verify `isBeingDragged → endDrag → isSliding → syncPosition` transitions
4. Feature flag — verify no state changes when `dragEnabled = false`
5. Bounce bounds — verify clamping to `dockX`/`dockX + travelDistance`

## Known Gaps

| Gap | Impact | Mitigation |
|-----|--------|-----------|
| No automated test coverage | Manual regression risk | Feature flag allows quick disable |
| Multi-monitor drag not tested | Possible position weirdness | Characters constrained to dock screen by controller |
| Retina/non-retina scaling | Threshold might feel different | 5px threshold should work at all scales |
| VoiceOver accessibility | Drag may not be accessible | Click-to-popover still works; drag is convenience only |
