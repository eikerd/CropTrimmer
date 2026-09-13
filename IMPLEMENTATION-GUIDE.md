# Crop Trimmer — Swift implementation and agent handoff guide

Prepared as an implementation plan on September 13, 2026, before the application was built. See [README.md](README.md) for the current working MVP, build instructions, and support limits. The user subsequently simplified the MVP to drop/open → edit → export beside the original; library and persistence are deferred.

## 1. Authority and intent

Read [Crop Trimmer.md](Crop%20Trimmer.md) first. That document is the product specification; this guide translates it into an implementation strategy. If they conflict, the product specification wins. Choices explicitly described here as defaults or proposals may be revised with evidence, while preserving the required behavior.

Build a standalone native macOS application that opens a movie, selects a time range, optionally crops its picture, exports safely, and compares the result with the original. Preserve the active source and edit after export.

Terminology:

- **Trim:** retain a time interval. Copy compressed media when feasible; decode and re-encode when accurate boundaries require it. This is a container-aware operation, not literal byte truncation of an arbitrary file.
- **Crop:** retain a fixed rectangle of source pixels for the entire selection. Requires decoding and re-encoding. Output dimensions equal the effective crop dimensions, without enlargement.
- **Fast trim:** stream copy with disclosed boundary shifts.
- **Accurate trim:** encoding with boundaries as close as source presentation timing permits.

Do not build multi-track editing, moving crops, effects, titles, batch jobs, target-byte encoding, or Blitzer catalog integration.

### Existing implementation reference

The user confirms that Blitzer is currently Windows-only and is checked into GitHub. Use it as a behavioral and media-processing reference, not as a native macOS implementation to port directly. Its repository URL has not been identified in this task. No Blitzer directory was found in a bounded search of `/Users/ernestoikerd/repos` during preparation of this guide. No Blitzer code has been reviewed. Before reusing its algorithms, obtain its actual location and inspect its trim planner, FFmpeg arguments, sampling, orientation handling, and output validation. Record file and symbol references and identify differences from this specification. Do not treat this guide as evidence of how Blitzer is implemented.

No `docs/CODEX-NAVIGATION-GUIDE.md` exists in this project at preparation time. Read it if subsequently supplied.

## 2. Decisions and early feasibility gates

Recommended initial architecture:

| Concern | Proposed choice | Reason / gate |
| --- | --- | --- |
| Application | Native SwiftUI macOS app with focused AppKit bridges | Native lifecycle, menus, dialogs, accessibility; custom editing gestures where needed |
| Playback | AVPlayer and an AppKit-backed video surface | Keep playback independent from inspector rendering; prove source compatibility |
| Media engine | Pinned, bundled FFmpeg and ffprobe executables | Align with stream copy and software H.264 CRF recipes |
| Encoding | libx264 medium, CRF 18/21/25; first audio track AAC 192 kb/s | Product reference recipes; availability and distribution obligations must be resolved |
| Time representation | Rational media time, bridged to CMTime | Avoid repeated floating-point conversion and assumed constant frame rate |
| Persistence | Versioned Codable metadata stored atomically in Application Support | Small reference library; avoid unnecessary database complexity initially |
| Concurrency | Main-actor UI state; actors/services for media jobs and persistence | Explicit ownership and cancellation |
| Deployment | Provisional macOS 14+; Apple silicon first | Confirm installed toolchain and required audience before fixing project settings |
| Distribution | Provisional signed and notarized direct distribution | App Store and sandbox configuration remain a separate feasibility decision |

These are implementation defaults, not additional user requirements. In particular, do not silently replace the software quality recipes with hardware encoder settings: they need their own calibration.

### Required spike before the main build

Demonstrate, with tiny fixtures and a command-line/test harness:

