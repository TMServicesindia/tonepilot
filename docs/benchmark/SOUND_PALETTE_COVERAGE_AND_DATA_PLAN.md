# Sound Palette Coverage and Data Plan

**Date:** 2 November 2026. **Status:** RESEARCHED / PROPOSED. Nothing here is implemented, approved, measured or validated.

What stays unchanged:
- production recognition;
- model selection (EfficientAT + head C stays the reference);
- `taxonomy.json`;
- benchmark splits;
- acceptance gates;
- the sealed 20-song catalogue (TEST).

Sources:
- [`TONEPILOT_SOUND_PALETTE_RESEARCH.md`](../TONEPILOT_SOUND_PALETTE_RESEARCH.md) §1, §1b, §1c;
- [`TAXONOMY_V3_PROPOSAL.md`](TAXONOMY_V3_PROPOSAL.md);
- [`TONEPILOT_INSTRUMENT_DATASET_RESEARCH.md`](../TONEPILOT_INSTRUMENT_DATASET_RESEARCH.md);
- the licensing checklist.

Machine-readable inventory: [`sound_palette_inventory.json`](sound_palette_inventory.json).

## 1. Executive summary

- **165 terms audited** from the composer palettes (6 primary + 25 more) and the deep-dive. Their dispositions:

| Disposition | Count |
|---|---|
| Existing v2 identities | 41 |
| Aliases | 12 |
| Variants | 1 |
| Kept v3 proposals | 11 |
| **Proposed new identities** | **24** |
| Needs review (not forced into an identity) | 19 |
| Moved to other dimensions or tags | 57 (source type 11, character 14, processing 5, role 4, sound design 3, relations 3, song metadata 11, ensembles 6) |

- **Most named sounds are not new identities.** Product names, effects, genres, techniques and ensembles map to the other dimensions. The 24 new identities are mostly Indian folk and world instruments. **All 24 are `unsupported`**: no lawful permissive real data exists for them today.
- **The coverage gap is real Indian recordings, not class names.** Of the 41 existing identities the composers name, the eight most often named Indian sources have **no permissive real data**: harmonium, shehnai, sitar, bansuri, santoor, sarangi, dhol, kanjira. They are the owner's first recording targets (§6).
- **Evidence:** 5 owner-supplied claims were promoted to `DOCUMENTED_SECONDARY` with song-level sources (§3); 3 were searched and are `NOT_FOUND`; everything else stays `OWNER_SUPPLIED`.
- **Composer identity is never a model input, label or prior.** It is song metadata, used for per-composer reporting and a composer-held-out TEST.
- **E2 and the launch A/B were still running when this was written** (§9). No results, no winner.

## 2. Candidate inventory (normalised)

Data codes:
- `sanidha` = CC BY 4.0, access pending;
- `commons:N` = eligible Wikimedia Commons files from the 1 Nov survey, not yet listened to;
- `nsynth(x)` = an NSynth family only, not the exact instrument;
- `openmic` = a permissive-track subset after per-track filtering;
- `none` = nothing lawful found.


#### Existing v2 identities (41)

