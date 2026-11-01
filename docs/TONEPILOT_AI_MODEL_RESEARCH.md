# TonePilot — AI Model Research

**Date:** 1 November 2026 · **Rule applied:** a model is only recommended if (1) its code **and exact weights** have verified commercial-use and redistribution rights, (2) it beats the current TonePilot implementation on independent test data, and (3) the same gain can't be had more cheaply with existing models, DSP or music theory. Zero paid APIs; offline-first.

**Bottom line:** only two new neural models are worth testing for production, and both are small:

1. **Beat This! (small, ~8.1 MB, MIT code and MIT weights)** for beats and downbeats — the measured weakest link for Song Arpeggio.
2. **Spotify Basic Pitch (Apache-2.0)** for note events in the separated accompaniment, used for arpeggio extraction and (the same model) as a melody cross-check.

For instrument recognition and tone matching **no third-party checkpoint can be cleared today**: the strongest candidates (LAION-CLAP, Microsoft CLAP, PANNs, MERT) host their weights on sites whose licence pages could not be opened from this session, and MuQ is verified non-commercial. The recommended path is **one small TonePilot-trained timbre model** on commercially licensed data, with CLAP kept only as a research comparison in the benchmark until its weights licence is verified.

## Classification key

| Class | Meaning | Shippable? |
|---|---|---|
| **SAFE** | FREE & COMMERCIALLY SAFE: code and exact weights have verified commercial-use and redistribution rights | Yes |
| **RESTRICTED** | FREE BUT RESTRICTED: non-commercial or research-only terms | No |
| **UNVERIFIED** | FREE BUT UNVERIFIED: weights or data rights not established — DO NOT SHIP | No |
| **PAID** | Needs payment or a commercial licence | No (zero budget) |

**Session limits on verification:** `huggingface.co`, `zenodo.org`, `magenta.tensorflow.org` and `essentia.upf.edu` were unreachable from this audit session (network policy), so model cards and dataset pages hosted there could not be read. Every such item is marked UNVERIFIED with the exact page to check; nothing below is filled in from memory as if verified.

---

## 1. Rhythm, beats, downbeats, structure

