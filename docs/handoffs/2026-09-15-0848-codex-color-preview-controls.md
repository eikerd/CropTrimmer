---
date: 2026-09-15 08:48 America/Chicago
tool: codex
model: GPT-6 Astra
repo: eikerd/CropTrimmer
branch: codex/openai-compatible-color-provider-ui
pr: https://github.com/eikerd/CropTrimmer/pull/9
state: pr-open
deployed: no
loose_ends: PR review and merge pending; live provider verification pending
supersedes: docs/handoffs/2026-09-14-2220-codex-openai-color-provider.md
---

# Working color preview and simplified controls

## What changed, and why

The Core Image cube filter now receives the source frame. Previously its output
was nil and the preview silently displayed the original image. The inspector
now separates Auto, Reference, and Looks into tabs, keeps action labels stable,
and places endpoint/model configuration in a gear popover. Nonblank model names
use the existing OpenAI-compatible adapter; blank names retain the custom LUT
service protocol. API keys are read only from the process environment.

## Where it is

- Commits: `adec03b` regression reproducer; `4979cb7` preview fix; `26a8405`
  approved inspector/model wiring; `83caf18` test and operator documentation.
- Files: `ColorPlaybackRenderer.swift`, `EditorView.swift`, `EditorModel.swift`,
  `docs/color-provider.md`, `docs/testing/color-preview.tdd.md`.
- Verified: 54 tests passed; packaged release built and signature verified;
  grayscale preview, three tabs, and settings popover exercised in the app.
- Three local Codex review passes are recorded in the test evidence. These are
  not independent agent reviews. External results are recorded in the scorecard.

## What is deployed

No remote deployment. The local build at `build/Crop Trimmer.app` contains the
approved code. No release distribution was created.

## Loose ends

- Live OpenRouter authentication and model quality have not been exercised.
  The app does not yet fetch the key from 1Password automatically. Provide it
  through a 1Password-rendered launch environment; never put it in preferences.
- Navigation guide referenced by the supplied instructions is absent.
- The task uses the existing checkout as required by the project instructions.

## Next agent: start here

1. Read `docs/color-provider.md` for the current UI and launch environment.
2. Verify a vision-capable provider on consented sample images, including a
   failure response; report quality and timing without exposing the key.
3. Preserve the shared LUT path for preview and export. The new regression
   test covers filter input; AVPlayer attachment still needs a UI smoke check.

## Decided by the owner

- “ok thats working” — accepted the preview fix.
- “i hate this UI ... lets improve this” — requested the controls redesign.
- “Yes, much better.” — approved the final rendered tab layout.
- “Continue until the code's merged, babysit the PR.” — authorized landing.

## Proposed rule changes

None.
