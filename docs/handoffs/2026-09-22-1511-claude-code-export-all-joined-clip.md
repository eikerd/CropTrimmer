---
date: 2026-09-22 15:11 America/Chicago
tool: claude-code
model: claude-opus-5
repo: eikerd/CropTrimmer
branch: claude/export-all-joined-clip
pr: https://github.com/eikerd/CropTrimmer/pull/15
state: pr-open
deployed: no
loose_ends: 2 (listed below)
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

- Commit `42c0139` feat: Export All chains every loop into one clip.
- New: `Sources/CropTrimmerCore` — `JoinFrame`, `JoinRequest`, `JoinFramePrompt` (Models), `MediaEngine.join`,
  `joinFilterGraph`, `joinFrame`, `OutputPublisher` `joined:` naming.
- Tests: `swift test`, 129 tests, 0 failures, 1 skipped (the render harness), 16 new.
  `JoinedExportTests` covers the frame choice, the filtergraph, the prompt wording and the filename;
  `EditorIntegrationTests.testExportAllChainsEveryLoopIntoOneClip` runs the real thing through ffmpeg —
  two loops with audio, one validated 4.5 s file out, no leftover working files — plus the single-loop
  fallback.
- Reviews: **none yet**. The PR is a draft; the three rounds and the scorecard have not been done.

## What is deployed

Nothing deploys; Crop Trimmer is a local macOS app. Rebuild from the branch with `scripts/build-app.sh`.

## Loose ends

1. **The PR is a draft with zero review rounds.** It needs the three rounds and `reports/pr-15.html`
   before it can merge.
2. **The size-mismatch dialog is not on the Figma canvas.** It is a stock `NSAlert` with no custom
   design, and the file models the app's own surfaces rather than system dialogs (there is no
   `NSOpenPanel` frame either). If the owner wants system dialogs represented, that is its own job.

## Next agent: start here

Mark PR #15 ready, run the three review rounds, write the scorecard, merge. To exercise the change by
hand: open a movie, add three loops, give one of them a crop or a quarter turn so the sizes disagree, and
press Export All — the dialog should name every loop and both frames, and the result should be one file.

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
