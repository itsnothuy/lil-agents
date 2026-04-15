# 01 — Overview: Drag & Fling Characters

**Date:** 2026-04-15  
**Branch:** `main` (itsnothuy/lil-agents)  
**Source PR:** [ryanstephen/lil-agents#9](https://github.com/ryanstephen/lil-agents/pull/9) — "feat: drag and fling characters to reposition them"  
**PR Author:** akdenizemirhan  
**PR Status:** Open, not merged. Repo owner commented: *"This is fun, but a little glitchy in practice."*

## Feature Summary

Characters sometimes walk in front of UI elements the user needs. This feature adds:

- **Click + drag** to reposition a character (5px threshold prevents accidental drags)
- **Short click** still opens the chat popover (unchanged behavior)
- **Fling** the character and it slides with friction, bouncing off travel bounds
- **Walking resumes** from the new position after 2 seconds

## Integration Decision

**Re-implement cleanly** on the current branch. The PR was not merged as-is because:

1. The ClaudeSession fix in the PR is already present on our branch
2. The PR has several glitch-causing bugs (see `05_glitches_and_root_causes.md`)
3. The PR's bounce logic uses screen edges instead of dock travel bounds
4. The PR has a stale type reference (`Message` vs `AgentMessage`)

## Documents in This Folder

| File | Description |
|------|-------------|
| `01_overview.md` | This file — index and context |
| `02_pr_review_summary.md` | What the PR changes, concern separation |
| `03_compatibility_assessment.md` | Current-branch compatibility analysis |
| `04_functional_validation.md` | Validation scenarios and pass/fail |
| `05_glitches_and_root_causes.md` | Defect list with root causes |
| `06_architecture_and_reversibility.md` | Unplug-ability and architecture |
| `07_merge_recommendation.md` | Final merge/reject decision |
| `08_implementation_summary.md` | What was actually changed |
| `09_rollback_plan.md` | How to revert |
| `10_follow_up_test_plan.md` | QA and regression checklist |

## Recommended Reading Order

1. `02_pr_review_summary.md` — understand what the PR does
2. `03_compatibility_assessment.md` — understand why it can't merge directly
3. `05_glitches_and_root_causes.md` — understand the glitches
4. `07_merge_recommendation.md` — the decision
5. `08_implementation_summary.md` — what was actually done
6. `06_architecture_and_reversibility.md` — how to disable/remove
7. `09_rollback_plan.md` — if it needs to be reverted
