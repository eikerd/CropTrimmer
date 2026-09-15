---
date: 2026-09-15 03:04 America/Chicago
tool: codex
model: GPT-6 (Astra)
repo: eikerd/CropTrimmer
branch: codex/color-provider-ui
pr: https://github.com/eikerd/CropTrimmer/pull/6
state: merged
deployed: no
loose_ends: none
supersedes: 2026-09-14-2148-codex-color-correction-implementation.md
---

# Reference color provider handoff

## What changed

The editor can now call an optional reference-conditioned color service. The
user enters an endpoint, chooses an unrelated reference image, and the app
sends a bounded upright PNG of the sampled source frame plus the reference
image. A validated LUT response is applied through the existing candidate,
preview, export, and saved-look flow. Requests are cancellable and stale
responses are ignored when the source, loop, or settings change.

The provider contract is version-neutral and accepts HTTPS endpoints. Cleartext
HTTP is limited to localhost development addresses. Source and reference image
payloads are bounded to 16 MiB each, and streamed provider responses are
bounded to 32 MiB. No model weights or network listener are bundled; the
endpoint remains an operator-configured service on a trusted host.

## Validation

- `swift build` passed.
- `swift test` passed: 50 tests, 0 failures.
- `scripts/build-app.sh` passed and produced `build/Crop Trimmer.app`.
- Packaged binary contains the new provider endpoint and reference-match UI
  strings. The endpoint controls are below the saved-look actions in the
  inspector scroll area.

## Next agent: start here

1. Read the color-correction plan and the merged implementation handoff before
   changing the rendering contract.
2. Benchmark a consented model service on the target PC before promising a
   particular checkpoint, latency, or GPU memory footprint.
3. Keep provider responses candidate-based and validated; never silently export
   an uncorrected result after provider failure.

## Decided by the owner

- “Continue until all the features are built out.”
- The model path should remain optional and should not make manual correction
  or matching-frame fitting depend on a remote service.

## Proposed rule changes

None.