1. Launch the proposed bundled executables, inspect a file, encode a crop, cancel a job, and clean its temporary output.
2. Copy a keyframe-aligned selection and verify its actual source-relative boundaries, including B-frames and audio timing.
3. Render portrait material upright and produce the exact selected rectangle once, without double rotation.
4. Open every proposed supported input and output container in the proposed playback path.
5. Prove the proposed helper signing, entitlements, access permissions, and packaging arrangement in a packaged app, not just an Xcode run.

**Playback compatibility is a release decision.** FFmpeg accepting a format does not mean AVPlayer can play it. The reference copy path may produce Matroska, which must be tested independently. If a required format is unavailable in AVPlayer, implement an appropriate fallback playback surface or present a clearly bounded support policy for user review. Do not claim universal playback, silently convert sources on opening, or ship an unplayable completed library item.

Pin the engine version, build configuration, architectures, checksums, and provenance. Review distribution obligations for the actual binary, including libx264 and enabled dependencies. Do not assume every FFmpeg build has the same license or encoders. The released app must not depend on the user's Homebrew installation or shell PATH.

## 3. Architecture and ownership boundaries

Use one application target plus a testable core package or equivalent isolated core target. Avoid creating one package per class. The following paths are proposed within this existing project folder; they do not exist yet.

| Area | Proposed files / folders | Responsibility |
| --- | --- | --- |
| App | `CropTrimmer/App/` | Entry point, dependency composition, window lifecycle, commands, open events |
| Domain | `CropTrimmerCore/Domain/` | Source descriptor, edit state, rational range, crop, plans, results, errors |
| Inspection | `CropTrimmerCore/Inspection/` | Metadata, stream inventory, timing index, support classification |
| Planning | `CropTrimmerCore/Planning/` | Method resolution, copy candidates, geometry, disclosures |
| Engine | `CropTrimmerCore/Engine/` | Argument construction, process runner, progress, estimates, export validation |
| Storage | `CropTrimmerCore/Storage/` | Bookmarks, library, source identity, publication, recovery journal |
| Editor | `CropTrimmer/Editor/` | Main view model, viewer bridge, timeline, transport, crop overlay |
| Inspector | `CropTrimmer/Inspector/` | Range, geometry, method, quality, output details, anchored Export |
| Library / Review | `CropTrimmer/Library/`, `CropTrimmer/Review/` | Selection, locating files, history, actual result comparison |
| Tests | `Tests/`, `UITests/`, `Fixtures/` | Domain tests, integration fixtures, UI journeys |

Dependencies flow from UI to domain/services. The core must not import SwiftUI. Views do not construct FFmpeg arguments, directly launch processes, or perform filesystem publication. Inject service protocols and test doubles at composition time.

### Core contracts

Define these data contracts before separate agents implement dependent areas:

- `SourceDescriptor`: stable source ID, resource identity snapshot, access reference, container, video/audio/subtitle inventory, rational presentation extent, encoded and upright dimensions, transform, pixel aspect, color/interlace/alpha classification, playback and engine capabilities.
- `EditState`: source ID, requested half-open range `[A, B)`, crop enabled, effective pixel rectangle, requested method, selected quality, revision. Current playhead, monitor volume, and crop-adjustment state belong to editor presentation state.
- `ExportPlan`: source snapshot, edit revision, requested range, planned range, signed shifts, resolved method, geometry, retained and omitted streams, container and extension, recipe/version, support reasons, warnings, destination requirement. Immutable once a job starts.
- `EstimateKey`: source identity plus range, effective geometry, method, recipe/version, retained audio policy. Quality switching must not discard the other two computed values.
- `ExportResult`: output identity/location, actual measured properties, requested/planned/measured timing and confidence, source mapping, method actually used, quality when encoded, comparison frame references, completion time.
- `JobEvent`: stage, bounded progress when measurable, status, completion or typed failure; a job ID accompanies events to reject stale updates.

Service interfaces should cover inspection, timing lookup, planning, playback, estimation, execution, validation, publication, file access, and library persistence. Prefer small interfaces named for operations rather than a single global media manager.

