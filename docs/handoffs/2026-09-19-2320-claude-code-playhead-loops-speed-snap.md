---
date: 2026-09-20 00:15 America/Chicago
tool: claude-code
model: claude-fable-5-1
repo: eikerd/CropTrimmer
branch: claude/playhead-insert-unlimited-loops
pr: https://github.com/eikerd/CropTrimmer/pull/12
state: merged
deployed: no
loose_ends: 4 (listed below)
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
  - `df5bf5e` fix: export progress by output length, Adjust Crop gating, bare status
  - `8d42cb4` fix: no ⌘-shortcut past Loop 9, freeze the playhead target during a drag
  - `b1e59a5` feat: one-row timeline, Apple-style A/B handles, play-all-loops
  - `a39980b` feat: Settings window with General, File Names and Shortcuts pages
  - `79b8f88` fix: review rounds 2 and 3, plus an export that could never publish under /private
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
- Verified by: `swift test` — 91 tests, 0 failures. Half speed renders 2 source seconds as 4.00
  with ~50 frames (spread, not duplicated); 8× renders 4 seconds as 0.5 with audio kept.
  In the running app on a synthetic 2-minute movie: bare start, `+`×6 stair-step, flush bars,
  last-loop delete back to whole movie, and a loop dragged out to A=33.434 then back landed
  exactly on 5.000, flush against its neighbour's B. Twelve loops added through the menu without
  the tenth crashing it, play-all rotating with every loop reading as selected, both settings
  pages driven, and a real export published from the directory whose publish used to fail.

## What is deployed

Nothing. This is a local macOS app; `scripts/build-app.sh` output stays in the worktree's
`build/`. A separately-identified copy (`com.croptrimmer.mac.preview`) was used for screenshots
so the owner's own running Crop Trimmer was never touched.

## Loose ends

1. **Worktree**: `/Users/ernestoikerd/repos/macos/CropTrimmer-wt-playhead-loops` — removed at merge.
2. **Another session's checkout is still dirty**: the main checkout sits on `codex/openrouter-settings`
   with 11 uncommitted files and draft [PR #10](https://github.com/eikerd/CropTrimmer/pull/10).
   Untouched by this session.
3. **`CropTrimmer-wt-omacut-keys`**: its uncommitted work (PreferencesView, persisted loop length,
   header focus, arrow-key nudges, ⌘I/⌘⇧O, "?") was **absorbed into this PR with the owner's
   say-so**, so that worktree's copy is now redundant and its branch `claude/omacut-hotkeys` can be
   deleted without losing anything. It was not modified.
4. **Copilot review unavailable** (quota reached for the day). The three rounds were Codex plus two
   local reviewer agents, which is what the owner authorised in session when asked.

## The bug user testing found

Exporting into any folder under `/private/tmp` or `/private/var` could never publish. It is
**pre-existing**, not from this branch: `standardizedFileURL` strips a `/private` prefix only once
the file exists, so the temporary registered before the encode was looked up under a different
spelling afterwards, failed the ownership check, and was left behind because `discard` missed it
the same way. Ownership now matches on every spelling, and the destination check compares paths
rather than URLs — which differ by the trailing slash `deletingLastPathComponent` leaves. Three
tests cover it, one of them proving a file this process never issued is still refused.

## Not built, still asked for

- **Rebinding** shortcuts (the reference list shipped; the owner chose that order).
- A **verbose control-label mode** remains deferred from an earlier session.

## Next agent: start here

1. **Rebinding keyboard shortcuts.** The Shortcuts page is a reference list; the owner chose
   "reference list now, rebinding later" when asked. Rebinding needs a capture UI, storage, and
   conflict rules, and `EditorModel`'s global key monitor has to read from that store.
2. **Delete `claude/omacut-hotkeys` and its worktree** — its work is merged here (loose end 3).
3. The owner has not yet seen the renders sent late in the session: the one-row timeline, the
   chunky A/B handles, play-all, and the two settings pages. They were committed on the owner's
   instruction to use judgement while away and send renders; anything they reject is a follow-up.

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
- "There should be a loop selector button next to all the loops… it just would rotate between
  just the clips and wouldn't play anything else" and "There should be a visual indicator when all
  of the clips are selected to play too" — Play all loops, with every loop reading as selected.
- "This can all be one line if we put all the buttons and controls in the center and leave the AV
  points with their time on the edges" — the single timeline row.
- "I hate our clip drag handles for the AB points. They need to be more snappy and… more chunky
  and grabby. Like Apple." — 16 pt caps with grip lines inside a thick rounded trim frame.
- "Use this time to just user test and then land the PR" — and, asked before they left: merge on
  Codex plus local reviewers, absorb the hotkeys worktree, reference list before rebinding, and
  commit visual work with renders sent for later review.
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
