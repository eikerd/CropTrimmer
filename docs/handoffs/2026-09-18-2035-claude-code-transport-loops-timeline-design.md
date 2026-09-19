---
date: 2026-09-18 20:35 America/Chicago
tool: claude-code
model: claude-opus-5, then claude-fable-5-1 from the timeline design onward
repo: eikerd/CropTrimmer
branch: claude/one-line-transport
pr: https://github.com/eikerd/CropTrimmer/pull/11
state: pr-open
deployed: no
loose_ends: 2 (listed below)
supersedes: none
---

# One-line transport, loop deletion, drag fixes, sticky playback, 12 pt text — and the approved timeline zoom design

## What changed, and why

The transport is one row, with the A–B dropdown replaced by a VLC-style mode
button (click cycles A–B repeat → play once → whole movie; right-click picks).
Loops are deleted with trash icons everywhere a loop is shown, any loop can be
deleted, and `+` chains the next loop from the selected loop's B point. While a
loop or its A handle is dragged the playhead rides on A; while B is dragged it
shows the loop's last kept frame; a loop pushed past the end shortens to the
movie's end instead of stopping; A trims with B held still. Playback is sticky
through edits, loop changes and opening another movie. The playhead is a 2 pt
line with a marker head through the loop bars and filmstrip. No text renders
below 12 pt, enforced by a source-scanning test. Every visual change was
rendered and approved in the built app before the commit.

The owner also asked for a zoomable timeline for very long sources (a 5-second
loop on a two-hour movie is 0.7 px wide today). The design was prototyped, tried
by the owner, and approved — see "Next agent".

## Where it is

- Commits: `28e7925` feat: one-line transport, loop deletion, drag fixes, sticky playback, 12 pt text
- Files that matter: `Sources/CropTrimmer/EditorView.swift` (transport, Filmstrip,
  LoopHeader, playhead), `Sources/CropTrimmer/EditorModel.swift` (`keepingPlayback`,
  `removeLoop(_:)`, drag functions), `Sources/CropTrimmerCore/MovieLoops.swift`
  (`add` chains from B, `move` shortens at the end, `minimumLength`),
  `Sources/CropTrimmerCore/Models.swift` (`PlaybackMode.next`),
  `Tests/CropTrimmerCoreTests/MinimumTextSizeTests.swift`,
  `docs/prototypes/timeline-zoom.html` (the approved interaction prototype).
- Verified by: `swift test` — 62 tests, 0 failures. Offscreen renders and the
  built app (`scripts/build-app.sh` from this worktree) exercised by the owner.

## What is deployed

Nothing. This app has no remote deployment; the local build in this worktree's
`build/` is untracked and disposable.

## Loose ends

- Codex's draft PR #10 (`codex/openrouter-settings`, OpenRouter settings) is
  open and untouched; the main checkout at `~/repos/macos/CropTrimmer` sits on
  that branch. This session worked in `~/repos/macos/CropTrimmer-wt-transport-bar`.
- Sources with non-square pixels (and interlaced, HDR, alpha, odd dimensions)
  refuse to encode — `MediaEngine.swift` builds `encodingRestriction` from
  ffprobe — so crop, color and accurate trim are blocked on them; fast trim
  still works. The owner asked why. Adding a `scale`/`setsar` step so those
  files can be re-encoded was offered, not decided.

## Next agent: start here

1. After #11 merges, cut a fresh branch from `origin/main` for the timeline zoom.
   Open `docs/prototypes/timeline-zoom.html` in a browser and use it: it is the
   approved interaction, fake tiles standing in for thumbnails.
2. Build order, each step usable on its own:
   - `TimelineViewport` in Core (visible start + duration; `x(for:)`, `time(at:)`,
     zoom about an anchor time, scroll, clamp to 1 s … whole movie; tests).
     Every position in `Filmstrip`/`LoopHeader` becomes `viewport.x(time)`. The
     44 px minimum bar width goes away (keep a ~10 px hit width).
   - Thumbnail tiles: a pyramid of levels (12 × 2ⁿ tiles across the movie),
     generated on demand for the visible range with `AVAssetImageGenerator`,
     cached with a memory cap, in-flight requests cancelled when the viewport
     moves on, old tiles stretched until sharper ones arrive.
   - Ruler (drag ↓ zoom in around the cursor, ↑ zoom out, ←→ scroll; ticks that
     adapt to zoom) and overview strip (whole movie, loop marks, draggable
     window with resizable edges, click to jump).
   - Snapping: A/B handle drags and bar moves snap to other loops' A/B, the
     playhead, and the movie's ends; tolerance 8 screen px converted to seconds
     at the current zoom; blue guide line from ruler to filmstrip plus a blue
     glow on the snapped handle/bar; ⌘ held overrides.
   - Keys and gestures: Z zoom to selected loop, X whole movie, ⌘+ / ⌘−, pinch,
     two-finger scroll pans, ⌘-scroll zooms.
   - Approved extras: follow the playhead while playing (page the view when it
     runs off screen), trim by dragging the ends of the yellow bars, double-click
     a bar to zoom to it, selecting a loop scrolls it into view.
3. Keep the 12 pt floor: `MinimumTextSizeTests` fails on point sizes below 12,
   `.caption`/`.footnote`/`.subheadline`, small/mini controls (spinners exempt)
   and `minimumScaleFactor`. Icons are exempt.

## Decided by the owner

- "These controls can all be fit into one line, and the dropdown on the left can
  be a multi-mode button. If you don't know what to do, just do what VLC does."
- "We need an easy way to delete loops … need a trash can icon in more places."
- "I don't want any text below 10 pt" → later "Now I'm saying the minimum should
  be 12 point. Make all adjustments based on that." Asked whether a floor is
  even the right metric; chose "Floor only" over an explicit 13/12 scale.
- "The playhead always follows the left-in point of the loop … when you click the
  B handle, the playhead shows the B frame out of the clip."
- "If the loop is too short then the loop quantization gets turned off. And the
  loop just automatically fills the rest of the clip" — a loop pushed past the
  end shortens; dragging back restores its length.
- "The play state of the clips is sticky. If you load another clip, it still
  keeps playing … It doesn't stop. Unless it needs to."
- "When you click the plus to add a new clip, it should automatically add a new
  clip starting at the out marker of the current clip."
- "The clip endpoints should snap … a vertical line … glows blue while they
  align" and "the Ableton Live way of dragging down on the zoom bar" — timeline
  design approved as prototyped, with all four optional extras.
- "I want a little bit of a more visible playhead marker … sitting over the clip."
- Approved committing the batch and opening the PR (AskUserQuestion, 20:25).

## Proposed rule changes

- New global rule, from the owner's words "I want to increase the minimum
  allowed text size for any app … the minimum should be 12 point": no UI text
  below 12 pt in any project on this machine; on macOS that also rules out
  `.caption`, `.caption2`, `.footnote`, `.subheadline`, and `.small`/`.mini`
  control sizes for text-bearing controls. A source-scanning test like
  `MinimumTextSizeTests` is the cheap way to hold the line.
- When the owner names a reference app ("do what VLC does"), that reference is
  the spec for the interaction: VLC for transport, Ableton Live for timeline
  zoom, Final Cut Pro for snapping feedback.
