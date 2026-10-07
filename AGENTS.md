# SYNC_MusicStudio agent guidance

## Context loading

- Start with `note.md`; it describes the current stage and next work.
- Product requirements live in `aviutl2_music_performance_editor_spec.md`.
- Read the relevant sections of `DESIGN.md` and `DEVELOPMENT.md`.
- Do not recursively inspect generated build directories, Git internals, IDE history or recovery.
- `Reference/SYNC_Lyrics/` holds copied reference documentation, not current project guidance.

## Working rules

- Preserve unrelated user changes and the reference project's source.
- Keep the plugin group `SYNC`, its name `演奏スタジオ`, and its project `SYNC_MusicStudio_Filter`.
- Keep the inherited UI files during development. Copy and adapt the parts needed here.
- Near completion, audit dependencies and delete files confirmed unnecessary. This cleanup is required.
- Follow `DEVELOPMENT.md` for builds, boundaries, encoding and distribution.
- Keep `note.md` concise; put completed verification in `HISTORY.md`.