Errors must distinguish unsupported media, unreadable source, changed source, unavailable helper, invalid range/crop, unwritable destination, insufficient space, engine failure, validation failure, and persistence failure. Include a user action and separately available diagnostic details.

## 4. Time and export planning

### Canonical timeline

Choose the displayed first video presentation point as the normalized source origin and preserve its mapping to stream timestamps. Do not assume the container or audio begins at zero. Store integer timestamps and time bases; convert only for display and API boundaries.

A and B define a half-open interval: A is included; B is the excluded boundary. Validate `0 <= A < B <= sourceEnd`. A frame's presentation timestamp and duration determine its displayed interval. Nominal FPS is informational, not a VFR stepping grid.

Document a consistent accurate-boundary policy using actual frame intervals, including which frame appears when A lies inside a frame. Display effective timing when meaningful. Integration fixtures must validate that policy rather than assuming all requests can become exact encoded boundaries.

### Planner decision table

| Condition | Resolved behavior |
| --- | --- |
| Crop enabled and encoding supported | Encode; explain that crop requires encoding |
| Accurate selected and supported | Encode requested range according to source timing |
| Automatic, valid copy candidate, both absolute shifts <= 0.25 s | Attempt copy and validate before publication |
| Automatic, no acceptable candidate, encoding supported | Encode |
| Fast selected, valid candidate | Copy; show planned start/end and signed shifts even outside tolerance |
| Requested operation unsupported | Block Export with specific reason and an available alternative |

Crop takes precedence over Fast: keep requested preference separately if desired, but display the actual resolved method prominently. Never apply quality controls to a copy job.

Inspect keyframes and packet dependencies near both boundaries. Expand a bounded inspection window if needed; cache against source identity. Do not load every packet of a multi-hour file into memory to move a handle. Mark planning as pending and disable export until a valid current plan exists.

A keyframe flag alone is not proof of an independently decodable segment. Open GOPs, decode order, edit lists, timestamp offsets, and packetized audio can affect the result. Candidate selection and execution are related but separate; test both.

### Result timing validation

Do not infer source-relative A/B from output duration alone. Rebased timestamps can hide an incorrect start. Carry source-to-output timing provenance through the engine, and independently verify first/last displayed content and decodability. Synthetic fixtures should have visible frame numbers and known timestamps; use them to validate production boundary measurement. Define a confidence policy for real media whose correspondence cannot be established reliably.

For Automatic, a copy with either measured boundary beyond tolerance, invalid decoding, or insufficient validation confidence is discarded and replaced with an accurate encode when supported. Report the fallback, validate the new result, and record the actual final method. Otherwise explain the failure without publishing success.

For manual Fast, if measured shifts materially differ from the displayed plan, present the changed timing before publishing or return a replanning error. Do not use manual selection as permission for arbitrary undisclosed timing.

## 5. Engine execution and validation

Use Foundation Process with a fixed executable URL and an argument array. Never interpolate filenames into a shell command. Restrict operation to selected local media; do not turn arbitrary user strings into engine options or remote protocols. Pass explicit stream mappings rather than relying on automatic stream choice.

The process runner owns concurrent draining of stdout/stderr, bounded diagnostic retention, progress parsing, completion, cancellation, and child cleanup. Large logs must not block a pipe or consume unbounded memory. A cancelled task must actually stop its subprocess and wait for exit before deleting its output. Distinguish cancellation from encoder failure. Test arguments containing spaces, quotes, Unicode, and leading hyphens.

The precise seek placement, timestamp options, audio trimming, rotation filters, and VFR output options must be established by the spike against the pinned engine version. Do not copy a generic `-ss` command and assume it meets this contract.

Copy policy: first video stream and all compatible audio streams. Prefer MP4 for suitable MP4/MOV sources; otherwise use the validated reference container policy. Inspect actual codec/container compatibility, not just the filename extension. Disclose omitted subtitles, chapters, attachments, extra video, or unsupported metadata.

