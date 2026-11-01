# TonePilot — Zero-Budget, Indian Film Music Accuracy-First Strategy (consolidated)

> **Platform rule (owner): this whole strategy and to-do list is for the iPhone/iOS app first.** Every model, tone, benchmark and feature is built, measured and validated on iPhone (Core ML, on-device) before Android. Android parity follows as the second priority.

**Date:** 1 November 2026 (IST). **Supersedes** `TONEPILOT_INDIAN_FILM_STRATEGY.md` where they differ
(that file is kept as history). Source: the owner's final consolidated instruction.

**Maximum practical accuracy. Zero financial investment. Honest measurement. No false confidence.**

**Owner approval reserved for:** large-scale training, production model replacement, activation of
experimental features.

---

## 1. Zero-budget rules

| Allowed (free) | Not allowed |
|---|---|
| Open-source code and appropriately licensed pretrained models | Paid APIs, datasets, models or sample libraries |
| Free, legally reusable datasets (licence verified per source) | Paid cloud GPUs and subscriptions |
| Free GitHub Actions runners (CPU, 6 h/job), free Colab/Kaggle quotas (never assumed unlimited), the owner's Mac | Commissioned recordings, paid annotation or external services |
| Core ML (iOS), LiteRT (Android), small TonePilot heads, offline inference | Any runtime dependency on a paid service |

Engineering rules:
- **Resumable jobs:** checkpoints, cached embeddings, per-clip outputs saved, so an interrupted run
  restarts where it stopped.
- **No repeated computation:** embeddings are computed once per model version and reused by every head.
- **Spend compute where it buys accuracy:** small heads on cached embeddings first, fine-tuning only if
  measured gains justify it.

The musician permission letter (`docs/outreach/MUSICIAN_PERMISSION_LETTER.md`) stays, for
**voluntary, unpaid** contributions only.

## 2. Dataset architecture

```
TRAIN  ── licensed instrument audio (verified ML-training permission)
          + synthetic arrangements rendered from licensed samples (FluidR3 GM, MIT; NSynth; Slakh)
          + recordings authorised for training (owner, volunteer musicians with a signed letter)
DEV    ── separate licensed recordings: model selection, thresholds, calibration
          (never a TEST song; never a TRAIN source)
TEST   ── REAL-WORLD: actual Tamil / Telugu / Hindi film songs, private, never trained or tuned on
          ├── PROXY-TEST (separate, labelled synthetic): GeneralUser GS renders, NSynth test split
          └── reported separately; never presented as film-music accuracy
```

Leakage rules:
1. A song, performer, source recording or sample bank belongs to one set only. NSynth and Slakh may
   share library samples, so results are reported per source.
2. Thresholds and model choice use DEV only.
3. TEST results are read only after a model is frozen.
4. Every file has a SHA-256. A duplicate hash across sets fails the manifest check.

## 3. Real-world film-song catalogue: scalable plan

**Goal:** as many songs as can be legitimately accessed. No fixed ceiling; no invented target.

**Constraints:**
- I cannot obtain copyrighted recordings.
- Private evaluation must respect copyright and access terms.
- Purchase does not automatically grant evaluation or training rights. Owner to confirm with legal
  advice. India's Copyright Act s.52 (fair dealing, including private use and research) may be
  relevant, but this is **not established here**.

**How the catalogue grows:**
1. **Catalogue entries** (metadata only, no audio) can scale to thousands. Source: the CC0
   `rajkumar-dhanasekaran/tamil-film-songs-metadata` (3,033 Tamil songs) for titles, films and
   composers. Telugu and Hindi need an equivalent CC0/CC BY metadata source (to find).
