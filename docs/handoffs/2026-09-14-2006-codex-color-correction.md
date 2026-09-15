---
date: 2026-09-14 20:06 America/Chicago
tool: codex
model: GPT-6 (Astra)
repo: eikerd/CropTrimmer
branch: codex/color-correction-handoff
pr: https://github.com/eikerd/CropTrimmer/pull/3
state: pr-open
deployed: no
loose_ends: 1 (open documentation PR; implementation has not started)
supersedes: none
---

# Color correction plan and next-agent instructions

## What changed, and why

The complete Slack assessment is now a tracked execution plan at `docs/plans/color-correction.md`, discoverable from README. It separates manual correction, saved looks, matching-frame fitting, model benchmarking, and provider integration into bounded packets with ownership and acceptance tests. The first packet, C00, is a required rendering experiment: it must establish color-space conversions and actual playback/export parity before smaller agents implement controls.

No application behavior, tests, dependencies, credentials, or Slack configuration changed. Every implementation packet is not started. Proposed numerical thresholds and control bounds must be resolved with evidence rather than treated as existing behavior.

## Where it is

- First commit: `7d8f70f` — docs: plan color correction and define first implementation gate.
- Plan: `docs/plans/color-correction.md`.
- Discovery link: `README.md`, Planned color correction.
- This handoff: `docs/handoffs/2026-09-14-2006-codex-color-correction.md`.
- Working folder: the repository root; no additional worktree was created.
- Baseline reviewed: `dfb96c8ed04f25673214ad301b6a3f8add1a62eb`.
- Verified earlier this session: `swift test`, 30 XCTest tests, zero failures, approximately 20 seconds. No rerun is needed for these documentation-only edits. The temporary baseline log was `/tmp/croptrimmer-color-plan-baseline.log`; it is not a portable test artifact.
- Verified during handoff: working tree/sweep, open PR inventory, source-file references, documentation links, and whitespace checks.

## What is deployed

Nothing from this task. The packaged application has not been rebuilt or replaced. This PR does not implement color correction.

## Loose ends

- Documentation PR #3 is open; three completed review rounds and the scorecard are required before merge. Check actual reviewer results rather than counting silence as a clean round.
- Review services at handoff: Copilot explicitly reported its quota exhausted; Greptile explicitly reported its trial ended. Neither performed a review. CodeRabbit accepted the request and was still processing; no completed substantive review had been returned. Do not count these as three rounds or create a scorecard claiming MERGED. Recheck the PR for results before requesting additional review.
- ECC Tools posted security-evidence and taxonomy success comments, plus generic reference-corpus suggestions unrelated to this documentation task. Its comments also report missing permission to publish GitHub checks. These comments are not application tests or substantive review rounds; no service permissions were changed.
- At the start of this task the checkout was clean, `main` matched `origin/main`, there were no open PRs, no stashes, and no additional worktrees. The only task branch created here is `codex/color-correction-handoff`, pushed with PR #3.
- Source rendering parity, paused-player updates, LUT interpolation, missing-metadata policy, and actual target-PC model performance remain unmeasured. These are explicitly listed future work, not passed tests.

## Next agent: start here

1. Read this note and `docs/plans/color-correction.md`. Run the session sweep and check PR #3 before editing; resolve or finish the documentation PR first under the one-active-PR rule. Read CodeRabbit's completed response if available; the other reviewers' availability failures are recorded above. No override of the three-round requirement was requested or granted.
2. Use the existing project directory. Project instructions prohibit making another checkout/worktree without permission. Do not edit another agent's dirty checkout or branch.
3. Begin **C00**, not the sliders and not a model server. Produce reproducible synthetic color fixtures and compare actual AVFoundation-rendered frames with the FFmpeg path before lossy encoding and after a production encode.
4. Current FFmpeg 8.0.1 has `lut3d` and `colorspace`, but no `zscale`. `lut3d` defaults to tetrahedral interpolation. Prove the explicit conversion and interpolation path with the tools that will actually be packaged.
5. Finish the C00 checklist: exact equations, working domain, conversions, channel order, metadata policy, interpolation, LUT grid, measured errors, thresholds, paused updates, orientation, and executable test commands. Record the result in tracked documentation and tests.
6. Only then freeze interfaces and assign C01–C06. Keep one writer each for `Models.swift`, `MediaEngine.swift`, `EditorModel.swift`, and `QueueLoopCard.swift`; hand ownership over explicitly. Each worker must report actual tests and unresolved issues.
7. Preserve exclusive output publication, source identity checks, independent loop settings, timeline origins, existing crop geometry and audio behavior. Color changes require estimate invalidation, immutable queue snapshots, and color-only quality controls.
8. Render visual changes and obtain explicit owner approval before committing them. This planning approval is not approval of an unseen UI.
9. Ship manual correction and saved looks independently of AI. Matching before/after frames and unrelated reference images are different tasks; do not fit unrelated pixels with the paired-frame solver.

## Decided by the owner

- “I want to get your assessment of the conversation on Slack and then formulate a plan to execute it. Be very thorough so that modest sub-agents can carry it out and test it.” — produce a source-grounded execution plan with bounded tasks and tests.
- “Continue. With leaving the instructions if you're done document for next agents.” — check the plan into the repository with a tracked handoff and visible PR.
- Earlier requested controls: black/white levels, gamma, and basic saturation. Temperature/tint remains deferred; it is not a prerequisite for those controls.

## Proposed rule changes

None. No instruction files were modified. The globally referenced `docs/CODEX-NAVIGATION-GUIDE.md` is absent in this repository; use README and the tracked plan for current source ownership.
