# Crop Trimmer

## Standalone macOS application specification

Crop Trimmer is a focused desktop application for turning a long or loosely framed movie into a shorter, more useful movie. Open a file, mark the portion worth keeping, optionally frame the action more tightly, and export a new file. The original remains intact.

The application combines the speed of a simple trimming utility with the precision and visual restraint of a professional editing tool. Its interface takes its cues from Final Cut Pro and Logic: a prominent viewer, a filmstrip with a precise range selection, a compact inspector, and a consistently available export action. It is a standalone macOS application with its own small media library, independent of Blitzer, proxy recipes, production catalogs, and multi-screen playback.

This document defines the intended macOS product. It carries forward the detailed behavior of the movie trim/crop utility we designed and specifies how that utility should stand on its own. It does not claim that a macOS application has already been built. Native application lifecycle, library persistence, and Finder integration below are requirements for that standalone version.

## The central promise

The user should be able to answer four questions without learning video encoding:

1. Which part of this movie do I want to keep?
2. Do I want the whole picture or just this rectangle?
3. Can this export preserve the original compressed video, or does it need to be encoded again?
4. What will I get in terms of framing, duration, quality, and file size?

Temporal trimming keeps the section between A and B. Spatial cropping keeps a rectangle within every frame of that section. The interface names these operations separately, even when both are applied in one export.

The application works on movies. It does not need a multi-track timeline, transitions, titles, compositing, proxy management, or an audio production workspace. Its higher functions concern precise selection, sensible export decisions, and useful comparisons.

## A complete working session

The user opens a movie from Finder, drops it onto the application, or selects it in Crop Trimmer's library. The viewer displays the source and the timeline shows its filmstrip. Opening a file should not require a catalog scan or media conversion.

They play or scrub to a useful starting point and set A. They move to the end of the action and set B. The area between the yellow handles is the material that will survive the export. A–B repeat lets them watch the selection repeatedly and refine it.

The export inspector immediately identifies the proposed method. If suitable keyframes allow an acceptably close trim, it offers Fast trim with source quality unchanged. Otherwise it chooses accurate re-encoding. The user can inspect any timing adjustment before exporting.

If the action occupies only part of the picture, they enable Crop, adjust a rectangle directly on the image, and click Done. The viewer returns to the selected framing and stays paused. The selected temporal range remains intact.

When encoding is required, the user selects High quality, Balanced, or Smaller file. Estimate all sizes calculates approximate sizes for all three choices so they can compare them together. Export produces a new movie, adds it to the library, and opens a review with original and exported information.

The user can then export the same range with another crop or quality setting. The source selection stays available, and the Exports review retains the variants for comparison.

## Main window and visual character

Use a genuine macOS window with standard system window controls, menus, file dialogs, and keyboard conventions. Use system typography and appropriate system symbols. The application should feel at home on macOS without copying Apple's branding or presenting itself as an Apple product.

The working area is composed of connected panes with thin divisions. Media sits on black; surrounding controls use neutral graphite. Avoid large floating cards, decorative gradients, oversized headings, and paragraphs of help occupying the editing area.

| Element | Design direction |
| --- | --- |
| Working background | Graphite, approximately `#1b1b1d` |
| Inspector and panel surfaces | Approximately `#242426` |
| Raised controls | Approximately `#303033` |
| Dividers | Subtle, approximately `#3a3a3e` |
| Primary text | Near white, approximately `#f1f1f3` |
| Supporting text | Readable gray, approximately `#b1b1b8` |
| Actions and keyboard focus | System blue; reference `#0a84ff` |
| Temporal selection | Yellow; reference `#ffd60a` |
| Crop geometry | White handles and outline |
| Playhead | Thin white rule and cap |

Use compact labels and aligned values. The established utility uses roughly 10–12 point text, but the macOS implementation must favor readability and accessibility over preserving an exact density. Use monospaced digits for time and geometry. Controls should remain identifiable without relying on color alone.

The reference editing window is approximately 1160 × 820, with a compact layout around 900 × 650. These are layout references in logical window units, not requirements to force a window beyond the available display. The inspector is approximately 300–326 units wide. Resizing should give most additional space to the media viewer.

### Window anatomy

The title bar identifies the active movie and contains an **Exports** action with the number of completed session exports. Long filenames truncate visually, with the full name and location available on demand.

An optional, collapsible library sidebar provides source and exported movie selection. It is a browser for this utility's files, not a separate production system. Hiding it leaves the focused editing workspace.

The main editing column contains the viewer, transport, and timeline. The right inspector contains range values, crop geometry, export method, and quality choices. A status strip reports readiness, progress, completion, or an actionable error.

