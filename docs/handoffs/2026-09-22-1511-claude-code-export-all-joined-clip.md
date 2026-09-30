---
date: 2026-09-22 15:11 America/Chicago
tool: claude-code
model: claude-opus-5
repo: eikerd/CropTrimmer
branch: claude/export-all-joined-clip
pr: https://github.com/eikerd/CropTrimmer/pull/15
state: merged
deployed: no
loose_ends: 3 (listed below)
supersedes: none
---

# Export All: chain every loop into one clip

## What changed, and why

The owner asked for a second export button: "now there will be Export Each, and Export All, all would be
chained together sequentially in one clip."

- **Export Each** is the old Export Queue, renamed — one numbered movie per loop, behaviour unchanged.
  `EditorModel.exportQueue()` is now `exportEach()`; the menu item and the inspector button follow.
- **Export All** (`EditorModel.exportAll()` → `startJoinedExport`) renders every loop to a hidden working
  file, then concatenates them into one published clip named `<source> - all loops`.
- **Nothing partial is ever published.** The segments are the job's own temporaries, discarded in a
  `defer`; only the joined clip goes through `OutputPublisher.publish`. A failure at loop 4 leaves the
  folder as it was, rather than three numbered pieces of a clip that was never made.
- **Joining always re-encodes.** FFmpeg's concat filter refuses segments whose stream parameters differ
  and will not conform them itself, so `MediaEngine.joinFilterGraph` scales each segment into one frame,
  pads it on black, and pins it to one frame rate and pixel format before concat sees it. The single rate
  is not cosmetic: a loop carrying a speed leaves its segment with the source's frame count over a shorter
  span, which would hand concat a second timebase. Conforming changes no loop's apparent speed.
- **A lone loop is not joined.** `exportAll()` with one loop delegates to the ordinary path, so it keeps
  its own `- loop 01` name and can still stream-copy instead of taking a re-encode from a join that never
  happens.
- **Quality**: the joined clip encodes at the best quality any of its loops asked for
  (`EditorModel.joinQuality`). A loop planned as `.copy` asked for source quality, so it pulls the whole
  clip to High.
- **`ExportResult.segments`** counts the loops that made one file. A joined clip has as many requested
  ranges as it has loops, so `ReviewView`'s "Requested: A – B" and boundary-shift lines would have
  described only loop 1; it now shows "Joined from N loops, in timeline order" instead.
- In-app help (the `?` alert) gained a sentence covering both buttons and the size question.

## Mixed frame sizes: asked at render, not decided for the owner

Per-loop crop and rotation mean loop 1 can be 1920 × 1080 while loop 2 is 1080 × 1920. My first plan was
a fixed policy; the owner changed it mid-task — "how about a warning if true, and user can choose at
render" — so the choice is now a dialog raised before anything is rendered:

> These loops are not all the same size.
> Loop 1 is 1920 × 1080, Loop 2 is 1080 × 1920. Choose the frame the joined clip is rendered into. A loop
> smaller than the frame is centred on black; none of them is cropped or stretched.
> **[ Fit Every Loop · 1920 × 1920 ]  [ Match Loop 1 · 1920 × 1080 ]  [ Cancel ]**

Loops that already agree are never asked. Neither answer crops or stretches. `JoinFramePrompt`
(CropTrimmerCore) holds the wording and returns nil when there is nothing to decide, so the owner-facing
text is testable and `EditorModel` holds only the dialog. `MediaEngine.joinFrame` computes both frames and
rounds up to even sizes, which H.264's 4:2:0 chroma requires.

## Where it is

- Commits: `42c0139` feat: Export All chains every loop into one clip · `c329ca9` handoff note ·
  `2a01f94` fix: joined loops keep their size, and the join honours encoding limits ·
  `04f7c92` fix: a lone loop is not refused for a restriction the join never hits.
- New: `Sources/CropTrimmerCore` — `JoinFrame`, `JoinRequest`, `JoinFramePrompt` (Models), `MediaEngine.join`,
  `joinFilterGraph`, `joinFrame`, `OutputPublisher` `joined:` naming.
- Tests: `swift test`, 135 tests, 0 failures, 1 skipped (the render harness), 22 new.
  `JoinedPictureTests` runs the real engine over real movies and reads real pixels; it fails against
  the pre-fix filtergraph with "the corner must be padding, not enlarged picture". The restricted-
  source integration test fails against the round-2 ordering. Both were checked against the broken
  code, not just the fixed code.
  `JoinedExportTests` covers the frame choice, the filtergraph, the prompt wording and the filename;
  `EditorIntegrationTests.testExportAllChainsEveryLoopIntoOneClip` runs the real thing through ffmpeg —
  two loops with audio, one validated 4.5 s file out, no leftover working files — plus the single-loop
  fallback.
