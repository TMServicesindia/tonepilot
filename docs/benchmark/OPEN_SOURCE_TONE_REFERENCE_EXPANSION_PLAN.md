# Open-Source Tone Reference Expansion: plan (research only)

**Date:** 2 November 2026. **Status: PLAN.** No production Swift/Kotlin changes, no matcher change, no model integration, no build, no large data in the repository.

**Owner decision (2 Nov):** **no manual keyboard recording** anywhere in the plan. The reference library is built automatically from open datasets and SoundFonts.

## 0. What our own measurements say first (shapes the design)

From `INSTRUMENT_PROXY_RESULTS.md`, "Tone recreation" section:
1. TonePilot's fingerprint ranks the true sound 1st in 10/12 cases **when the same sample is in the library**.
2. **Across sound sources it fails** (sealed FluidR3 TEST: lead family 3/12). Literature agrees: hand features average about 42% across databases vs > 90% within one (Livshin & Rodet 2003).
3. So **more reference data cannot fix the hand fingerprint by itself**. References are useful in two different roles, kept apart:

| Role | What it needs | Sources |
|---|---|---|
| **A. Playable candidates:** tones TonePilot can recommend and play | Must be renderable by TonePilot's own engine (SF2 or multisample) **and** licensed for redistribution in the app | GeneralUser GS (shipping), FluidR3 GM (MIT), MuseScore General (MIT), VSCO 2 CE / VCSL / Meta Open Sound (CC0) |
| **B. Similarity training and evaluation:** learn "same instrument across different sources = near" | Many sources of the *same* instrument, with labels; training rights | NSynth (CC BY 4.0), TinySOL (CC BY 4.0), Slakh2100 (CC BY 4.0), multi-bank renders (FluidR3, GeneralUser, MuseScore General, VSCO/VCSL) |

## 1. Verified source and licence matrix (accessed 2 Nov 2026)

| Source | Version / location | Licence (verified) | Commercial use | Training | Redistribution | Content | Size (approx.) | Status |
|---|---|---|---|---|---|---|---|---|
| FluidR3 GM | Debian/Ubuntu `fluid-soundfont-gm` (copyright file: MIT) | MIT | Yes | Yes | Yes (keep notice) | GM SF2, 128 programs + kits | 148 MB | **APPROVED.** ⚠ Currently the **sealed TEST** bank of the tone bench (§5) |
| GeneralUser GS | github.com/mrbumpy409/GeneralUser-GS | Custom permissive: "use … without restriction … in your software projects"; the author can't verify every sample's origin; **silent on ML training** (existing register) | Yes (playback) | **Unverified** | Yes | GM SF2 | 32 MB | **APPROVED WITH CONDITIONS:** candidates yes; training only after the author answers (draft email exists) |
| MuseScore General | MuseScore download; COPYING (MIT per handbook / Fedora) | MIT | Yes | Yes | Yes (notice) | GM SF2 | ≈ 200 MB (full; ESTIMATE) | **APPROVED WITH CONDITIONS:** confirm the COPYING file |
| NSynth | magenta.withgoogle.com/datasets/nsynth | CC BY 4.0 | Yes | Yes | Yes (attribution) | 305,979 isolated notes, 1,006 instruments; family, source, 10 quality labels | ≈ 30 GB (train tar ≈ 22 GB) | **APPROVED.** Already streamed as a subset in the instrument bench |
| TinySOL | Zenodo record 3685367 (v6.0; 3685331 is v5.0) | CC BY 4.0 | Yes | Yes | Yes (attribution) | 2,913 real Ircam notes, 14 orchestral instruments, official 5 folds | < 1 GB (ESTIMATE) | **APPROVED.** ⚠ Metadata row count (2,478 in one listing) to check |
| Slakh2100 | slakh.com / Zenodo 4599666 (official release) | CC BY 4.0 (existing register; mirrors may differ, so use the official release) | Yes | Yes | Yes (attribution) | 2,100 multitracks, 187 patches / 34 classes, stems + MIDI | ≈ 100 GB full (FLAC; ESTIMATE) | **APPROVED.** Subset only |
| Meta Open Sound | github.com/facebookincubator/Meta-open-sound | Instruments **CC0** (LICENSE + README, read 2 Nov); Oculus Audio Pack CC BY 4.0 | Yes | Yes | Yes | Upright piano (88 keys, 4 velocities), nylon guitar, steel guitar; SFZ maps | Small (ESTIMATE) | **APPROVED** |
| VSCO 2 CE / VCSL | github.com/sgossner (LICENSE: CC0) | CC0 | Yes | Yes | Yes | Real strings, winds, brass, harp, pianos, mallets, world percussion | Several GB raw (ESTIMATE) | **APPROVED** (see `research/TONEPILOT_TONE_LIBRARY_SOURCES.md`) |
| Iowa MIS | theremin.music.uiowa.edu | Free; must not be redistributed "as samples or a sampler instrument" | Evaluation | — | **No** | Real anechoic orchestral notes | ≈ several GB | **RESEARCH ONLY:** sealed real-recording TEST |
| LAION-CLAP music | `laion/larger_clap_music` | Apache-2.0 (weights, existing register) | Yes | — | Yes | Audio–text model | 776 MB | **RESEARCH ONLY:** offline reference signal; too large for the phone |
| Microsoft CLAP | github.com/microsoft/CLAP | MS-PL (HF) / CC BY 3.0 US (Zenodo), existing register | Yes | — | — | Audio–text model | — | **RESEARCH ONLY** |
| Casio / Yamaha factory tones | — | Proprietary | — | — | — | — | — | **REJECTED** (no ROM extractions) |
| FluidSynth (renderer) | fluidsynth CLI | LGPL | CI tool only | — | Not shipped | — | — | **APPROVED** for CI rendering of external banks only (see §3) |

