# TonePilot — Indian Film Music Accuracy-First Strategy (first deliverable)

**Date:** 1 November 2026 (IST) · **Status:** for the owner's review. **No large-scale training, and no
production model replaced, until approval.**

**Target domain: Tamil, Telugu and Hindi film music**, the primary domain for data, models,
benchmarks and validation. "Accuracy improved" is reported only with results on **previously
unseen** Tamil, Telugu and Hindi recordings. Everything measured so far is synthetic and is labelled
as such.

Strategic choice (owner's recommendation, adopted): build **TonePilot's own Indian-music
intelligence layer**, made of four parts:
- pretrained audio models for general sound understanding;
- TonePilot-trained heads for Indian instruments and arrangements;
- music-specific analysis (rhythm cycles, harmony, bass, arrangement);
- a separate tone-creation and matching system.

It improves as the licensed dataset grows, instead of being capped by one generic model.

---

## 1. Architecture audit (summary)

Detail: `TONEPILOT_ARCHITECTURE_AUDIT.md`, `TONEPILOT_INSTRUMENT_RECOGNITION_PLAN.md` §1.

| Layer | What runs today | Platforms |
|---|---|---|
| Import + separation | Demucs 4/6-part (Core ML + C++), Lead/Backing DSP split; shared `SongImportPipeline` | Separation **iOS only** |
| Song analysis | `TempoAnalyzer` (beats), `SectionInsights` (metre), `HarmonyAnalyzer` (key, chords), `StructureAnalyzer` (sections), `MelodyExtractor` | Core (both) |
| Instrument recognition | Apple SoundAnalysis → 13 families per section | **iOS only** |
| Instrument Maker / tones | `ToneMatcher` analysis-by-synthesis + EQ/reverb fit; 26-tone Film Tone Library; 20 Indian "-like" imitation tones (processed GM samples) | Core (both) |
| Accompaniment | `ArpeggioLearner` → per-section pattern; `AutoArranger` rules | Core; Song Arpeggio **iOS only** |
| Live Song Arpeggio | `LiveFill` + `LiveArpeggiator` over USB-MIDI from the CT-X870IN | **iOS only** |
| Built and measured, **off in the app** | Beat This! (not adopted), rhythm-cycle inference, harmony hypotheses, inference back-ends (Core ML; LiteRT ABI), accompaniment benchmark | Core |

Biggest structural gaps:
1. Android lacks separation, instrument recognition and Song Arpeggio.
2. No real-music benchmark exists for any feature.
3. Recognition and tone matching were conflated in earlier reporting.

## 2. Existing features and their accuracy evidence

| Feature | Best evidence today | Measured on | Real Indian evidence |
|---|---|---|---|
| Instrument recognition (Apple) | Family 14/19 (74%) | Clean single GM instruments | **None** |
| Instrument Maker / tone matching | Lead 4/12 exact, 7/12 family; backing 2/12, 5/12 | 12 rendered GM songs | **None** |
| Separation | Core ML within 0.5 dB of the C++ reference per part (CI gate) | MUSDB-style reference check | **None**; weights licence: Personal only |
| Beats | F 0.92 with drums, **0.52 without** | 24 rendered songs | None |
| Tempo | 18/24 within 4% | 24 rendered songs | None |
| Metre / rhythm cycle | Current 10/24 (audit); 6/36 cycles incl. Indian cycles (83% wrong but confident). New cycle stage 31/36, 0% wrong-confident (**off**) | Rendered | None |
| Chords | Current 73% per beat in-sample, 46–66% held-out. New hypotheses 83% on the untouched set with stems (**off**) | Rendered | None |
| Sections | Boundaries F 1.00; repeat grouping wrong | 1 rendered song | None |
| Melody | Not measured | — | None |
| Accompaniment pattern | 100% degrees with true inputs; **false arpeggios 7/7** (fills on strums, pads, hooks, solos, silence) | Rendered sections | None |
| Live Song Arpeggio | Unit tests (deadlock and stuck notes fixed) | — | **Owner's Casio test pending** |

## 3. Proposed Indian film-music instrument taxonomy

Machine-readable: `Native/tools/instruments/taxonomy.json` (v1). Every prediction carries:
- **level:** instrument / family / unknown;
- **source:** `acoustic` (physical instrument, recorded or sampled, including amplified),
  `electronic` (a synth in its own right), `imitation` (synthesised or processed sound imitating a
  specific traditional instrument), or `unknown`;
- **confidence**;
- **time ranges.**

| Family | Instruments |
|---|---|
| Strings | violin, viola, cello, double bass, string ensemble, sarangi |
| Indian winds | bansuri, nadaswaram, shehnai, kuzhal |
| Western winds | flute, piccolo, oboe, clarinet, saxophone |
| Other winds | pan flute, shakuhachi, duduk |
| Indian plucked | veena, sitar, tanpura |
| Other plucked | acoustic guitar, electric guitar, mandolin, harp, koto |
| Keys | piano, electric piano, organ, accordion, harmonium |
| Bells | celesta, glockenspiel, music box, vibraphone, marimba, tubular bells, kalimba, santoor |
| Indian percussion | tabla, mridangam, dholak, ghatam, kanjira, thavil, dhol |
| Other percussion | drum kit, electronic percussion, frame drums |
| Electronic | synth lead, synth pad, orchestral synth, bass synth, synth brass, ambient texture, hybrid orchestral texture |
| Bass | bass guitar |
| Other | brass (trumpet, trombone, French horn, section), kombu, choir, vocal-like synth |

v2 change from v1: percussion is split into Indian and Other, adding ghatam, kanjira, thavil and
dhol, which are common in Tamil and Telugu film percussion.

Rule: a label exists in the output **only after the model is shown to recognise it** on held-out
data. Until then it reports the family (or unknown). Never map a generic label to an Indian name
without validation.

## 4. Training-data sources and verified licences

"Verified" = we read the licence text ourselves. "Declared" = the host's metadata only (to confirm
before use). Free download ≠ permission to train.