Encode policy: first video, first audio if present, H.264 at the selected recipe, AAC 192 kb/s, MP4. Silent input stays silent. Preserve source presentation timing without unnecessary fixed-rate conversion. Normalize supported orientation consistently; do not retain a rotation tag that applies the same transform again. Preserve supported SDR color meaning. Out-of-scope HDR, wide color, interlacing, non-square pixels, and transparency require explicit support or a clear block on encoding; copy support is assessed separately.

Validate temporary output before success:

- Process completed and produced a readable, nonempty container.
- Expected streams, codecs, dimensions, orientation, and audio policy match the plan.
- Video begins and ends decodably; timing and A/V synchronization satisfy the measured policy.
- Selected source moments map correctly to the output; Automatic tolerance is satisfied for copy.
- Source identity has not changed, destination is still valid, and output is playable in the promised path.

A full decode may be appropriate for short outputs; define bounded validation for long outputs and disclose its technical limits in developer documentation. A zero exit status alone is insufficient.

## 6. Editor layout and interaction

Use the specification's graphite surfaces, yellow temporal selection, white crop outline, compact typography, and native system controls. Keep the viewer and timeline stable while inspector sections expand. The inspector scrolls; the Export button stays anchored. Fit to available screen dimensions at launch.

Layout: optional library sidebar; central viewer, transport, filmstrip; right inspector approximately 300–326 points; status strip. Reference size 1160 × 820, compact target around 900 × 650. Test resizing and accessibility instead of hard-coding these as universal minimums.

Playback controller owns player observers and removes them on source replacement/disposal. Use generation IDs for source loading and seek completions. Coalesce interactive seeks; use a precise final seek on release. Playback updates never modify A/B.

Transport supports play/pause, stop, actual frame backward/forward, larger jumps, current time, mute, and volume. Proposed larger jump default: five seconds, clamped to source bounds. Proposed stop behavior: pause and return to A in selection modes, source start in Whole movie. Record these defaults in help.

Modes: A–B repeat by default; Whole movie; Play selection once. End handling must prevent repeated callbacks and respect source replacement. Monitor volume/mute must never enter the export plan.

Timeline behavior:

- Click A/B to seek to the stored endpoint; Shift-click stores current position.
- I/O store A/B only when editor shortcuts own focus.
- Handles and precise fields update the same range model.
- Scrubbing changes only the playhead; reset restores full range.
- Reject or visibly correct invalid field entries; do not silently reverse endpoints.
- Thumbnail work is asynchronous, cancellable, cached, and bounded by display needs.

Scope commands through native focus/command routing. Text fields, save dialogs, and review sheets must suppress editor shortcuts. Do not install a global keyboard handler that consumes ordinary typing.

## 7. Crop geometry

Use top-left-origin, integer pixel coordinates in the visually upright image. Store one effective rectangle with positive dimensions inside the upright source bounds. Use the same geometry for fields, overlay, estimates, plan, and export.

Compute aspect-fit display bounds and letterbox offsets before mapping pointer positions. Map logical points to source pixels; do not confuse Retina backing pixels with source pixels. Test transforms and their inverses for all supported right-angle rotations.

Enabling crop pauses playback and opens full-frame adjustment. Darken only the outside area. Drag the rectangle to move it; drag corners to resize; expose numeric fields and keyboard movement/resizing. Proposed keyboard increments: one pixel, Shift for ten pixels, with separately discoverable resize controls. Provide large invisible hit areas and accessible numeric alternatives to dragging.

Done exits adjustment, displays cropped framing, and remains paused. Adjust crop restores the full image and overlay. Reset means full source rectangle. Turning crop off preserves A/B.

For the selected pixel format, normalize dimensions and alignment to the encoder's real constraints before finalizing the plan. Show the effective geometry immediately and explain any adjustment; never display one rectangle while encoding another. Odd full-frame dimensions also need a disclosed policy. Do not silently resize or introduce padding merely to make an encoder accept input.