2. **Audio** comes only from the owner's lawfully held recordings or owner-recorded performances. It
   is evaluated **locally** (owner's Mac or phone) by a **private evaluation tool**: non-production,
   dev builds only. Audio never enters the repository or CI. Only annotations, file hashes and scores
   are kept.
3. **Tiers per song:** `collected → imported → analysed → annotated (verified / partial) → evaluated`,
   or `excluded (reason)`. Coverage is always reported per tier and per language.
4. **Coverage balance:**
   - decades: 1950s → 2020s;
   - composers: Ilaiyaraaja, A. R. Rahman, Harris Jayaraj, Yuvan, Anirudh, Devi Sri Prasad,
     M. M. Keeravani, Thaman, R. D. Burman, Laxmikant–Pyarelal, Pritam, Vishal–Shekhar, …;
   - styles: classical, folk, melody, electronic, orchestral, rock, fusion;
   - sections: intro, interlude, verse, chorus, background score.

   Imbalance is reported, never hidden.
5. **Format:** one JSON Lines file per language (`docs/benchmark/catalogue/{tamil,telugu,hindi}.jsonl`)
   with stable song IDs. The 20-song list moves there as the first Tamil entries.

## 4. Ground-truth annotation format and workflow

**Format:** `docs/benchmark/annotation.schema.json`, checked by `Native/tools/dataset/annotations.py`.
One file per song:

```json
{ "song_id": "ta-0001", "language": "ta", "audio_sha256": "<64 hex>", "annotator": "owner",
  "verification": "verified | partial | unverified",
  "events": [
    { "section": "interlude-1", "start": 62.4, "end": 78.0,
      "label": "bansuri", "level": "instrument | family", "family": "Indian winds",
      "source": "acoustic | electronic | imitation | unknown",
      "audibility": "clear | partial | uncertain", "overlaps": ["string ensemble"],
      "confidence": 0.8, "evidence": "solo phrase 62–70 s, breathy attack; stem 'other' isolates it" } ],
  "sections": [ { "id": "interlude-1", "type": "interlude", "start": 62.4, "end": 78.0 } ],
  "beats": "optional file", "chords": "optional file", "accompaniment": [ ] }
```

Workflow:
1. **Suggest:** TonePilot's analysers pre-fill events. They are marked `unverified` and are **never
   ground truth**.
2. **Inspect:** listen, look at the spectrogram, and check separated stems where lawful and reliable.
3. **Correct:** the owner fixes the labels. Use family level when the exact instrument isn't clear,
   `source: unknown` when real vs imitation can't be told, and `uncertain` audibility when unsure.
4. **Verify:** a second listen (another day, or a second person) sets `verified`.
5. **Count only verified events** in accuracy. Partial songs are reported separately.

**Coverage report (always):** songs collected / imported / analysed / verified / partial / excluded
(no ground truth); sections evaluated; sections with reliable labels.

## 5. Free dataset and model licence register

Verified = licence text read by us. Declared = host metadata only, to confirm.

| Item | Kind | Licence | Commercial | ML training | Attribution | Status |
|---|---|---|---|---|---|---|
| NSynth | Data | CC BY 4.0 | Yes | Yes | Required | Verified |
| Slakh2100 | Data | CC BY 4.0 | Yes | Yes | Required | Verified |
| GuitarSet | Data | CC BY 4.0 | Yes | Yes | Required | Verified |
| FluidR3 GM | Samples | MIT | Yes | Yes | Notice | **Verified 1 Nov** (Debian copyright file) |
| GeneralUser GS | Samples | Custom: playback and software use | Yes (playback) | **Unclear** | Credit | Test renders only; email drafted |
| Saraga Audiovisual | Data | CC BY 4.0 | Yes | If it covers the audio | Required | Declared; confirm the record |
| Saraga (orig.), mridangam, tonic sets | Data | CC BY-NC(-SA/-ND) | No | No | — | Evaluation only, excluded from training |
| Freesound clips | Data | Per file: CC0 / CC BY / CC BY-NC | Per file | CC0, CC BY only | Per file | Per-file check |
| Wikimedia Commons recordings | Data | Per file | Per file | CC0, CC BY only | Per file | Per-file check |
| ccMixter | Songs and stems | Per track | Per track | CC BY only | Per track | Per-track check |
| Tamil film metadata (rajkumar-dhanasekaran) | Metadata | CC0 | Yes | Yes (text) | None | Verified (README) |
| Apple SoundAnalysis | Model | Apple SDK | Yes | — | — | Verified |
| EfficientAT | Model | MIT (repo) | Yes | Fine-tune ok | Notice | Verified (LICENSE) |
| PANNs | Model | Code MIT, weights CC BY 4.0 | Yes | Fine-tune ok | Required | Verified (Zenodo) |
| YAMNet | Model | Code Apache-2.0; weights licence **to confirm** | Probably | — | Notice | Partly verified |
| LAION-CLAP music | Model | Apache-2.0 | Yes | Yes | Notice | Verified (HF card); training-data provenance noted |
| Microsoft CLAP | Model | Weights MS-PL / CC BY 3.0 | Yes | — | Required | Verified; comparison only |
| Beat This! small | Model | MIT | Yes | — | Notice | Verified; not adopted |
| Basic Pitch | Model | Apache-2.0 | Yes | — | Notice | Verified; CI test model only |
| Demucs htdemucs / 6s | Model | Weights unclear / likely NC | **No** (until permission) | — | — | Personal builds only; email drafted |

Machine-readable: `docs/LICENSES/manifest.json` (gate in every iPhone build).

## 6. Benchmark report structure

Every progress report and benchmark page uses these **status buckets**, never merged:

| Bucket | Meaning |
|---|---|
| Completed | Done and in the repository |
| Implemented, not tested | Code exists; no measurement yet |
| Tested on synthetic data | Renders / GM / proxy only |
| Tested on licensed real recordings | NSynth, GuitarSet, Saraga, CC clips |
| Tested on real Tamil / Telugu / Hindi recordings | Verified-annotation songs only, per language |
| Awaiting ground-truth annotation | Collected or analysed, not verified |
| Awaiting owner approval | Ready, blocked on a decision |

Per feature, the report shows:
- the current production system and the candidate side by side;
- per language, per family, solo / layered / dense, per section type;
- the coverage counts (§4);
- model size, memory, speed and battery (when measured on a phone).

Metrics are as listed in the owner's §9. Machine-readable results live in the CI branches
(`ci/*-bench`, `ci/*-results`) and render into one Markdown report per run.

## 6b. Owner's additions (1 Nov, ~20:30 IST)

Included in `docs/TODO.md`:
- **A** large-scale growing song catalogue, keeping audio and metadata apart;
- **B** formal annotation workflow with AI pre-annotation and prioritised verification;
- **C** Indian instrument coverage tracking;
- **D** Instrument Maker chain test in full arrangements and on the CT-X870IN;
- **E** per-language real-world dashboard;
- **F** free-compute management;
- **G** legal dependency for film-song evaluation.

**Execution priority:**
1. Dataset and ground truth.
2. Instrument Analyser.
3. Instrument Maker.
4. Song intelligence.
5. Accompaniment and Live Song Arpeggio.
6. Android parity and release.

Regression, stability and security work runs in parallel throughout.

**Platform priority (owner, 1 Nov ~21:00 IST): iPhone/iOS is the main priority; Android second** (parity still required, but after iPhone).

**Next milestone:** a reliable instrument benchmark on actual instruments in Tamil, Telugu and Hindi music.

## 7. Phased plan (zero budget)

| # | Phase | Free resources | Depends on | Status |
|---|---|---|---|---|
| 1 | Docs: this strategy, audit, licence register | — | — | **Completed** (this document) |
| 2 | Catalogue: metadata JSONL (CC0 Tamil source; find Telugu/Hindi), private evaluation tool (dev build, local only) | Owner's Mac/phone | Owner's legal check on private evaluation | Pending |
| 3 | Annotation workflow: schema, validator, coverage report, pre-fill from analysers | — | 2 | Schema + validator started |
| 4 | Licensed data: Freesound/Commons per-file collection, Saraga licence check, NSynth/Slakh subsets | GitHub Actions | — | Pending |
| 5 | Instrument benchmark on proxy data (A vs C) | GitHub Actions (CPU) | — | **Running now** |
| 6 | Model comparison with licensed real recordings (NSynth, GuitarSet, Saraga, CC clips); fine-tuning (B) only if justified | Actions; Colab/Kaggle free quotas (resumable) | 4, 5 | Pending |
| 7 | Instrument Analyser candidate (5 stages, Core ML + LiteRT), shadow mode only | — | 6, owner approval | Pending |
| 8 | Instrument Maker: recognition-driven tones from licensed samples and synthesis; similarity + owner A/B | — | 7 | Pending |
| 9 | Song analysis (cycles, chords, bass, sections): validate the built-off candidates on real songs | Owner's annotations | 3 | Built, off |
| 10 | Accompaniment no-fill classifier + pattern fidelity; Live Song Arpeggio Casio test | — | 9 | Benchmark done (7/7 false arpeggios); classifier pending |
| 11 | Validate everything on unseen real songs, per language | — | 2–10 | Pending |
| 12 | iOS, Android, CT-X870IN regression; Android parity throughout | — | — | Ongoing |
| 13 | Final accuracy and readiness report | — | 11, 12 | Pending |
