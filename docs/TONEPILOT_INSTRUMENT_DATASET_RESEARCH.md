# TonePilot — Instrument Dataset Research (accuracy-first Instrument Analyser)

**Date:** 2 November 2026. **Status:** research and audit only. Nothing has been downloaded, trained or changed in production for this document.

**Evidence labels:**
- **VERIFIED** = stated by the official source, or found consistently in the dataset's own metadata;
- **SECONDARY** = stated by a third party (mirdata, mirrors, papers about the dataset);
- **INFERENCE** = our reasoning;
- **UNKNOWN** = could not be confirmed.

**Method limit:** this session's network blocks Zenodo, Hugging Face and most dataset hosts, so facts come from web-search results of those pages. Every UNKNOWN licence is **excluded from commercial training** until it is checked at the source.

**Rule applied:** a dataset being downloadable gives TonePilot no training rights. Code, weights, audio, labels and annotations are recorded separately.

## 1. Summary

| Dataset | Indian domain | Polyphonic | Temporal labels | Audio licence | Commercial ML training | Recommended use |
|---|---|---|---|---|---|---|
| **Sanidha** (GT, 2024) | **Yes (Carnatic)** | Yes, multitrack, minimal bleed | Derivable from clean stems | **CC BY 4.0** (VERIFIED: homepage + paper) | **Permitted with attribution** (INFERENCE from CC BY 4.0; confirm on files) | **Train / DEV / TEST, split by concert session**; highest priority |
| Saraga Carnatic / Hindustani 1.5 (Zenodo 4301737) | Yes | Carnatic multitrack (168 of 249 tracks) | Sections, tempo, rhythm; stems (with bleed) | **NC**: CC BY-NC 4.0 (paper) vs CC BY-NC-SA 4.0 (OpenAIRE, mirdata), **contradictory** | **Prohibited** without permission | **Evaluation-only research, pending legal view** (commercial-company internal evaluation may count as commercial use) |
| Saraga Audiovisual (Zenodo 17405610) | Yes (Carnatic vocal concerts, 42 concerts, > 60 h) | Multitrack + mixtures | UNKNOWN | CC BY 4.0 listed for the **record/paper**; file-level licence **UNKNOWN** | **UNKNOWN** until confirmed | Investigate first (could be the largest permissive Indian source) |
| NSynth | No | No (single notes) | Note-level | CC BY 4.0 (VERIFIED, existing register) | Permitted with attribution | Train (timbre, family, source type); already used in v3–v4 |
| Slakh2100 | No | Yes (rendered MIDI), 34 classes | Exact (MIDI-aligned) | CC BY 4.0 (existing register: Zenodo 4599666, slakh.com; re-confirm on the release files) | Permitted with attribution | Train layered and temporal detection (synthetic domain) |
| OpenMIC-2018 (Zenodo 1432913) | No | Yes (real CC music, 10 s) | Clip-level, **partial** labels | Dataset CC BY 4.0 (VERIFIED); **audio per-track licences** in `openmic-2018-metadata.csv` | Only for tracks whose own licence permits | Train / DEV on a per-track-filtered subset; unlabelled ≠ absent |
| FSD50K (Zenodo 4060432) | Few | Mostly single events | Clip-level | **Per clip:** about 19.9k CC0, 23.5k CC-BY, 6.0k CC-BY-NC, 1.8k Sampling+ (VERIFIED counts from the record) | CC0/CC-BY clips only; commercial use of the curated dataset says "contact the authors" | Supplementary training, filtered to CC0/CC-BY music classes |
| MedleyDB | No | Yes, multitrack | **Instrument activations** | Non-commercial (VERIFIED: release announcement); subsets CC BY-NC-SA 4.0 (SECONDARY) | **Prohibited** | Research evaluation of timing only, if permitted; not for commercial training |
| HamNava | No (Persian) | Yes, multi-label, soft labels | Clip-level | **UNKNOWN.** The TISMIR *article* is CC BY 4.0; the dataset terms weren't found. The owner's brief says non-commercial (**contradiction**) | UNKNOWN, so excluded | Method reference (soft labels, cross-cultural); request terms |
| IRMAS | No | Predominant instrument in mixtures | Clip-level | CC BY-NC-SA 3.0 (SECONDARY: mirdata) | **Prohibited** | Not used |
| CompMusic Tabla Solo | Yes (tabla) | Solo | Bol transcriptions | **Restricted:** copyrighted commercial audio, non-commercial research only, no redistribution (Zenodo 1267023) | **Prohibited** | Not used for training |
| CompMusic Mridangam Stroke | Yes | Solo strokes | Stroke labels | CC BY-NC 4.0 (existing register) | **Prohibited** | Not used |
| CompMusic Mridangam Tani-avarthanam | Yes | Solo | Strokes (about 8,800) | UNKNOWN | UNKNOWN, so excluded | Ask CompMusic |
| Four-Way Tabla (mirdata) | Yes | Solo | Stroke onsets | CC BY 3.0 (SECONDARY: mirdata) | Likely permitted with attribution (confirm) | Candidate for tabla stroke/timbre training |
| AudioSet | Partial (classes Tabla, Sitar, …) | Yes (YouTube) | Clip-level | Labels CC BY 4.0, **ontology CC BY-SA 4.0** (VERIFIED: Google download page); **audio not distributed**, YouTube copyright per video | **Audio: prohibited** (YouTube rule + copyright) | Ontology/labels as a reference only. TonePilot never downloads AudioSet audio. The pretrained models we use were trained on it (see the model document) |
| Wikimedia Commons Indian instruments (our survey, 1 Nov) | Yes | Mostly solo | None | Per file (our survey classes: eligible / review / excluded) | Eligible files only (CC0/CC BY/CC BY-SA, after listening verification) | Train / DEV for solo Indian timbre; owner listening check pending |
| Owner recordings (Casio, voluntary musicians with written permission) | Yes | As recorded | Owner-annotated | Owner's rights / written permission | Permitted | Train / DEV / acceptance; Casio imitations **always labelled `imitation`, never as the real instrument** |

