---
date: 2026-09-15 10:38 America/Chicago
tool: codex
model: GPT-5
repo: eikerd/CropTrimmer
branch: codex/openrouter-settings
pr: https://github.com/eikerd/CropTrimmer/pull/10
state: pr-open
deployed: no
loose_ends: OpenRouter live naming remains unverified because the saved test key returned HTTP 401; replace the key in Settings before testing again. The PR needs the normal review rounds.
supersedes: docs/handoffs/2026-09-15-0848-codex-color-preview-controls.md
---

# Crop Trimmer handoff

## What changed

Added a native Settings window for OpenRouter configuration, with a masked API-key field stored in the macOS Keychain. The endpoint and model preferences remain in UserDefaults; the saved key is only used for the exact `openrouter.ai` host, with environment fallback for other configured providers.

Added offline random filename suggestions and an optional OpenRouter vision suggestion. The AI path samples one upright 512px frame, sends only that PNG, validates a strict JSON filename proposal, and fills the rename draft without renaming automatically. Cancellation, source changes, and manual edits prevent stale results from replacing the draft.

Replaced model text fields in Settings with image-capable dropdowns for Gemini 2.5 Flash Lite, GPT-4.1 Mini, and Claude Haiku 4.5. Existing custom provider endpoint configuration remains available under the disclosure. HTTP errors now explain key rejection, billing, permissions, missing model, rate limiting, and unsupported image requests separately.

Documentation is in `docs/color-provider.md` and `docs/filename-suggestions.md`.

## Verification

- `swift test`: 64 tests passed.
- `swift test --filter FilenameSuggestionTests`: 6 tests passed.
- `scripts/build-app.sh`: packaged app successfully.
- `git diff --check`: passed.
- Manual UI verification: Settings opens with both model dropdowns; each lists all three vision choices. The synthetic `tmp/UI Sample.mp4` naming request reached OpenRouter and returned HTTP 401; no private movie was uploaded and the source was not renamed.

## Next agent

First read the PR diff and rerun the packaged app. If the owner replaces the OpenRouter key, test AI naming with `tmp/UI Sample.mp4`; a successful response should only update the draft until Rename is clicked. Keep the model dropdowns independent for color and naming. Do not print or copy the Keychain value.

## Owner decisions

- Owner asked for several selectable models because they do not know which providers or contracts are available.
- Owner approved the rendered Settings layout before asking to check the work in.
- Owner wants the next agent to continue from a tracked branch and handoff.

## Proposed rule changes

None.