| Term | Family | Real/permissive data now | Evidence | Action |
|---|---|---|---|---|
| veena | Indian plucked | commons:28 | OWNER_SUPPLIED | keep |
| nadaswaram | Indian winds | commons:1 | DOCUMENTED_SECONDARY | keep |
| bansuri | Indian winds | none | OWNER_SUPPLIED | keep; collect real examples |
| flute | Western winds | nsynth, openmic | OWNER_SUPPLIED | keep |
| tabla | Indian percussion | commons:21 | OWNER_SUPPLIED | keep |
| shehnai | Indian winds | none | DOCUMENTED_SECONDARY | keep; collect real examples |
| sitar | Indian plucked | none | DOCUMENTED_SECONDARY | keep; collect real examples |
| mridangam | Indian percussion | sanidha, commons:1 | OWNER_SUPPLIED | keep |
| violin | Strings | sanidha, nsynth, openmic | OWNER_SUPPLIED | keep |
| cello | Strings | nsynth, openmic | OWNER_SUPPLIED | keep |
| harp | Other plucked | slakh | OWNER_SUPPLIED | keep |
| string ensemble | Strings | slakh | OWNER_SUPPLIED | keep |
| accordion | Keys | openmic | OWNER_SUPPLIED | keep |
| harmonium | Keys | none | DOCUMENTED_SECONDARY | keep; collect real examples |
| piano | Keys | nsynth, openmic | DOCUMENTED_SECONDARY | keep |
| guitar | Other plucked | nsynth, openmic, guitarset | DOCUMENTED_SECONDARY | keep |
| electric guitar | Other plucked | openmic, slakh | OWNER_SUPPLIED | keep |
| bass guitar | Bass | nsynth, slakh | OWNER_SUPPLIED | keep |
| saxophone | Western winds | nsynth(reed), openmic | DOCUMENTED_SECONDARY | keep |
| trumpet | Other | nsynth(brass), openmic | OWNER_SUPPLIED | keep |
| trombone | Other | nsynth(brass), openmic | OWNER_SUPPLIED | keep |
| thavil | Indian percussion | commons:1 | DOCUMENTED_SECONDARY | keep |
| kanjira | Indian percussion | none | OWNER_SUPPLIED | keep; collect real examples |
| dholak | Indian percussion | commons:10 | OWNER_SUPPLIED | keep |
| dhol | Indian percussion | none | OWNER_SUPPLIED | keep; collect real examples |
| ghatam | Indian percussion | sanidha | OWNER_SUPPLIED | keep |
| santoor | Bells | none | DOCUMENTED_SECONDARY | keep; collect real examples |
| vibraphone | Bells | nsynth(mallet) | DOCUMENTED_SECONDARY | keep |
| glockenspiel | Bells | nsynth(mallet) | DOCUMENTED_SECONDARY | keep |
| mandolin | Other plucked | openmic | OWNER_SUPPLIED | keep |
| sarangi | Strings | none | DOCUMENTED_SECONDARY | keep; collect real examples |
| clarinet | Western winds | openmic | OWNER_SUPPLIED | keep |
| oboe | Western winds | nsynth(reed) | OWNER_SUPPLIED | keep |
| organ | Keys | nsynth, openmic | OWNER_SUPPLIED | keep |
| drums | Other percussion | slakh, openmic | DOCUMENTED_SECONDARY | keep |
| synth pad | Electronic | nsynth, slakh | OWNER_SUPPLIED | keep |
| bass synth | Electronic | nsynth, slakh | OWNER_SUPPLIED | keep |
| choir | Other | none (permissive) | OWNER_SUPPLIED | keep; collect real examples |
| electric piano | Keys | nsynth | OWNER_SUPPLIED | keep |
| tanpura | Indian plucked | sanidha | OWNER_SUPPLIED | keep |
| french horn | Other | nsynth(brass) | OWNER_SUPPLIED | keep |

#### Aliases of existing/new ids (12)

| Term | Canonical / parent | Note | Evidence | Action |
|---|---|---|---|---|
| nagaswaram | nadaswaram  | spelling variant | OWNER_SUPPLIED | map to existing id |
| kanjeera | kanjira  | spelling variant | OWNER_SUPPLIED | map to existing id |
| mouth organ | harmonica  | common Indian English name | OWNER_SUPPLIED | map to existing id |
| orchestral strings | string ensemble  |  | OWNER_SUPPLIED | map to existing id |
| string orchestra | string ensemble  |  | OWNER_SUPPLIED | map to existing id |
| violin ensemble | string ensemble  | DSP | OWNER_SUPPLIED | map to existing id |
| string quartet | string ensemble  | ensemble size is metadata | OWNER_SUPPLIED | map to existing id |
| rock bass | bass guitar  |  | OWNER_SUPPLIED | map to existing id |
| dholki | dholak  | diminutive name | OWNER_SUPPLIED | map to existing id |
| dhols | dhol  | plural | OWNER_SUPPLIED | map to existing id |
| electric organ | organ  |  | OWNER_SUPPLIED | map to existing id |
| dilruba | esraj/dilruba  | merge with esraj (needs musician check) | OWNER_SUPPLIED | alias of esraj/dilruba |

#### Variants (1)

