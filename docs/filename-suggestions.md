# Filename suggestions

Click the pencil beside the source filename, then open **Suggest name**.

- **Random name** generates an offline name such as `quiet-river-a31f08c2`.
  The words are random, not a description of the movie. A random suffix reduces
  collisions; the existing exclusive rename still prevents overwriting files.
- **Describe frame with AI** sends one upright source frame, at the paused
  playhead and limited to 512 pixels per side, to OpenRouter. It fills the draft
  with a short description such as `dog-running-in-park`. It does not upload
  the whole movie or send the existing filename.

Edit the draft if needed and click **Rename**. This changes the original source
filename in its existing directory, preserving the extension, edit settings,
and existing exports. Neither suggestion method renames anything automatically.

Settings contains a separate **File naming · OpenRouter** model dropdown. The
default is `google/gemini-2.5-flash-lite`; it is independent of the color model.
The dropdown also offers OpenAI GPT-4.1 Mini and Anthropic Claude Haiku 4.5.
These are catalog choices, not a guarantee of access for a particular key.
Select another model after a model error; HTTP 401 requires replacing the key.
Naming uses the OpenRouter key saved in app preferences, with the existing
environment fallback. Requests always target OpenRouter over HTTPS and refuse redirects.
API usage may incur charges. A live check using a synthetic color-bar frame
reached OpenRouter but returned HTTP 401 (key rejected). Successful live naming
remains unverified pending a valid key; no private movie was uploaded or renamed.

Returned names are validated as JSON, reject paths and control characters, and
are reduced to at most eight lowercase ASCII words and 80 characters. The
model is asked to describe visible subjects, actions, and setting without
identifying people or inferring sensitive traits. Treat its description as a
suggestion: review it before renaming.

Cancellation, switching files, or editing the draft while a request is running
prevents a late result from replacing the user's current draft. Network,
authentication, and malformed response errors leave the filename unchanged.

Model reference: https://openrouter.ai/google/gemini-2.5-flash-lite/