| Model | Task | Code licence | Weights licence | Data terms | Size | iPhone / Android | Published accuracy | Class | Recommendation |
|---|---|---|---|---|---|---|---|---|---|
| [Beat This!](https://github.com/CPJKU/beat_this) (CPJKU, ISMIR 2024) | Beats + downbeats, no DBN needed | MIT | **MIT** — README: "The code and the published model weights are released under the MIT license" | 16 datasets; README warns some training files are "fully copyrighted or under limited Creative Commons licenses" (affects the data, not the weight licence) | `final*` ~78 MB, `small*` ~8.1 MB (README) | Pure PyTorch transformer on spectrograms; Core ML / ONNX conversion **untested** | Paper tables (not restated in README; to be re-measured on our bench) | **SAFE** (data-provenance caveat recorded) | **Adopt for testing** — small variant first |
| [All-In-One](https://github.com/mir-aidj/all-in-one) | Tempo, beats, downbeats, segment labels (intro/verse/chorus/…) | MIT | **Not stated** on the repository | Harmonix Set (terms not stated) | Not stated | Needs NATTEN, madmom and Demucs inside its pipeline | Not restated | **UNVERIFIED** | Research comparison only |
| [madmom](https://github.com/CPJKU/madmom) | Beats, downbeats, chords, onsets | BSD | **CC BY-NC-SA 4.0** (README) | — | — | — | — | **RESTRICTED** | Reject |
| librosa | Onset, tempo, beat (DSP) | ISC | — (no weights) | — | — | DSP ideas portable into Swift | — | SAFE | Use ideas only (TonePilot already implements Ellis DP) |
| TonePilot `TempoAnalyzer` (current) | Tempo + beats | own | — | — | 0 | Shared core (iOS + Android) | **Measured:** beat F 0.92 with drums, 0.52 without; 18/24 tempo | SAFE | **Keep as fallback and for confidence** |
| TonePilot `StructureAnalyzer` (current) | Boundaries, repeats, labels | own | — | — | 0 | Shared core | **Measured:** boundaries 4/4; grouping wrong; labels weak | SAFE | **Improve, don't replace** (no SAFE model exists) |

Why Beat This! and not more: it is the only candidate with explicitly MIT weights, it gives downbeats (fixing meter 10/24 and bar alignment for Song Arpeggio), it needs no non-commercial post-processing, and its small model is ~8 MB.

## 2. Instrument recognition and tone matching

| Model | Task | Code licence | Weights licence | Data terms | Size | iPhone / Android | Class | Recommendation |
|---|---|---|---|---|---|---|---|---|
| Apple SoundAnalysis (version 1, current) | 300+ everyday sounds incl. instrument families | Apple SDK | Apple SDK | — | 0 MB (in iOS) | iOS only | **SAFE** | Keep as a free prior on iOS; **measured 14/19 (74%)** on clean instruments |
| [LAION-CLAP](https://github.com/LAION-AI/CLAP) music checkpoint `music_audioset_epoch_15_esc_90.14.pt` | Audio–text embeddings; zero-shot instrument tags; audio similarity | **CC0-1.0** (repository) | **Not stated on GitHub**; weights hosted on Hugging Face (`lukewys/laion_clap`) — model card unreadable this session. README: training data cannot be released "due to copyright reasons"; "Please take your own risk when using this model" | Unreleased training set | HTSAT-base encoder (size **unknown** until the checkpoint is inspected in CI) | Core ML conversion **untested** | **UNVERIFIED** | Research comparison in the benchmark; adopt only if weights terms are confirmed **and** it beats the TonePilot model |
| [Microsoft CLAP](https://github.com/microsoft/CLAP) (msclap 2022/2023) | Audio–text embeddings | MIT | Not stated on GitHub; Hugging Face card reportedly tagged MS-PL (search result only, card unreadable); Zenodo record unreadable | Not stated | Not stated | Untested; repository archived | **UNVERIFIED** | Research comparison only |
| [MERT](https://github.com/yizhilll/MERT) v1-95M / v1-330M | Music representation | Apache-2.0 | **Not stated on GitHub**; Hugging Face cards unreadable this session | Not stated | 95M / 330M params; 24 kHz | Large for on-device | **UNVERIFIED** | Reject for production (size + unverified weights) |
| [MuQ / MuQ-MuLan](https://github.com/tencent-ailab/MuQ) | Music representation; text–music similarity | MIT | **CC BY-NC 4.0** (README, `LICENSE_weights`) | — | ~300M / ~700M params | Too large | **RESTRICTED** | Reject |
| [PANNs](https://github.com/qiuqiangkong/audioset_tagging_cnn) (Cnn14 etc.) | AudioSet tagging (527 classes) | MIT | Hosted on Zenodo record 3987831 — licence **unreadable this session** | AudioSet (YouTube-sourced audio) | Not stated on GitHub | Convertible CNN (untested) | **UNVERIFIED** | Research comparison only |
| [EfficientAT](https://github.com/fschmid56/EfficientAT) (mn04–mn40, dymn) | AudioSet tagging, efficient CNNs | MIT | GitHub Releases; **licence not stated** | AudioSet | mn04 0.98M params … mn40 68M (README); mAP 43.2–48.7 | Designed for constrained devices; conversion untested | **UNVERIFIED** | Strong architecture to *retrain* on our own data (code is MIT) |
| [BEATs](https://github.com/microsoft/unilm/tree/master/beats) | Audio representation | Repository LICENSE (not shown on the page) | OneDrive links, **no stated terms** | AudioSet | Not stated | Untested | **UNVERIFIED** | Reject for now |
| [YAMNet](https://github.com/tensorflow/models/tree/master/research/audioset/yamnet) | AudioSet 521 classes | tensorflow/models repository licence (not shown on the page) | Not stated on the page | AudioSet | ~3.7M weights, 16 kHz | Small; TFLite path common | **UNVERIFIED** | Not needed: same job as Apple's classifier |
| Essentia pre-trained models (instrument taggers) | Instrument tagging | AGPL (library) | Models page unreadable this session | — | — | — | **UNVERIFIED** | Reject for now |
| TonePilot `ToneMatcher` + `PartMatcher` (current) | Nearest library tone, EQ/reverb fit | own | — | — | 0 | Shared core | SAFE | **Measured:** lead 4/12 exact, 7/12 family; keep only for EQ/reverb fine-tuning |
| **Proposed: TonePilot Timbre model** (own) | Instrument family/instrument tags + an embedding for nearest-tone retrieval, in one small network | own | own (trained by us) | Commercially licensed training data only (see §5) | Target ≤ 5 MB (**estimate**; EfficientAT-class CNN) | Core ML + ONNX/TFLite for Android | **SAFE if the data is cleared** | **Adopt for testing** — the only path to a shippable instrument model today |

**Indian instruments:** no checkpoint above was trained on a licensed Indian-instrument corpus, and no commercially licensed nadaswaram/veena/sarangi dataset was found (CompMusic/Saraga focus on melody; IMID licence not found). Realistic claim: **family-level recognition** (reed, bowed, plucked, flute, keys, brass, synth) plus "-like" patch mapping; exact Indian instrument names only after licensed recordings exist.

## 3. Transcription (accompaniment notes for arpeggio; melody)

| Model | Task | Code licence | Weights licence | Data terms | Size | iPhone / Android | Class | Recommendation |
|---|---|---|---|---|---|---|---|---|
| [Spotify Basic Pitch](https://github.com/spotify/basic-pitch) | Polyphonic, instrument-agnostic note events with pitch bends | Apache-2.0 | Weights are files inside the Apache-2.0 repository (`basic_pitch/saved_models`), no separate terms | Training-data mix not restated on the README (check the ICASSP 2022 paper; some public transcription datasets carry non-commercial terms) | Not stated on README (to measure) | README lists Core ML, TFLite and ONNX conversions → iPhone and Android paths exist | **SAFE** (weights covered by the repository licence; data provenance to record) | **Adopt for testing** — accompaniment stems first, then melody cross-check |
| [MT3](https://github.com/magenta/mt3) | Multi-instrument transcription | Apache-2.0 | **Not stated** (Colab checkpoints) | Not stated | Not stated; T5X transformer | Heavy | **UNVERIFIED** | Reject (heavy, unverified) |
| [Omnizart](https://github.com/Music-and-Culture-Technology-Lab/omnizart) | Notes, chords, beats, vocals, drums | MIT | **Not stated** | — | — | — | **UNVERIFIED** | Reject |
| [SOME](https://github.com/openvpi/SOME) | Sung vocal → MIDI notes | MIT | Releases page, **no separate terms**; optional RMVPE from another project | Not stated | Not stated | Conversion untested | **UNVERIFIED** (weights not separately licensed; dependency unverified) | Research comparison for melody |
| [RMVPE](https://github.com/yxlllc/RMVPE) | Vocal pitch from mixtures | **Not stated** | **Not stated** | MIR-1K, PTDB, M4Singer synth | — | ONNX export script | **UNVERIFIED** | Reject |
| [CREPE](https://github.com/marl/crepe) / [torchcrepe](https://github.com/maxrmorrison/torchcrepe) | Monophonic pitch | MIT | Not stated separately | — | tiny … full | Convertible | **UNVERIFIED** (weights) | Not needed (stems + current tracker) |
| [PESTO](https://github.com/SonyCSLParis/pesto) | Monophonic pitch, streaming | LGPL-3.0 | Not stated | MIR-1K | Small (ONNX ~0.7 ms/frame per README) | ONNX export | **UNVERIFIED** | Not needed |
| [FCPE](https://github.com/CNChTu/FCPE) | Pitch estimation | MIT | Not stated (Hugging Face + repo asset) | — | — | — | **UNVERIFIED** | Not needed |
| [ROSVOT](https://github.com/RickyL-2000/ROSVOT) | Singing transcription | MIT | Google Drive zip, trained only on M4Singer | M4Singer terms unverified | — | GPU research code | **UNVERIFIED** | Reject |
| [Sheet Sage](https://github.com/chrisdonahue/sheetsage) | Lead sheet from mix | MIT | **CC BY-NC-SA 3.0**; Jukebox ~10 GB, 12 GB GPU | HookTheory | — | Not feasible | **RESTRICTED** | Reject |
| TonePilot `MelodyExtractor` (current) | Predominant melody with bends | own | — | — | 0 | Shared core | SAFE | Keep; benchmark on real vocals vs Basic Pitch |
| TonePilot `ArpeggioLearner` (current) | Chord-relative broken-chord patterns | own | — | — | 0 | Shared core | SAFE | **Keep and extend** (100% degrees with correct inputs) |

## 4. Source separation

| Model | Code | Weights | Class | Notes |
|---|---|---|---|---|
| Demucs `htdemucs` (current) | MIT | README: "The license of the weights is not clear" (MUSDB research-only data) | **UNVERIFIED** | Works; keep for personal use; blocker for commercial release |
| Demucs `htdemucs_6s` (current) | MIT | Meta internal data; CC-NC-BY "likely" (README) | **RESTRICTED (likely)** | Same |
| BS-RoFormer / Mel-Band RoFormer ([ZFTurbo list](https://github.com/ZFTurbo/Music-Source-Separation-Training/blob/main/docs/pretrained_models.md)) | MIT (training code) | **No licence stated for any checkpoint**; community-trained; one multi-stem model trained only on MUSDB18-HQ | **UNVERIFIED** | Vocals SDR up to 10.98 on Multisong (vs htdemucs 9.00 on MUSDB HQ — different test sets, not comparable); no piano/guitar RoFormer listed |
| [Open-Unmix](https://github.com/sigsep/open-unmix-pytorch) | MIT | `umxl` **CC BY-NC-SA 4.0**; `umxhq` terms not stated (MUSDB data) | RESTRICTED / UNVERIFIED | Reject |
| [Spleeter](https://github.com/deezer/spleeter) | MIT | Not stated on README | **UNVERIFIED** | 5-stem includes piano; older, lower quality |

**Conclusion:** no separation checkpoint with verified commercial rights was found. Options for a commercial release: (a) written permission/licence for the Demucs weights, (b) train our own separator on licensed multitracks, (c) keep separation off for commercial builds. Not a blocker for the owner's personal builds.

## 5. Training data for a TonePilot-owned model

| Source | What | Licence | Class | Use |
|---|---|---|---|---|
| TonePilot's own synth patches | Rendered notes | Own | SAFE | Yes |
| GeneralUser GS | Rendered notes from 287 presets | Commercial music creation allowed; **silent on ML training**; sample origins not fully certain (licence text) | **UNVERIFIED for training** | Ask the author (S. Christian Collins) for written permission before training |
| [Slakh2100](https://github.com/ethman/slakh-utils) | 2 100 mixed tracks, per-instrument stems, MIDI, GM classes (145 h) | Not stated on the utils repo; dataset page (slakh.com / Zenodo) unreadable | **UNVERIFIED** | Ideal for "instrument in a separated stem" training once cleared |
| NSynth | ~300k single notes, 11 instrument families | Dataset page unreadable this session | **UNVERIFIED** | Ideal for family recognition once cleared |
| Owner's own recordings (Casio + app) | Real performances | Owner's rights | SAFE | Validation and Indian-instrument examples |
| Commercially licensed / CC0 music for validation | Real mixes | Per track (CC0 / CC BY only) | SAFE per track | Benchmark only, never shipped |

## 6. Ranking by practical TonePilot value

| Rank | Integration | Why | Size | Class |
|---|---|---|---|---|
| 1 | **Beat This! small** | Fixes the measured weakest input of Song Arpeggio (no-drum beats 0.52, meter 10/24); gives downbeats and bars; MIT weights | ~8.1 MB | SAFE |
| 2 | **Basic Pitch** on the accompaniment stem | Real note events → exact chord-relative patterns (register, duration, octave) instead of onset + harmonic-sum probing; same model can cross-check melody | Small (to measure) | SAFE |
| 3 | **TonePilot Timbre model** (own, trained on cleared data) | The only shippable route to instrument recognition and tone matching that beats 4/12 | ≤ 5 MB target | SAFE once data cleared |
| — | DSP upgrades (chords, structure, ToneMatcher method) | Measured gaps that need no model | 0 MB | SAFE |

## 7. Rejected (and why)

madmom models (CC BY-NC-SA) · MuQ / MuQ-MuLan (CC BY-NC) · Sheet Sage (CC BY-NC-SA, 10 GB) · Open-Unmix umxl (CC BY-NC-SA) · MERT (unverified + 95–330M params) · MT3, Omnizart, RMVPE, ROSVOT, All-In-One, BEATs, Spleeter, RoFormer checkpoints (weights terms not stated) · YAMNet (duplicates Apple's classifier) · any paid API.

## 8. How to clear the UNVERIFIED items (zero cost)

1. Allow `huggingface.co` and `zenodo.org` in the session's network settings (or read them in CI) and record the licence field of: `lukewys/laion_clap`, `microsoft/msclap`, `m-a-p/MERT-v1-95M`, Zenodo 3987831 (PANNs), Zenodo 8378278 (MS-CLAP), the Slakh2100 record, NSynth.
2. Email the GeneralUser GS author for written permission to train on renders.
3. Re-run the decision matrix: only items that turn SAFE **and** beat the TonePilot baseline in `TONEPILOT_BENCHMARK_PLAN.md` move forward.