- Reviews: three rounds, all on 2026-09-29/30 after the PR came out of draft.
  - **Round 1** (`c329ca9`): three real defects. A swift-reviewer pass found that
    `scale=W:H:force_original_aspect_ratio=decrease` *enlarges* a segment smaller than the joined
    frame — a 320x240 loop filled a 640x480 clip with upscaled pixels and no bars, contradicting
    the frame dialog's own promise. Codex found (P1) that an all-copy queue never reaches
    `encodedPlan`, so the join's unconditional encode bypassed `encodingRestriction` and would
    silently convert HDR/interlaced/alpha/non-square sources; and (P2) that `ReviewView` compared a
    joined clip against an unrelated source frame. All three fixed in `2a01f94`.
  - **Round 2** (`2a01f94`): Codex (P2) caught a regression from round 1's own fix — the restriction
    check had been placed above the single-loop delegation, so Export All on a one-loop restricted
    movie errored instead of taking the ordinary path that can copy it. Fixed in `04f7c92`.
  - **Round 3** (`04f7c92`): see the scorecard.
  - CodeRabbit reviewed once, at the end, after its free-plan rate limit reset: the whole diff, all
    twelve files, clean — no inline comments and no findings, rated 4/Complex. It was rate-limited
    through rounds 1 and 2 and had to be waited out.
  - Copilot replied "quota limit" on both attempts and reviewed nothing, as on PR #14. ecc-tools'
    gates passed except its standing generic reference-corpus complaint, which it files against
    every PR here.
  - Scorecard: `reports/pr-15.html`.

## What is deployed

Nothing deploys; Crop Trimmer is a local macOS app. Rebuild from the branch with `scripts/build-app.sh`.

## Loose ends

1. **CodeRabbit's free-plan rate limit shapes review coverage in this repo.** It reviewed nothing
   for the first two rounds here and had to be waited out. Codex carried the load. If CodeRabbit is
   meant to be a real second reviewer, the plan is the thing to change.
2. **The render rule was broken once, mid-review.** The `ReviewView` change (dropping the original
   pane for joined clips) is visual and was committed before it was rendered. A render was produced
   afterwards and sent to the owner, and `RenderShotTests.testRenderJoinedReview` now produces it on
   demand, but the order was wrong. See the proposed rule change below.
3. **The size-mismatch dialog is not on the Figma canvas.** It is a stock `NSAlert` with no custom
   design, and the file models the app's own surfaces rather than system dialogs (there is no
   `NSOpenPanel` frame either). If the owner wants system dialogs represented, that is its own job.

## Next agent: start here

Merged. To exercise the change by hand: open a movie, add three loops, give one of them a crop or a
quarter turn so the sizes disagree, and press Export All — the dialog should name every loop and both
frames, and the result should be one file with the smaller loops centred on black at their own size,
not blown up to fill.

## Decided by the owner

- Scope: "for exporting id like to add an export button so nowthere will be Export Each , and Export All,
  all would be chained together sequentially in one clip".
- Mixed sizes: first chose "Fit inside one frame", then changed it — "how about a warning if true, and
  user can choose at render". The warning is what shipped; fit-every-loop is the leading button.
- Render review: "approved", on the inspector footer with Export All as the prominent button.

## Figma

File `4otxM7dLAxgK6KQJ5YIJzx`, Editor frame `3:2`, Inspector footer `4:190`. The single
`button/export-queue` (`4:191`, "Export Queue (1)") was removed and replaced with an `Export buttons` row
(`16:2`): `button/export-each` (`16:3`) in the file's existing neutral button style, beside a prominent
`button/export-all` (`16:5`) in the accent blue sampled from the approved render (#00A1FF). Both fill half
the 270 pt content width with an 8 pt gap, 30 pt tall, matching the code. The alert: see loose end 2.

## Proposed rule changes

- **`render-before-commit` assumes the running app can be driven.** The owner declined computer-use access,
  and the app is a bare SwiftPM executable, so `open`/Apple Events cannot hand it a document either — the
  usual fallbacks left only a mockup. What worked was rendering the real `EditorView` through SwiftUI's
  `ImageRenderer` inside a test (`Tests/CropTrimmerCoreTests/RenderShotTests.swift`, skipped unless
  `RENDER_SHOT` and `RENDER_MOVIE` are set). It renders real layout and real controls with no permissions
  at all. Worth naming in the rule as the fallback to reach for before a mockup, for any SwiftUI project.
  Note its one artefact: SF Symbols come out as placeholder glyphs, so crop to the part under review.
