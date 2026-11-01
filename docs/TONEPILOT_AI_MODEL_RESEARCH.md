# TonePilot — AI Model Research (revision 2)

**Date:** 1 November 2026 · **Revision 2** adds the Hugging Face and Zenodo licence scan (`docs/research/model_scan.md`, generated in CI by `Native/tools/research/hf_scan.py` from the hosts' public APIs) and the owner's Phase 0 review.

**Rule applied:** a model is recommended only if (1) its code **and exact weights** have verified commercial-use and redistribution rights, (2) it beats the current TonePilot implementation on independent test data, and (3) the same gain can't be had more cheaply with existing models, DSP or music theory. Zero paid APIs; offline-first; every model needs an Android path.

**Bottom line (revised):**

- **Song Arpeggio inputs.** Test *Beat This! small* (MIT, ~8 MB) for beats and downbeats. Test *All-In-One* (MIT, 1.4 MB per fold, from the authors' own page) as a structure and downbeat comparison. Test the *BTC chord model* (MIT repository, 12 MB) against improved DSP chords.
- **Accompaniment notes.** Test *Basic Pitch* (Apache-2.0, 0.84 MB LiteRT) against the existing learner, stem by stem. The heavy piano and multi-instrument transcribers (ByteDance piano 172 MB, YourMT3 2.7 GB) serve only as offline reference "upper bounds" in the benchmark, never on the phone.
- **Instruments and tones.** *LAION-CLAP music* is now **verified Apache-2.0** (`laion/larger_clap_music`). It competes with a small TonePilot-trained model whose training data is now clearable: **NSynth (CC BY 4.0, real instrument samples)** and **Slakh2100 (CC BY 4.0)**. Both are research until the benchmark decides.
- **Current separation.** Demucs's weights are **confirmed problematic**: MUSDB18-HQ, part of its training data, is licensed "other-nc" on Zenodo, and the Demucs README says the weight licence "is not clear".

## Classification key

| Class | Meaning | Shippable? |
|---|---|---|
| **SAFE** | FREE & COMMERCIALLY SAFE: code and exact weights carry a licence permitting commercial use and redistribution, stated by the original authors | Yes, after benchmark |
| **SAFE\*** | As SAFE, but training data includes copyrighted or non-commercial material; record it, have it reviewed before a store release | Yes, with recorded caveat |
| **RESTRICTED** | Non-commercial / research-only / proprietary-on-request | No |
| **UNVERIFIED** | Weights terms missing, or only claimed by a re-uploader | No (research only) |
| **PAID** | Needs payment or a commercial licence | No |

A licence claimed by a **re-uploader** (someone other than the original authors) is not accepted as proof; the original source decides.

---

## 1. Rhythm, beats, downbeats, structure

| Model | Task | Code | Weights (source) | Data terms | Size | iPhone / Android | Class | Recommendation |
|---|---|---|---|---|---|---|---|---|
| [Beat This!](https://github.com/CPJKU/beat_this) | Beats + downbeats, no DBN | MIT | **MIT**, README: "The code and the published model weights are released under the MIT license" | README: some training files "fully copyrighted or under limited Creative Commons licenses"; annotations/spectrograms on Zenodo 13922116 are CC BY 4.0 | `small` ~8.1 MB, `final` ~78 MB (README) | PyTorch transformer; Core ML and ONNX conversion **untested** | **SAFE\*** | **Test first** |
| All-In-One ([code](https://github.com/mir-aidj/all-in-one), [weights](https://huggingface.co/taejunkim/allinone)) | Beats, downbeats, functional segments (intro/verse/chorus/bridge/inst/solo/outro) | MIT | **MIT** on the author's Hugging Face repo (`taejunkim/allinone`) | Harmonix Set annotations; audio not distributed | **1.4 MB per fold**, 8 folds | Needs NATTEN (neighbourhood attention) and Demucs-separated input: conversion feasibility **unknown, likely hard** | **SAFE\*** | **Test as comparison** for structure and downbeats; adopt only if convertible and better |
| [madmom](https://github.com/CPJKU/madmom) | Beats, downbeats, chords | BSD | **CC BY-NC-SA 4.0** (README) | — | — | — | RESTRICTED | Reject |
| Essentia models | Tagging, rhythm | AGPL lib | **CC BY-NC-SA 4.0**, "proprietary license upon request" (essentia.upf.edu/models) | — | — | — | RESTRICTED / PAID | Reject |
| TonePilot `TempoAnalyzer` (current) | Tempo + beats | own | — | — | 0 | Shared core | SAFE | Keep as fallback and tempo cross-check |
| TonePilot `StructureAnalyzer` (current) | Boundaries, repeats, labels | own | — | — | 0 | Shared core | SAFE | Improve (DSP) |

## 2. Chords and harmony

| Model | Task | Code | Weights (source) | Data terms | Size | iPhone / Android | Class | Recommendation |
|---|---|---|---|---|---|---|---|---|
| [BTC](https://github.com/jayg996/BTC-ISMIR19) (Bi-directional Transformer for Chords, ISMIR 2019) | Frame-level chords; maj/min or large vocabulary | MIT (repository) | Model files ship in the MIT repository; re-packaged by `puar-playground/btc-chord` (MIT, "architecture unchanged from the official release") | Isophonics, Robbie Williams, UsPop2002 annotations; audio "collected from online music service providers" (README) | 12.2 MB (`btc_model.pt`), 12.2 MB large-vocab | Small transformer: Core ML/ONNX conversion **untested** | **SAFE\*** | **Test against improved DSP chords** |
| ChordMini ChordNet 2E1D ([app](https://github.com/ptnghia-j/ChordMiniApp), [ONNX](https://huggingface.co/musetric/chordmini-onnx)) | Chords, ~2.3M params | MIT (app repo) | ONNX re-upload says weights are MIT "per upstream LICENSE"; upstream README doesn't state the weights' licence; trained with pseudo-labels from other models | Not stated | 17 MB ONNX | ONNX exists | **UNVERIFIED** | Research comparison only |
| TonePilot `HarmonyAnalyzer` (current) | Key + 24 triads, beat-level Viterbi | own | — | — | 0 | Shared core | SAFE | **Improve first** (bass-aware, key-aware, beat-level changes) |

## 3. Accompaniment transcription and melody

| Model | Task | Code | Weights (source) | Data terms | Size | iPhone / Android | Class | Recommendation |
|---|---|---|---|---|---|---|---|---|
| [Spotify Basic Pitch](https://github.com/spotify/basic-pitch) | Instrument-agnostic polyphonic notes with bends | Apache-2.0 | Model files inside the Apache-2.0 repo; official HF card Apache-2.0; LiteRT build `litert-community/Basic-Pitch-LiteRT` Apache-2.0 | Training-data mix per ICASSP 2022 paper (record before release) | **0.84 MB** (`basicpitch.tflite`) | README lists Core ML, TFLite, ONNX; LiteRT card reports Pixel 8a and Galaxy S26 benchmarks → **Android path verified**, iPhone via Core ML (to measure) | **SAFE\*** | **Test against the existing learner, per stem** |
| ByteDance piano transcription ([HF re-upload](https://huggingface.co/asigalov61/bytedance_piano_transcription), author repo `qiuqiangkong/piano_transcription` MIT) | Piano notes + pedal (high accuracy on piano) | Apache-2.0 / MIT | Author's HF repo MIT (`conformer2d`, 628 MB); CRNN re-upload Apache-2.0 (172 MB) | MAESTRO (CC BY-NC-SA 4.0) | 172–628 MB | Too large for the phone | SAFE\* (author repo) | **Offline reference only** (benchmark upper bound for piano stems) |
| YourMT3 (`mimbres/YourMT3`) | Multi-instrument transcription | Apache-2.0 | Apache-2.0 (HF card) | Slakh, MAESTRO and others | 2.77 GB | Not feasible on device | SAFE\* | **Offline reference only** |
| [MT3](https://github.com/magenta/mt3) | Multi-instrument transcription | Apache-2.0 | Not stated | Not stated | — | Heavy | UNVERIFIED | Reject |
| [SOME](https://github.com/openvpi/SOME) | Sung vocal → MIDI | MIT | Releases, no separate terms | Not stated | — | Untested | UNVERIFIED | Research only |
| RMVPE (via `lj1995/VoiceConversionWebUI`, MIT) | Vocal pitch in mixtures | — | Hosted in the RVC repo (MIT) but RMVPE's own repo states no licence | MIR-1K, PTDB, M4Singer synth | — | ONNX export exists | UNVERIFIED | Research only |
| FCPE (`ChiTu/FCPE`) | Pitch estimation | MIT | **CC BY-NC-SA 4.0** (HF card) | — | 43 MB | — | RESTRICTED | Reject |
| [PESTO](https://github.com/SonyCSLParis/pesto), [CREPE](https://github.com/marl/crepe) | Monophonic pitch | LGPL-3.0 / MIT | Not stated | — | small | ONNX | UNVERIFIED | Not needed |
| [Sheet Sage](https://github.com/chrisdonahue/sheetsage) | Lead sheet | MIT | CC BY-NC-SA 3.0 | HookTheory | 10 GB with Jukebox | No | RESTRICTED | Reject |
| TonePilot `ArpeggioLearner` (current) | Chord-relative patterns | own | — | — | 0 | Shared core | SAFE | **Keep and extend** |
| TonePilot `MelodyExtractor` (current) | Melody with bends | own | — | — | 0 | Shared core | SAFE | Keep; benchmark vs Basic Pitch on vocals |

## 4. Instrument recognition and tone matching

| Model | Task | Code | Weights (source) | Data terms | Size | iPhone / Android | Class | Recommendation |
|---|---|---|---|---|---|---|---|---|
| **LAION-CLAP music** ([`laion/larger_clap_music`](https://huggingface.co/laion/larger_clap_music); original checkpoints [`lukewys/laion_clap`](https://huggingface.co/lukewys/laion_clap) CC0-1.0) | Audio–text embeddings: zero-shot instrument descriptions; audio-to-audio similarity for tone retrieval | Apache-2.0 / CC0 | **Apache-2.0** (HF card, LAION's own repo) | LAION-Audio-630k and music data; LAION states the training set can't be released "due to copyright reasons" | 776 MB full model (fp32, audio + text); audio branch only on device: **size to measure** (text side pre-computed at build time) | Core ML/ONNX: an ONNX port exists (`Xenova/clap-htsat-unfused`, general model); music model conversion **untested** | **SAFE\*** | **Test** as recognition + retrieval engine; risk = size |
| Microsoft CLAP (`microsoft/msclap`) | Audio–text embeddings | MIT | MS-PL (HF card); CC BY 3.0 US (Zenodo 8378278) | Not stated | 4.7 GB repo (all versions) | Repo archived | SAFE\* | Secondary comparison only |
| PANNs (Zenodo 3987831) | AudioSet tagging, 527 classes | MIT | **CC BY 4.0** (Zenodo) | AudioSet (YouTube audio; labels CC BY 4.0) | Cnn14 ~300 MB class; smaller variants in the record | Convertible CNN (untested) | SAFE\* | Comparison only (general-audio labels, like Apple's) |
| AST (`MIT/ast-finetuned-audioset-10-10-0.4593`) | AudioSet tagging | BSD-3 | BSD-3 (HF card) | AudioSet | 693 MB repo | Too large | SAFE\* | Reject (size, general audio) |
| MERT v1 95M / 330M | Music representation | Apache-2.0 | **CC BY-NC 4.0** (HF card) | — | 1.7 / 5.3 GB repos | — | RESTRICTED | Reject |
| MuQ / MuQ-MuLan | Music representation, text–music | MIT | **CC BY-NC 4.0** (README + HF card) | — | ~2.7 GB | — | RESTRICTED | Reject |
| Community instrument classifiers (`onnx-community/Musical-Instrument-Classification-ONNX` MIT, `dima806/musical_instrument_detection` Apache-2.0) | Instrument classes | — | Licences as tagged; provenance and training data undocumented | Unknown | 1.1–1.9 GB | Large | UNVERIFIED (provenance) | Reject |
| Apple SoundAnalysis (current) | Everyday sounds incl. instruments | SDK | SDK | — | 0 | iOS only | SAFE | Keep as free iOS prior; **14/19 measured** |
| **TonePilot Timbre model** (own) | Instrument family/instrument + embedding | own | own | **NSynth (CC BY 4.0, real instrument samples)**, **Slakh2100 (CC BY 4.0)**, PDMX synthesized (CC0 audio), own recordings, GeneralUser renders *only with the author's permission* | ≤ 5 MB target (estimate) | Core ML + LiteRT/ONNX | SAFE\* once trained | **Research**, compete with CLAP in the benchmark |

**Indian instruments:** still no commercially licensed instrument-labelled Indian corpus found. CC BY 4.0 Carnatic sets exist on Hugging Face (`monodox/carnatic-raga-vocals`, `monodox/carnatic-gamaka-annotations`, `monodox/carnatic-mridangam-strokes`, `monodox/carnatic-tala-kriyanga`, `kaumudi-ai/carnatic-ragas-talas`), but their cards don't document how the audio was produced. **Inspect provenance (real recordings vs generated) before use**; they are candidates for vocal ornament and tala evaluation, not instrument identity. Claims stay at family level.

## 5. Source separation

| Model | Code | Weights | Data | Class |
|---|---|---|---|---|
| Demucs `htdemucs` (current) | MIT | README: weight licence "is not clear" | MUSDB18-HQ is **"other-nc"** on Zenodo 3338373 + 800 extra songs | **UNVERIFIED (non-commercial data)** |
| Demucs `htdemucs_6s` (current) | MIT | Meta internal data; CC-NC-BY "likely" (README) | Internal | **RESTRICTED (likely)** |
| RoFormer community checkpoints | MIT (training code) | No licence per checkpoint; a 128 GB re-host (`Politrees/UVR_resources`) tags MIT, but a re-uploader can't license others' weights | Mostly unknown | UNVERIFIED |
| Open-Unmix `umxl` / `umxhq` | MIT | CC BY-NC-SA 4.0 / not stated (MUSDB) | MUSDB | RESTRICTED |
| Spleeter | MIT | Not stated on README | — | UNVERIFIED |
| **Own separator trained on Slakh2100 (CC BY 4.0) + PDMX synthesized (CC0)** | own | own | Licensed | SAFE (quality on real recordings unknown; long-term option) |

## 6. Training and evaluation data (verified)

| Dataset | Licence (source) | Real or synthetic | Use |
|---|---|---|---|
| NSynth | **CC BY 4.0** (magenta.tensorflow.org) | Real notes from 1 006 instruments, commercial sample libraries | Timbre model training, family recognition |
| Slakh2100 | **CC BY 4.0** (Zenodo 4599666, slakh.com) | Sample-based renders of 2 100 MIDI songs, per-instrument stems + MIDI | Training/eval: instrument-in-stem, transcription, separation |
| GuitarSet | **CC BY 4.0** (`jhartquist/guitarset`, upstream Zenodo) | Real acoustic guitar with note annotations | **Real-audio accompaniment transcription test** |
| Beat This! annotations / spectrograms | CC BY 4.0 (Zenodo 13922116) | Annotations | Beat/downbeat references |
| PDMX multi-instrument synthesized | CC0 audio, CC BY captions | Synthesized | Training |
| OpenMIC-2018 (DynamicSuperb copy) | CC BY 4.0 tag | Real (FMA tracks, mixed CC licences per track) | Instrument presence evaluation (check per track) |
| MUSDB18-HQ | "other-nc" (Zenodo) | Real | **Not usable** commercially |
| Mridangam stroke | CC BY-NC 4.0 (Zenodo 1265188) | Real | **Not usable** commercially |
| ccmusic-database instrument sets | CC BY-NC-ND 4.0 | Real | **Not usable** |
| Carnatic sets (monodox, kaumudi-ai) | CC BY 4.0 (tags) | **Unknown — inspect** | Possible evaluation only after provenance check |

## 7. Ranking by TonePilot value (revised)

| Rank | Candidate | Serves | Size | Class | Status |
|---|---|---|---|---|---|
| 1 | Beat This! small | Beat grid, downbeats, cycles (Song Arpeggio) | ~8 MB | SAFE\* | Test (Phase 2) |
| 2 | Improved DSP chords + BTC comparison | Chord degrees (Song Arpeggio) | 0 / 12 MB | SAFE / SAFE\* | Test (Phase 3) |
| 3 | Basic Pitch vs existing learner | Accompaniment note events | 0.84 MB | SAFE\* | Test (Phase 4) |
| 4 | All-In-One | Structure labels, downbeats | 1.4 MB/fold | SAFE\* | Comparison (Phase 2) |
| 5 | LAION-CLAP music vs TonePilot Timbre model | Instruments and tones | to measure / ≤5 MB | SAFE\* | Research (Phase 6) |

## 8. Rejected

Verified non-commercial: madmom models, Essentia models, MERT, MuQ/MuQ-MuLan, FCPE, Sheet Sage, Open-Unmix umxl, MUSDB18-HQ, Mridangam stroke, ccmusic-database. Unverified weights: MT3, SOME, RMVPE, PESTO, CREPE, ChordMini, RoFormer checkpoints, Spleeter, community instrument classifiers. Too large for the phone (reference only): ByteDance piano, YourMT3, AST, Microsoft CLAP. Paid APIs: all.
