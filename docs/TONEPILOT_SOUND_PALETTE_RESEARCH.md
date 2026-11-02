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

### 1.1 Promotions found on 2 Nov (song-level, `DOCUMENTED_SECONDARY`)

Full table with links: [`benchmark/SOUND_PALETTE_COVERAGE_AND_DATA_PLAN.md`](benchmark/SOUND_PALETTE_COVERAGE_AND_DATA_PLAN.md) §3.

| Composer | Song / album | Claim | Source |
|---|---|---|---|
| Ghibran | *Uttama Villain* | Tabla, ghatam, dholak **not** used; Bali instruments | https://en.wikipedia.org/wiki/Uttama_Villain_(soundtrack) |
| Santhosh Narayanan | *Sarpatta Parambarai* | 1970s skin-headed instruments; gaana musicians | https://en.wikipedia.org/wiki/Sarpatta_Parambarai_(soundtrack) |
| Pritam | *Kalank*, "Tabaah Ho Gaye" | Qanun (Tamer Pınarbaşı), glockenspiel, pakhawaj | https://thegreatbollywoodparty.com/2019/04/17/music-review-kalank-2019/ |

Searched and `NOT_FOUND`:
- the *Vathikuchi* avoidance;
- the *Madrasapattinam* oboe and santoor;
- *Kalank* bagpipes, hulusi, ney and bulbul tarang;
- saxophone on *Vaaranam Aayiram*.

**Normalised inventory of all 165 terms in §1, §1b and §1c:** [`benchmark/sound_palette_inventory.json`](benchmark/sound_palette_inventory.json) and the coverage report §2. The owner-supplied entries below are kept unchanged.

## 1b. Owner-supplied composer palette (2 Nov): **OWNER-SUPPLIED, unverified; no sources attached**

The owner supplied per-composer palettes for 6 + 25 music directors across Tamil, Hindi, Telugu, Malayalam and Kannada film. **How they are used:**
- **Yes:** as a **coverage checklist**, deciding which sounds the taxonomy and the data collection must cover, and in what priority.
- **No:** as labels or as a prior. A composer's name never makes the analyser predict an instrument, and a song's ground truth always comes from listening plus credits.
- **Promotion to DOCUMENTED** happens per claim, only when a source (interview, liner or session credit) is found and linked in §1.

### 1b.1 Six primary composers (owner summary)

| Composer | Core / signature sources | Electronic / production | Processing, roles and character mentioned |
|---|---|---|---|
| A. R. Rahman | veena, nadaswaram, bansuri/flute, tabla, shehnai, sitar, mridangam; orchestral strings, cello, harp; flamenco guitar, accordion/harmonium, piano; rock bass (Guy Pratt) | synths, keyboards, **harpejji** | "Syncretic" layering of different idioms |
| Yuvan Shankar Raja | guitar, violin, synth, piano, many Indian folk drums (*Avan Ivan*) | drum machines, "skittering" synths | Simple melody over dense synth/folk beds |
| Harris Jayaraj | guitar (incl. "Carnatic-styled" guitar), piano, strings, flute, **saxophone**; classical humming | synth programming, polished layering | Sax/guitar **interlude leads**; strings building to a crescendo |
| G. V. Prakash Kumar | **mridangam** (trained), guitar, keys/piano, mandolin, electric guitar, **Greek baglama, oud, bouzouki, saz**; tabla, flute, sitar, dhol | "mild" synths, drums | Global plucked strings with Indian percussion |
| Anirudh Ravichander | nadaswaram, thavil, urumee, shehnai, veena, saxophone; distorted electric guitar, acoustic guitar plucks | EDM, trap, hip-hop beats, synths, **808 bass**, bass drops | Traditional leads **with distortion over electronic beats**; dark ambient + synth-pop |
| Vidyasagar | **santoor, vibraphone**, harmonium, keyboard, piano, guitar, violin, flute, strings | keyboard | Melody-forward preludes ("guitar–violin–flute"); "shimmering" character |

### 1b.2 Further composers (owner summary, condensed)