| Term | Canonical / parent | Note | Evidence | Action |
|---|---|---|---|---|
| venu | bansuri  | Carnatic transverse bamboo flute; same construction class as bansuri → variant label 'venu', parent Indian bamboo flute | OWNER_SUPPLIED | map to existing id |

#### Already proposed in v3 (kept) (11)

| Term | Family | Real/permissive data now | Evidence | Action |
|---|---|---|---|---|
| banjo | Other plucked | openmic | OWNER_SUPPLIED | keep as v3 proposal |
| ukulele | Other plucked | openmic | OWNER_SUPPLIED | keep as v3 proposal |
| tuba | Other (brass) | nsynth(brass) | OWNER_SUPPLIED | keep as v3 proposal |
| flugelhorn | Other (brass) | nsynth(brass) | OWNER_SUPPLIED | keep as v3 proposal |
| harmonica | Western winds | none | OWNER_SUPPLIED | keep as v3 proposal |
| melodica | Western winds | none | OWNER_SUPPLIED | keep as v3 proposal |
| conga | Latin percussion | slakh? | OWNER_SUPPLIED | keep as v3 proposal |
| bongo | Latin percussion | slakh? | OWNER_SUPPLIED | keep as v3 proposal |
| tambourine | Small percussion | fsd50k | OWNER_SUPPLIED | keep as v3 proposal |
| lead vocal | Voice | sanidha, openmic | OWNER_SUPPLIED | keep as v3 proposal |
| backing vocal | Voice | none | OWNER_SUPPLIED | keep as v3 proposal |

#### Proposed NEW identities (unsupported until data) (24)

| Term | Canonical / parent | Note | Evidence | Action |
|---|---|---|---|---|
| esraj | esraj/dilruba / Indian bowed (fretted, sympathetic) | dilruba = near-identical regional variant | OWNER_SUPPLIED | identity 'esraj/dilruba'; family-only until data |
| sarod | sarod / Indian plucked lute | fretless, metal fingerboard; pair with sitar/oud | OWNER_SUPPLIED | identity; unsupported |
| tumbi | tumbi / Indian plucked (one-string) | high single string, Punjabi | OWNER_SUPPLIED | identity; unsupported |
| bulbul tarang | bulbul tarang / keyed zither | 'Indian banjo' | OWNER_SUPPLIED | identity; unsupported |
| pakhawaj | pakhawaj / Indian barrel drum | Kalank (DS) | DOCUMENTED_SECONDARY | identity; pair with mridangam |
| urumi | urumi / Tamil folk drums | hourglass drum with a roaring friction-like sound; distinctive | DOCUMENTED_SECONDARY | identity; unsupported |
| pambai | pambai / Tamil folk drums | paired cylindrical drums | OWNER_SUPPLIED | identity; family-only until data |
| thudumbu | thudumbu / Tamil folk drums |  | OWNER_SUPPLIED | identity; family-only until data |
| parai | parai / Indian frame drums | struck with sticks; ceremonial | OWNER_SUPPLIED | identity; pair with thappattai |
| chenda | chenda / Kerala drums | cylindrical stick drum | OWNER_SUPPLIED | identity; unsupported |
| ghungroo | ghungroo / bells (worn) | ankle bells | OWNER_SUPPLIED | identity; small-percussion |
| castanet | castanet  |  | OWNER_SUPPLIED | identity; small-percussion |
| oud | oud / fretless lute | pair with sarod / guitar | OWNER_SUPPLIED | identity; unsupported |
| bouzouki | bouzouki / long-neck paired-course lute | pair with mandolin | OWNER_SUPPLIED | identity; family-only until data |
| saz | saz / long-neck lute | Turkish bağlama is the common saz type | OWNER_SUPPLIED | identity 'saz/bağlama (Turkish)' |
| tar | tar / long-neck lute | Persian/Azerbaijani (brief says 'Turkish': flagged) | OWNER_SUPPLIED | identity; unsupported |
| kamancheh | kamancheh / spike fiddle | pair with sarangi/esraj/violin | OWNER_SUPPLIED | identity; unsupported |
| qanun | qanun / plucked zither | Kalank 'Tabaah Ho Gaye' (DS); pair with santoor/swarmandal | DOCUMENTED_SECONDARY | identity; unsupported |
| ney | ney / end-blown flute | pair with bansuri | OWNER_SUPPLIED | identity; unsupported |
| hulusi | hulusi / free-reed gourd pipe | Kalank claim NOT FOUND | NOT_FOUND | identity; unsupported |
| bagpipes | bagpipes / drone reed | Kalank claim NOT FOUND | NOT_FOUND | family-only (rare) |
| hang drum | hang drum / steel tongue/handpan | pair with steelpan/mallets | OWNER_SUPPLIED | identity; unsupported |
| harpejji | harpejji / electric tapped strings | electric (not synth); rare | OWNER_SUPPLIED | identity; family-only |
| ravanahatha | ravanahatha / folk spike fiddle | Kalank 'Rajvaadi Odhni' (DS) | DOCUMENTED_SECONDARY | identity; unsupported |

