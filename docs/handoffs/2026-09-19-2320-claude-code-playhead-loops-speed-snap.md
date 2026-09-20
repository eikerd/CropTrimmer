---
date: 2026-09-19 23:20 America/Chicago
tool: claude-code
model: claude-fable-5-1
repo: eikerd/CropTrimmer
branch: claude/playhead-insert-unlimited-loops
pr: https://github.com/eikerd/CropTrimmer/pull/12
state: pr-open
deployed: no
loose_ends: 3 (listed below)
supersedes: none
---

# Bare-start timeline, playhead loop insert, unlimited flush loops, snapping, per-loop speed

## What changed, and why

A movie used to open with a five-second loop nobody asked for, capped at three loops, and the
bars looked like they overlapped even when chained. Now a movie opens bare — whole timeline in
play, no loops — and the first `+` (or `I`) starts a loop at the playhead; later presses chain
from the selected loop's B. The cap is gone entirely, the last loop can be deleted (returning the
movie to whole-timeline playback), and bars are drawn at their exact A–B span so chained loops
sit flush, with a 44 pt grab target kept underneath so short loops stay draggable.

Dragging now snaps, Adobe-style: a dragged loop or a dragged A/B handle sticks to any other
loop's A or B, the playhead, or either end of the movie when it comes within 7 pt, and a dashed
guide marks the edge it stuck to. Speed became a property of the loop rather than the monitor:
0.1×–8×, previewed and rendered from the same number, so an export at 0.5× really is twice as
long with its audio intact.

## Where it is

- Commits:
  - `d3b8d7c` feat: open movies bare, insert the first loop at the playhead, drop the loop cap
  - `b2f00a5` feat: Adobe-style snapping while dragging, and per-loop playback speed
- Files that matter:
  - `Sources/CropTrimmerCore/MovieLoops.swift` — `withFirstLoop:`, `add(length:at:settings:)`,
    `snapTargets(excluding:playhead:)`, `snap(start:end:targets:tolerance:)`, uncapped `add`,
    `remove` down to zero. `maximumCount` is gone.
  - `Sources/CropTrimmerCore/Models.swift` — `EditSettings.speed`, `speeds`, `speedLabel`,
    `outputDuration`; speed validated against the menu; `ExportPlan.outputDuration`.
  - `Sources/CropTrimmerCore/MediaEngine.swift` — speed forces `.encode`; `setpts` plus an
    `atempo` chain built to stay inside atempo's 0.5–2 per-stage range; `-t` is the OUTPUT
    length; `validateOutput` measures against `outputDuration` with the allowance scaled by speed.
  - `Sources/CropTrimmer/EditorModel.swift` — bare open, playhead insert, `snapGuide`,
    `endLoopDrag()`, `speed`/`setSpeed`/`applyRate`.
  - `Sources/CropTrimmer/EditorView.swift` — exact-span bars, dashed guide, speed picker,
    `Filmstrip.snapDistance`.
  - `Sources/CropTrimmer/QueueLoopCard.swift` — per-loop Speed row.
- Verified by: `swift test` — 78 tests, 0 failures. Half speed renders 2 source seconds as 4.00
  with ~50 frames (spread, not duplicated); 8× renders 4 seconds as 0.5 with audio kept.
  In the running app on a synthetic 2-minute movie: bare start, `+`×6 stair-step, flush bars,
  last-loop delete back to whole movie, and a loop dragged out to A=33.434 then back landed
  exactly on 5.000, flush against its neighbour's B.

## What is deployed

Nothing. This is a local macOS app; `scripts/build-app.sh` output stays in the worktree's
`build/`. A separately-identified copy (`com.croptrimmer.mac.preview`) was used for screenshots
so the owner's own running Crop Trimmer was never touched.

## Loose ends

1. **Worktree still live**: `/Users/ernestoikerd/repos/macos/CropTrimmer-wt-playhead-loops`
   (branch `claude/playhead-insert-unlimited-loops`, PR #12 open). Remove after merge.
2. **Another agent's work, untouched**: `/Users/ernestoikerd/repos/macos/CropTrimmer-wt-omacut-keys`
   (`claude/omacut-hotkeys`, 5 uncommitted files) holds a `PreferencesView.swift` with a General
   tab and a Shortcuts reference list. It overlaps the settings pages the owner asked for in this
   session (filename-affecting operations, key bindings) — **that work should land from there, not
   be rewritten here**. The main checkout is also dirty on `codex/openrouter-settings` (draft PR #10).
3. **Reviews not finished**: Codex review was still running at handoff; Copilot declined (quota
   reached). Three completed rounds are still owed before the scorecard and merge.

## Not built, still asked for

- **Settings pages** the owner asked for: filename-affecting operations (which operations alter
  the export filename) and a key-bindings page that explains and lets people change shortcuts.
  See loose end 2 — the hotkeys worktree already has the Shortcuts tab started.
- A **verbose control-label mode** remains deferred from an earlier session.

## Next agent: start here

1. Finish the review rounds on PR #12, write `reports/pr-12.html` from the template, merge,
   delete the branch and worktree.
2. Then pick up the settings pages from `CropTrimmer-wt-omacut-keys` rather than starting fresh.

## Decided by the owner

- "I hate how dragging a clip starts with a weird bullshit default loop… we click plus, and then
  the behavior is wherever the timeline head is playing, that's where we insert the A point of our
  first clip" — bare start, playhead insert, default length still 5 s and still settable.
- "we don't need to maximize it to three loops… like, we just add them and when we do it snaps to
  the edge of the last one just like in a stair step" — the cap is gone, `+` chains from B.
- "I don't like how the endpoints in the clip seem to overlap. They should be flush if they're
  really end to end." — bars are drawn at their exact span.
- "I don't feel any snap… that Adobe Smart Object snap type feel… with a little like a snap
  indicator" — 7 pt snapping to neighbours, playhead and movie ends, with a dashed guide.
- "the loops can have playback speeds… both preview and rendered… down to ten percent, up to
  eight times" — `EditSettings.speed`, 0.1×–8×, one number for preview and export.
- "these fucking controls all need to be on one line, along with a dropdown of playback speed.
  Stop fucking changing my decisions." — the one-line transport from PR #11 is preserved, and the
  speed menu joined that row rather than starting a second one.
- "we should keep Figma updated. We're going to migrate all of our design decisions to Figma…
  make a rule to make sure that that's current" — new rule in eikerd/central PR #4, and the
  Crop Trimmer Figma file's Editor frame was updated in this session (see below).

## Figma

`4otxM7dLAxgK6KQJ5YIJzx`, page "Page 1", frame **Editor** (`3:2`) brought up to the shipped UI:

- **Transport** is now the single shipped row — the A–B mode dropdown became an icon button, a
  `Picker/speed` was added beside it, volume moved up, and the second "Playback" row was deleted.
- **Loops row** carries per-colour chips 1–3 with a `+` and a trash button; the old `−` chip is
  gone, and nothing implies a three-loop cap.
- **Loop headers** are three stair-stepped rows, each bar drawn at its exact A–B span so loop 2's
  left edge meets loop 1's right edge, plus a dashed **Snap guide (while dragging)** at the edge
  a drag has stuck to.
- **Loop card** gained the **Speed row** (`0.5×` picker).

The frame was stale by more than this PR — it still showed the two-row transport from before
PR #11 — so this update also caught it up on that merge.

## Proposed rule changes

None beyond the Figma rule already opened as a PR (eikerd/central#4), which the owner asked for
in words in this session.
