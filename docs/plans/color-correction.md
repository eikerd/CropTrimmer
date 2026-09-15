# Crop Trimmer color correction: assessment and execution plan

Prepared September 14, 2026. Planning only; no application changes made.

## Execution status

All implementation packets below are **not started**. Begin with C00. The parameter bounds, interchange domain, metadata policy, numerical thresholds, and performance targets below are proposals to resolve in that experiment; they are not measured capabilities or completed implementation decisions. The user's request to continue and leave instructions authorizes this tracked plan and handoff. Do not infer that an unrendered UI has already received visual approval.

This tracked document supersedes the earlier copy in the Codex visualization output folder. Keep future changes here so another checkout or machine receives them.

## 1. Recommendation

Proceed with manual correction and saved looks first. Use one compiled color transform for playback and export, while preserving the settings that produced it. Make learned correction a replaceable supplier of suggested transforms after the rendering system has passed its tests.

A reference library helps, but there are three different products hidden in that phrase:

1. **Saved look:** save adjustments already made in Crop Trimmer and apply them to another loop. No model or reverse engineering is needed.
2. **Matching before/after pair:** extract a frame, correct that same frame elsewhere, and fit a color transform between the two. This is a useful intermediate milestone.
3. **Unrelated reference photograph:** use another person, scene, or lighting setup as a desired example. This requires statistical or learned matching. It does not supply corresponding pixels and cannot use the same fitting algorithm as a before/after pair.

Start with the first, then the second. Evaluate the third as a separate capability. Applying a saved look to a new video is not the same as adapting that video to a reference.

## 2. Assessment of the Slack conversation

I read the channel and the entire assessment thread, including Claude's latest reconciliation. The revised agreement is technically reasonable, but it needs more boundaries before smaller agents implement it.