## 8. Size estimates

Before calculation, all three encoded quality rows show Not estimated. Estimate all sizes starts one cancellable operation, freezes relevant settings, and runs all three recipes with the same crop, audio policy, and engine version as export.

Sample duration is `min(3 seconds, selection duration)`, centered within the selection and clamped to it. Scale measured sample size to selected duration and label the result approximate. Document mux/audio overhead and sampling limitations; avoid false precision. No estimate is a promised final size.

Retain all three results when quality selection changes. Changes to source, A/B, effective crop, method, or recipe invalidate them. Late results from an obsolete revision must not become visible. Cancelled partial runs should not look like a complete comparison.

Copy mode displays Source quality unchanged and a single approximate byte estimate based on selected stream data where available; use a clearly approximate bitrate fallback when necessary. Quality rows do not imply copy compression choices.

## 9. State, cancellation, and recovery

State progression: opening → ready → estimating/exporting → cancelling or validating → publishing → complete; any active stage can produce a typed failure. After cancellation/failure, return to a useful editor with the edit retained. Keep job stage and editor content separate so an error does not erase the source.

Permit one media operation at a time for the first version. Freeze all settings that affect its meaning and prevent source replacement during work. Keep Cancel available until publication commits. Publication is a brief commit boundary: cancellation before it removes owned temporary output; cancellation after it cannot pretend a completed file never existed.

Closing during active work offers a native choice to keep working or cancel and close. Resume safe persisted edit state after launch; do not automatically resume a half-written encoder output. Clean only app-owned stale temporary artifacts identified by a recovery journal.

## 10. File access, publication, and persistence

Use normal Open/Save panels and Finder open/drop events. Store references to originals rather than importing copies. Access coordination must support the chosen sandbox configuration; pair security-scoped access lifetimes where applicable, handle stale bookmarks, and provide Locate for moved or missing sources.

Library records include source/result identity, bookmark or access reference, display name, metadata cache, last-used timestamp, and relationship to originating source when known. Store edit state by source identity. Persist versioned records atomically; corrupt metadata should yield recovery options rather than a crash. Keep thumbnails in a purgeable cache.

Default to a writable source directory; otherwise request a destination. Remember a destination selected through normal UI. A combined trim and crop uses ` - crop`; trim-only uses ` - trim`; collisions increment ` 2`, ` 3`, and so on. The container determines the extension.

Publication transaction:

1. Acquire destination access and create a unique app-owned temporary file on that destination volume.
2. Execute and validate output there; temporary names never appear as successful library items.
3. Recheck source resource identity, size, and modification information. Use stronger identity checks when the filesystem cannot provide sufficient confidence; do not claim these checks prove byte immutability in every race.
4. Attempt publication using a verified no-replace filesystem operation. A check-then-rename sequence alone is unsafe. On collision, choose another suffix and retry without overwriting.
5. If the volume lacks the chosen primitive, use a tested safe alternative or fail clearly. Do not assume hard links or atomic rename semantics across every supported destination.
6. Persist the committed result in the library and open review. If persistence fails after publication, retain the valid file, disclose the indexing issue, and use the journal to reconcile on relaunch.

Never overwrite source, existing export, or unrelated files. Test APFS and a supported external-drive filesystem, collision races, unplugged drives, full disks, and app termination between publication and indexing. Success means both a valid published output and a discoverable library result, with recovery for the intermediate state.

## 11. Review and library behavior

After success, present a native review sheet/window while retaining the active edit. Exports shows the session result count and reopens history. Adding an output must not select it as the editor source automatically.

Review uses a decoded frame from the actual exported file, paired to the corresponding source presentation moment through recorded timing correspondence. Do not substitute the crop-preview image or assume output time zero equals requested A. If pairing cannot be established, show the limitation instead of a false comparison.

