# TonePilot — Instrument Recognition Improvement: Audit, Comparison and Proposal

**Date:** 1 November 2026 (IST) · **Status:** deliverables 1–7 of the owner's brief, for approval.
**No production code was changed.** Implementation starts only after approval.

Labels used: **Measured** (by us, with method) · **Source** (from the publisher's page or licence
file) · **Estimate** (our estimate, to be measured) · **Unknown**.

---

## 1. Existing implementation audit

TonePilot has **two separate systems** today. The brief's baseline numbers mix them, so they are
separated here.

### 1a. Instrument *recognition*: `App/Sources/Audio/InstrumentRecognizer.swift` (iOS only)

| Item | Fact |
|---|---|
| Model | Apple SoundAnalysis built-in classifier, `SNClassifySoundRequest(classifierIdentifier: .version1)`: 300+ everyday-sound classes, some of them instruments. Ships inside iOS; no download, no TonePilot weights |
| Training data | Apple's, undisclosed. **TonePilot has trained no model** |
| Input | Separated instrument parts (`lead, backing, other, piano, guitar` stems) when the song has been separated; otherwise the full mix |
| Windows | Apple's default window, `overlapFactor 0.25` |
| Labels → families | `InstrumentEvidence` (in `TonePilotCore/Arrangement/ToneIntensity.swift`) maps Apple label names to **13 families**: brass, strings, flute, reed, synth, electricGuitar, acousticGuitar, piano, organ, plucked, bells, choir, voice. Broad labels (keyboard, plucked/bowed string, "guitar") count half. Bass labels are ignored |
| Aggregation | Per window: strongest label per family. Per section: mean over windows, kept if ≥ 0.03. Across stems: the maximum per family |
| Output | Section → family → 0…1 score. **No exact instrument, no "unknown", no time positions inside a section** |
| Used by | `AutoArranger` (AI tone choice: e.g. brass ≥ 0.25, synth ≥ 0.4) |
| Android | **None**: `AppCore.analyze` passes no recognizer, so Android songs get no instrument evidence |
| Indian instruments | The label map names shehnai, nadaswaram, sitar, veena, santoor, sarod and harmonium, but **whether Apple's classifier ever outputs those labels is unverified**. Tabla, mridangam and dholak are not mapped |

### 1b. Tone *matching*: `TonePilotCore/Arrangement/ToneMatcher.swift` + `PartMatcher.swift` (shared core)

It works by analysis-by-synthesis:
1. Take each separated part's own notes.
2. Play them on candidate TonePilot tones.
3. Compare a fingerprint: 24 spectral bands from 80 Hz to 12 kHz, attack, hold, release and
   noisiness, measured only at the notes' harmonics.
4. Fit EQ and reverb, and keep the closest tone. A match is trusted from a similarity of 0.62.

This answers "which of *our* tones sounds closest", **not** "which instrument is this".

### 1c. Evaluation methods behind the existing numbers

| Number | What it measures | Method | Caveat |
|---|---|---|---|
| Lead 4/12 exact, 7/12 family; backing 2/12, 5/12 | **Tone matching** (1b), not recognition | `ToneMatchingBenchmarks`: 12 songs rendered from GeneralUser GS (General MIDI sounds); is the matched tone the rendering instrument? | Synthetic, Western GM sounds, 12 cases. **Not real film music** |
| 16/19 (84%), was 14/19 | **Recognition** (1a), family level | `Native/tools/instrument_check`: one clean phrase per GeneralUser GS instrument through Apple's classifier, in the iPhone build | Single clean instruments, no mix, no reverb, no Indian instruments. **Not real film music** |
| 8/15 (53%) held-out, was 6/15 | Same, on 15 other GM instruments | Pre-registered 11 Nov before any change; never used to choose a fix | Same caveats; shows the 19-instrument score overstates general accuracy |

