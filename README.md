# Crop Trimmer

A native Swift macOS app for selecting a movie's time range, optionally cropping its picture, and exporting a separate file beside the original.

## MVP workflow

1. Drop a movie onto the window, or use **Open Movie** (⌘O). To shorten its name, double-click the filename in **Source File** (or the toolbar), or use the pencil button. Edit the name and press **Rename** or Return; Escape/Cancel leaves it alone. This renames the original in place, preserves its extension, and reloads it with the loop settings intact. Existing files are never replaced. Future exports use the new name; completed exports keep their names.
2. Start with a five-second loop. Use **+** to add up to three independent loops — each new loop starts at the selected loop's **B** point — and the numbered buttons or headers to select one. **5s / 10s** resize the current loop and choose the length of newly added loops. Short movies are clamped to their available duration.
3. Each loop has its own color — random when it's added, changeable from the swatch beside its name in the queue (36 colors) — shown on its queue panel, its timeline header and its number in the Loops row; the selected loop is drawn solid, and its A/B handles and filmstrip outline take its color. Drag a **loop header** to move its whole range; the playhead follows A, and a loop pushed past the end of the movie shortens to the end (drag it back to restore its length). Drag **A** to change where the loop starts with B fixed; the playhead follows A. Drag **B** to change where it ends with A fixed; the playhead shows the loop's last frame. Drag the filmstrip below the headers to scrub. Optionally enable **Crop**, adjust the rectangle or source-pixel fields, and choose **Done**.
4. Each queue entry lays out its **Color correction**, **Crop** and **Export** controls flat and always expanded — no cards, no disclosure groups. The method and quality menus explain their current value, and what is planned right now, in a tooltip; the planned filename is the **Export Loop** button's tooltip. **Estimate** samples an encoded loop's size and shows it beside the buttons; stream copies show a quick estimate from the source size.
5. Each **Queue** entry holds its own trim, color, crop, method, quality and export controls. Edit any entry directly without changing the preview selection. Click its title to preview or **Adjust** to edit its crop onscreen. Use its **Export Loop** button for that entry (⌘E exports the selected loop), or **Export Queue** to process all entries sequentially. The app validates each temporary output, then saves it beside the source. Cancelling keeps completed exports and discards the unfinished output.

Names append ` - loop 01`, ` - loop 02`, or ` - loop 03`, followed by ` - trim`, ` - crop`, or ` - trim crop`. Loop numbers follow the current queue order, including after removing an entry. Existing names receive a numeric suffix. The original and existing files are never intentionally replaced. If the source directory is not writable, choose a different destination.

The Source File header shows original size and video codec. In each queue entry, hover the method menu for the planned video encoding, what re-encoding drops and any encoding restriction, the quality menu for its CRF, and **Export Loop** for the planned output filename. The estimated size shows beside the buttons: stream-copy plans use a quick source-size/duration estimate at once; encoded sizes appear after the entry’s **Estimate** button samples the loop and are cleared by content-affecting edits. Estimates are approximate, and existing filenames receive an extra number when saved.

There is no media library, import catalog, or persistent edit database in this MVP. The Exports sheet compares completed results from the current session; the actual exported movies remain in Finder after quitting.

## Editing

Queue entries show the loop number, **A** (start), **B** (end), and **D** (duration) on one line, in seconds truncated to one decimal place, beside the loop's color swatch; the selected loop's panel is brighter and outlined in its color. Every entry's A/B fields are editable without selecting it. Display truncation does not change the stored cut precision. Right-click an entry to set that loop to the whole movie or delete it.

- Click **A** or **B** to seek to an endpoint; **Shift-click** to store the playhead there.
- **I / O** set the start/end when the editor owns keyboard focus. **Space** plays/pauses.
- Scrubbing does not change any loop. Moving a loop or dragging A keeps the playhead on A; dragging B shows the loop's last frame.
- Numbered buttons, headers, or **⌘1 / ⌘2 / ⌘3** select a loop. Playback and single-loop export use the selected loop. Each entry retains independent crop and encoding settings; a new entry copies the selected entry’s settings as its starting point. The trash buttons (Loops row, Queue header, each queue entry), "Delete Loop N" in a header's or entry's context menu, or Delete on a focused header remove a loop, leaving at least one.
- Each loop has its own header row so overlapping ranges stay accessible. Arrow keys on a focused header move it 0.1s; Shift-arrow moves it 1s. Narrow selections use a top **A** and bottom **B** handle so the endpoints do not cover each other.
- New loops start at the selected loop's B point and run to the end of the movie when less than a full length remains; only when the selected loop already ends at the movie's end does a new loop take an unused spot, where it may overlap. The last 5s/10s preset is reused for new loops and newly opened movies during the session. Manual resizing does not change that preset.
- Playback defaults to A–B repeat. The transport's mode button cycles A–B repeat → Play selection once → Whole movie; right-click it to pick directly. Transport buttons finish crop adjustment automatically. Playing is sticky: five-second jumps, loop edits, length changes, adding or deleting loops, and opening another movie all keep playing if playback was on; Stop, frame stepping, export, the Exports sheet and crop adjustment pause. Previous/Next select the adjacent loop and seek to A, preserving playing/paused state; the buttons disable at the first/last loop. Navigating loops changes Whole movie mode to A–B repeat; Stop pauses and returns to A (or zero in Whole movie mode). Transport is disabled during analysis/export/estimation.
- **Aspect ratio** offers Freeform, Original, 16:9, 4:3, 1:1, 9:16, 1.85:1, and 2.39:1. Each loop remembers its lock. Choosing a preset fits it inside the current crop; Reset gives the largest centered crop for that ratio. The compact crop row contains the preset dropdown, editable X/Y, a lock toggle, and a width × height readout. Unlock keeps the rectangle unchanged; relock restores the last preset (Original if none was chosen). Corner drags keep the opposite corner fixed, and Shift-arrow resizing honors the lock. Dimensions round to even pixels, so the ratio may differ slightly at small sizes.
- Crop coordinates refer to the upright source image. Even pixel coordinates/dimensions match the H.264 4:2:0 output. Crop is fixed across the selected interval.
- **Done** leaves crop adjustment and stays paused. Mute and volume affect monitoring only.