Show actual duration, dimensions, bytes, method, applicable quality, requested/planned/measured range, and meaningful boundary shifts. Provide Play result and Reveal in Finder. Still images demonstrate framing; moving playback is necessary for judging compression.

History contains one row per successful session export. Persistent library results remain discoverable after restart even if session review history is not retained. Missing result files receive Locate or a clear unavailable state.

Review owns focus and suspends underlying shortcuts. Test the AppKit video surface's layering under sheets and restoration afterward without seek jumps or lost selection.

## 12. Accessibility and performance

Expose names, values, and actions for endpoints, geometry, quality, playback, and export progress. Numeric fields provide full keyboard alternatives to custom handles. Announce stage changes without flooding VoiceOver with frame-by-frame progress. Respect reduced motion, visible focus, readable contrast, and practical pointer targets.

Keep disk access, inspection, thumbnails, sampling, and process management off the main actor. Bound thumbnail caches and timing scans. Instrument opening, scrubbing latency, memory growth, and export cancellation. A large source should not require complete decoding before editing begins. Establish performance budgets from measured fixtures on the target Mac rather than inventing unsupported guarantees.

## 13. Verification strategy and acceptance matrix

Use domain tests for mathematical and state invariants, integration tests with the real pinned engine for media correctness, and UI tests for complete editing journeys. Avoid tests that merely duplicate implementation expressions. Generate deterministic fixtures where possible and retain their generation recipe, expected timestamps, and redistribution provenance.

| Fixture / scenario | Required evidence |
| --- | --- |
| CFR, frequent keyframes | Automatic copies when both measured shifts meet tolerance |
| Sparse keyframes / only opening keyframe | Automatic encodes; manual Fast shows its larger shifts |
| Open GOP / B-frames | Valid decoding and source-relative boundary verification |
| Nonzero starts / edit lists / audio priming | Correct normalized display and output A/V correspondence |
| VFR | Frame stepping follows actual presentation times; export avoids accidental CFR conversion |
| Rotations 0/90/180/270 | Preview and export retain the same numbered pixel region |
| Odd dimensions / tiny crops / boundary drags | Valid disclosed geometry; no silent enlargement |
| Silent / multiple audio / captions | Correct track policy and pre-export omissions disclosure |
| HDR / wide color / interlaced / non-square pixels / alpha | Explicit supported behavior or actionable limitation |
| FFmpeg-readable but AVPlayer-unplayable media | Honest playback support decision, including result container |
| Tiny and long selections | Valid ranges, bounded estimation, no unbounded indexing |
| High-motion sample mismatch | Estimates remain approximate; exact final bytes reported |
| Source moved, removed, or replaced | Locate/reinspection or failure; no false success |
| Filename collision / external volume / disk full | No overwrite and no successful partial result |
| Cancel estimate/export / terminate app | Process stops, owned temp cleanup, edit recovery |
| Publication succeeds, indexing fails | Output survives and becomes recoverable/discoverable |
| Review open / text entry | I/O and playback shortcuts do not leak through focus |
| Repeated variants | Same active A/B and crop retained; all results added |

Primary end-to-end journey: open → set A/B → repeat playback → adjust crop → Done remains paused → estimate all qualities → export → compare actual result → reveal/play → export another variant → relaunch and locate results.

Also test fast trim without crop, fallback after failed copy validation, cancelled save panel, and smallest practical window. Build and run tests with the actual selected Xcode scheme; record commands and results in the handoff. Release validation additionally includes packaged helper execution, signing verification, notarization, clean-machine launch, and no dependency on development tools.

## 14. Build sequence and agent work packets

Use the existing project folder. Follow the user's one-active-development-branch and one-open-PR rule. Do not create additional worktrees, duplicate checkouts, or project directories without approval. The paths above are internal source organization, not a request for another checkout. This guide does not authorize pushing, publishing, or dispatching remote agents. No agents have been launched as part of writing it.

