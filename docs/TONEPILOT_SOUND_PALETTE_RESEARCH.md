# TonePilot — Modern Indian Film Sound Palette (2000–2026): addendum research

**Date:** 2 November 2026. **Status:** research and proposal only. Production recognition, the model selection, `taxonomy.json` and app builds are all unchanged.

Addendum to [`TONEPILOT_INSTRUMENT_ACCURACY_ROADMAP.md`](TONEPILOT_INSTRUMENT_ACCURACY_ROADMAP.md). EfficientAT + head C stays the baseline.

**Principle:** TonePilot recognises **sound sources and sound design**, not just instruments. A modern Tamil film song can carry 20–40 layers: guitars, synths, samples, voices, and pure sound design.

**Evidence labels:**
- **DOCUMENTED** = a retrievable source states it (linked);
- **OWNER-SUPPLIED** = in the owner's brief, but the source could not be retrieved from this session;
- **NOT FOUND** = searched and not found;
- **HYPOTHESIS** = listening-based, to be verified.

**Rule:** no instrument is inferred from a composer's name or genre.

## 1. Composer evidence matrix (first pass)

| Composer | Album / song | Instrument / source | Character / processing | Role | Evidence | Source |
|---|---|---|---|---|---|---|
| A. R. Rahman | *Slumdog Millionaire* (score) | Sitar over an electronic pulse; Indian instruments blended with reggae, Brazilian drumming, Western electronica | Electronic production | Lead (sitar) | DOCUMENTED (secondary: Wikipedia summary of reviews) | https://en.wikipedia.org/wiki/A._R._Rahman |
| A. R. Rahman | General | Plays guitar, percussion, drums, keyboard, piano, accordion, harp; fuses traditional instruments with electronic sounds | — | — | DOCUMENTED (secondary) | same |
| A. R. Rahman | Studio interview (sitar, guitar, taiko, orchestral strings, processing) | — | — | — | OWNER-SUPPLIED (the Apple-hosted interview cited in the brief was not retrieved) | — |
| Yuvan Shankar Raja | *Billa* (2007) | Wanted "very modern, very metallica"; avoided live sounds | Electronic, programmed | — | DOCUMENTED (secondary: soundtrack article) | https://en.wikipedia.org/wiki/Billa_(soundtrack) |
| Yuvan Shankar Raja | *Avan Ivan* (2011) | Ethnic instrumentation, folk and orchestral; orchestral parts recorded in one take | Live orchestra | — | DOCUMENTED (secondary) | https://en.wikipedia.org/wiki/Avan_Ivan_(soundtrack) |
| Yuvan Shankar Raja | *Super Deluxe* (2019) | Rock, jazz, contemporary classical, Indian classical, experimental; realistic sound design prioritised | Sound design | — | DOCUMENTED (secondary) | https://en.wikipedia.org/wiki/Super_Deluxe_(soundtrack) |
| Yuvan Shankar Raja | Billboard India interview (electronic / orchestral / raw / minimalist) | — | — | — | OWNER-SUPPLIED, NOT FOUND | — |
| Harris Jayaraj | Career | Keyboard player from age 12; synth/keyboard programmer for many composers, including A. R. Rahman | Keyboard/synth programming | — | DOCUMENTED (secondary) | https://en.wikipedia.org/wiki/Harris_Jayaraj |
| Harris Jayaraj | Live bass sessions | — | — | Bass | OWNER-SUPPLIED, NOT FOUND | — |
| G. V. Prakash Kumar | *Madarasapattinam* (oboe, symphonic strings, string quartet, santoor, tabla) | — | — | — | OWNER-SUPPLIED, NOT FOUND (Behindwoods interview not retrieved) | — |
| G. V. Prakash Kumar | Strings arranger | Strings arranged with Das Daniel | Orchestral strings | — | DOCUMENTED (interview) | https://silverscreenindia.com/features/gv-prakash-kumar-interview-100-kaadhal-sarvam-thaala-mayam/ |
| Anirudh Ravichander | "Why This Kolaveri Di" (*3*, 2012) | South Indian folk rhythm; **nadaswaram, shehnai, saxophone, urumee, thavil, drums** | Folk + band | Lead winds; folk percussion | DOCUMENTED (secondary: soundtrack article) | https://en.wikipedia.org/wiki/Why_This_Kolaveri_Di · https://en.bharatpedia.org/wiki/3_(soundtrack) |
| Anirudh Ravichander | Piano as his strongest instrument; acoustic jazz guitar on Kolaveri | — | — | — | OWNER-SUPPLIED, NOT FOUND (Rediff interview not retrieved) | — |
| Vidyasagar | Career | Harmonium, santoor, vibraphone, keyboard, piano, guitar; played vibraphone for Shankar-Ganesh | Mallets, keys | — | DOCUMENTED (secondary + interview) | https://en.wikipedia.org/wiki/Vidyasagar_(composer) · https://www.onmanorama.com/entertainment/interviews/2023/06/05/vidyasagar-music-director-malayalam-movies-interview.amp.html |
| Vidyasagar | Xylophone, glockenspiel, 90-piece orchestra | — | — | — | OWNER-SUPPLIED, NOT FOUND | — |

