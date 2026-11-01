# Indian acceptance set

Real Indian audio that every Phase 2+ stage must pass on (rhythm cycles, minor keys, drones,
half-bar chord changes, dense accompaniment). Synthetic results are not acceptance.

- `manifest.json` lists every clip; `clip.example.json` shows one complete entry.
- Validate: `python3 Native/tools/dataset/validate_indian_set.py docs/benchmark/indian-set/manifest.json`
  (also run in every iPhone build).
- **Audio is not stored in the repo.** Each clip records where it is kept and its SHA-256.
- **Allowed sources:** the owner's own recordings (Casio CT-X870IN performances, Tamil/Telugu/Hindi
  film-style accompaniment), and recordings with a written licence. No ripped/pirated MP3s, nothing
  downloaded from YouTube or piracy sites.
- **Licence per clip.** Only `Cleared` clips may be used for training; others are evaluation only.
- **Train/test separation.** A clip is `train` or `test`; the same audio or the same source recording
  (`source_group`) may never be in both. Acceptance numbers are reported on `test` only.
- **Annotations:** cycle (name, beats, confident/ambiguous/unknown), tempo, beats, downbeats,
  chords (with confident/ambiguous state; drones are labelled as drones, not forced to a triad),
  accompaniment type and pattern, sections, plus the annotator.
- **Milestone:** 20 annotated clips is the minimum start, not proof. Phase 2 rhythm acceptance
  waits for a representative set (agreed with the owner).

Status (Phase 1): infrastructure ready; **0 clips** — needs the owner's recordings.