Each future agent must read the product specification and this guide, identify owned files, preserve others' changes, and record unresolved assumptions. Shared contracts should be agreed before parallel dependent work. One integrator owns project settings, shared model changes, and final validation.

### Phase 0 — Evidence and platform spike

Owner: media/platform agent. Inspect Blitzer once located; establish toolchain, engine packaging, playback matrix, timing validation, orientation, and distribution feasibility. Deliver a decision record, fixture evidence, pinned engine metadata, and precise supported scope. Exit: the five feasibility gates above pass or their unresolved choices are explicitly reviewed.

### Phase 1 — Core contracts and native shell

Owner: integration agent. Create app/core/test targets, domain models, dependencies, lifecycle, native menus, state routing, and persistence schema. Deliver a running window with open-file flow and testable service contracts. Exit: source identity, range, geometry, plan, and result types are stable enough for independent work.

### Phase 2 — Media pipeline

Owner: media agent; owns Inspection, Planning, Engine. Build real inspection, candidate planning, encoding/copy execution, validation, sampling, and cancellation. Deliver fixture-driven integration tests and documented timing policy. Exit: outputs meet declared behavior without relying on UI logic.

### Phase 3 — Editing interface

Owner: editor agent; owns Editor and Inspector. Build playback, filmstrip, endpoint conventions, crop mapping, estimates presentation, focus rules, and compact resizing. Can proceed alongside Phase 2 after contracts exist using test doubles, then integrate real services. Exit: required gestures and shortcuts work with the real engine and accessible alternatives.

### Phase 4 — Storage and review

Owner: storage/review agent; owns Storage, Library, Review. Build access persistence, collision-safe publication, journal recovery, review correspondence, and variant history. Coordinate transaction boundaries with media owner. Exit: no overwrite in race tests, no partial-success items, and exported files remain discoverable across launch.

### Phase 5 — Integration, independent review, release preparation

Owner: integrator plus a reviewing agent when the user dispatches the build team. Review timing and publication especially; run the full acceptance matrix, accessibility journeys, packaged-app tests, and appropriate Swift/code review. Fix issues before calling the app complete. Deliver build instructions, architecture notes, test evidence, known limitations, and distributable artifacts only within the user's release authorization.

Each packet must report: changed files, decisions, exact validation performed, remaining limitations, and dependencies for the next packet. Mocked UI alone, a successful encoder exit alone, or an unsigned development app alone does not satisfy completion.

## 15. Open decisions that need evidence, not immediate user interruption

- Blitzer GitHub repository location and exact reusable behavior; its current application is Windows-only.
- Final minimum macOS version and Intel support, based on audience and toolchain.
- Required non-AVPlayer formats and the fallback playback implementation.
- Bundled FFmpeg build, licensing, helper signing, and sandbox/distribution policy.
- Production source-relative boundary verification and uncertainty fallback.
- Verified no-replace publication implementation for supported external volumes.

Resolve technical choices through the spike. Ask the user only when evidence exposes a real product tradeoff, such as dropping a promised format, changing quality behavior, or narrowing supported machines. Do not reopen product decisions already specified.

## 16. Primary technical references

These references were consulted while preparing the plan; detailed API signatures and deployment availability must be checked against the toolchain selected for implementation. Architectural prescriptions above are proposed design decisions, not claims that these documents supply a complete implementation.

- [FFmpeg documentation](https://ffmpeg.org/ffmpeg.html): stream copy versus transcoding, option ordering, explicit stream mapping, and process-facing options.
- [ffprobe documentation](https://ffmpeg.org/ffprobe.html): structured media inspection, including streams, frames, and packets.
- [Apple AVPlayer documentation](https://developer.apple.com/documentation/avfoundation/avplayer): native playback foundation.
- [Apple sandbox file access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox): file-access design reference for a sandboxed configuration.

The product specification remains the acceptance authority. This plan is complete as a build handoff, not proof that the proposed engine, timing strategy, or packaged application already works.