| Industry | Composer | Sources named (beyond common guitar, keys, drums, strings) | Production / character named |
|---|---|---|---|
| Hindi | R. D. Burman | santoor, vibraphone, mouth organ, banjo, tambourine, dafli, castanet, conga, sax, trumpet | electric organ, synth; jazz trumpet, groovy guitar |
| Hindi | Bappi Lahiri | tabla, dholak, bongos, sax | **Moog synth, drum machines**, disco strings, horn sections, syncopated bass |
| Hindi | Shankar–Ehsaan–Loy | live band; tabla, dholak, dhol, mandolin, shehnai, sarangi, flute | layered keyboard harmonies; rock/blues guitar, jazz keys |
| Hindi | Pritam | accordion, **bagpipes, hulusi, ney, qanun**, sitar, glockenspiel, tabla, mandolin, **bulbul tarang** | modern orchestration / programming |
| Hindi | Amit Trivedi | sitar, **esraj**, sarangi, **iktara**, dholak, clarinet, oboe, mandolin, harmonica, harmonium | keyboard sequences, techno elements; "rustic, organic" |
| Hindi | Vishal–Shekhar | dhol, banjo, tambourine, trumpet | **heavily distorted electric guitars** (processing, not an instrument) |
| Hindi | Himesh Reshammiya | tabla, dholak, sarangi, sitar, bongos, harmonium, violin | programming; soft-rock backdrop |
| Hindi | Mithoon | **piano** (defining), acoustic guitar, live strings, tabla, ghatam, **ghungroo** | ambient synths, loops; minimalist |
| Hindi/Bengali | Jeet Gannguli | guitar, tabla, flute, violin, **khomok**, kanjira | Bengali folk rhythm |
| Tamil | Ilaiyaraaja | veena, **venu**, nadaswaram, dholak, mridangam, tabla, sax, flute, orchestra | **Yamaha DX7, Roland Jupiter-8, E-mu drumulator, MIDI** (character / source type only; the model never names hardware) |
| Tamil | Santhosh Narayanan | **pambai, thudumbu, urumi, parai, thara, thappattai**, thavil, kanjira, nagaswaram, trumpet | "raw, authentic"; occasional electronics |
| Tamil | Sean Roldan | acoustic/electric guitar, harmonium, violin, flute, thavil, mridangam, sax | indie grooves, guitar riffs |
| Tamil | Ghibran | strings, piano, **Balinese/Indonesian instruments** | synth bass; jazz–folk fusion |
| Tamil | D. Imman | nadaswaram, trumpet, sarangi, dhol, tabla; **harpejji, Continuum fingerboard** | some projects all-live, no electronics |
| Tamil | Sam C. S. | banjo, mandolin, ethnic sounds, **six-foot bamboo instrument**; 72-piece orchestra, full brass | dark, intense orchestral |
| Tamil/Telugu | Vishal Chandrashekhar | 140 musicians on native instruments (*Sita Ramam*) | German electronic instruments; swing + EDM |
| Tamil | Justin Prabhakaran | keyboard, guitar | layered programming; church-influenced harmony |
| Tamil | Nivas K. Prasanna | piano, keyboard, bass guitar | clean modern production |
| Tamil | Karthik Raja | piano, guitar, string ensembles, dholak, tabla, violin | synth beats, reverbs |
| Telugu | Mani Sharma | keyboard, synth, piano, mandolin, harmonium, guitar, drums, tabla | "total mass effect" |
| Telugu | Devi Sri Prasad | shehnai, mandolin, harmonium, violin ensembles, guitar | electric pads, drums |
| Telugu | M. M. Keeravani | harmonium, violin, cello, flute, guitar | classical ragas over Western arrangement |
| Telugu | S. Thaman | drums, rhythm pads, trumpet, **Kinnera veena** | heavy guitar riffs, rhythm programming |
| Malayalam | Sushin Shyam | **tar, saz, kamancheh**, veena, acoustic guitar, trumpet, flugelhorn, sax, trombone | EDM, atmospheric |
| Malayalam | Rex Vijayan | guitar, synth, ukulele, mandolin, horns, **chendamelam** | alt-rock, techno |
| Kannada | Arjun Janya | piano, guitar, string orchestra, operatic female voice, dhol, **tumbi** | echoing synths |
| Kannada | V. Harikrishna | harmonium, keyboard, guitar, **pump organ** | vocal-driven |

### 1b.3 What this changes in the taxonomy proposal (candidates only; data status as in §7)

Sources named here that are **not in v2 or the v3 proposal yet** (add as candidate ids, status `unsupported` until data exists):

| Group | New candidate sources |
|---|---|
| Indian / South Asian winds and strings | venu (alias of bansuri/kuzhal family), esraj, iktara, tumbi, bulbul tarang (Indian banjo), Kinnera veena, pump organ (alias of harmonium) |
| Tamil folk percussion | pambai, thudumbu, urumi/urumee, parai, thara, thappattai |
| Kerala / Bengali / other percussion | chenda (chendamelam ensemble), khomok, ghungroo, dafli |
| World plucked / bowed | oud, bouzouki, saz/baglama, tar, kamancheh, qanun |
| World winds | ney, hulusi, bagpipes, mouth organ (alias of harmonica) |
| Electronic instruments (identity) | harpejji, Continuum fingerboard (both electronic), 808 bass (character of synth bass / kick) |
| Percussion (Western/Latin) | castanet |

**Not identities, so they map to other dimensions:**

| Named in the brief | Dimension |
|---|---|
| "Distorted electric guitar" | processing |
| "Shimmering" | character |
| "Skittering synths" | character + role |
| "Bass drops", "808" | character / role |
| "Moog, DX7, Jupiter-8, drumulator" | source type = electronic. **Never output a hardware name** |
| "Operatic voice", "classical humming" | voice family + character |
| "Interlude lead" | role |

### 1b.4 Data-collection priority from coverage (INFERENCE)