The viewer and timeline stay in place when crop controls or output details expand. The inspector scrolls independently. Export remains anchored at its bottom and reachable at the smallest supported window size.

## Viewer and transport

The viewer displays the movie with its correct orientation and aspect ratio. Fit the image within the available space without stretching it. Letterboxing belongs to the viewing surface, not to the exported image.

Provide play/pause, stop, frame backward/forward, larger backward/forward navigation, a current-position readout, mute, and volume. Navigation and audio controls use compact groups with descriptive tooltips and accessible names.

There are three playback modes:

| Mode | Behavior |
| --- | --- |
| A–B repeat | Repeats the selected section; the default for refining an edit. |
| Whole movie | Plays the source without constraining playback to the selection. |
| Play selection once | Plays A through B and stops at the end of the selection. |

The playhead and the selection endpoints are independent. Scrubbing should not silently move A or B. Playback volume and mute are monitoring controls; they must not silently remove or attenuate audio in the exported file.

## Timeline and the A/B interaction

The timeline is a filmstrip rather than a multi-track editing canvas. A yellow span marks the retained section. The rest of the filmstrip is subdued with neutral shading. A white playhead shows the current viewing position.

Preserve the specific endpoint convention from the original utility:

- Click **A** or **B** to recall that endpoint and seek to it.
- Shift-click **A** or **B** to store the current playhead position as that endpoint.
- Press **I** to set A and **O** to set B when editing shortcuts have focus.
- Drag either endpoint handle to refine the selection.
- Edit the start and end fields for precise values.
- Reset the range to the whole movie without altering the source.

Show selected duration prominently near the timeline, alongside the source duration. Keep endpoint fields and the filmstrip synchronized. Invalid or reversed ranges must receive a clear correction or explanation; they must never become an ambiguous export.

Frame stepping supports close visual inspection. For variable-frame-rate sources, use the source's actual timing; do not imply that a constant-rate frame grid can represent every source timestamp exactly.

Keyboard shortcuts must yield to text entry and modal review. Typing a filename or editing a number must not unexpectedly set an endpoint or start playback.

## Crop interaction

Crop is optional and applies to the entire A–B selection. It selects one fixed rectangle from the source picture. It does not track a subject, animate over time, pan, or zoom.

Enabling crop exposes a clearly bounded adjustment mode. Pause on a representative frame, show the whole source image, draw the crop rectangle, and darken the area outside it. Keep the retained picture visually faithful; the overlay must not introduce a color cast inside the crop.

The user can drag the rectangle to reposition it, drag its corner handles to resize it, and enter its X, Y, width, and height in pixels. Provide keyboard adjustment with discoverable increments and a visible focus indicator. Keep the rectangle inside the source image and disclose any adjustment needed to produce valid encoded dimensions.

Coordinate fields and handles refer to the visually upright image. A portrait phone recording with rotation metadata must crop the same region in the preview and the exported file. Display scaling and letterboxing must not affect the source-pixel geometry.

**Done** exits crop adjustment and shows the cropped framing without resuming playback. **Adjust crop** reopens the full-frame adjustment view. Reset restores the full frame; turning crop off keeps the temporal selection and returns to trimming alone.

Export uses the crop's native pixel dimensions. A 640 × 360 rectangle becomes a 640 × 360 movie; the application should not silently enlarge it back to the original dimensions. A tighter crop can make the action more prominent, but it cannot create detail that was absent from the source.

## Export method: intelligent defaults with visible consequences

The method selector offers **Automatic**, **Fast trim**, and **Accurate trim**. The inspector also displays the resolved method, so Automatic never conceals whether encoding will occur.

### Automatic

The user's tolerance is approximately one quarter of a second at each endpoint. If a suitable compressed-stream cut can place both boundaries within **0.25 seconds** of the requested A and B, prefer copying the compressed media. Display the planned start/end and any shifts.

Keyframe spacing is a property of the particular movie. Do not assume keyframes occur every quarter-second or at a universal interval. Inspect the source around the requested boundaries. A short movie may contain no useful nearby keyframe beyond its beginning.

If either boundary cannot meet the tolerance, use accurate re-encoding. Once encoding is necessary, honor the requested A/B boundaries as accurately as the source's frame and audio timing permit; there is no benefit to deliberately retaining the larger keyframe approximation.

Container and packet timing can make an actual copy differ from the initial plan. Check the produced timing before publishing the result. In Automatic mode, a copy that exceeds the accepted tolerance should fall back to accurate encoding when the source is supported, with a clear status explanation.

### Fast trim

Fast trim copies compressed video rather than recompressing it. It preserves the copied picture's encoding quality, usually finishes quickly, and avoids introducing another generation of video compression.