| Source | Contents | Licence | ML training | Status |
|---|---|---|---|---|
| NSynth | 305k notes from 1,006 instruments; labels acoustic/electronic/synthetic | CC BY 4.0 | Allowed (attribution) | **Verified** (earlier research) |
| Slakh2100 | 2,100 multitrack renders with stems and MIDI | CC BY 4.0 | Allowed | **Verified** |
| GuitarSet | Real guitar, annotated | CC BY 4.0 | Allowed | **Verified** |
| FluidR3 GM SoundFont | Instrument samples for rendering training material | **MIT** ("I hereby release Fluid under the MIT license") | Allowed | **Verified** (Debian copyright file, 1 Nov) |
| GeneralUser GS | Instrument samples | Playback cleared; **silent on ML training** | Unclear | Test-side rendering only; **ask the author** |
| Saraga Audiovisual (+ Mini) | Carnatic/Hindustani concerts with tala, section and melody annotations; some multitrack | CC BY 4.0 | Allowed **if** it covers the audio | **Declared**; confirm the record text. Classical, not film |
| Saraga original, mridangam, tonic sets | Classical audio | CC BY-NC / NC-SA / NC-ND | **No** (non-commercial) | Evaluation only |
| Freesound | Single-instrument clips incl. Indian instruments | Per file: CC0 / CC BY / CC BY-NC | CC0 and CC BY only | Per-file check; needs a free API key from the owner |
| Wikimedia Commons | Instrument recordings | Per file (CC0 / CC BY / CC BY-SA / PD) | CC0 / CC BY | Per-file check |
| ccMixter | Songs and **stems** | Per track (CC BY, BY-NC, sampling+) | CC BY only | Per-track check; few Indian-style tracks |
| Pre-1965 Indian film recordings | Old film songs | Indian sound-recording/film copyright (60 years) may have expired, but **compositions and lyrics are still protected** | **Unclear** | **Legal advice required; excluded until then** |
| Commercial sample libraries | Indian instrument samples | Most EULAs forbid ML training | No, unless the EULA says yes | Excluded unless written permission |
| **Owner and musician recordings** | Anything, including film-style arrangements | Owner's rights / written permission (template needed) | **Yes, with permission** | **Primary source for Indian instruments and film styles** |
| Commissioned session recordings | Indian instruments, film-style parts, stems | Work-for-hire contract incl. ML training | Yes | Optional (costs money: owner's decision) |

**Not usable** (surveyed 1 Nov, `docs/benchmark/tamil-cinema/SOURCE_SURVEY.md`): masstamilan,
`sajeevan16/tamil-songs-corpus` (lyrics only), `code-mohanprakash/tamil` (features from pirated
files), Hugging Face Tamil emotion set (speech, no licence), unlicensed Bollywood/Tamil audio sets
on Hugging Face.

**Commercial film songs cannot be used for training**, even when owned or freely available,
without the rights holders' permission.

## 5. Dataset collection and annotation plan

Three datasets, never mixed:

| Set | Purpose | Contents | Size goal |
|---|---|---|---|
| **TRAIN** | Train heads and fine-tunes | Licensed single instruments (Indian + Western + electronic); licensed and synthetic layered arrangements; owner/musician recordings made **for training** | Phase A: 50–200 clips per instrument from ≥ 3 performers or sources; Phase B: 500+ layered film-style excerpts |
| **DEV** | Thresholds, calibration, model choice | Same kinds as TRAIN, different performers and songs | ~15% of TRAIN |
| **TEST (sealed)** | Acceptance only | The 20-song catalogue (owner recordings / permitted audio) plus later Telugu and Hindi songs, **split by song identity and performer**, never seen in training | ≥ 20 songs to start, growing to ≥ 60 (20 per language) |

Collection, in order:
1. Licensed solo instruments from Freesound/Commons (CC0/CC BY).
2. NSynth / Slakh / FluidR3 renders for Western and electronic families.
3. Owner recordings: Casio parts of film-style arrangements, and the catalogue songs as TEST.
4. Musician recordings with a permission letter: bansuri, nadaswaram, shehnai, veena, sitar,
   santoor, tabla, mridangam, dholak, violin.
5. Layered film-style arrangements built from licensed stems, with production variants (reverb,
   compression, EQ, stereo width, synth layering).

Annotation, per file (manifest fields already defined in `docs/benchmark/tamil-cinema/catalogue.json`):
- source URL, licence text, ML-training permission, SHA-256, performer/source identity;
- instrument and family labels **with time ranges** and source category;
- annotation confidence.

Songs are also annotated for beats, cycle, chords, bass, sections and accompaniment type.

Workflow: I pre-annotate with the analysers; the owner corrects (in-app correction UI, later); a
second listen sets the confidence. Annotation cost (Estimate): 30–60 min per song section set.

Leakage rules:
- No song, performer or source recording in two sets.
- NSynth and Slakh share sample-library origins, so results are reported per source.

## 6. Model comparison and fine-tuning strategy

| Step | What | Decision rule |
|---|---|---|
| A. Off-the-shelf | Apple SoundAnalysis (baseline), YAMNet, EfficientAT, PANNs, CLAP: native labels mapped to the taxonomy | Baseline numbers per family; no adoption decision |
| C. Frozen embeddings + TonePilot head | Embeddings from each model (1 s windows); multi-label instrument, family and source heads; calibrated per-class thresholds; abstain → family / unknown | Prototype; compared with A on DEV |
| B. Fine-tune | The best small backbone from A/C, fine-tuned on TRAIN (CPU in CI for small CNNs; free GPU notebook for larger ones) | Only if it beats C on DEV by a meaningful margin |
| Choice | The winner on DEV, confirmed once on sealed TEST | Efficiency counts: prefer what runs on iPhone and Android; CLAP only as an optional download if it clearly wins |

Licences are checked per model for code **and** weights:
- **Verified:** Apple SDK, EfficientAT (MIT repo), PANNs (CC BY 4.0 weights), LAION-CLAP music (Apache-2.0).
- **To confirm:** YAMNet (Apache-2.0 code; weights licence).

Ready tooling (not wired into the app):
- `taxonomy.json`;
- `InstrumentSetRender` (solo and timed layered clips; FluidR3 train bank vs GeneralUser test bank,
  so proxy results are not measured on training sounds).

## 7. Benchmark plan for all major features

Every feature is reported **per language (Tamil / Telugu / Hindi), per family and per section type**,
on sealed TEST, against the current production system.

| Feature | Metrics | Gate (target, not assumption) |
|---|---|---|
| Instrument Analyser | Exact accuracy; family accuracy; multi-label P/R/F1 (window and section); start/end timing error; false-positive and false-negative rates; unknown rate; calibration (ECE); solo / layered / dense; acoustic vs imitation | Lead exact ≥ 80%, backing exact ≥ 75%, family ≥ 90% on unseen real recordings |
| Instrument Maker | Similarity to the isolated original (spectral, envelope); listening A/B by the owner; playable range and velocity checks | Owner prefers the new tone in ≥ 70% of A/B; similarity better than the current matcher |
| Separation | SDR/SI-SDR per stem on licensed multitracks (Slakh, ccMixter, Saraga multitrack); timing alignment; leakage | Not worse than the current engine (existing gate) |
| Beats / tempo / cycle | Beat F; tempo accuracy; cycle accuracy; wrong-confident rate | Beat F ≥ 0.85 without drums; cycle ≥ 85%; wrong-confident ≤ 5% |
| Chords / bass | Beat-level root + quality; bass-note accuracy; truth in alternatives; drone handling | ≥ 85%; minor ≥ 75%; alternatives ≥ 95% |
| Sections | Boundary F (±2 beats); repeat grouping; instrument changes per section | Boundary F ≥ 0.85; grouping ≥ 80% |
| Accompaniment | False-arpeggio rate; pattern degree accuracy; onset error; owner listening on 10 real sections | False arpeggios **0**; degrees ≥ 90%; owner approves |
| Live Song Arpeggio | Chord detection from Casio MIDI; latency; stuck/duplicate notes; no fill when uncertain | 0 stuck, 0 duplicates; owner's CT-X870IN test passed |
| Platforms | iOS vs Android outputs equal within tolerance | Contract tests (Phase 1 harness) |

## 8. Phased roadmap

Efforts are focused engineering days (**estimates**).

| # | Phase | Depends on | Effort | Main risks |
|---|---|---|---|---|
| 1 | Finish the architecture audit (this document) | — | done | — |
| 2 | Dataset and licensing: permission template, Freesound/Commons collection, Saraga licence check, owner recording plan, sealed TEST of 20 songs | Owner recordings and approvals | 5–8 + owner time | **Lawful Indian film audio is scarce**; everything real waits on recordings |
| 3 | Instrument benchmark: proxy sets now (renders, NSynth, Slakh); real TEST when recorded | 2 for real data | 4–6 | Proxy results flatter models |
| 4 | Model comparison A vs C vs B | 3 | 6–10 | CPU-only CI; CLAP size |
| 5 | Instrument Analyser: chosen model, 5-stage hierarchy, Core ML + LiteRT, shadow mode beside Apple's classifier | 4, owner approval | 8–12 | Indian instruments with few licensed examples |
| 6 | Instrument Maker: recognition-driven tone choice; new Indian tones from licensed samples or synthesis; similarity vs isolated stems; owner A/B | 5 | 8–12 | Lack of licensed Indian samples for tones |
| 7 | Song analysis (rhythm cycle, chords, bass, sections), switching on what passes (work from Phases 2–3) | 2 (real TEST) | 5–8 | Real audio differs from renders |
| 8 | Accompaniment Maker + Live Song Arpeggio: no-fill classifier, pattern fidelity, Casio test | 7 | 10–14 | Owner's listening time |
| 9 | Full validation on unseen Tamil/Telugu/Hindi recordings | 2–8 | 3–5 | Test set size |
| 10 | iOS, Android and CT-X870IN regression; commercial licence review; rollout with owner approval | 9 | 4–6 | Demucs weights licence; Android parity |

Running alongside:
- Android parity work (LiteRT back-end, emulator tests);
- the nightly reproducibility benchmarks;
- the speed and crash gate on every build.

## 9. Decisions needed from the owner

1. Approve this strategy (or change it).
2. Recordings: catalogue songs (sealed TEST) and Indian instrument parts (TRAIN).
3. A permission-letter template for musicians, and whether to commission session recordings.
4. A free Freesound API key, for the per-file licence collection.
5. Legal advice on pre-1965 recordings, and on private evaluation with purchased copies.
6. Permission emails: Demucs weights, GeneralUser GS (training use).
