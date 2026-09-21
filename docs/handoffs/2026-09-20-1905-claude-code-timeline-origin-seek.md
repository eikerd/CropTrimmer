---
date: 2026-09-20 19:05 America/Chicago
tool: claude-code
model: claude-fable-5-1
repo: eikerd/CropTrimmer
branch: claude/timeline-origin-seek
pr: https://github.com/eikerd/CropTrimmer/pull/13
state: merged
deployed: no
loose_ends: 3 (listed below)
supersedes: none
---

# Export movies whose picture starts after the container

## What changed, and why

The owner kept hitting *"Encoding is not supported for different video and container timeline
origins"* when exporting loops from ordinary MP4s, and asked whether more encoders were needed.
None were: FFmpeg was never run. `MediaEngine.inspect` refused every re-encode when the video
stream's `start_time` differed from the container's by more than 25 ms — less than one frame at
30 fps. Phones, screen recorders and B-frame H.264 routinely write audio at 0 and the first
picture a few frames later, and every loop export re-encodes, so the refusal was constant.

The guard existed because FFmpeg's input `-ss` counts from the container's start while the editor
counts from the first picture (`NativeTimeline.videoOrigin`). Measured on a fixture with the
picture delayed 0.2 s: `-ss 1` returns the source frame at 0.8, `-ss 1.2` returns the frame at 1.0.
So the offset is now carried instead of refused:

- `MediaSource.seekOffset` = video start − container start.
- One helper, `MediaEngine.seek(_:_:)`, adds it to every editor-time `-ss`: encode, size
  estimates, fast copy (both inputs) and the boundary fingerprints.
- The restriction is gone. HDR/wide colour, interlaced, non-square pixels, alpha and odd
  dimensions are untouched.
- Review found the same mistake on the AVFoundation side: the three colour-suggestion samplers
  and the filename-suggestion frame passed editor time straight to `AVAssetImageGenerator`.
  All four call sites in `EditorModel` now add `playbackOrigin`, as the player's seeks already did.
- `README.md`'s support paragraph no longer calls these sources unsupported.

## Where it is

- Commits:
  - `44ee010` fix: export movies whose picture starts after the container
  - `ec4b983` fix: give copy verification the source origin, document the seek clamp
  - `54a282b` fix: sample colour and naming frames from the first picture, update README support boundary
  - (this commit) test: audio starting after the picture; handoff
- Tests: `swift test` — 102 tests, 0 failures. New:
  `testVideoStartingAfterTheContainerEncodesFromTheChosenFrame` (pixel-checks the first output
  frame against the source frame at 1.0 and against the wrong one at 0.8) and
  `testAudioStartingAfterThePictureNeedsNoSeekOffset`.

## What is deployed

Nothing deploys; Crop Trimmer is a local macOS app. The owner's running build predates this fix
until it is rebuilt from `main`.

## Loose ends

1. **Not tried on one of the owner's own failing MP4s.** The fixture reproduces the structure
   (audio at 0, picture at 0.2 s) and the exact error, but no real file from the owner was
   exported end to end.
2. **Fast copy with a nonzero offset has no test.** `copyPlan` still requires
   `abs(source.startTime) < 0.001`, so the only reachable case is a container that starts
   *before* zero (AAC priming), which FFmpeg's MP4 muxer will not produce for a fixture. The
   review agent confirmed A/V sync by hand outside the suite. That guard is load-bearing:
   `packets()` uses absolute timestamps, so do not loosen it without revisiting `packets()` and
   `verifyCopy` together.
3. **The main checkout sits on `codex/openrouter-settings`**, whose PR #10 has merged. It is
   Codex's checkout and was left alone.

Review status, because a quiet bot is not a clean review: Copilot answered "quota limit" and
reviewed nothing. Greptile never attached to this PR. The rounds that ran were Codex and
CodeRabbit.

## Next agent: start here

Rebuild the app from `main` and export a loop from a phone or screen recording. If the error
still appears, the message names which restriction fired; the others in
`MediaEngine.inspect` are real encoding limits, not timeline arithmetic.

## Decided by the owner

- On whether to go ahead with the fix: "implement whatever you've got, understanding other
  stuff's been checked."

## Figma

No visual change: the same pixels, one error dialog that no longer appears. Nothing for the
Figma file (`4otxM7dLAxgK6KQJ5YIJzx`) to catch up on.

## Proposed rule changes

None.