Manual Fast trim may accept boundary shifts larger than 0.25 seconds, but those shifts must be visible before export. It must not promise frame accuracy. If the format or packet structure cannot produce a valid result, explain why it is unavailable.

Quality controls do not apply to copied video. Display **Source quality unchanged** and a single approximate size instead of implying that the three encoding presets would alter the copy.

### Accurate trim and cropped export

Accurate trim decodes and re-encodes the selected interval. Crop also requires re-encoding. Enabling a spatial crop therefore resolves the method to re-encode and explains that relationship next to the method control.

Keep the source frame timing and avoid unnecessary scaling. Show the output dimensions, selected duration, and active quality choice before export.

## Three quality choices and useful size estimates

Use three compact, mutually exclusive rows. Each has a visible selection indicator, its quality name, and its own estimated output size aligned to the right.

| Choice | User meaning | Reference encoding recipe |
| --- | --- | --- |
| High quality | Preserve more detail, with a larger likely file. | H.264, CRF 18 |
| Balanced | Default compromise between size and detail. | H.264, CRF 21 |
| Smaller file | Prioritize size, accepting more visible compression. | H.264, CRF 25 |

The established software encoding reference uses the medium preset and AAC audio at 192 kb/s. These values belong in technical documentation or a secondary details disclosure, not in the main decision flow. They are reference recipes, not directly interchangeable settings for a macOS hardware encoder; a different encoder needs its own quality calibration.

Before calculation, each size reads **Not estimated**. **Estimate all sizes** encodes a bounded sample from the selected material at each quality, using the same crop and output geometry. The existing approach samples up to three seconds near the middle and scales the result to the chosen duration.

Run the sample jobs as one cancellable operation with coherent progress. Once calculated, retain all three results as the user switches quality choices. Changing A/B, crop geometry, or export method invalidates the old estimates. Clearly label every estimate as approximate.

A sample may miss a burst of motion, grain, or a scene change elsewhere in the selection. Present the estimate as guidance, not a promised size or artificial precision. Exact final bytes appear only after the completed export.

## File-size and quality judgment

A shorter movie will often be smaller, but cropping does not guarantee a proportional reduction. Encoded size depends on the retained image, motion, detail, noise, codec, quality setting, and audio. Keeping one third of the frame does not promise one third of the bytes.

Re-encoding a tightly compressed source at a generous quality setting can produce a file larger than the source or larger than a fast-trim equivalent. That is a legitimate result to explain, not hide. Re-encoding cannot restore detail already lost from the original.

The interface should separate factual observations from visual judgments:

- **Smaller file:** supported by measured byte counts.
- **Shorter duration:** supported by measured timing.
- **Tighter framing:** supported by the selected crop and dimensions.
- **Quality unchanged by recompression:** appropriate for a confirmed stream copy.
- **Re-encoded:** disclose that another compression generation occurred.
- **Looks better or worse:** something the user judges from the moving image; do not claim an automatic quality score that the app has not measured.

## Before-and-after review

After a successful export, open a dedicated review sheet or window. Keep detailed comparisons out of the main inspector so the editing workspace stays compact. The **Exports** action reopens this review later.

Display the original and result side by side, with images corresponding to the same source moment inside the selected range. The result frame must come from the actual exported movie. Label the images clearly, including the crop's dimensions, so a zoomed preview cannot be mistaken for added resolution.

Show actual duration, dimensions, file size, method, and quality where applicable. Include the requested range and actual boundary shifts when relevant. Provide Play result and Reveal in Finder. Still previews support framing comparison; opening the result for playback is necessary to assess motion and compression artifacts.

Keep an export history for the working session, with one row per result. Include filename, trim/crop operation, duration, dimensions, quality or copy status, actual size, and an action to reopen the result. This supports the user's central comparison: a five-second trim versus the same five seconds with a subsection selected, optionally repeated at different quality settings.

For a fair comparison, retain the source A/B and crop settings after export. Automatically add the result to the library without replacing the active source or losing the current edit. A user can deliberately open a result as a new source afterward.

### Concrete example from the original utility

An earlier sample run produced the following results. These illustrate the review's content; they are not predictions for other movies or evidence of a finished macOS build.

| Version | Duration | Dimensions / framing | Actual bytes |
| --- | --- | --- | --- |
| Original butterfly movie | 8 seconds | Full source frame | 2,985,690 |
| Trim | 5 seconds | Full source frame | 1,754,526 |
| Trim with crop | 5 seconds | 320 × 360 subsection | 371,707 |

That source had only a starting keyframe useful to this decision, so the automatic trim used re-encoding. The cropped result was much smaller in that example. The user still needs to judge whether the tighter framing preserves the desired action and enough detail.

## Library, saving, and filenames

