# TonePilot — Instrument Analyser Accuracy Roadmap (proposal for owner approval)

**Date:** 2 November 2026. **Status:** a plan only. No production change, no major training, no release.

Companions:
- [dataset research](TONEPILOT_INSTRUMENT_DATASET_RESEARCH.md);
- [model comparison](TONEPILOT_INSTRUMENT_MODEL_COMPARISON.md);
- [taxonomy v3 proposal](benchmark/TAXONOMY_V3_PROPOSAL.md).

**Governing objective (owner, 2 Nov):** Instrument Analyser accuracy on Tamil, Telugu and Hindi film music comes first. Chord/Arpeggio and Tone Maker enhancements wait. **Instrument Analyser** ("what is playing, and when") and **Tone Maker** ("which sound recreates it") stay separate systems.

**First measurable milestone (owner):**

> Given a legally usable, previously unseen Indian music recording, TonePilot identifies the audible instrument families, returns multiple simultaneous instruments, and shows their entry and exit times with calibrated confidence.

## 1. Stages, gates and what can be measured today

| Stage | Output | Proposed gate (owner targets) | Measurable today? |
|---|---|---|---|
| 1. Dataset | Permissive, verified, session-disjoint pools | — | Partly. Synthetic + NSynth exist. **Sanidha needs access.** Film: none |
| 2. Recognition | Family → instrument (hierarchical, with abstention) | Family selective acc. ≥ 90%; exact ≥ 85% (supported classes); wrong-family ≤ 5% | Synthetic and NSynth: yes. **Real Indian: NOT EVALUABLE** (no data yet) |
| 3. Layered + temporal | Multi-label per window; entry/exit | Multi-label macro-F1 ≥ 0.80; event F1 ≥ 0.75 | Synthetic: yes (current F1 0.34 instrument / 0.50 family). Real: **NOT EVALUABLE** until Sanidha |
| 4. Role | Lead / counter-melody / harmony / bass / rhythm / drone / texture / unknown, **independent of identity** | To be set once labels exist | **NOT EVALUABLE** (no role labels anywhere) |
| 5. Acceptance | Unseen lawful Tamil/Telugu/Hindi recordings, human-verified | All of the above, reported per language, family, source and mix density | **NOT EVALUABLE** (legal check + recordings pending) |

Targets are never lowered to "pass". A gate without data is reported as **NOT EVALUABLE**.

**Support tiers per class:**
1. **Tier 1, validated:** the gate is met on real TEST.
2. **Tier 2, family-only.**
3. **Tier 3, experimental:** shown as uncertain, never as fact.
4. **Unknown.**

**Today, no class is Tier 1 on real Indian audio.**

## 2. Experiment plan (each pre-declared; DEV selects, TEST is reported once)

