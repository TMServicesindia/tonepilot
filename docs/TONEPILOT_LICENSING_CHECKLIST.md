# TonePilot — Licensing Checklist

**Date:** 1 November 2026 · **Purpose:** a record per dependency, kept separately for **code**, **exact weights**, **runtime dependencies** and **training/evaluation data**, so that no uncleared model or dataset reaches a commercial build.

**SAFE\* is not commercial clearance.** It means the code and weights carry permissive licences from the original authors, but training-data provenance or attribution duties still need review. A commercial (paid or store) build requires every row it uses to be **Cleared**, with review sign-off by the owner or their adviser. Personal builds may use items marked "Personal only".

Status values: **Cleared** (all four records permissive, attribution done, reviewed) · **SAFE\*** (permissive code + weights; data/provenance review pending) · **Personal only** · **Rejected** · **Unverified**.

## 1. Records for every dependency

| Item | Code licence (source) | Exact weights + licence (source) | Runtime deps | Training data and terms | Attribution duty | Commercial status | Next action |
|---|---|---|---|---|---|---|---|
| Demucs `htdemucs` (shipping) | MIT ([repo](https://github.com/adefossez/demucs)) | `htdemucs` from dl.fbaipublicfiles; README: "license of the weights is not clear" | demucs.cpp MIT, Eigen MPL-2.0 | MUSDB18-HQ **"other-nc"** (Zenodo 3338373) + 800 internal songs | — | **Personal only** | Permission request (Phase 1) |
| Demucs `htdemucs_6s` (shipping) | MIT | Meta internal data; README: CC-NC-BY "likely" | as above | Internal | — | **Personal only** | Permission request (Phase 1) |
| GeneralUser GS (shipping) | — | SoundFont: "use … without restriction for your own music creation, private or commercial"; "use it in your software projects" ([licence](https://github.com/mrbumpy409/GeneralUser-GS/blob/main/documentation/LICENSE.txt)) | — | Author can't verify every sample's origin; **silent on ML training** | Credit in app (done) | **Cleared for playback**; training use **Unverified** | Ask author re training (Phase 1) |
| LAME 3.100 (shipping) | LGPL | — | — | — | LGPL notice + relinkable object/source offer | Cleared with LGPL obligations | Confirm static-link compliance package |
| Apple SoundAnalysis / Core ML (shipping) | Apple SDK | Apple | — | — | — | Cleared | — |
| Beat This! small (candidate) | MIT ([README](https://github.com/CPJKU/beat_this)) | `small*` checkpoint (authors' cloud), MIT per README | PyTorch (conversion only) | 16 datasets; README: some files "fully copyrighted or under limited Creative Commons licenses"; annotations CC BY 4.0 (Zenodo 13922116) | MIT notice | **SAFE\*** | Record exact checkpoint hash; data review before commercial |
| Basic Pitch (candidate) | Apache-2.0 ([repo](https://github.com/spotify/basic-pitch)) | `icassp_2022` model files in repo; LiteRT `basicpitch.tflite` (Apache-2.0, `litert-community/Basic-Pitch-LiteRT`) | LiteRT (Apache-2.0) | Per ICASSP 2022 paper (to record) | Apache NOTICE | **SAFE\*** | Record training sets; hash files |
| BTC chords (candidate) | MIT ([repo](https://github.com/jayg996/BTC-ISMIR19)) | `btc_model.pt`, `btc_model_large_voca.pt` (12.2 MB each) in MIT repo; HF re-package says unchanged | PyTorch (conversion only) | Isophonics, Robbie Williams, UsPop2002 annotations; audio collected by authors | MIT notice | **SAFE\*** | Data review |
| All-In-One (comparison) | MIT ([repo](https://github.com/mir-aidj/all-in-one)) | `all-fold*.pth` 1.4 MB each, MIT on author's HF (`taejunkim/allinone`) | NATTEN (licence to record), Demucs (see above) | Harmonix Set annotations | MIT notice | **SAFE\*** (blocked in practice by Demucs dependency) | Check NATTEN licence |
| LAION-CLAP music (comparison) | Apache-2.0 / CC0 | `laion/larger_clap_music` `pytorch_model.bin` (776 MB) Apache-2.0; `lukewys/laion_clap` CC0-1.0 | transformers (Apache-2.0) | LAION-Audio-630k + music data; LAION: dataset not releasable "due to copyright reasons" | Apache NOTICE | **SAFE\*** | Data review before commercial |
| PANNs (comparison) | MIT | Zenodo 3987831, **CC BY 4.0** | — | AudioSet (YouTube audio; labels CC BY 4.0) | Attribution | **SAFE\*** | — |
| Microsoft CLAP (comparison) | MIT | MS-PL (HF), CC BY 3.0 US (Zenodo 8378278) | — | Not stated | Attribution | **SAFE\*** | — |
| ByteDance piano / YourMT3 (offline reference only) | MIT / Apache-2.0 | MIT (author HF) / Apache-2.0 | — | MAESTRO (CC BY-NC-SA) and others | — | **Benchmark use only, never shipped** | — |
| LiteRT runtime (Phase 1) | Apache-2.0 | — | — | — | NOTICE | Cleared (after notice added) | Add to attribution file |
| ONNX Runtime (if used) | MIT | — | — | — | Notice | Cleared (after notice added) | — |
| `mir_eval` (CI only) | MIT | — | — | — | — | Cleared (not shipped) | — |

## 2. Training and evaluation data

| Dataset | Licence (source) | Use allowed | Attribution | Status |
|---|---|---|---|---|
| NSynth | CC BY 4.0 (magenta.tensorflow.org) | Train + evaluate | Required | SAFE\* (record citation) |
| Slakh2100 | CC BY 4.0 (Zenodo 4599666, slakh.com) | Train + evaluate | Required | SAFE\* |
| GuitarSet | CC BY 4.0 (upstream Zenodo via `jhartquist/guitarset`) | Evaluate (train possible) | Required | SAFE\* |
| PDMX multi-instrument synthesized | CC0 audio, CC BY captions | Train + evaluate | Captions only | SAFE\* |
| Beat This! annotations | CC BY 4.0 (Zenodo 13922116) | Evaluate | Required | SAFE\* |
| OpenMIC-2018 | CC BY 4.0 labels; audio from FMA with per-track licences | Evaluate only after per-track check | Per track | Unverified per track |
| Carnatic sets (`monodox/*`, `kaumudi-ai/*`) | CC BY 4.0 tags; production method undocumented | Evaluate only after provenance check | Required | Unverified |
| Owner recordings | Owner's rights | Train + evaluate | — | Cleared (owner) |
| MUSDB18-HQ | "other-nc" (Zenodo 3338373) | **Not for commercial training** | — | Rejected |
| Mridangam stroke | CC BY-NC 4.0 | No | — | Rejected |
| ccmusic-database sets | CC BY-NC-ND 4.0 | No | — | Rejected |
| MAESTRO | CC BY-NC-SA 4.0 | Benchmark reference only | — | Rejected for training |

## 3. Rejected models (verified non-commercial or unverified)

Non-commercial: madmom models (CC BY-NC-SA 4.0), Essentia models (CC BY-NC-SA 4.0; commercial licence on request), MERT (CC BY-NC 4.0), MuQ/MuQ-MuLan (CC BY-NC 4.0), FCPE (CC BY-NC-SA 4.0), Sheet Sage (CC BY-NC-SA 3.0), Open-Unmix umxl (CC BY-NC-SA 4.0). Unverified weights: MT3, SOME, RMVPE, ChordMini, RoFormer checkpoints (including re-hosts tagged MIT by non-authors), Spleeter, community instrument classifiers.

## 4. Commercial-build gate (Phase 1 deliverable)

1. `docs/LICENSES/manifest.json` lists every shipped file with its SHA-256, the licence for each of the four records, status and reviewer.
2. CI fails a commercial build if any shipped or downloadable model or data file is not **Cleared**.
3. The app's About screen and an attribution file include all MIT/Apache/LGPL/CC BY notices.
4. Personal builds are labelled as such and may include "Personal only" items.

## 5. Evidence

Licence facts for Hugging Face and Zenodo items come from the hosts' public APIs, captured in `docs/research/model_scan.md` / `.json` (generated by `Native/tools/research/hf_scan.py` in CI on 1 Nov 2026). GitHub facts come from each repository's README or licence file, linked above.