The standalone library is a lightweight collection of movie references and completed exports. Support thumbnail and list presentation, selection, playback, and opening a movie for editing. Persist the collection and recent locations across launches; do not require copying originals into an application-owned media store.

Open Movie, Finder drag-and-drop, and recent movies are first-class entry points. Missing or moved files should have a clear Locate action. Access permissions should be handled through normal macOS file selection and persisted access where supported.

By default, save beside the original when that location is writable. Allow another destination using a standard save/location dialog, and remember the user's choice. The output name retains the source base and appends the operation:

```text
Beach walk.mov
Beach walk - trim.mp4
Beach walk - trim 2.mp4
Beach walk - crop.mp4
Beach walk - crop 2.mp4
```

A combined temporal trim and spatial crop uses the crop suffix. The extension reflects the actual output container; copied exports may need a different container from encoded exports. Never disguise one format with another extension.

Reserve a unique final name safely even when another export or application creates a file at the same time. Never overwrite the source or an existing result. Write temporary output, finish and validate it, then publish the completed file. Cancelled or failed output must not appear as a successful library item.

Successful publication automatically adds the result to the library and makes it playable. No manual refresh, catalog scan, or restart should be required.

## Supported media and preservation details

The initial reliable re-encoding scope carried forward from the utility is progressive SDR video with square pixels, including right-angle rotation metadata. Inspection must identify features outside that scope before export. HDR, wide color, interlacing, non-square pixels, and transparency need explicitly supported processing or a clear limitation; they must not silently produce an incorrect-looking movie.

The reference copy path retains the first video stream and all audio streams, using MP4 for suitable MP4/MOV-family sources and Matroska otherwise. The reference accurate/crop path produces H.264 video with the first audio track encoded as AAC. Subtitles, chapters, attachments, and additional metadata are not guaranteed by that baseline.

The standalone application must disclose meaningful track omissions before export, particularly for movies with multiple languages or captions. A later extension can add track selection and preservation, but the initial interface must describe the actual behavior truthfully. Files with no audio should remain valid silent movies.

The macOS implementation must use safe publication compatible with supported destination volumes, including external drives. The earlier utility's hard-link publication is an implementation detail to replace or adapt where unsupported; it is not a user-facing requirement to use a particular filesystem.

## Progress, cancellation, and recovery

Use clear states: opening, ready, estimating, exporting, cancelling, complete, and failed. Display concise status near the work, with technical details available separately when needed.

During an estimate or export, freeze settings that would change the job's meaning and retain their visible values. Keep Cancel available. Do not allow the user to mistake an edited selection for the settings of an already running export.

On cancellation, remove temporary results, retain the edit, and return to a useful ready state. On failure, describe the immediate cause and a next action: choose a writable destination, free space, locate the original, select a supported export method, or retry.

Recheck source availability and changes before final publication. If the source was replaced during the operation, do not silently present the output as corresponding to the original inspected file.

Closing the app during active work needs a native choice to continue or cancel that work. Preserve useful window geometry, library locations, and edit state for reopening; a completed output must remain discoverable independently of session review history.

## macOS polish and accessibility

Provide standard Open and Quit commands, a Window menu, native focus behavior, and familiar Command-key shortcuts. Make the important actions available in menus as well as buttons. Keep I/O endpoint shortcuts discoverable through menu labels or help.

Support VoiceOver names and state announcements for playback, range endpoints, crop geometry, quality selection, progress, and export results. Provide visible focus, keyboard access to inspector sections, adequate contrast, and reduced-motion behavior. A/B and crop handles need practical pointer targets larger than their fine visible strokes.

Respect Retina scaling and resizing. Opening a review sheet must correctly cover or suspend the underlying video surface, and closing it must restore the viewer without jumping playback or losing the selection. The underlying editor must not respond to shortcuts while the review owns focus.

Use progressive disclosure: duration, framing, method, quality, and size are immediately visible; codec details, track handling, estimate caveats, and unusual-source restrictions live under Output details. Essential warnings that change an export decision must remain visible outside that disclosure.

## Product boundary and completion intent

The finished application should make one movie operation feel complete: open, inspect, select, trim, optionally crop, choose an export tradeoff, save safely, and compare the result. It should remain fast to understand even as its export decisions become sophisticated.

The defined higher functions are keyframe-aware automatic trimming, precise fallback encoding, source-coordinate cropping, three comparable sample-based size estimates, actual before/after review, export variant history, safe sequential naming, and immediate library availability. Moving crops, multi-track editing, effects, target-byte encoding, and batch automation are outside the established scope and should not complicate this interface.

This specification is the standalone macOS product definition. Implementation planning, platform selection, testing, packaging, signing, and distribution are subsequent work.