#### Needs review (not forced into an identity) (19)

| Term | Canonical / parent | Note | Evidence | Action |
|---|---|---|---|---|
| keyboard (as instrument) |   | ambiguous: family Keys, source unknown → family-level only | OWNER_SUPPLIED | family-level only |
| synthesizer (generic) |   | family Electronic only; subtype from character | OWNER_SUPPLIED | family-level only |
| thappattai |   | may be the same as parai (thappu), or a regional variant: musician check | OWNER_SUPPLIED | musician/source check |
| thara |   | instrument not identified from the term | OWNER_SUPPLIED | musician/source check |
| khomok |   | Bengali plucked drum (gopiyantra family?): check | OWNER_SUPPLIED | musician/source check |
| iktara |   | several regional constructions (plucked drone; Baul): check | OWNER_SUPPLIED | musician/source check |
| Kinnera veena |   | ancient stick zither, distinct from Saraswati veena: check | OWNER_SUPPLIED | musician/source check |
| pump organ |   | reed organ, related to harmonium; don't merge without a listening check | OWNER_SUPPLIED | musician/source check |
| Greek baglama |   | small bouzouki-family lute, NOT the Turkish bağlama: keep apart | OWNER_SUPPLIED | musician/source check |
| baglama (unspecified) |   | Turkish saz type or Greek baglamas: resolve per source | OWNER_SUPPLIED | musician/source check |
| dafli |   | frame drum (daf family): alias of frame drums? | OWNER_SUPPLIED | musician/source check |
| tasha |   | kettle drum in dhol tasha; candidate identity | OWNER_SUPPLIED | musician/source check |
| swarlin |   | unknown term (Kalank credit): check | OWNER_SUPPLIED | musician/source check |
| Balinese/Indonesian instruments |   | Uttama Villain (DS); unspecified, likely gamelan metallophones/gongs | DOCUMENTED_SECONDARY | musician/source check |
| six-foot bamboo instrument |   | Sam C. S.: unidentified | OWNER_SUPPLIED | musician/source check |
| Continuum fingerboard |   | electronic controller: its sound depends on the synth patch → source type electronic + character (continuous glides), not an identity | OWNER_SUPPLIED | musician/source check |
| kuzhal (existing v2 id) |   | ambiguous: Tamil 'pullanguzhal' = bamboo flute; Kerala 'kuzhal' = double reed. Split or rename | OWNER_SUPPLIED | musician/source check |
| folk drums (varied) |   | family-level Indian percussion only | OWNER_SUPPLIED | musician/source check |
| Indian reeds / wood-winds |   | family-level only | OWNER_SUPPLIED | musician/source check |

#### Ensembles (tags, not identities) (6)

Terms: chendamelam; dhol tasha; symphony orchestra (72/90/140-piece); live band; brass section/horns; gaana ensemble.

Action: song-level/section tag; members annotated individually.

#### Source type (hardware/product names never output) (11)

Terms: Moog; Yamaha DX7; Roland Jupiter-8; E-mu drumulator; Kurzweil K2000; Korg M1; drum machine / rhythm box / rhythm pads; programmed rhythm; electronic musical instruments; electric violin; MIDI.

Action: source type electronic/electric; never output a product name.

#### Character (14)

