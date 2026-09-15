# Live color preview regression

The reported failure was an unchanged preview despite enabled levels, gamma,
and saturation controls. The cube filter had no input image, so its nil output
triggered the original-frame fallback.

- RED: commit `adec03b`, `swift test --filter ColorPlaybackRendererTests`, failed
  to compile because the renderer had no testable `filteredImage` entry point.
- GREEN: commit `4979cb7` supplies `kCIInputImageKey` in the shared production
  and test path. The test renders a gray pixel through a gamma LUT, verifies
  lifted brightness and neutral channels, and rejects nil output.
- Regression run: `swift test`, 54 tests passed, zero failures.
- Packaging: `scripts/build-app.sh` passed, including signature verification.
- Manual: saturation zero produced grayscale in the live video while source
  thumbnails remained colored. The owner confirmed it worked.

Coverage percentage was not measured. The test exercises the Core Image pixel
pipeline; live AVPlayer attachment was checked in the packaged app.

## Review rounds for PR 9

These are three local Codex passes, not independent bot reviews.

1. Correctness: inspected frame input, cube dimensions/data, per-frame filter
   ownership, and reuse of the compiled cube. No additional defects found.
2. Security: inspected environment-only credentials, OpenRouter host restriction
   for its named key, inherited endpoint/range/payload validation, error handling,
   and stale-result checks. No additional defects found. No live paid API request
   was made, and no secret was read or committed.
3. Integration/accessibility: inspected tab routing and unavailable-action
   guards, exercised Auto/Reference/Looks navigation and the settings popover,
   confirmed accessible control names, and reviewed the final packaged render.
   The owner approved the layout: “Yes, much better.”

## Independent review follow-up

CodeRabbit found that a blank primary credential suppressed the OpenRouter
fallback. Commit `a9aea39` normalizes both values before choosing a credential.
Two tests cover blank/whitespace values, precedence, missing credentials, and
the OpenRouter host restriction. The full suite now passes 56 tests.
This was a small functional bug missed by the initial local passes.

Round two requested composition-level regression coverage. A generated one-frame
gray movie now goes through `AVAssetImageGenerator.videoComposition`, comparing
corrected brightness with the decoded original and checking neutral channels.
Both renderer tests pass. This closes the automated attachment gap; no artificial
filter-failure seam was added just to exercise the fallback.