Sources: [original assessment](https://chungusai.slack.com/archives/C0C1W500BGR/p1789428739536909), [my corrections](https://chungusai.slack.com/archives/C0C1W500BGR/p1789428958386219), [Claude's reconciliation](https://chungusai.slack.com/archives/C0C1W500BGR/p1789430775751799).

| Topic | Assessment | Execution consequence |
|---|---|---|
| Shared LUT for preview and export | Good rendering boundary | Share transform semantics, not necessarily identical serialized bytes. Prove color conversions around both renderers. |
| LUT as the only saved state | Correctly withdrawn | Preserve manual parameters and optional base LUT. Compile a derived LUT for rendering. |
| 33×33×33 LUT represents any adjustment | Too strong | It samples a transform. Measure approximation error, especially near black and with steep gamma. |
| SDR eliminates transfer-function concerns | Incorrect and subsequently corrected | Record primaries, transfer, matrix, and range. Define the LUT's working space. |
| Fast, simple image-pair fitting | Premature; correctly qualified later | Implement regularized fitting with held-out validation and measured cost. |
| All candidate models are tiny | Withdrawn appropriately | Measure each checkpoint and inference pipeline on the actual GPU. |
| Four implementation PRs | Sensible outline, too large for modest agents | Split into six milestones and the smaller work packets below. Keep one active PR under this repository's rules. |
| Temperature/tint | Useful but outside the four requested controls | Defer. It need not block black point, white point, gamma, and saturation. |
| Reference library | Valuable | Separate saved settings, matching frame pairs, unrelated references, and regression fixtures. |

### Important limits of the proposed technique

A global LUT gives the same output color whenever it sees the same input color. It cannot make a shirt blue while leaving another object of the same original color unchanged. It cannot restore clipped detail, fix focus, or reproduce local relighting. A generated target image may contain those changes; the fitter must report poor fit rather than pretend they can be reproduced globally.

Use one fixed correction for a shot or loop initially. Independent model decisions on successive frames risk flicker. If a loop spans multiple shots, validate it across those shots or ask the user to split the loop; automatic scene segmentation is a later feature.

## 3. Verified starting point

- Repository: the Crop Trimmer repository root.
- Reviewed commit: `dfb96c8ed04f25673214ad301b6a3f8add1a62eb` on `main`.
- Checkout was clean; no open PRs or additional worktrees were reported.
- Baseline: **30 XCTest tests passed, zero failures**, approximately 20 seconds. This establishes the existing baseline, not color correctness.
- Installed FFmpeg: **8.0.1**. It has `lut3d` and `colorspace`; it does **not** have `zscale`.
- Installed `lut3d` defaults to tetrahedral interpolation. Do not depend on the default.
- Current playback uses `AVPlayerItem`; crop display is applied separately by the SwiftUI viewer. A color composition must not apply the crop or rotation twice.
- Existing source inspection reads some color information for encoding restrictions but does not retain a full color description in `MediaSource`.
- Queue cards distinguish crop from trim. Their quality controls and explanatory text must also handle color-only encoding.
- Estimates are explicitly requested. Color changes should invalidate affected estimates, without starting an encode on every slider movement.
- Existing exports use exclusive publication and preserve originals. Preserve that mechanism.
- The referenced `docs/CODEX-NAVIGATION-GUIDE.md` is absent. Do not assign agents a nonexistent prerequisite.

No target-PC benchmark, GPU memory check, AI inference, or new preview/export color comparison has been performed. The RTX 5060 Ti's installed memory capacity remains unverified.

## 4. Scope and behavior to freeze

### First release

Each loop has independently editable black point, white point, gamma, and saturation, plus enable/bypass and reset. Selecting a loop previews its correction. Editing an inactive loop must not change the active preview. Export queue jobs use immutable snapshots of each loop's settings.

Defaults: black `0`, white `1`, gamma `1`, saturation `1`, correction disabled. Saturation `0` produces monochrome. Enabling a correction with unchanged identity values need not force encoding if its compiled transform is demonstrably identity.

Proposed control bounds: black and white within `[0,1]`, minimum separation `1/255`, gamma `[0.25,4]`, saturation `[0,2]`. Reject invalid/nonfinite programmatic values. The UI prevents endpoints crossing. Gamma greater than one brightens midtones; document and test that convention.

Bypass preserves the settings. Reset restores defaults and removes an applied base look. It affects only the target loop. Do not introduce undo history as part of this work.

If correction changes pixels, export must encode, including when the requested method is Fast. This follows the existing crop behavior. The card must show the resulting method and expose quality controls rather than silently discarding the correction.

Keep filmstrip thumbnails uncorrected for this release: different loops may overlap and have different grades. Do not regenerate the filmstrip while sliders move.

### Deliberately deferred

Temperature/tint, curves, separate RGB levels, masks, scopes, histogram UI, automatic scene detection, per-frame adaptive grades, a project database, training a new model, and automatic selection among a large reference library. Add these only as separate decisions.

## 5. Rendering and state contract

These names describe responsibilities. A lead should freeze exact Swift declarations in milestone 0 before distributing implementation packets.

| Type/responsibility | Required contents |
|---|---|
| `SourceColorDescription` | Pixel format, primaries, transfer, matrix, range; distinguish reported values from chosen interpretation and unknown values. |
| `ManualColorSettings` | Four finite validated values; defaults and versioned decoding. |
| `ColorAdjustment` | Enabled state, manual settings, optional immutable base LUT; deterministic effective-identity decision. |
| `ColorLUT` | Grid size, RGB samples, domain and color-space identifier, format version, deterministic content digest. Validate payload before use. |
| `ResolvedColorTransform` | Immutable compiled table and source/output interpretation; input settings digest and renderer contract version. |
| `SavedLook` | Schema version, user name, manual settings, optional base LUT, optional reference thumbnail and provenance. |
| `ColorSuggestionRequest` | Source samples and metadata, optional reference, explicit mode, cancellation/request ID. |
| `ColorSuggestionResult` | Candidate LUT or paired target frame, provenance, diagnostics and validation results. It is a proposal, not an automatic overwrite. |

### Order of operations

`source decode → explicit color normalization → base LUT if present → manual adjustment → output color conversion → display or encode`

Crop and timeline operations retain their existing ownership. Apply rotation once. Define the grading domain independently from whether the viewer is displaying the crop or the full source.

Preserve manual settings instead of attempting to recover slider values from an imported or fitted LUT. Compose the base transform and manual adjustment by sampling their composition into the compiled render table.

Use a stable content hash, not Swift's process-randomized `Hasher`, for persistent identity or cache keys. Include the color-contract version and relevant source interpretation in cache keys.

### Color-space decision gate

Recommended interchange domain: normalized, encoded sRGB RGB, D65, because ordinary reference PNGs and many image tools use it. Production output initially remains SDR BT.709 with explicitly chosen matrix, transfer, primaries, and range.

This recommendation must pass milestone 0. Apple documents Core Image cube data in linear premultiplied RGBA; a standard `.cube` file normally provides RGB samples. Setting a filter's output space alone is not proof that both engines interpret the table identically. The adapters must perform the specified coordinate/color conversions and be tested. [Apple filter reference](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/index.html)

Try `CIColorCubeWithColorSpace` with an explicit context and conversion path. Compare against FFmpeg using explicit interpolation. If that cannot meet the contract, evaluate a small explicit Core Image kernel that samples the agreed table. Do not ship two visually different renderers simply because both accept something called a LUT.

If the proposed interchange domain is changed after the spike, update the contract, fixtures, serialization version, and all downstream tickets together before implementation begins.

### Input metadata policy

Begin with correctly tagged SDR BT.709, both limited and full range. Add BT.601 only when the same parity tests pass. Retain existing HDR/wide-gamut restrictions; do not remove them incidentally.

Do not silently treat all untagged sources as BT.709. Milestone 0 must establish how both decoders interpret missing tags. For ambiguous sources, require an explicit source interpretation before applying color; offer only interpretations the pipeline has actually tested. Normal opening and supported uncorrected copy operations should continue to work.

This is a necessary source setting, not a diagnostic dashboard. Never label an assumption as metadata read from the file. Tests must cover missing and contradictory metadata as well as correct tags.

## 6. Milestones and work packets

Execute milestones sequentially. Within a milestone, new isolated modules can be developed independently after their interfaces are frozen. Only one agent edits a shared integration file at a time.

### Milestone 0 — Prove the rendering contract

**Owner:** lead with color-pipeline experience. This is the part not to ask a modest agent to invent.

**Packet C00: contract and independent fixtures**

- Own new color-contract documentation and fixture/test helpers; no UI changes.
- Generate gray ramps, RGB/secondary patches, skin-like patches, near-black gradients, and full/limited-range clips with independently known values.
- Implement a small comparison harness for the proposed Core Image and FFmpeg paths. Extract processed pixels before lossy encoding as well as decoded production output.
- Test an asymmetric LUT so swapped axes or channel order cannot pass. Also test identity, gamma, saturation zero, and a moderately nonlinear transform.
- Determine actual Core Image interpolation behavior. Explicitly choose FFmpeg interpolation; never leave its tetrahedral default implicit. [FFmpeg filter documentation](https://ffmpeg.org/ffmpeg-filters.html)
- Demonstrate a working conversion graph on the installed/bundled FFmpeg without assuming `zscale`. If a different build is required, document and test packaging before dependent work proceeds.
- Prove orientation handling and paused-frame update using the proposed AVPlayer composition path.
- Measure 33-grid approximation separately from cross-renderer disagreement. Increase grid resolution or change the sampling scheme only if the measurements justify it.

**Outputs:** frozen type signatures, operation equations/domain, LUT order, conversion graph, interpolation choice, source metadata policy, actual measured error report, fixture helper, and proposed acceptance thresholds.

**C00 handoff checklist:** the next packet cannot begin until the lead fills in all of these with evidence:

- The exact level/gamma/saturation equations, including whether saturation uses linear-light luminance, coefficients, clamping order, and behavior outside the input domain.
- Input-to-working-space and working-to-output conversions for each supported metadata combination. Include ambiguous-input behavior for both preview and export.
- The native preview adapter, its color-space/context settings, actual interpolation result, and FFmpeg filter graph with explicit interpolation.
- LUT grid choice and sample/channel ordering, separate mathematical/approximation/renderer error measurements, and frozen tolerances with rationale.
- An actual AVFoundation-rendered paused frame after a correction update, plus orientation and nonzero-origin checks; pure Core Image output alone does not complete this check.
- An executable list of test commands and fixture seeds, environment versions, results, known unsupported cases, and the exact contract version downstream workers must implement.

**Stop condition:** no dependable parity path, unresolved black-level differences, or unexplained orientation/range mismatch. Resolve these before building sliders or fitting models.

### Milestone 1 — Manual correction through export and playback

**Packet C01: values and serialization** — depends on C00.

- Own new core color value files and the agreed small changes to `Sources/CropTrimmerCore/Models.swift`.
- Add source color metadata and per-loop correction settings with compatibility defaults.
- Decode older settings using explicit defaults where fields are absent; synthesized `Codable` with a property default is not sufficient evidence of compatibility.
- Validate numbers, LUT dimensions, table lengths, bounds, domains, and schema versions at load boundaries.
- Keep payloads immutable; equality must represent effective content, not a mutable library object ID.
- Tests: defaults, older JSON, new round trip, malformed/nonfinite input, incompatible schema, loop-copy independence.

**Packet C02: compiler and LUT adapters** — depends on C00/C01.

- Own new compiler, cube parser/writer, and Core Image table-adapter files in core as appropriate.
- Implement the frozen mathematical transform; test gamma direction and black/white endpoints with independent expected values.
- Compile base LUT plus manual transform in the agreed order. Recognize bypass/identity without unnecessary work.
- Parser initially supports explicit 3D LUTs only. Suggested limits: file at most 32 MiB, grid from 2 through 65, exact table length, finite samples, supported domain and color space. Reject unsupported 1D/shaper formats with a useful error.
- Do not assume every model's cube format fits these limits. An adapter may convert a verified supported model format later.
- Tests: asymmetric axis order, composition order, identity, clamp policy, parser corruption, duplicate headers, truncated tables, oversized input, and parser/writer semantic round trip.

**Packet C03: engine integration and artifact lifetime** — depends on C01/C02; sole owner of `MediaEngine.swift` during this packet.

- Retain metadata from inspection; resolve a color transform during preflight.
- Treat effective correction as an encoding requirement in planning and automatic fallback. Preserve copy behavior for bypass/identity.
- Build one shared filter-graph function used by final exports and all estimate qualities. Compose color and crop filters without overwriting either.
- Make transform preparation fallible before launching FFmpeg. Never fall back to an uncorrected export after a LUT error.
- Create export/estimate-owned temporary LUT files with deterministic contents and cleanup on success, failure, and cancellation. Snapshot contents before the queue begins.
- Account for FFmpeg filtergraph escaping even though `Process.arguments` avoids shell parsing. Test spaces, Unicode, apostrophes, commas, and colons in relevant paths.
- Preserve source-identity validation, audio behavior, stream selection, timing, exclusive publication, and completed outputs on cancellation.
- Tests: color-only encode in all requested methods, bypass copy, crop+color, automatic fallback, all estimate qualities, immutable queued settings, bad-LUT failure before publication, cleanup/cancel, metadata and decoded pixel checks.

**Packet C04: playback renderer** — depends on C00/C02; own a new playback-color renderer file, not `EditorModel.swift`.

- Build a reusable AVFoundation/Core Image adapter accepting immutable resolved settings.
- Keep Core Image resources reusable; do not compile tables on the main thread or rebuild resources per video frame.
- Do not read mutable `@MainActor` model state inside asynchronous frame callbacks.
- Preserve native timeline origin, full upright frame dimensions, and existing viewer crop handling.
- Expose explicit update, clear, and cancellation/invalidation behavior to the editor.
- Tests: actual rendered frame comparison, orientation 0/90/180/270, nonzero timeline origin, identity, and error propagation.

**Packet C05: editor lifecycle** — depends on C03/C04; sole owner of `EditorModel.swift`.

- Attach the renderer on source load, selected-loop changes, color edits, reset/bypass, and reload following source rename.
- Tag asynchronous work with source ID, loop ID, and settings revision. Reject stale completions, including those arriving after source replacement or selection change.
- Debounce expensive compilation separately from planning. Verify a paused viewer shows the latest correction without the user pressing Play.
- Preserve time, play/pause state, playback boundaries, crop adjustment state, and independent inactive-loop edits.
- Invalidate only the affected loop's estimates on color changes. Keep the existing quality-selection behavior. Do not start automatic estimates on slider movement.
- Freeze settings and transform contents for queue jobs before publication begins.
- Tests: rapid edits, edit inactive loop, switch during compilation, load another source, rename source, paused update, bypass/reset, queue snapshots, and cancellation.

**Packet C06: minimal controls and integration QA** — depends on C05.

- Own new `ColorControlsView.swift`, `QueueLoopCard.swift`, and minimal `EditorView.swift` wiring.
- Add four controls, enable/bypass and reset within each loop's controls. Give controls accessible names including the loop where needed.
- Separate crop controls from encoding/quality controls. Color-only loops must expose quality and display the actual method.
- Use the existing per-loop error presentation. Do not add histograms, new status badges, extra metrics, or unrelated inspector redesign.
- Retain source filenames unless the existing operation suffix becomes misleading. If adding a color suffix, own `OutputPublisher.baseName` and its callers together, preserving every existing name when color is off and all exclusive-publication behavior.
- Validate keyboard control, focus, labels, Space playback shortcut behavior, and value adjustment without accidental loop selection.
- Render and show the actual app. Obtain the owner's visual approval before committing visual code, as required by the repository's standing instructions.

**Milestone acceptance:** four independent controls work across all three loops, preview/export parity passes, queue and naming regressions pass, source unchanged, approved UI, clean packaged-app smoke test. No model dependency.

### Milestone 2 — Save and reuse looks

**Packet L01: persistent look packages** — depends on milestone 1.

- Own a new `SavedLookStore` and versioned package format.
- Store explicitly saved presets under the application's Application Support directory. This is a small look library, not persistent project or media-library state.
- Save manual parameters directly. Include the base LUT when present. Never fit an image to recover settings the application already knows.
- Use atomic writes, bounded input sizes, safe filenames, schema validation, and collision-safe user naming.
- Apply a look by copying its immutable contents into the loop. Renaming/deleting a saved look must not alter an already configured loop or pending export.
- Optional thumbnails are not authoritative color data. Store provenance separately from transform contents.
- Tests: save/load identical behavior, restart persistence, corrupt/unsupported packages, interrupted writes, name collision, and deletion after application.

**Packet L02: save/apply/import UI** — depends on L01; owns the affected UI while C06 is complete.

- Add only the save, choose/apply, and supported LUT import actions needed for the library.
- Apply to the explicitly targeted loop. Imported LUTs remain a base transform with manual controls above it.
- Explain unsupported file errors through existing error presentation.
- Test three-loop independence and imported transform preview/export parity. Obtain rendered visual approval before commit.

**Milestone acceptance:** the user can correct one frame by eye, save that look, reopen the app, and apply the same look without fitting or a model.

### Milestone 3 — Fit a matching before/after frame pair

**Packet F01: frame extraction and pairing contract** — depends on milestones 0–2.

- Own frame sampling and reference-package types.
- Extract a frame at an exact application timeline position, normalized to the agreed image space and upright orientation. Record source identity, timestamp, dimensions, color interpretation, and extraction-contract version.
- For the initial workflow, export a full upright frame for external correction and require an unchanged-size, unchanged-geometry corrected image. Crop handling must be explicit; do not accidentally compare full-frame and cropped pixels.
- Verify correspondence. Dimension equality alone cannot detect warps, substituted images, or generated faces. Reject or flag pairs with registration/structural residuals inconsistent with pure global color changes.
- Preserve original/target frame data only within the explicit reference workflow or private temporary job storage. Do not commit personal media as tests.
- Tests: nonzero origin, rotated sources, metadata conversion, dimension mismatch, transformed geometry, stale source identity, cancellation and cleanup.

**Packet F02: regularized fitter** — depends on F01; initially no generated imagery.

- Fit an identity-regularized, smooth 3D mapping from corresponding normalized pixel samples.
- Suggested first implementation: trilinear lattice fitting with a modest fitting grid, stratified color samples, squared data residual, identity penalty, and neighboring-node smoothness penalty. Freeze constants and solver limits in a reproducible configuration.
- Each source sample contributes to at most eight lattice nodes. Use sparse or matrix-free operations; do not allocate a dense square matrix over all LUT nodes.
- Keep training and held-out pixels distinct. Reserve other timestamps for temporal/scene validation, which cannot be replaced by testing more pixels from the fitting frame.
- Constrain or validate output gamut and finite values. Penalizing roughness does not prove a transform is safe everywhere; test unseen colors and ramps for spikes and banding.
- Return diagnostics and an explicit poor-fit result. No silent identity fallback presented as success.
- Measure runtime, peak memory, sample counts, convergence, and error. Set cancellation checkpoints inside the solver.
- Tests: recover known synthetic global transforms; handle noise/compression; reject unrelated images; detect local-only changes; remain stable in sparsely sampled colors; validate on other frames; cancellation and bounded memory.

**Packet F03: candidate review and apply** — depends on F02.

- Present the candidate on the actual source video with compare/bypass; the internal target image need not appear by default.
- Apply only after the user chooses the candidate. Retain manual adjustment after application and allow saving the result as a look.
- If fit quality is insufficient, offer no claim of equivalent reproduction. Preserve the current loop's prior correction on failure/cancel.

**Milestone acceptance:** recover a known grade from a synthetic pair and a real externally corrected matching frame; no structural video modification; acceptable held-out and multi-frame behavior. Unrelated photographs remain unsupported by this fitter.

### Milestone 4 — Benchmark model options

**Packet A01: comparison harness and evidence report** — may be researched earlier, but cannot choose the product integration before rendering/fitting gates pass.

Evaluate three distinct routes:

| Route | What it provides | Main uncertainty |
|---|---|---|
| Image Adaptive 3D LUT | Lightweight automatic enhancement baseline | It is not inherently conditioned on an unrelated user reference. |
| VideoColorGrading, ICCV 2025 | Reference-based video grading using LUTs | Actual checkpoint requirements, video input assumptions, GPU memory, and latency. |
| Hosted image editor followed by F02 | Desired corrected image of the sampled source frame | Structure preservation, repeatability, fitting residuals, latency, and price. |

Read the exact checkpoints' licenses and dependency requirements. Repository code license alone does not establish weight, training-data, or hosted-service permissions.

Primary sources: [Image Adaptive 3D LUT](https://github.com/HuiZeng/Image-Adaptive-3DLUT), [reference-based VideoColorGrading](https://github.com/seunghyuns98/VideoColorGrading). The latter's demo accepts reference and video inputs; do not assume it already implements the application's sampled-frame request contract.

Record on the actual LAN PC: GPU model and VRAM, driver/runtime, checkpoint digest, dependencies, cold/warm latency, peak GPU and host memory, output transform size, success/failure cases, and end-to-end time including extraction and fit. No inference speed or memory promises before this run.

Use a small consented local evaluation set covering daylight, warm indoor light, mixed lighting, dark footage, faces/skin, saturated objects, and clips with changing exposure. Keep it separate from saved artistic looks. Include identity/no-correction and manual-grade baselines.

Evaluate visual preference with blinded comparisons where practical, skin appearance, clipping, retained scene contrast, frame-to-frame stability, and how often the user must fix the suggestion. A low pixel difference from a generated image is not by itself a good color grade.

**Decision gate:** choose a route only if it improves on manual/saved-look baselines often enough to justify measured waiting time and operational burden. A model that fails this gate is a valid research result; manual correction still ships independently.

### Milestone 5 — Integrate the chosen provider

**Packet A02: provider boundary and optional LAN service** — depends on A01 winner.

- Freeze a versioned request/response format independent of a particular model. Modes distinguish automatic enhancement, matching-pair target generation, and unrelated-reference matching.
- Sample multiple representative timestamps for validation, even if only one drives inference. Reject stale responses using request/source/loop/revision identity.
- For a direct LUT model, parse and validate the LUT through the existing adapter. For a target-image model, run correspondence checks and F02. Both paths produce the same candidate type.
- Keep generated target frames out of the normal media library. Store privately for the job and clean up by policy; retain only an explicit saved reference or diagnostic artifact the user chooses to keep.
- Provide cancellation, timeout, clear model-unavailable errors, bounded uploads and outputs, and deterministic cache invalidation. No automatic uncorrected export after provider failure.
- For LAN hosting, bind only to the intended trusted interface, authenticate requests, bound concurrency, and keep credentials in 1Password-backed configuration. Confirm the host endpoint before deploying; do not expose a public listener by default.
- Tests: unavailable service, timeout, cancellation, invalid response, oversized response, malformed LUT, changed model version, stale response after loop switch/source change, and successful application/export.

**Milestone acceptance:** one end-to-end suggestion works on the actual target machine, can be previewed/applied/saved, and all failure paths preserve existing settings and original files.

## 7. Verification and release gates

### Numerical correctness

Separate three errors: mathematical implementation, finite-LUT approximation, and preview/export color conversion. Lossy video encoding adds a fourth. Do not let one generous tolerance hide all four.

- Scalar math and independently computed expected samples: tight floating-point tolerances.
- LUT approximation: compare analytic/manual mapping against LUT evaluation across dense samples, especially shadows and endpoints.
- Cross-renderer parity before encoding: initial target mean absolute error at most `1/255`, 99th percentile at most `2/255`, excluding only explicitly documented resampling boundaries. Milestone 0 measures feasibility and freezes the actual gate before implementation. Do not relax it after a failure without explaining the mechanism.
- Production H.264: use patch interiors and a matched identity encode baseline. Report incremental transform error separately from chroma-subsampling and compression error. Do not apply a universal “within two levels” claim to every decoded pixel.
- Include actual AVFoundation-rendered output. Testing a CPU implementation twice does not prove the on-screen player agrees with export.

### Required regression matrix

| Dimension | Required cases |
|---|---|
| Transform | Disabled, enabled identity, four individual controls, combined controls, base LUT plus manual, malformed LUT |
| Input | Tagged 709 limited/full, untagged/ambiguous, supported 601 after its gate, HDR restriction, odd dimensions, attached cover art |
| Geometry/time | All right-angle rotations, crop on/off, nonzero origin, variable frame rate, short and sparse-keyframe clips |
| Editor | Three independent loops, inactive edits, rapid changes, selection changes, paused update, source replacement and rename |
| Export | Automatic/Fast/Accurate, color-only, crop+color, all estimate qualities, queue snapshots, failure/cancel, audio handling |
| Storage | Same-name collision, no overwrite, temporary cleanup, corrupt look, preset deleted after application |
| Fitting/model | Valid pair, unrelated images, geometric changes, sparse colors, held-out frames, timeout, stale response, bad payload |

Synthetic fixtures should be reproducible and redistributable. Keep personal footage local. Native/FFmpeg-dependent mandatory tests must run in the release environment; a skipped test is not a passed gate.

### Responsiveness and packaging

Provisional interaction target: 95th-percentile slider-to-visible-preview update within 100 ms after any deliberately specified debounce, measured on the user's Mac at 1080p. Record debounce separately so it cannot conceal latency. No main-thread compilation stalls. Fit/model operations show cancellable progress and do not freeze transport.

Run `swift test` for each relevant integration milestone. Before releasing manual correction, run the packaging script and launch the packaged app with its bundled FFmpeg. Verify helpers and filter availability there, including paths with spaces. Do not substitute the developer's Homebrew binary for the packaged binary in this check.

Run the existing transport, rotation, source rename, timing, audio, cancellation, independent queue, and exclusive-publication tests. Extend these behaviors rather than replacing them with narrower color-only checks.

## 8. Instructions for the coordinating agent

1. Recheck the working tree, current branch, open PR, and session sweep before implementation. The findings above describe the reviewed commit, not future state.
2. Use the existing folder as the project requires. Do not create a worktree without permission. Resolve ownership conflicts before editing shared files.
3. Give each worker one packet, frozen interfaces, exact owned files, its dependency versions, applicable fixtures, and an explicit done definition. Tell it other agents may be present and not to revert their work.
4. Keep `MediaEngine.swift`, `EditorModel.swift`, `Models.swift`, and `QueueLoopCard.swift` under one writer each. Sequence handoffs when ownership changes.
5. Require workers to report changed files, tests and outcomes, remaining uncertainty, and interface deviations. A successful build is not completion of a behavior packet.
6. Do not let workers broaden metadata support, change the LUT working space, add UI, choose model licenses, or weaken pixel tolerances independently. Those decisions return to the lead.
7. Show and approve rendered visual changes before commit. Follow the repository's PR process: one active PR, three completed review rounds, findings fixed or explicitly resolved, scorecard, then merge. Apply relevant Swift/code reviews during implementation.
8. Land each milestone before starting the next milestone's integration. A bounded research failure should be documented; it must not leave the working manual correction dependent on an unfinished model.

### Reusable worker assignment

> Implement packet [ID] against the frozen color contract at [path/version]. You own [exact files]. Other agents may be working in this repository; do not revert or edit their owned files. Dependencies [IDs] are complete at [commit]. Required behavior is [packet requirements]. Run [specific tests] and report actual outcomes, including skips. Do not change the rendering domain, source interpretation policy, or acceptance tolerances. Report an interface conflict before inventing an alternative. Return changed files, test evidence, remaining risks, and any requested lead decision. Do not claim the milestone complete merely because compilation succeeds.

## 9. Suggested first implementation slice

Approve and execute C00 first, then C01–C06 as the first user-facing release. The most valuable early deliverable is a clip whose black point, white point, gamma, and saturation can be adjusted independently per loop, with the same appearance in playback and export.

Follow with saved looks. Only after those work should same-frame fitting and model suggestions become product dependencies. This sequence directly serves the original request, produces usable results early, and concentrates the hardest uncertainty in explicit experiments rather than leaving it for smaller agents to discover during integration.