Terms: shimmering; skittering (synths); mild (synths); haunting (guitar); Carnatic-styled guitar (gamaka bends); flamenco guitar (nylon, rasgueado); acoustic guitar plucks; animal skin vs fibre heads; 808-style; kitschy synths; dark ambient; echoing (synths); operatic (voice); humming.

Action: character head (multi-label).

#### Processing (5)

Terms: distortion (heavily distorted electric guitar); Auto-Tune → pitch correction; reverb; delay/echo; loops (production).

Action: processing head (multi-label).

#### Role (4)

Terms: interlude lead; melodically dynamic bassline; guitar riffs; lead voice (traditional instrument as lead).

Action: role annotation.

#### Sound-design events (3)

Terms: bass drop; electronic scratches; cinematic hits.

Action: sound-design event head.

#### Annotation relations (3)

Terms: call-and-response ('unusual conversations'); Western drums → folk rhythm switch; deliberate instrument avoidance.

Action: annotation relation (responds_to, handover_from, absent).

#### Song-level metadata only (11)

Terms: EDM; trap; hip-hop; techno/trance; R&B; rock/alt-rock/heavy metal; jazz; disco; folk; indie; polyrhythms.

Action: song-level metadata / rhythm analysis only.

## 3. Evidence-backed findings (promotions; `DOCUMENTED_SECONDARY` unless stated)