Automatic attempts stream copying when planned boundaries are within 0.25 seconds of the request. Copied results undergo boundary-content validation; an unverifiable copy falls back to encoding. Manual Fast trim can have larger disclosed shifts and fails rather than silently encoding if validation fails. Crop always re-encodes. High quality / Balanced / Smaller file use software H.264 CRF 18/21/25, medium, with AAC audio at 192 kb/s.

## Build and run

Requires Xcode command-line tools with Swift 6.2 or compatible Swift 6 toolchain, macOS 14+, and installed Homebrew FFmpeg at `/opt/homebrew/bin` for development and packaging. The current local build targets Apple silicon.

```sh
swift build
swift test
./scripts/build-app.sh
open "build/Crop Trimmer.app"
```

Open `Package.swift` in Xcode to work on the source. `scripts/build-app.sh` builds a release executable, bundles FFmpeg/ffprobe and their non-system dynamic-library dependencies, adjusts install names, and ad-hoc signs the resulting application. The packaged app uses its bundled tools first and does not need Homebrew at runtime. Development binaries also search the standard Homebrew locations.

The output is **`build/Crop Trimmer.app`**. This is a local development build, not Developer ID signed or notarized for distribution. Bundled FFmpeg is GPL-enabled. Exact binary provenance, build configuration, and available dependency licenses are inside `Contents/Resources`; redistribution needs a separate license/source and signing review.

## Current support boundary

The viewer uses AVFoundation, so a source must be playable by native macOS media frameworks. Compatible MP4 and MOV movies are the initial target. The broader specification's universal/container-fallback playback is not implemented.

Fast copy currently supports zero-video-start H.264/HEVC MP4/MOV with compatible audio tracks. Unsupported copy structures resolve to accurate encoding in Automatic, where supported. A static/repeated picture can make hash-based boundary correspondence ambiguous and cause fallback. Copy retains the first video and all audio tracks; encoding retains the first video and first audio track. Subtitles, chapters, attachments, and extra video are omitted and disclosed.

Encoding is limited to supported progressive SDR square-pixel sources, including right-angle rotation. HDR/wide color, interlaced material, alpha, and non-square pixels are blocked rather than silently converted. Odd full-frame dimensions require an even crop. Sources whose video and container timeline origins differ materially are not supported for encoding in this MVP. Encoded output is H.264/AAC MP4. Size estimates are sample-based and approximate.

The process runner and estimates are cancellable. Publication uses a no-replace filesystem operation on the destination volume. External-drive behavior has not yet been tested on physical removable media; unsupported publication operations fail rather than falling back to an overwrite-prone implementation.

## Color correction and optional models

The editor supports manual black/white levels, gamma, saturation, saved looks,
`.cube` import, Core Image automatic enhancement, matching-reference fitting,
and an optional OpenAI-compatible vision-provider boundary. The provider can be
backed by OpenRouter or a local llama.cpp/MLX server; it returns bounded global
exposure and color-intensity parameters that are compiled into the same
validated LUT used by preview and export. Channel-specific white balance is
outside this first provider contract. See [color-provider.md](docs/color-provider.md)
for the M1 fallback and secret-handling guidance.

## Code layout

- `Sources/CropTrimmerCore/MovieLoops.swift`: bounded independent loop ranges, selection, fixed-length moves, and presets.
- `Sources/CropTrimmerCore/Models.swift`: source/edit/plan/result values and geometry validation.
- `Sources/CropTrimmerCore/MediaEngine.swift`: inspection, planning, FFmpeg jobs, estimation, and media validation.
- `Sources/CropTrimmerCore/NativeTimeline.swift`: maps native playback through nonempty video segments, including leading empty edits.
- `Sources/CropTrimmerCore/OutputPublisher.swift`: unique names and exclusive publication.
- `Sources/CropTrimmer/EditorModel.swift`: playback, job state, editor actions, and export coordination.
- `Sources/CropTrimmer/EditorView.swift`, `CropOverlay.swift`, `ReviewView.swift`: native editor and session result review.
- `Tests/CropTrimmerCoreTests/`: actual media fixtures, boundary/geometry tests, and publication-race tests.

[Product specification](Crop%20Trimmer.md) and [implementation guide](IMPLEMENTATION-GUIDE.md) describe the broader product. The simplified file workflow above reflects the user's subsequent MVP clarification and supersedes their library/persistence requirements for this build.
