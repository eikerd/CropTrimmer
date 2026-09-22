---
date: 2026-09-22 09:20 America/Chicago
tool: claude-code
model: claude-opus-5
repo: eikerd/CropTrimmer
branch: claude/rotate-button
pr: https://github.com/eikerd/CropTrimmer/pull/14
state: merged
deployed: no
loose_ends: 3 (listed below)
supersedes: none
---

# Rotate button: quarter turns per loop

## What changed, and why

The owner asked for a rotate control right beside the crop control, doing 90°, 180° and 270°. They then clarified: "It's a multi-mode button. It's not a freaking big control. It's an easy, simple multi-mode button with a rotate mark."

- **The button**: `↻` (`rotate.right`) directly after each loop card's **Crop** checkbox (`QueueLoopCard.rotateButton`). Each click moves that loop a further quarter turn clockwise, 0 → 90 → 180 → 270 → 0, VLC-style like the playback-mode button. It uses the accent colour while the loop is rotated. It has no text label and no right-click menu; the owner chose "keep it bare".
- **`EditSettings.rotation`** is an Int in {0, 90, 180, 270}. `validate` refuses anything else, and older settings decode as 0.
- **The crop is measured on the turned picture**, not on the raw source. `EditSettings.pictureSize(of:)` is the canvas: the upright source, with width and height swapped on quarter turns. Every crop consumer uses it: validation, the overlay, X/Y entry, aspect fit, reset, and `ExportPlan.width/height`. The reason for this choice: after turning a sideways phone clip, a 9:16 lock gives a 9:16 export.
- **`turnedClockwise(source:)`** carries the crop with the picture, (x, y) → (H − y, x), so four clicks give back the same rectangle. Locks turn too: `CropAspectRatio.quarterTurned` swaps 16:9 with 9:16, and Freeform, Original and 1:1 stay as they are. 4:3, 1.85:1 and 2.39:1 have no turned counterpart in the menu, so they become Freeform and `lastLockedCropAspectRatio` keeps them for the lock button. Re-fitting was rejected because it shrinks the crop on every click.
- **Export**: rotation forces a re-encode ("Rotating requires re-encoding."; `MediaEngine.encodingReason` now gathers every reason in one place). `MediaEngine.rotationFilter` gives `transpose=clock`, `hflip,vflip` or `transpose=cclock`, which runs after FFmpeg's own autorotate and before `crop`.
- **Preview**: `PlayerSurface(rotation:)`. `PlayerLayerView` keeps the `AVPlayerLayer` in the upright shape and turns it about its centre inside a frame of the turned shape. AppKit's layer space has y pointing up, so a clockwise turn is a negative angle. The turn direction was verified off-screen inside an `NSHostingView` with a control image.
- **AI naming frame**: `framePNGData(…, rotation:)` turns the frame with `CIImage.oriented` (`.right` = 90° clockwise, verified) before cropping.
- **File names**: rotated exports get `… - rot90` / `rot180` / `rot270`, after trim/crop and before speed. The owner picked this. `FilenameOptions.includeRotation` (default on) has a **Rotation** switch under Settings → File Names, above Speed; the owner approved it in the preview build. `FilenameOptions` now has a hand-written decoder, so options stored before this change keep the owner's other choices instead of failing to decode and resetting to standard.
- In-app help (the `?` alert) gained one sentence about the button.

## Where it is

- Commits: `00541aa` feat: rotate button that turns a loop a quarter turn per click; review-round fixes (listed in the PR); this note and `reports/pr-14.html`.
- Tests: `swift test`, 114 tests, 0 failures, 12 new. `RotationTests` (9), `MediaEngineTests.testRotateButtonTurnsThePictureBeforeTheCrop` (90/180/270, whole and cropped, pixel-checked against FFmpeg's own filters), and two `FilenameOptionsTests`.

## What is deployed

Nothing deploys; Crop Trimmer is a local macOS app. The owner's `build/Crop Trimmer.app` was deliberately left alone. The render was a debug binary wrapped in a scratch bundle (`com.croptrimmer.mac.preview`), so rebuild from `main` with `scripts/build-app.sh` to get the button.

## Loose ends

1. **Figma Settings frame (`6:2`) has no File Names section.** It predates the tabbed Settings (General / AI / File Names / Shortcuts), so the new Rotation switch has nowhere to go on the canvas. The loop card was updated (below). Catching the Settings frame up to the tabbed window is its own job.
2. **Figma and code already disagreed about the loop card's crop row** before this change. Figma shows crop icon · aspect · lock · W × H · preview eye on one row; the code has a Crop checkbox, Adjust/Reset, then a second row with aspect, X, Y, lock and W × H. The rotate mark went where each layout puts "the crop control". Reconciling the two rows is a separate decision for the owner.
3. **The preview-layer rotation was never seen in the running app by an agent.** The owner declined computer-use access to the preview build. It was opened on their screen for them to try, and they approved it. The direction is covered by the off-screen check and the export pixel tests.

## Next agent: start here

Rebuild from `main`, open a sideways phone clip, add a loop, click ↻ once, pick 9:16 and export. The export should be upright and 9:16, named `… - rot90`.

## Decided by the owner

- Scope: "It's a multi-mode button. It's not a freaking big control. It's an easy, simple multi-mode button with a rotate mark."
- Render review: "Commit it". Extras: "None, keep it bare" for the button, plus "Angle in filename".
- Settings switch: "Commit with switch".

## Figma

File `4otxM7dLAxgK6KQJ5YIJzx`, loop card `4:175`, crop row `5:12`: added `icon/rotate` (`14:2`), a 16 pt clockwise arrow in the neutral icon gray, directly after `icon/crop`. The W × H fields fill the rest of the row and went from 44 pt to 34 pt, in line with the code's 35 pt cap. Settings: see loose end 1.

## Proposed rule changes

- **`AGENTS.md` line 5, "Crop uses upright source pixels and requires encoding."** This PR measures the crop on the picture *as the loop turns it*. Codex flagged that as breaking the line (PR #14, review round 2), and it was declined on the thread. The line guards against measuring a crop in the encoded, sideways-stored pixels of a file with rotation metadata, and that still holds. Proposed wording: "Crop uses upright source pixels, turned by the loop's own rotation (the picture the user sees), and requires encoding." Only the owner can make that edit.
