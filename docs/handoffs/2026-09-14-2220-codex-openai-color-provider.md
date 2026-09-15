---
date: 2026-09-14 22:20 America/Chicago
tool: codex
model: gpt-6-astra
repo: eikerd/CropTrimmer
branch: codex/openai-compatible-color-provider
pr: https://github.com/eikerd/CropTrimmer/pull/8
state: merged
deployed: no
loose_ends: none
supersedes: docs/handoffs/2026-09-15-0304-codex-color-provider-ui.md
---

# Add an M1 and OpenRouter color-model fallback

## What changed, and why

Added an OpenAI-compatible vision provider boundary that can target OpenRouter
or a local loopback server such as llama-server. It sends a source frame and
reference image as data URLs, asks for four bounded global adjustments, rejects
unsafe responses, and compiles accepted values through the existing local LUT
pipeline. Added tests and documentation covering endpoint validation, response
parsing, size limits, fallback order, and secret handling.

## Where it is

- Commits: `d883073` adapter and docs; `cec76e3` contract wording review; `28ca7c3` handoff
- Files that matter: `Sources/CropTrimmerCore/ColorSuggestion.swift`,
  `Tests/CropTrimmerCoreTests/ColorSuggestionTests.swift`,
  `docs/color-provider.md`, `README.md`
- Verified by: three review rounds (correctness, security, integration),
  `swift test` (53 tests, 0 failures), `swift build`, and `git diff --check`

## What is deployed

Nothing.

## Loose ends

None from the repository sweep. The OpenAI-compatible adapter is a core library
boundary; the existing inspector still uses the generic provider endpoint. A
follow-up UI slice can add a model selector and environment/1Password launch
configuration after a rendered inspector review.

## Next agent: start here

1. Review PR #8 and run the tests. If wiring the adapter into the inspector,
   keep the API key out of UserDefaults and render the visual change before
   committing it.

## Decided by the owner

- "Ah, well, it's going to be running on an M1 Mac. So let's figure out what we
  can run as a fallback to run a model, or if there's like an API we can use,
  like OpenRouter or something." — support both local Apple Silicon and
  OpenRouter through one OpenAI-compatible provider boundary.

## Proposed rule changes

None.