## 2. Dataset records (by priority)

### 2.1 Sanidha (highest priority)

- **Source:** https://ccml.gtcmt.gatech.edu/data/Sanidha/ · paper arXiv 2501.06959 (ISMIR 2024; Krishnan, Alben, Nair, Condit-Schultz).
- **Content (VERIFIED, homepage):**
  - studio-quality Carnatic multitrack;
  - about **8 hours, 5 concert sessions**, 2–5 performers each;
  - tracks: Violin-1/2, mridangam (2 mics), ghatam (2 mics), tanpura, vocals;
  - "minimal to no overlap or bleed" (unlike Saraga, which has significant leakage).
- **Licence (VERIFIED):** CC BY 4.0. The audio and annotation split is not separately stated (UNKNOWN; confirm per file).
- **Access:** hosted on a Georgia Tech server. It **requires a free GT guest account and VPN** after an email exchange. **Permission step:** an access request email (a draft is needed; it will not be sent without the owner's approval).
- **Why it matters:** **the only verified permissive, real, Indian-domain polyphonic multitrack source found.** Clean stems give **strong temporal labels** (stem activity → instrument active / inactive) for violin, mridangam, ghatam, tanpura and voice, and real mixtures for multi-label detection.
- **Limits:**
  - Carnatic concert music, not film orchestration;
  - 5 sessions is a small number of performers, so splits must be **session-disjoint** (e.g. 3 / 1 / 1), and results carry wide confidence intervals;
  - activity labels derived from stems are *derived*, so a human spot-check is required before they count as ground truth.
- **Size (ESTIMATE):** 8 h × about 7 tracks of uncompressed audio, about **20–35 GB**. This exceeds a GitHub runner's free disk, so plan a per-session download, convert to 32 kHz mono FLAC, and keep only the manifest and hashes in the repository.

### 2.2 Saraga 1.5 (Carnatic and Hindustani)

- **Source:** https://mtg.github.io/saraga/ · Zenodo 4301737 · https://github.com/MTG/saraga.
- **Content (VERIFIED/SECONDARY):**
  - 249 Carnatic and 108 Hindustani recordings, about 96 h in total;
  - 168 Carnatic tracks with multitrack stems: lead voice, violin, secondary voice, mridangam left/right, ghatam;
  - sections, tempo and rhythm annotations.
- **Licence:** non-commercial. **Contradiction:** CC BY-NC 4.0 (paper) vs CC BY-NC-SA 4.0 (OpenAIRE, mirdata). Not resolved here; check the Zenodo "Rights" field.
- **Commercial training: prohibited** without written permission from MTG/UPF and the artists.
- **Recommended use:**
  - **none until the owner decides** whether internal evaluation by a (potentially commercial) product is acceptable under NC;
  - a permission request to MTG is an option.
- Stems have significant bleed (per the Sanidha paper), so labels derived from stem energy need care.

### 2.3 Saraga Audiovisual

- **Source:** Zenodo 17405610 · UPF repository record.
- **Content:** 42 Carnatic concerts, > 60 h; multitrack audio + mixtures; metadata; video for some concerts. The abstract says all concerts have video; the Zenodo description says three samples (contradiction).
- **Licence:** CC BY 4.0 is listed for the record/paper. **Whether the audio files themselves are CC BY 4.0 is UNKNOWN.**
- **Action:** verify the licence on the Zenodo record files before any download. If the audio is CC BY 4.0, this becomes the **largest permissive Indian-domain source** (INFERENCE).

### 2.4 NSynth — already in use

- 305,979 notes, 1,006 instruments; family + source (acoustic / electronic / synthetic) labels; instrument-disjoint splits; CC BY 4.0.
- Use: timbre and source-type training (v3 showed real-note training raised NSynth-test selective accuracy 33% → 87%). Not polyphonic.

### 2.5 Slakh2100

- 2,100 rendered-MIDI multitracks, 145 h, 34 classes, stems + aligned MIDI; CC BY 4.0 (existing register).
- Use: layered and temporal training with exact activity labels. The domain is synthetic: report it separately and never as real accuracy.

### 2.6 OpenMIC-2018

- 20,000 × 10 s real CC music clips from FMA; 20 classes; **partial labels**.
- Dataset CC BY 4.0; each track's own licence is in `openmic-2018-metadata.csv`.
- **Loss must mask unlabelled classes** (unlabelled ≠ negative).
- Filter to tracks whose licence permits commercial use (CC BY / CC BY-SA / CC0; exclude NC and ND).

### 2.7 FSD50K

- 51,197 clips, 200 AudioSet classes, per-clip Freesound licences.
- **Use only CC0 / CC-BY clips** (about 43k across all classes; music-instrument classes are a subset, counts to be computed from the metadata).
- The curated dataset is CC BY, but the authors ask to be contacted for commercial use, so record that request as a permission step.

### 2.8 MedleyDB, IRMAS, CompMusic tabla/mridangam, HamNava

- **Non-commercial or restricted:** MedleyDB, IRMAS, Tabla Solo, Mridangam Stroke. **Not used for training.** MedleyDB's activation annotations are the best public timing benchmark; use it only if its terms allow our use (to confirm).
- **Unknown:** Tani-avarthanam and HamNava dataset terms. Excluded until confirmed.
- **Four-Way Tabla:** CC BY 3.0 (secondary). A candidate for tabla timbre; confirm at the source.

## 3. What we are missing

| Need | Gap | Zero-budget route |
|---|---|---|
| **Indian film orchestration** (dense, mixed, modern production) | No public permissive dataset exists | Owner recordings; voluntary musicians with written permission; film audio only after the legal check and only for **evaluation** |
| Bansuri, nadaswaram, shehnai, sitar, veena, santoor, sarangi, harmonium, dholak, thavil, kanjira, dhol | Sanidha covers only violin, mridangam, ghatam, tanpura and voice. Commons survey: tabla 21, veena 28, viola 17, dholak 10, mridangam 1, thavil 1, nadaswaram 1 eligible files; **none** for ghatam, dhol, bansuri, shehnai, sitar, santoor, tanpura, sarangi or harmonium | Freesound CC0/CC-BY search per instrument (per-file licence); musician contributions; Casio imitations labelled as imitations |
| Acoustic vs imitation **pairs** (same phrase) | None | Owner records the same phrase on a real instrument (a volunteer musician) and on the Casio |
| Role labels (lead / counter-melody / harmony / bass / rhythm / drone / texture) | None in any public dataset | Owner/musician annotation, using the existing schema plus a new `role` field |
| Human-verified temporal labels on Indian music | None verified | Derive from Sanidha stems, then human spot-check |

## 4. Exact permission requirements (drafts only; nothing sent without the owner's approval)

1. **Sanidha:** a GT guest-account / VPN access request. Licence already permissive.
2. **Saraga 1.5:** permission from MTG/UPF for (a) commercial-product evaluation and (b) training. The NC licence otherwise bars both for a commercial product (INFERENCE; legal view needed).
3. **Saraga Audiovisual:** confirm the file-level licence (no permission needed if the files are CC BY 4.0).
4. **FSD50K:** the authors' note on commercial use of the curated set; we only use the CC0/CC-BY clips.
5. **HamNava, Tani-avarthanam:** request the terms.
6. **Musicians:** the existing letter template (`docs/outreach/MUSICIAN_PERMISSION_LETTER.md`), per recording.
7. **Film recordings:** legal check (already an open owner decision).

## 5. Data pools (proposal)

| Pool | Contents | Rule |
|---|---|---|
| TRAIN | NSynth-train; Slakh (subset); OpenMIC/FSD50K permissive subsets; Sanidha sessions A–C; Commons-eligible solo files; owner/musician recordings marked train | Rights verified per file |
| DEV | Sanidha session D; NSynth-valid; held-out permissive OpenMIC subset | Model selection, calibration and thresholds only |
| TEST | Sanidha session E; NSynth-test; GeneralUser renders (synthetic, reported separately) | Untouched; reported once per declared experiment |
| REAL-WORLD ACCEPTANCE | The 20-song catalogue (11/4/5, metadata) plus owner-verified Indian film-style recordings | Never used for tuning; the 20-song set stays sealed as designated |

All splits are disjoint by recording, session and performer. No windows from one recording may cross pools.

## 6. Storage and compute (ESTIMATE, zero budget)

- **Repository:** manifests, hashes, licence records and annotations only; **no raw audio**.
- **CI runners:** about 14 GB free disk, so process one Sanidha session per job (download → resample → embed → delete) and keep only embeddings (fp16, about 1 MB per minute of audio per model) as artifacts or on a research branch.
- **Embedding cost (MEASURED, CI CPU):** EfficientAT about 0.12 s per 4-min song for the front-end on a Mac runner; the full model on Linux CPU about real-time ÷ 10 (from bench timings).
  - Eight hours of Sanidha = 480 min of audio, about **1–2 CPU-hours per model** (ESTIMATE).
  - That fits within free CI if split across jobs; the quotas are not unlimited, so jobs must be resumable.
- **Fine-tuning:** frozen embeddings + heads (as today) is feasible on CPU. **Full fine-tuning of EfficientAT or BEATs is not feasible** on free CPU runners. It would need a free Colab/Kaggle GPU session (quota-limited); deferred until frozen heads plateau.

## 7. Source register (accessed 2 Nov 2026 via web search; direct fetch blocked)

| Item | Source |
|---|---|
| Sanidha | https://ccml.gtcmt.gatech.edu/data/Sanidha/ · https://arxiv.org/abs/2501.06959 |
| Saraga 1.5 | https://mtg.github.io/saraga/ · https://zenodo.org/records/4301737 · https://explore.openaire.eu/search/result?pid=10.5281%2Fzenodo.4301737 · https://www.researchgate.net/publication/356947674 · https://mirdata.readthedocs.io/en/latest/source/quick_reference.html |
| Saraga Audiovisual | https://zenodo.org/records/17405610 · https://repositori.upf.edu/items/2aca058e-9ab4-4d7d-9c02-12cafcca9324/full |
| OpenMIC-2018 | https://zenodo.org/records/1432913 · https://github.com/cosmir/openmic-2018 |
| FSD50K | https://zenodo.org/records/4060432 · https://arxiv.org/abs/2010.00475 |
| MedleyDB | https://auditory.org/postings/2014/614.html · https://steinhardt.nyu.edu/marl/research/resources/medleydb · mirdata loaders |
| HamNava | https://transactions.ismir.net/articles/257 |
| IRMAS | https://zenodo.org/records/1290750 · mirdata loader |
| Tabla Solo | https://zenodo.org/record/1267023 · https://compmusic.upf.edu/ta/tabla-solo-dataset |
| Four-Way Tabla | https://mirdata.readthedocs.io/en/latest/_modules/mirdata/datasets/four_way_tabla.html |
| AudioSet | https://research.google.com/audioset/download.html · https://research.google.com/audioset/balanced_train/tabla.html |
| NSynth, Slakh2100, Mridangam Stroke | Existing register: `docs/TONEPILOT_LICENSING_CHECKLIST.md` §2 |
