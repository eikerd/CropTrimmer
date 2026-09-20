# Color model providers

Crop Trimmer keeps manual levels, gamma, saturation, saved looks, and the
Core Image automatic suggestion fully local. The optional `OpenAICompatibleColorSuggestionProvider`
is a separate boundary for a reference-conditioned vision model.

## What the adapter does

The app sends a representative upright PNG frame and a user-selected reference
image as two base64 data URLs in an OpenAI-style `chat/completions` request. The
model is asked for a compact JSON proposal containing `blackPoint`, `whitePoint`,
`gamma`, and `saturation`. Crop Trimmer validates the ranges and compiles the
proposal into its own 33³ sRGB LUT. The model never writes pixels or media files,
and a failed or unsafe response is rejected before it can affect an export.

This deliberately asks for parameters instead of a giant LUT. Vision-language
models are good at judging the direction of a correction, but token-generated
3D tables are too large and too easy to corrupt. The deterministic local LUT
compiler remains the source of truth.

## OpenRouter

In the inspector, open **Color → Reference**, choose **Another image · AI
model**, and use the gear to open Settings and choose a model from the dropdown. Then choose a
reference image. A blank endpoint opens settings. A blank model name selects
the custom LUT-service protocol; a nonblank name selects the OpenAI-compatible
adapter. Auto correction and saved looks have their own tabs.

Open **Crop Trimmer → Settings…** (Command-comma) and paste the OpenRouter key
into the masked field, then click **Save key**. It is stored as a plain app
preference in `~/Library/Preferences/com.croptrimmer.mac.plist`, so anything
running as you can read it — treat the key as rotatable, not secret. The
Keychain was dropped deliberately: the app is signed ad-hoc, so its identity
changes on every build and macOS re-prompted for the login password each
session. Settings reopens with the saved key in the field; paste a replacement
and save again to rotate it. Blank input cannot overwrite a saved key. Saving a key fills the OpenRouter
endpoint when no endpoint has been configured; choose a vision model too.
The dropdown offers Gemini 2.5 Flash Lite, GPT-4.1 Mini, and Claude Haiku 4.5.
Custom provider endpoints remain available in the disclosure below the picker.

The stored key takes precedence for `openrouter.ai` only. If no stored key
exists, the app falls back to `CROPTRIMMER_COLOR_PROVIDER_API_KEY`, then
`OPENROUTER_API_KEY` for OpenRouter. Other endpoints can use the general
environment key but never receive the stored OpenRouter key. Only endpoint
and model name are saved in preferences. No key is fetched from 1Password
automatically; it can be pasted from the user's existing 1Password record.

OpenRouter exposes an OpenAI-compatible endpoint at:

```
https://openrouter.ai/api/v1/chat/completions
```

Use a vision-capable model, pass its name as the adapter configuration's
`model`, and save the bearer token through Settings or provide it from the
launch environment. Do not save the token in UserDefaults, a look, or
the repository. OpenRouter's image input format is the same `messages[].content`
array used by this adapter.

## Local M1 fallback

For an offline path, run an OpenAI-compatible local server on the Mac and point
the same adapter at its loopback endpoint. `llama-server` from llama.cpp is the
most straightforward first target because it exposes `/v1/chat/completions` and
can offload the vision projector to Apple Silicon GPU/Metal. MLX-based servers
are another good option for Apple Silicon. Start with a small quantized vision
checkpoint (roughly 3B–4B on an M1; 7B only when the Mac has enough unified
memory) and benchmark on representative frames before choosing a default.

The local server is allowed over HTTP only on loopback (`localhost`,
`127.0.0.1`, or `::1`). Any LAN or hosted endpoint must use HTTPS.

## Fallback order

1. Manual controls and saved looks (always available).
2. Core Image automatic enhancement (offline, already integrated).
3. A local OpenAI-compatible vision server (no image leaves the Mac).
4. OpenRouter or another HTTPS provider (convenient, but sends the selected
   images to that service and requires its API key).

The model result is a suggestion. The user can inspect the preview and undo it;
exports still go through the normal validation and exclusive-publication path.
