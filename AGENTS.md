# Crop Trimmer

Build with `swift build`; run tests with `swift test`; package locally with `scripts/build-app.sh`. The executable product is `build/Crop Trimmer.app`. Open `Package.swift` in Xcode.

The MVP uses drag/drop or Open, edits one active movie, and exports a uniquely named new file in the source directory. No media library or persisted edit state. Keep original file contents and all existing exports intact. Explicit source renaming is supported via SourceRenamer: preserve extension/directory, never overwrite another file, and reload using the new path. Never bypass exclusive publication. Crop uses upright source pixels and requires encoding; playback monitoring audio never affects exported audio.

Read README.md for current support limits and source ownership. The product specification and implementation guide describe later library/persistence features that are outside the current MVP.

Use the existing folder. Do not create a separate checkout, worktree, or project folder without permission. If Git is initialized, follow one active feature branch and one open PR.

- tmp/docs/2026-09-13-mvp-build-handoff.md — implementation findings, validation, and remaining release limits.

- tmp/docs/2026-09-13-three-loop-update.md — independent loops, drag/scrub separation, and verification.

- tmp/docs/2026-09-13-loop-queue-transport.md — per-loop settings, sequential queue exports, and transport verification.

- tmp/docs/2026-09-13-source-rename.md — explicit in-place source rename, reload, and verification.

- tmp/docs/2026-09-13-crop-aspect-lock.md — crop preset locking, geometry and verification.

- tmp/docs/2026-09-13-independent-queue-cards.md — independent controls, drafts, estimates and exports per card.