**Label-mapping fixes (11 Nov), chosen from Apple's raw labels, kept because neither set lost a case:**
- organ labels before synth ("electronic_organ" was counted as synth);
- no family for the generic "keyboard (musical)" label (given to organs, synths, brass, strings and guitars);
- guitar technique labels ("guitar_tapping", "guitar_strum") at half weight, like plain "guitar";
- "bowed_string_instrument" at full weight (it names the strings family).

**Left (classifier errors, not mapping):**
- trombone heard as bassoon (91%);
- steel, jazz and clean electric guitars heard as keyboard, harpsichord or piano;
- French horn, tuba and GM strings get a strong "synthesizer" label, probably because GM SoundFont playback sounds synthetic to the classifier.

These need real recordings (owner action 0.3/0.4) or the EfficientAT head (stage 1, option C) as a second opinion. Run-to-run noise is a few points per clip; the distortion guitar margin is narrow (43% vs 41%).

**There is no measurement of either system on real Tamil, Telugu or Hindi film music.**

---

## 2. Candidate model comparison

Nothing here has been measured on our data yet; licences are **Source** facts checked earlier
(`docs/TONEPILOT_AI_MODEL_RESEARCH.md`, `docs/research/model_scan.md`).

| Model | Type | Code / weights licence (Source) | Training data | Size | iOS / Android path | Fit for this task |
|---|---|---|---|---|---|---|
| **Apple SoundAnalysis** (current) | 300+ class tagger | Apple SDK | Undisclosed | 0 MB (in iOS) | iOS only; **no Android** | Family hints only; no exact or Indian instruments verified |
| **LAION-CLAP music** (`laion/larger_clap_music`) | Audio–text embeddings: zero-shot labels from text and audio similarity | Apache-2.0 (HF card); original checkpoints CC0 | LAION-Audio-630k + music. LAION says the training set can't be released "due to copyright reasons" | 780 MB repo (Source); audio branch alone ~100–300 MB fp32 (**Estimate**) | Conversion **untested**; an ONNX port of the general CLAP exists | Strongest zero-shot candidate; **size is the risk** |
| **Microsoft CLAP** (`microsoft/msclap`) | Audio–text embeddings | Code MIT; weights MS-PL (HF) / CC BY 3.0 US (Zenodo 8378278) | Not stated | 4.7 GB repo (all versions) | Repo archived; heavy | Comparison only |
| **PANNs** (Zenodo 3987831) | AudioSet tagger, 527 classes | Code MIT; weights **CC BY 4.0** | AudioSet (YouTube audio; labels CC BY 4.0) | Cnn14 ~300 MB class (Source); smaller variants exist | Convertible CNN (untested) | Comparison only (general-audio labels, like Apple's) |
| **EfficientAT** (fschmid56, MN/DyMN) | AudioSet-trained efficient CNNs; good embeddings | Repo **MIT** (LICENSE, Source); weights published in the same repo | AudioSet | ~1–10 M parameters (paper; **Estimate** 4–40 MB fp32) | Small CNN: Core ML / LiteRT conversion likely easy (**untested**) | **Best size/quality candidate for the hybrid (C)** |
| **YAMNet** (Google) | AudioSet tagger, 521 classes, MobileNet | Code **Apache-2.0** (Source); weights file separate, licence to confirm | AudioSet | ~3.7 M parameters (**Estimate** ~4 MB TFLite) | TFLite native, so the Android path is easy; Core ML via conversion | Light baseline; same label limits as Apple |
| Community instrument classifiers (ONNX/HF) | Instrument classes | Tagged MIT/Apache, provenance undocumented | Unknown | 1–2 GB | Large | **Rejected** (unverified provenance) |

Do not assume bigger is better: AudioSet-trained models (PANNs, YAMNet, EfficientAT, Apple) know
"violin", "sitar" and "tabla" as everyday sound labels, but were never trained on Indian film
mixes. CLAP knows words but is large. Only measurement decides.

---

## 3. Dataset and licensing plan

**Rule:** a dataset's *code* or *model* licence says nothing about its *audio*. Every audio file
needs its own source, licence, permission, label and annotation confidence (manifest fields as in
`docs/benchmark/tamil-cinema/catalogue.json`). UNVERIFIED audio is excluded from training.

| Need | Source | Audio licence (Source) | Use |
|---|---|---|---|
| Western single instruments (strings, flute, guitar, piano, organ, synth, brass) | **NSynth** | CC BY 4.0 | Train + evaluate (family and instrument) |
| Multi-instrument mixes with per-instrument stems | **Slakh2100** | CC BY 4.0 | Train + evaluate (multi-label, layered) |
| Real guitar | GuitarSet | CC BY 4.0 | Evaluate |
| Indian classical: violin (Carnatic), mridangam, vocals, ghatam, veena, … | **Saraga Audiovisual** (Zenodo 17405610 / Mini 16411600) | **CC BY 4.0** declared; **confirm in the record text** that it covers the audio | Train + evaluate, after confirmation. Concert style, not film |
| Indian classical (original Saraga, mridangam, tonic sets) | Zenodo 4301737 etc. | CC BY-NC / NC-SA / NC-ND | **Evaluation only, never training** |
| Bansuri, nadaswaram, shehnai, sitar, veena, mandolin, tabla, dholak — solo | Freesound / Wikimedia Commons, **per file** | CC0 / CC BY only (no NC); provenance checked per clip | Train + evaluate |
| Same instruments, guaranteed rights | **Recordings by musicians with written permission** (owner's network) | Permission letter | Train + evaluate |
| Real film songs (Tamil, Telugu, Hindi) | The 20-song catalogue (`docs/benchmark/tamil-cinema/`). **No lawful audio was found** (see `SOURCE_SURVEY.md`) | Owner recordings (owner owns the recording; composition copyrighted), written permission, or purchased copies for **private evaluation only** | **Test set** (unseen songs), split by song identity |
| Owner's keyboard tones | CT-X870IN recordings | Owner | Target sounds for tone mapping (stage 5) |

Splits:
- **By song identity**: no song, and no recording of a song, in two splits.
- **For solo clips, by performer/source**: no performer in both train and test.

Leakage check: NSynth and Slakh are both sample-library based, so a Slakh instrument preset and an
NSynth instrument may share samples. Report scores per source.

**Main gap:** licensed, labelled Indian film-style audio does not exist publicly. Without owner or
permission recordings, the Indian part of the targets **cannot be verified**.

---

## 4. Baseline benchmark report

| System | Real Indian film music | Synthetic / clean (Measured, §1c) |
|---|---|---|
| Recognition: Apple SoundAnalysis | **Not measurable yet (no lawful test audio)** | Family 14/19 (73.7%), clean single instruments |
| Tone matching: ToneMatcher | **Not measurable yet** | Lead 4/12 exact, 7/12 family; backing 2/12, 5/12 (rendered GM songs) |

Every metric the brief asks for will be reported per system on the same unseen-song test:
exact accuracy, family accuracy, multi-label precision/recall/F1, confusion matrix,
unknown/uncertain rate, accuracy per family, solo vs layered, and performance on unseen songs.

Until the real test set exists, there are two proxy test sets, both licence-clean:
- a **proxy**: Slakh2100 test split, NSynth test split and Saraga (after licence confirmation);
- a **synthetic** set: the existing rendered songs.

**Proxy results will never be presented as film-music accuracy.**

---

## 5. Fine-tuning feasibility (architecture B)

| Question | Answer |
|---|---|
| Fine-tune CLAP? | Needs a GPU and plenty of labelled data. The free CI runners are CPU-only with 6 h jobs, so this is **not feasible in CI**. A free GPU notebook (Kaggle/Colab free tier on the owner's account) is possible but manual |
| Fine-tune a small CNN (EfficientAT MN, YAMNet)? | **Feasible**: ~1–10 M parameters; a few thousand 1–3 s clips; hours on CPU (**Estimate**) |
| Data | Western families: plenty (NSynth, Slakh). **Indian instruments: the bottleneck.** Roughly 50–200 licensed clips per instrument from several performers are needed (**Estimate**) |
| Risk | Overfitting to a few recordings of each Indian instrument. Classical concert sound (Saraga) differs from film production (reverb, layering, compression) |

Verdict: B is feasible for small models once data exists, but it is data-limited, not compute-limited.

---

## 6. Hybrid architecture proposal (architecture C, recommended for investigation)

Frozen pretrained embeddings plus a small TonePilot multi-label head, in five stages.

| Stage | What | How |
|---|---|---|
| 1 Content | Vocals / percussion / bass / instrumental present? | Separated stems first (already in the app), confirmed by embedding energy per stem; unknown allowed |
| 2 Family | strings, winds (flute family), double reeds (nadaswaram/shehnai), plucked (sitar, veena, mandolin, guitar), keys (piano, EP, organ), synth (lead, pad, texture), percussion (tabla, mridangam, dholak, electronic), brass, choir | Multi-label sigmoid head on a frozen embedding (EfficientAT or CLAP audio branch, 1–3 s windows); per-class thresholds calibrated on the dev split |
| 3 Instrument | Specific instrument **only when confident** | Second head per family. When below its calibrated threshold, report the **family** only. Never force an exact label |
| 4 Aggregation | Where each instrument plays | Window scores → per section and over time (persistence, top-k mean). Output: instrument/family, confidence, time ranges; states `confident / family-only / ambiguous / unknown` |
| 5 Tone mapping | Closest TonePilot or keyboard tone | A **separate** table (instrument → candidate tones), refined by the existing ToneMatcher. A violin stays "violin" even when the nearest available tone is "Orchestral Strings" |

Why C first:
- It can use whatever licensed data exists (the head is small).
- The embedding model can be swapped (EfficientAT vs CLAP) without changing the rest.
- It runs on both platforms through the existing `InferenceBackend` (Core ML on iPhone, LiteRT on Android).

Architecture A (each model unchanged, zero-shot or with its own labels) is measured first as the
baseline. B and C are measured on the same unseen-song test, and the measured results choose.

---

## 7. Estimated model size and mobile inference cost (Estimates, to be measured)

| Option | App download | Compute per 4-min song (1 s hop) | Memory |
|---|---|---|---|
| Apple SoundAnalysis (current) | 0 | ~1 s on CI Mac (Measured: 0.8% of real time) | small |
| EfficientAT MN (≈ 1–5 M parameters) + head | **~4–20 MB** fp32, ~2–10 MB fp16 | ~2–8 s on iPhone 15 (Estimate) | < 100 MB |
| YAMNet + head | ~4–15 MB | ~2–6 s (Estimate) | < 100 MB |
| CLAP audio branch + head | **~100–300 MB** (Estimate), as an optional download | ~20–60 s (Estimate) | 300–800 MB, within the 1.5 GB gate but heavy |
| Head only (multi-label MLP) | < 1 MB | negligible | negligible |

All options are offline, with no paid APIs. A downloadable model follows the existing in-app model
download (as with the separation models).

## 8. Proposed next steps (on approval)

1. **A-baseline run** (CI only, no app change):
   - models: Apple, YAMNet, EfficientAT and CLAP;
   - data: the Slakh/NSynth proxy and Saraga (after licence confirmation), plus the synthetic set;
   - measures: exact, family, multi-label, short clips, reverberant/processed (with added reverb
     and compression), size, latency.
2. **Licensed Indian instrument collection:** Freesound/Commons CC0/CC BY clips with per-file
   manifest, owner and musician recordings, and owner recordings of the 20 catalogue songs as the
   unseen-song test.
3. **C prototype** (frozen embedding + head) vs **B** (fine-tuned small CNN) vs **A** on the same test.
4. Adopt only if the winner measurably beats the current system on unseen real recordings. Then a
   commercial licence review, Core ML + LiteRT builds, and the speed/crash gate.

Targets (lead exact ≥ 80%, backing exact ≥ 75%, family ≥ 90%) are **targets**, not expectations.
No success will be claimed without unseen real recordings.
