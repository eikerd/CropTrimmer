---
date: 2026-09-14 21:48 America/Chicago
tool: codex
model: GPT-6 (Astra)
repo: eikerd/CropTrimmer
branch: codex/color-correction-core
pr: https://github.com/eikerd/CropTrimmer/pull/4
state: merged
deployed: no
loose_ends: none
supersedes: 2026-09-14-2006-codex-color-correction.md
---

# Color correction implementation handoff

## What changed

The manual color workflow is implemented per loop: enable/bypass, black point,
white point, gamma, saturation, reset, paused playback refresh, queue snapshot,
and encoded export. A shared validated 3D LUT is used by estimates and export;
color-only edits force re-encoding while bypassed edits retain fast-copy behavior.

Saved looks persist atomically in Application Support and can be applied or
deleted independently. Supported unit-domain 3D `.cube` files can be imported.
LUT payloads are validated on construction and decoding, including finite,
in-gamut samples and exact table size.

The suggestion path has two local options. Core Image auto-adjusts a sampled
representative frame and the fitter converts the before/after pixels into a
global LUT. A matching corrected frame can be selected and fitted the same way;
aspect mismatch is rejected. The core also exposes a version-neutral HTTP
provider for a future LAN/API model. Unrelated reference images remain
unsupported by the fitter because they do not provide corresponding pixels.

Inspection now retains pixel format, primaries, transfer, matrix, and range tags
so a later color-space gate can distinguish known SDR metadata from ambiguity.

## Validation

- `swift build` passed.
- `swift test` passed: 47 tests, 0 failures.
- `scripts/build-app.sh` passed and produced `build/Crop Trimmer.app` with the
  bundled FFmpeg/FFprobe helpers.
- Packaged-app smoke test loaded `tmp/UI Sample - trim crop.mp4`, expanded the
  color controls, and ran the automatic frame suggestion. The first attempt
  found an Objective-C Core Image exception caused by an invalid Boolean value
  for the `features` option; that option was removed, and the second run
  applied the correction successfully without quitting.
- Three review passes were completed: core math/serialization/export review,
  lifecycle/cancellation review, and packaged-app/provider-payload review.
  CodeRabbit reported no correctness findings; its docstring-coverage warning
  is a non-blocking style signal. Copilot and Greptile were unavailable because
  of account limits. ECC security and taxonomy gates passed.

## Next agent: start here

1. Read `docs/plans/color-correction.md` and this note. The implementation is
   merged in PR #4; nothing is deployed by this task.
2. The next work is the C00 parity gate: measure Core Image playback versus
   FFmpeg export in an explicit working color space, including tagged and
   ambiguous metadata, orientation, interpolation, and decoded output.
3. Do not claim an RTX 5060 Ti model integration yet. Benchmark candidate model
   checkpoints and licenses on the target PC before wiring the HTTP provider to
   a service. Keep automatic correction global and candidate-based until
   held-out and multi-frame validation exists.
4. Preserve the existing source-identity, exclusive-publication, timing,
   rotation, audio, cancellation, and independent-loop behavior.

## Decided by the owner

- “Continue until all the features are built out.”
- Earlier requested controls are black/white levels, gamma, and basic
  saturation. Temperature/tint and unrelated-reference model matching remain
  separate future decisions.

## Proposed rule changes

None. The referenced `docs/CODEX-NAVIGATION-GUIDE.md` is absent in this repo.