| # | Composer | Song / album | Claim | Source | Status |
|---|---|---|---|---|---|
| 1 | Ghibran | *Uttama Villain* (2015) | Tabla, ghatam and dholak deliberately **not** used (period-film staples) | [Wikipedia: Uttama Villain (soundtrack)](https://en.wikipedia.org/wiki/Uttama_Villain_(soundtrack)), attributed to a Ghibran interview | **Promoted** (absence) |
| 2 | Ghibran | *Uttama Villain* | Instruments bought in Bali, Indonesia; mixed with orchestra | same + [Silverscreen India](https://silverscreenindia.com/movies/news/exotic-musical-instruments-uttama-villain/) | **Promoted**; the instruments are unnamed, so `needs_review` |
| 3 | Santhosh Narayanan | *Sarpatta Parambarai* (2021) | 1970s skin-headed instruments (not modern fibre); veteran gaana musicians (Rev Ravi, Gana Bala) | [Wikipedia: Sarpatta Parambarai (soundtrack)](https://en.wikipedia.org/wiki/Sarpatta_Parambarai_(soundtrack)) | **Promoted** (character variant) |
| 4 | Pritam | *Kalank* (2019), "Tabaah Ho Gaye" | **Qanun** played by Tamer Pınarbaşı opens the track | Review: [thegreatbollywoodparty.com](https://thegreatbollywoodparty.com/2019/04/17/music-review-kalank-2019/) | **Promoted** |
| 5 | Pritam | *Kalank*, "Tabaah Ho Gaye" | **Glockenspiel** (Aditya Dev, DJ Phukan) | same | **Promoted** |
| — | Pritam | *Kalank*, "Tabaah Ho Gaye" | Pakhawaj interlude | same | New documented item (not owner-claimed) |
| — | Pritam | *Kalank*, "Rajvaadi Odhni" | Ravanahatha (Chandan Singh), sarangi (Dilshad Khan), "swarlin" (Abhijit Mazumdar) | Blog: [Milliblog](https://milliblog.com/2019/04/06/milliblog-weeklies-apr07-2019/) | New documented items; "swarlin" `needs_review` |
| — | Harris Jayaraj | *Vaaranam Aayiram*, "Nenjukkul Peidhidum" | Guitar solo: Steeve Vatz | Credit listing (search result) | New documented item; URL to re-confirm |
| (earlier) | Anirudh | "Why This Kolaveri Di" (*3*, 2012) | Nadaswaram, shehnai, saxophone, urumee, thavil, drums | [Wikipedia](https://en.wikipedia.org/wiki/Why_This_Kolaveri_Di) | Already documented in §1 |
| NF | Ghibran | *Vathikuchi* | Avoided flute/veena/acoustic guitar/sax; heavy bass, low strings, brass | — | `NOT_FOUND` (stays owner-supplied) |
| NF | G. V. Prakash | *Madrasapattinam* | Oboe, string quartet, santoor, tabla | — | `NOT_FOUND` |
| NF | Pritam | *Kalank* | Bagpipes, hulusi, ney, bulbul tarang | — | `NOT_FOUND` |

All of these are **secondary** sources (encyclopaedia summaries, reviews, blogs). The best targets for a primary upgrade are album liner credits and the credits pages of streaming services.

**Promoted evidence describes the song. It is not a label for any clip until a human annotates the clip.**

## 4. Which distinctions deserve a class (Task C)

Hierarchy: family → identity → variant (only when acoustically distinguishable **and** supported), then source type, character, processing, role, timing, unknown.

| Difficult pair | Distinguishable in a stereo mix? (INFERENCE) | Lawful data now | Recommendation |
|---|---|---|---|
| Sitar ↔ processed guitar (pitch-modulated, sitar patch) | Partly: the sitar's jawari buzz and sympathetic strings vs the guitar's attack. Confusable when processed | Sitar: none. Guitar: GuitarSet, NSynth | Parent **"plucked lute (Indian-like)"** + source type. Sitar is `unsupported` until there are ≥ 5 performers' recordings |
| Nadaswaram ↔ shehnai | Hard: both double reeds; register, loudness and ornamentation differ | Nadaswaram: Commons 1; shehnai: none | Parent **"Indian double reed"**; identities `experimental` / `unsupported` |
| Bansuri ↔ concert flute | Moderate: breathier tone, glides | Flute: NSynth/OpenMIC; bansuri: none | Parent "flute"; bansuri `unsupported`; a strong owner recording target |
| Esraj/dilruba ↔ sarangi ↔ violin ↔ kamancheh | Hard in mixes; sympathetic resonance helps | Violin: Sanidha (pending); others: none | Parent **"bowed strings"**; abstain below family |
| Santoor ↔ zither-like sampled patches ↔ qanun | Moderate: hammered vs plucked attack | None (santoor), none (qanun) | Parent **"struck/plucked zither"**; source-type head for sampled |
| Harmonium ↔ reed/pump organ ↔ accordion | Hard: all free reeds | Accordion: OpenMIC; harmonium: none | Parent **"free-reed keyboard"**; pump organ `needs_review` |
| Urumi ↔ other folk drums | Urumi's friction roar is distinctive (INFERENCE) | None | Identity once recordings exist; otherwise "Indian folk drum" |
| Parai ↔ thappattai | Possibly the same instrument family | None | Single parent "Tamil frame drum"; `needs_review` on the names |
| Oud ↔ acoustic guitar ↔ sarod | Fretless glides vs fretted | Guitar: yes; oud/sarod: none | Parent "plucked lute"; oud/sarod `unsupported` |
| Bouzouki ↔ mandolin (↔ Greek baglama) | Hard: paired metal courses | Mandolin: OpenMIC | Parent **"paired-course lute"**; abstain |
| Saz/bağlama ↔ other plucked | Moderate | None | `unsupported`; Greek baglama kept apart (`needs_review`) |
| Sampled orchestral strings ↔ real section | Hard: realism varies | Real: Sanidha violin (solo), OpenMIC; sampled: Slakh, GeneralUser | **Source-type** question, not identity; needs paired real/sampled material |
| Synth pad ↔ processed voice | Hard when vocals are formant-shifted | Pads: Slakh/NSynth; processed voice: self-generated from permissive vocals | Voice family + processing; the sound-design head can abstain |
| Electronic drum samples ↔ acoustic drums | E-GMD (electronic kits) vs acoustic recordings: **both are sampled/recorded**, so it's a kit-timbre question | E-GMD CC BY 4.0, Slakh | Source-type head; report kit-held-out |

**Rules:**
- A regional name alone never creates a class (venu → bamboo-flute variant; nagaswaram/kanjeera → aliases).
- Acoustically distinct instruments are never merged just because they are culturally related (sarangi ≠ esraj; Greek baglama ≠ Turkish bağlama).
- When evidence can't support a distinction, use the parent class with abstention.

## 5. Lawful data sources (Task D)

| Source | Status | Covers |
|---|---|---|
| NSynth, Slakh2100, GuitarSet, E-GMD (CC BY 4.0) | **Confirmed** (register) | Western families; synths; acoustic guitar; electronic drums; NSynth character qualities |
| OpenMIC-2018 (per-track licences), FSD50K (CC0/CC-BY clips) | **Confirmed with a filter** | Real polyphonic Western instruments; small percussion; sound-design events |
| Self-generated processing on the above | **Confirmed** (derivatives allowed) | Processing labels by construction |
| Sanidha (CC BY 4.0) | **Pending** access (draft email, not sent) | Violin, mridangam, ghatam, tanpura, voice (real Carnatic) |
| Saraga Audiovisual | **Pending** file-level licence check | Carnatic multitrack |
| Wikimedia Commons eligible files | **Pending** owner listening check | Tabla 21, veena 28, viola 17, dholak 10, mridangam/thavil/nadaswaram 1 each |
| Four-Way Tabla (CC BY 3.0, mirdata) | **Pending** confirmation at source | Tabla strokes |
| Owner Casio recordings | **Confirmed** (owner's rights) | `imitation` / `sampled` only, never as the real instrument |
| Volunteer musicians | **Pending** written permission (letter template exists) | Real Indian instruments, the priority gap |
| Saraga 1.5, MedleyDB, IRMAS, Tabla Solo, Mridangam Stroke, IDMT effects, AudioSet audio | **Rejected** for training (NC / ND / restricted / YouTube) | — |
| HamNava, Tani-avarthanam, EGDB/EGFxSet, VocalSet | **Unknown**, so excluded | — |

## 6. Recording priorities and specification (for the owner and volunteer musicians)

### 6.1 Priority order (coverage × no data × confusion importance)

1. **Harmonium** (the most-named Indian source; no data).
2. **Bansuri / venu**.
3. **Shehnai** and **nadaswaram** (the double-reed pair).
4. **Sitar** (vs processed guitar).
5. **Santoor**.
6. **Sarangi** (vs violin / esraj).
7. **Dhol**, **thavil**, **kanjira**.
8. **Tamil folk set:** parai, urumi, pambai, thudumbu.
9. Veena, tabla, dholak (top up the Commons files).
10. **Casio imitation pairs** for every item above: same phrases, same room. These are labelled `imitation`.

### 6.2 What to record, per instrument

**Takes:**
- **Dry:** close microphone, untreated room OK, no effects.
- **Room:** 1–2 m distance.
- Optional **processed** copies are made later by script, never at recording time.

**Content (about 10 minutes per performer):**
- sustained notes, low / mid / high register (3 × 5 s);
- the scale up and down, slow and fast;
- 3 short phrases in typical film style (8–15 s);
- typical ornaments (meend/glides, gamaka);
- for percussion: basic strokes ×10 each, then 3 rhythmic patterns (slow, medium, fast) and 30 s of free playing.

**Diversity:**
- **≥ 3 different performers, and ≥ 2 physical instruments where possible**, before any training;
- ≥ 5 performers before a class can be promoted.

**Format:**
- 48 kHz or 44.1 kHz, 24-bit (16-bit OK), WAV, mono or stereo;
- note the phone or microphone model;
- no automatic gain control or noise suppression (turn off the "voice" modes).

**Noise:** a quiet room; a 10 s room-tone take per session (for noise augmentation).

**Casio CT-X870IN:**
- record the line out, the same phrases, with the patch name noted;
- source = `imitation` (or `sampled` for kits and pianos);
- **never** labelled as the real instrument.

### 6.3 Consent, licence and metadata

- **Consent:** written permission using the existing letter template, covering ML training and evaluation, commercial use and no redistribution of the raw audio. Record the performer's name or pseudonym.
- **File name:** `<instrument>_<source>_<performer-id>_<session>_<take>_<content>.wav`, e.g. `shehnai_acoustic_p03_s01_t02_phrase2.wav`.
- **Metadata per file:**
  - instrument, plus regional or alternate name;
  - source type (acoustic / electric / electronic / sampled / imitation);
  - performer id, instrument id, session, device, microphone, room;
  - content type, register, tempo;
  - licence/consent id;
  - annotator and verification.
- **Quality control:**
  - no clipping (peaks < −1 dBFS);
  - SNR above about 30 dB against room tone;
  - correct label confirmed by a second listener;
  - SHA-256 recorded;
  - raw audio stays out of the public repository.

## 7. Benchmark requirements per new class (Task E)

**Minimum before training a class:**
- ≥ 3 performers;
- ≥ 2 physical instruments;
- ≥ 15 minutes of audio;
- ≥ 20 phrases;
- 1 performer held out entirely for TEST.

**Promotion `unsupported → experimental → supported`:**
- **experimental:** DEV + TEST from held-out performers or sessions exist, and results are reported with coverage.
- **supported:**
  - ≥ 5 performers;
  - on real held-out TEST, wrong-family ≤ 5% at the reported coverage, with selective exact accuracy ≥ 85% (the owner's targets);
  - per-class confusion against its difficult pair reported;
  - for film-mix claims, confirmed on real mixes.

**Splits:**
- by **performer + session + physical instrument**;
- processed copies stay in the same split as their dry source (no leakage);
- the 20-song catalogue stays sealed TEST.

**Difficult negatives:** every class trains and tests against its pair from §4, plus Casio imitations of itself.

**Reported separately, never merged into one number:**
- clean synthetic;
- short windows;
- imitation;
- NSynth;
- layered mixtures;
- real Indian solo instruments;
- real Indian film mixes (once lawful).

## 8. Dimensions: what can be trained now (Task F)

| Dimension | Trainable now with permissive data | Needs new annotations or recordings |
|---|---|---|
| Identity (Western families) | Yes (NSynth, Slakh, OpenMIC subset): synthetic / Western domain | Indian identities: recordings (§6) |
| Source type | acoustic vs electronic (NSynth); electronic kits (E-GMD) | imitation pairs (Casio + real); sampled vs real ensembles |
| Character | NSynth qualities (10 labels) | Film-mix character |
| Processing | Self-applied effects (exact labels) | Effects as heard in real mixes |
| Role | — | Role annotations (none exist) |
| Sound design | FSD50K CC0/CC-BY subset | Film annotations |
| Timing | Slakh / synthetic layered; Sanidha (pending) | Film annotations |

**Examples (from the brief, kept):**
- distorted guitar = electric guitar + distortion;
- shimmering = character;
- skittering synth = electronic + character + role;
- 808 = synth bass/kick + character "808-style";
- bass drop and riser = sound design;
- interlude lead = role.

**Never output** a plugin, synth model or hardware name.

## 9. E2 and launch A/B: status at the time of writing

| Experiment | Run | Commit | Status | Jobs | Artifacts | Decision possible? |
|---|---|---|---|---|---|---|
| E2: PANNs CNN10 challenger | [41386940981](https://github.com/TMServicesindia/tonepilot/actions/runs/41386940981) | 9bf59ceba83a | **in progress** (embedding step) | embed: running; calibrate: pending | none yet | **No** |
| Launch A/B, same machine | [41386232452](https://github.com/TMServicesindia/tonepilot/actions/runs/41386232452) | 56d78ee4e08c | **completed, success** (after this report was first written) | ab: done | `launch-ab` (JSON + logs) | **Yes:** no regression (see PROJECT_MEMORY §6j) |

Neither run was modified, cancelled or rerun.

## 10. Decisions and unresolved questions (owner)

1. **Approve the recording programme (§6)** and the volunteer-musician outreach (letter template exists; nothing has been sent).
2. **Approve the hierarchical parents** for the difficult pairs (§4), i.e. abstention at parent level instead of guessing.
3. **The v2 id `kuzhal` is ambiguous** (Tamil bamboo flute vs Kerala double reed): rename or split? (`needs_review`).
4. Musician checks for the 19 `needs_review` terms (thappattai vs parai, thara, khomok, iktara, Kinnera veena, pump organ, Greek baglama, swarlin, …).
5. The Sanidha access email (draft) and the Saraga Audiovisual licence check, both still pending.

**What is still impossible to validate:**
- any accuracy on **real Indian film mixes** (no lawful annotated data);
- any Indian identity beyond Sanidha's five (no recordings);
- role and sound-design accuracy (no annotations);
- iPhone performance of any candidate (no physical-device run yet).