| ID | Experiment | Data | Baseline vs challenger | Primary / guard metrics | Compute (ESTIMATE) | Needs approval? |
|---|---|---|---|---|---|---|
| **E1** | **Real Indian-domain evaluation of the existing frozen encoders:** multi-label family + instrument activity on Sanidha, with labels derived from the clean stems (energy-gated, smoothed) and spot-checked by a human | Sanidha, session-disjoint (A–C train heads, D DEV, E TEST) | C vs PANNs-CNN10 vs YAMNet (same heads) | Family macro-F1 at wrong-family ≤ 5%; event F1, onset/offset error; guard: NSynth-test | About 1–2 CPU-hours per model; one session per CI job (disk) | **Yes:** the Sanidha access request (email draft) |
| E2 | PANNs-CNN10 added to the existing synthetic/NSynth bench | Existing bench | C vs CNN10 | Same as the v4 report | About 1 CI hour | Within approved research scope |
| E3 | Hierarchical head: family → instrument with explicit "ambiguous pair" outputs (e.g. Indian double reed) | E1 data + Commons-eligible solos | C (flat heads) vs hierarchical heads | Wrong-family, exact selective accuracy on difficult pairs | CPU | After E1 |
| E4 | Multi-resolution + temporal smoothing for entry/exit | Slakh subset (synthetic) + Sanidha | Per-window decision vs 1 s + 3 s pooling + HMM/median smoothing | Event F1, onset/offset p90 | CPU | After E1 |
| E5 | Partially-labelled training (OpenMIC, masked loss) + FSD50K CC0/CC-BY subset | Filtered per-track licences | C heads with vs without the real polyphonic data | Real-domain DEV (Sanidha D) | CPU, plus downloads of a few GB | Licence filter first |
| E6 | Source type with **paired** acoustic/imitation recordings | Owner + volunteer musician recordings | Current source head vs a head trained on the pairs | Source macro-F1, imitation recall | CPU | Recordings (owner) |
| E7 | Role labels (separate from identity) | Owner/musician annotation of Sanidha + acceptance songs | Rule baseline (register, loudness, continuity, stem) vs learned | Role macro-F1 | CPU | Annotation effort |
| E8 | BEATs frozen embeddings | E1 data | C vs BEATs | As E1 | Heavier (transformer); free GPU optional | Licence check |
| E9 | Partial fine-tuning of EfficientAT's last blocks | E1 + E5 data | Frozen vs partially fine-tuned | As E1 | **Free Colab/Kaggle GPU, quota-limited**; resumable | **Yes** (major training change) |

**Ablation rule:** hand-crafted DSP features (attack, harmonicity, HPSS) are added only if an ablation on DEV shows a gain.

**Augmentation:**
- recipes (gain, EQ, reverb, compression, pan/width, noise, controlled mixtures, ±1 semitone / ±5% stretch) are recorded with seeds;
- synthetic-only, real-only and mixed training are always reported separately.

## 3. Annotation schema extension (proposal; the current schema is unchanged until approved)

Add to each event in `docs/benchmark/annotation.schema.json`:
- `recording_id`;
- `instrument_id` and `family_id` (taxonomy v3 ids);
- `role` (`lead | counter_melody | harmony | bass | rhythm | drone | texture | unknown`);
- `audibility` (`direct | inferred | uncertain`; replaces clear / partial / uncertain);
- `overlap_with` (event ids);
- `annotators` (a list, for multi-annotator agreement);
- `disputed` (bool);
- `provenance` (`human | ai_prefill_verified | stem_derived_verified`).

AI and stem-derived labels count as ground truth only after human verification.

## 4. iPhone deployment (only after a model wins offline)

1. Core ML conversion and parity, which already exists for C.
2. A physical iPhone 15 run of TonePilot Lab: model load, full-song time, peak memory, thermal and battery (G2.4, **PENDING**).
3. Offline and long-song stability.
4. Multi-label and abstention outputs survive conversion (decision agreement, as in Gate 2).
5. Developer-only shadow mode on real songs.
6. Only then, owner approval for any user-visible change.

## 5. Compute, storage and cost (zero budget; ESTIMATES)

| Item | Estimate | Note |
|---|---|---|
| Sanidha raw | 20–35 GB | Process per session; never committed |
| Embeddings (3 encoders × 8 h) | About 1.5 GB fp16 | CI artifacts / research branch |
| CI CPU time per full E1 | About 3–6 hours across jobs | Free quota is limited; resumable jobs |
| GPU (E8/E9 only) | Free Colab/Kaggle sessions | Quota-limited; not assumed available |
| Money | **0** | No paid service anywhere |

## 6. What to do first (for approval)

1. **Approve the Sanidha access request.** A draft will be prepared; it won't be sent without approval. It is the only verified permissive real Indian multitrack source.
2. **Verify the Saraga Audiovisual file licence.** It is potentially the largest permissive Indian source.
3. **Run E2 now** (CNN10 on the existing bench; within approved research scope) while access is pending.
4. **Then E1:** the first real Indian-domain numbers, which are what make the owner's first milestone measurable.
5. **Owner:** confirm whether Saraga 1.5 (NC) may be used for internal evaluation; otherwise request permission from MTG.