## 2. Recommended download strategy

- **Never in the repository.** Everything is downloaded inside CI jobs; only manifests, checksums, licence files and derived fingerprints / embeddings (small) are kept, on a research branch.
- **SoundFonts:** apt (FluidR3), GitHub raw (GeneralUser), MuseScore download (MuseScore General). Record a SHA-256 per file.
- **NSynth:** the existing single-pass stream of `nsynth-train` (no full extract); valid and test whole.
- **TinySOL:** the whole v6.0 archive (small).
- **Slakh2100:** a subset of tracks (e.g. 100 tracks' stems + MIDI) via the official release; a full download exceeds a runner's disk.
- **VSCO / VCSL / Meta Open Sound:** git sparse checkout of the needed instrument folders (CC0).

## 3. Automated rendering architecture

- **Renderer:** TonePilot's own engine (`ToneMatcher.render`), not FluidSynth, **for anything that is a candidate**, because the app plays candidates through TonePilot's engine. A candidate's fingerprint must be the sound the user will actually hear.
  - The existing `ToneTableDump` test already renders the whole library (130 tones × 3 registers in about 70 s on CI-class CPU).
  - FluidSynth is used only to render *external* reference banks that are not candidates, if their SF2 features exceed TonePilot's SF2 reader.
- **Grid per program:** 5 pitch regions (MIDI 36 / 48 / 60 / 72 / 84, clipped to the instrument's range) × 3 durations (0.25 / 0.6 / 1.5 s) × 3 velocities (50 / 90 / 120), dry.
  - That is 5,760 clips per 128-program bank.
  - **Effects variants** (reverb / chorus / delay / distortion, seeded) are a **separate** set.
  - Loudness normalised to −23 LUFS-equivalent RMS; 32 kHz mono.
- **Cost (ESTIMATE from ToneTableDump timing):** ≈ 0.15 s per clip, so ≈ 15 min per bank on one CI runner. NSynth and TinySOL are ingested, not rendered.
- **Labelling:** generated renders are labelled `source: soundfont_render`, never "recording of a keyboard".

## 4. Fingerprint / index schema (`reference_index.jsonl`, one row per clip)

```json
{"id": "fluidr3:prog41:p60:d0.6:v90:dry", "source": "fluidr3", "source_type": "soundfont_render",
 "licence": "MIT", "sha256": "...", "renderer": "tonepilot-engine@<commit>",
 "instrument_gm": 41, "family": "strings", "taxonomy_id": "violin", "playable_candidate": false,
 "pitch_midi": 60, "duration_s": 0.6, "velocity": 90, "effects": [],
 "features": {"fingerprint": "base64(24 bands + attack/sustain/tail/noise)",
              "descriptors": {"log_attack": -1.6, "centroid_over_f0": 4.1, "irregularity": 0.12, "decay_30": 0.8, "noise": 0.03},
              "embedding_efficientat": "base64(fp16[960])"},
 "split": "train"}
```

Candidate rows (`playable_candidate: true`) also carry the TonePilot `patchId`. The app needs only the candidate rows (a few thousand embeddings, ≈ 2–6 MB fp16; ESTIMATE).

## 5. Benchmark experiment design (splits preserved)

**Split rule.** No source is in both training and TEST:

| Use | Sources | Status |
|---|---|---|
| **TRAIN** | NSynth-train, TinySOL folds 0–2, Slakh subset, FluidR3 + MuseScore General renders, VSCO/VCSL | — |
| **DEV** | NSynth-valid, TinySOL fold 3, TimGM6mb bench targets | Existing |
| **Sealed TEST (new)** | **Iowa MIS** real recordings + TinySOL fold 4 + the existing tone-bench targets rendered from a bank not in TRAIN | — |
| Sealed real-world TEST | 20-song catalogue | **Untouched** |

**FluidR3 conflict:** FluidR3 is the 2 Nov sealed tone-bench TEST. If it becomes TRAIN data, the tone bench must move to a new sealed bank: MuseScore General *or* FluidR3, whichever is not used for training.

**Experiments, compared on the same targets:**

| # | System | Notes |
|---|---|---|
| E-1 | Current shipping fingerprint matcher | Baseline |
| E-2 | Fingerprint + expanded *playable* candidates (FluidR3, MuseScore General, CC0 sample tones) | Tests whether more candidates help |
| E-3 | Multi-descriptor fingerprint (log-attack, centroid/f0, irregularity, decay), ablated one at a time | Literature-backed descriptors (McAdams; Caclin 2005) |
| E-4 | Embedding cosine (EfficientAT, CNN10), frozen | Harness ready: `ToneTableDump.swift` + `tone_t1.py` |
| E-5 | **Learned cross-source similarity:** a small projection head on frozen embeddings, trained with pairs (same instrument across sources = positive; different = negative) on TRAIN | The core hypothesis |
| E-6 | CLAP-assisted retrieval (offline reference only) | Optional; not deployable on the phone |

**Reported separately:**
- same-bank;
- cross-bank;
- isolated notes;
- layered synthetic (Slakh);
- short excerpts (≤ 1 s);
- human listening (when available).

**Metrics:**
- top-1 / top-3 exact (GM program) and family;
- mean reciprocal rank;
- time per part (ms) and memory.

**Never** reported as real Indian film-music accuracy.

## 6. Expected limitations

- **CT-X870IN factory tones cannot be fingerprinted** without capturing their audio.
  - Without recording, Casio tones can only be **name/category-mapped** to reference fingerprints. That is approximate, labelled "by name, not measured".
  - The measured recommendation is always a **TonePilot tone, which plays from the owner's keyboard** through the app.
  - An *automatic* capture (program change + notes over MIDI out, Casio audio into an interface; no playing) remains an optional future step. It needs MIDI out (not implemented) and an audio cable.
- **Indian instruments:** no open sample library exists; NSynth/TinySOL/Slakh don't cover them. Cross-source learning helps the Western/orchestral palette first.
- Synthetic renders and isolated notes are cleaner than film mixes. Slakh and the leakage targets partly cover that; real film validation still needs lawful annotated audio.
- GeneralUser GS training rights are unconfirmed, so it is a candidate only.

## 7. Zero-budget implementation sequence

| Step | Work | Effort | Manual? |
|---|---|---|---|
| 1 | **E-4 on existing DEV** (harness built; run in CI with EfficientAT/CNN10) | Small | No |
| 2 | Render FluidR3 + MuseScore General grids with the TonePilot engine; ingest TinySOL + NSynth subset | Small–medium | No |
| 3 | E-2 and E-3 (fingerprint variants) on DEV | Small | No |
| 4 | E-5 learned cross-source similarity (CPU; frozen embeddings + small head) | Medium | No |
| 5 | Sealed TEST once (Iowa MIS + TinySOL fold 4 + new-bank bench targets) | Small | No |
| 6 | Owner listening check of top results | Small | Listening only, no recording |

## 8. Go / no-go

- **GO:** steps 1–5. Automated, zero cost, licences verified, uses existing harnesses.
- **NO-GO for now:**
  - CLAP on the phone (776 MB);
  - FluidSynth inside the app (not needed; TonePilot has its own engine);
  - any production matcher change before E-5 beats E-1 on DEV **and** the sealed TEST.

## 9. The smallest experiment that answers "does it help?"

**E-4 on the existing cross-bank DEV.** TimGM6mb targets against the current GeneralUser library: does a frozen EfficientAT embedding cosine beat the shipping fingerprint (lead 2/12 exact, 3/12 family) at top-1 / top-3 family? The harness exists, so it only needs one CI run. If it wins clearly, proceed to E-5 (learned cross-source similarity). If not, the expansion must go through E-5 before it can help.