These are the sources named by the most composers in the owner's lists. They are counted as mentions, not usage frequency:
- strings/violin, guitar (acoustic/electric), piano/keys, synths/pads, flute;
- tabla, harmonium, dholak/dhol, mandolin, saxophone, nadaswaram/shehnai, thavil, sitar, santoor, trumpet/brass.

Implications:
1. Most of the **Indian** items in this list have **no permissive real data yet** (§7 and the dataset research §3): harmonium, nadaswaram, shehnai, thavil, sitar, santoor, sarangi, bansuri.
2. **They are the first owner/musician recording targets**, together with the Tamil folk percussion set above. Volunteer musicians and written permission, using the existing letter template.
3. Casio imitations of all of them are useful **only** as `imitation` source examples.

## 1c. Owner-supplied deep-dive (2 Nov): **OWNER-SUPPLIED, unverified**; same rules as §1b

### 1c.1 New claims and what each means for the analyser

| Composer (claim) | New sources | Implication for TonePilot |
|---|---|---|
| Ilaiyaraaja: "unusual conversations" (guitar ↔ veena, trumpet ↔ flute call-and-response); melodically dynamic basslines; polyrhythms; constant harmonium | — | Annotate **interplay** between events (`responds_to`), not only overlap. The bass role must allow melodic movement. Polyrhythm belongs to rhythm analysis, not to instrument labels |
| Santhosh Narayanan: *Sarpatta Parambarai* drums with **animal-skin vs fibre heads**; gaana musicians; mridangam with rap | — | Drum-head material is a **character variant** of the same identity. It is likely beyond what can be told apart in a mix (INFERENCE), so record it but don't promise it |
| Ghibran: *Uttama Villain* **avoided** tabla, ghatam, dholak and used **Balinese/Indonesian** instruments; *Vathikuchi* avoided flute, veena, acoustic guitar, sax, using heavy bass, low strings, trumpet, trombone | Gamelan family: metallophones, gongs (**new candidates**) | **Documented absence is valuable ground truth.** Annotations need an explicit `absent` list (unlabelled ≠ absent). "Both Indian and exotic" timbres are where the model must abstain |
| Yuvan: *Avan Ivan* **without synths or Auto-Tune** | — | Add **pitch correction** as a processing label (the effect, never the product name) |
| Harris Jayaraj: synth + bass guitar + drums + R&B; "haunting" guitar lines | — | Character and role (interlude lead guitar) |
| Anirudh: within-song **switch from Western drums to Tamil folk rhythm**; electronic scratches; bass drops | Turntable scratch (sound design) | Temporal **handover inside a section**; the scratch is sound design |
| Nadeem–Shravan: **bansuri, sitar, shehnai** in almost all songs | — | All three are unsupported Indian priority sources, which reinforces the recording priority (§1b.4) |
| Amit Trivedi: Chennai String Orchestra; piano + acoustic guitar + bass guitar | — | A test case for real orchestra vs sampled strings (source type) |
| Vishal–Shekhar: **dhol tasha**, Indian reeds, woodwinds | Dhol tasha (new candidate, ensemble) | — |
| Sushin Shyam: **melodica** | — | Already a v3 candidate |
| Rex Vijayan: **dilruba, sarod, hang drum, electric violin**, oud | Dilruba, sarod, hang drum, electric violin (**new candidates**) | New **difficult pairs**: sarod ↔ sitar ↔ veena (parent: Indian plucked lute); dilruba ↔ esraj ↔ sarangi (parent: Indian bowed) |
| A. R. Rahman: **Kurzweil K2000, Korg M1, Auto-Tune** | — | Hardware/product names map to source type = electronic plus a processing label. **The model never outputs a product name** (it can't be known from a mix) |

### 1c.2 The owner's structured fields: where each one goes

| Owner field | Where it lives | Allowed use | Not allowed |
|---|---|---|---|
| Primary composer | **Song-level metadata** (catalogue) | Per-composer reporting; **composer-held-out test split** (does the model generalise beyond the composers it was trained on?) | Model input, prior or threshold (it would leak "composer → instrument") |
| Core / folk / regional instruments | **Event-level annotation** (identity) per song, from listening + credits | Ground truth after human verification | Copying a composer profile into a song's labels |
| Electronic / processed elements | Event-level **source type, character, processing** | Ground truth after verification | Product names (K2000, M1, DX7) as labels |
| Orchestral elements | Event-level identity (ensemble ids) + source type (real vs sampled) | — | — |
| Signature production technique | Event relations (`responds_to`, `handover_from`) + notes | Analysis and reporting | A label the model must predict |
| Rhythmic foundation | Rhythm analysis chain + percussion events | — | — |
| Genre context, era | Song-level metadata | Stratified reporting; split design | Model input |

**Annotation schema additions** (extends the roadmap §3 proposal; not applied yet):
- song level: `composer`, `industry`, `year`, `genre_context`, `credits_source`, `absent`;
- event level: `responds_to`, `handover_from`.

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