**Result of the first pass:** documented, per-song instrument evidence is thin. Most of it is secondary, and "Kolaveri Di" is the strongest single-song record.

**Next:** album liner credits (session-musician credits on the streaming services' credits pages) and musician interviews, recorded per song with a URL. Listening-based hypotheses go in a separate column and **never count as ground truth**.

## 2. The analyser's output: six independent dimensions

| Dimension | Values (examples) | Head type | Notes |
|---|---|---|---|
| **Identity** (hierarchical) | family → instrument → variant (e.g. Strings → electric guitar → clean / distorted *as character, not identity*) | Multi-label, hierarchical, with abstention | Distortion, reverb etc. are **never** identities |
| **Source type** | acoustic · electric (amplified acoustic) · electronic/synthesised · sampled · imitation · processed voice · sound design · unknown | Multi-class + unknown | "Sampled strings" ≠ "real violin section"; "sitar-like guitar" ≠ sitar |
| **Character** | bright, dark, plucked, bowed, sustained, percussive, metallic, airy, warm, distorted, soft attack, … | Multi-label | NSynth "qualities" already label bright, dark, distortion, percussive, reverb, fast_decay, long_release, multiphonic, nonlinear_env, tempo-synced (CC BY 4.0) |
| **Processing** (likely) | reverb, delay, chorus, flanger, phaser, tremolo, vibrato, distortion/overdrive, filter sweep, sidechain pump, gate, pitch/formant shift | Multi-label | **Perceptual likelihood only.** The exact plugin, synth model or effect chain is not claimed from a stereo mix |
| **Role** | lead, counter-melody, melody fill, harmony, pad, bass, rhythm/percussion, drone, texture, unknown | Multi-class per event | Independent of identity |
| **Timing** | start, end, continuous/intermittent, overlaps | Temporal post-processing | Event F1, onset/offset error |

**Sound design (risers, impacts, sweeps, glitches, reverse sounds, granular textures, booms) is its own "sound-design event" class family, not an instrument.**

## 3. Taxonomy additions (extends [`benchmark/TAXONOMY_V3_PROPOSAL.md`](benchmark/TAXONOMY_V3_PROPOSAL.md); still a proposal)

- **Strings, acoustic/electric:**
  - guitar variants: steel, nylon;
  - electric guitar, with clean / overdrive / distorted / muted / palm-muted as **character**;
  - bass guitar, with finger / pick / slap as character;
  - pedal steel / slide;
  - ukulele, banjo, harp.
- **Winds:** add English horn, bassoon, flugelhorn, tuba, harmonica, melodica, whistle, low flute.
- **Percussion:**
  - Western: kick, snare, toms, cymbals, timpani, taiko, orchestral bass drum;
  - Latin/world: conga, bongo, shaker, tambourine, claves;
  - small: claps, snaps, triangle;
  - urumee (from the Kolaveri evidence).
  - **Electronic vs acoustic drum** is a *source-type* distinction, not a separate instrument.
- **Keys/synths:**
  - piano: grand, upright;
  - electric pianos: Rhodes, Wurlitzer, FM;
  - organ: drawbar, church, rock;
  - synth families: lead, pad, bass (sub, analog, FM, Reese), supersaw, pluck, bell/FM bell, arpeggiator/gated sequence, synth strings, synth brass, digital keys.
- **Orchestral articulations as character:** ostinato, pizzicato, spiccato, tremolo. Also orchestral hits and choir.
- **Bells/mallets:** chimes, FM bell, digital mallet, metallic pluck.
- **Voice family:** lead, backing, choir, humming, whisper/breath, vocal chop, reverse vocal, pitch- or formant-shifted vocal, spoken sample, crowd chant, beatbox.
- **Sound design (not instruments):**
  - riser, downlifter, sweep, reverse cymbal, impact/boom;
  - glitch/stutter, granular texture, filtered noise;
  - reverse piano/strings, metallic hit;
  - rhythmic gate, delay feedback.

**Distinctions to evaluate explicitly** (in addition to the v3 difficult pairs):
- clean electric guitar with pitch modulation ↔ sitar;
- processed voice ↔ synth pad;
- programmed kick ↔ acoustic bass drum;
- sampled string ensemble ↔ real section.

## 4. Sound Character Dataset: licence audit

| Source | What it provides | Licence | Commercial ML training | Use |
|---|---|---|---|---|
| **NSynth qualities** | 10 note-quality labels (bright, dark, distortion, percussive, reverb, …) on 306k notes | CC BY 4.0 (VERIFIED, existing register) | Permitted with attribution | **Character head, available now** |
| **Self-generated processing** on permissive dry audio (NSynth, GuitarSet, Slakh stems, Sanidha stems once approved, owner/Casio recordings) | **Exact processing labels by construction** (reverb, delay, chorus, flanger, phaser, tremolo, vibrato, distortion, filter, gate, pitch/formant shift) | Inherits the source licence (CC BY permits derivatives) | Permitted (with source attribution) | **Processing head**; recipes and seeds recorded |
| IDMT-SMT-Audio-Effects (Zenodo 7544032) | 55,044 guitar/bass notes × 11 effect classes | **CC BY-NC-ND 4.0** (mirdata; confirm on Zenodo) | **Prohibited** | Not used (research reference only) |
| **E-GMD** | 444 h of **electronic drum kits** (43 kits, Roland TD-17) aligned to MIDI | **CC BY 4.0** (VERIFIED, Magenta page) | Permitted with attribution | Electronic-drum source type, kit timbre (download is 90 GB, so use a subset) |
| GuitarSet | Acoustic guitar, hexaphonic, annotated | CC BY 4.0 (existing register) | Permitted | Dry guitar for self-generated processing |
| EGDB / EGDB-PG / EGFxSet | Electric guitar through amps / plugins | **UNKNOWN** | Excluded until checked | Check the licences |
| VocalSet | Singing techniques | **UNKNOWN** (not found in this pass) | Excluded until checked | Check |
| FSD50K (CC0/CC-BY clips) | Sound-design-like events (whoosh, boom, glitch-like classes subject to the ontology), claps, snaps, shakers | Per clip | CC0/CC-BY only | Sound-design events, small percussion |
| Slakh2100 | Synth patches in context (leads, pads, basses) | CC BY 4.0 | Permitted | Synth subtypes in mixtures (synthetic) |
| Owner recordings | Casio patches (synth families, imitations), processed versions | Owner | Permitted | Source type (imitation), synth subtypes |

**Domain caveat:** self-generated processing on clean notes is easy to learn but may not transfer to dense film mixes. Report it separately and validate on real mixes (Sanidha, acceptance songs) before claiming anything.

## 5. Architecture proposal (no implementation before approval)

1. **One shared frozen encoder** (EfficientAT baseline; CNN10 as the E2 challenger) produces per-window embeddings, computed once per song on device.
2. **Small independent heads** on the same embeddings:
   - identity (hierarchical, abstaining);
   - source type;
   - character (multi-label);
   - processing (multi-label);
   - sound-design event detector.
   - Each is calibrated on DEV with its own coverage and abstention report.
3. **Role** from rule features first (register, continuity, loudness, stem, harmonic function, melody overlap), with a learned head only once role labels exist.
4. **Temporal layer:** multi-resolution pooling (1 s and 3 s) plus smoothing, giving events with start, end and overlap.
5. **Output per event:**
   - identity (or family / unknown) + confidence;
   - source type;
   - character;
   - likely processing;
   - role;
   - start and end;
   - overlaps.
   - It never names a plugin or synth model.

Cost on device (INFERENCE): one encoder pass (about 4 ms per window, Mac CI; iPhone PENDING) plus linear heads, which is negligible.

## 6. Small reproducible benchmark plan (pre-declared)

| ID | Task | Data | Metric | Gate (proposal) | Can run now? |
|---|---|---|---|---|---|
| S1 | Character head (NSynth qualities) | NSynth train/valid/test (instrument-disjoint) | Per-quality F1, macro-F1 | Report only (first baseline) | **Yes** (NSynth already in the pipeline; CPU) |
| S2 | Processing head with self-applied effects | NSynth + GuitarSet dry sources; effects applied with held-out instruments on TEST | Per-effect F1; confusion (reverb vs delay vs chorus) | Report only | Yes (CPU; needs an effect script) |
| S3 | Electronic vs acoustic drums | E-GMD subset (electronic) vs GM/Slakh (acoustic samples): **both are sampled**, so this measures kit timbre only | Source macro-F1 | Report only | Yes (download a subset) |
| S4 | Sound-design event detection | FSD50K CC0/CC-BY subset | Event F1 | Report only | After the licence filter |
| S5 | All heads on real Indian mixes | Sanidha (identity, timing), owner film-style recordings (character, processing, role) | All of the above | Owner gates | After Sanidha access / recordings |

## 7. Labels supportable now vs needing data

| Category | Measurable now (synthetic / NSynth only; **not validated on film audio**) | Needs data before it can be measured |
|---|---|---|
| Identity | 13 v2 families; Western instruments in GM / NSynth | All Indian instruments beyond Sanidha's set (violin, mridangam, ghatam, tanpura, voice; access pending); synth subtypes in real mixes |
| Source type | acoustic vs electronic (NSynth source labels) | imitation (paired recordings), sampled vs real ensemble, processed voice |
| Character | NSynth's 10 qualities | Film-mix character (owner annotation) |
| Processing | Self-applied effects (S2), once built | Effects in real mixes (annotation) |
| Sound design | — | FSD50K subset (licence filter), film annotations |
| Role | — | Role annotations (none exist) |
| Timing | Synthetic layered (current F1 0.34 / 0.50) | Sanidha (stem-derived), film annotations |

**Today, nothing in this table is a validated claim about Indian film music.**
