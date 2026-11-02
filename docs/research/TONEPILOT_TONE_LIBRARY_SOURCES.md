# TonePilot — Lawful sample sources for TonePilot's own tones (2 Nov 2026)

**Owner question:** can we fetch sample data for better tones, even Casio or Yamaha tones?

**Answer:**
- **Casio and Yamaha factory samples: no.** Their built-in sample data is proprietary and copyrighted. "Extracted ROM" sets online are unlicensed copies, the same category as the pirated audio the project excludes.
- The owner's **own Casio** can still be **recorded** tone by tone as a search candidate (proposal §4c), never redistributed.
- What we can use are **openly licensed recordings of real instruments**, verified at source.

## 1. Verified sources

| Library | Licence (verified) | What it contains | Use |
|---|---|---|---|
| **VSCO 2 Community Edition** (`sgossner/VSCO-2-CE`) | **CC0 1.0** (LICENSE file, read 2 Nov) | Real recordings: **solo violin, violin / viola / cello sections, contrabass, harp, flute, piccolo, oboe, clarinet, bassoon, F horn, trumpet, tenor trombone, tuba**, organ, 2 upright pianos, orchestral percussion (≈ 3,200 files) | **Ship as TonePilot tones** (no conditions) |
| **Versilian Community Sample Library, VCSL** (`sgossner/VCSL`) | **CC0 1.0** (LICENSE + README: "even make commercial software, no royalties, no credit") | **Steinway B and Kawai grands, Yamaha and Knight uprights**, harpsichords, concert and folk harp, recorders, harmonicas, tenor sax, saxello, pipe organ, TX81Z FM pianos, kalimba / mbira, balafon, **marimba, vibraphone, xylophone, glockenspiel**, tubular bells, dan tranh zither, darbuka, frame drum, cajon, congas, bongos, timpani, cymbals, shakers | **Ship as TonePilot tones** |
| **MuseScore General** SoundFont | **MIT** (MuseScore handbook; Fedora packaging notes); keep the notices | General MIDI bank (FluidR3 lineage) | Optional extra GM bank; also usable as a new sealed TEST bank *if not shipped* |
| University of Iowa Musical Instrument Samples | Free since 1997; one quoted licence says the samples **must not be redistributed "as is" (as samples or a sampler instrument)** | Real anechoic recordings of orchestral instruments | **Evaluation only:** a **real-recording sealed TEST** for tone recreation; **not shipped** |
| Sonatina Symphonic Orchestra | CC Sampling Plus 1.0 (per MuseScore handbook) | Orchestral | **Avoid:** ambiguous for redistribution inside an app |
| Indian instrument libraries | **None openly licensed found** (only commercial packs: Sitar Nation, Big Fish, etc.) | — | Gap. Routes: Freesound / Commons **per-file** CC0 / CC-BY, volunteer musicians with written permission, owner recordings |

## 2. What this changes

- **TonePilot's own tones get real-instrument samples** for the orchestral and Western palette that film songs use heavily (strings, flute, oboe, clarinet, brass, harp, pianos, mallets), instead of GM approximations.
- The tone search (T1) and the fit (T3) then choose among more realistic sounds, which matters most for "nearest recognisable sound".
- **Indian instruments remain the gap.** Synthesised imitations stay labelled as imitations until lawful real recordings exist.

## 3. Integration plan (proposal; not implemented)

1. **Format:**
   - VSCO / VCSL ship as WAV with SFZ mappings.
   - TonePilot reads SF2 and user multisamples (WAV + key ranges).
   - Either add an SFZ subset importer (key / velocity ranges, loop points, release), or convert offline in CI to SF2 or TonePilot's multisample format.
2. **Size:**
   - Raw VSCO + VCSL is large (VCSL README: about 20–75 MB per instrument as WAV).
   - Per the build rules, large assets are **downloaded in the app** like the separation models, never bundled.
   - Plan per-instrument packs, compressed (e.g. 24 kHz / mono for leads, about 3–10 MB per instrument; INFERENCE).
3. **Quality gate:** each new tone must beat the GM tone it replaces in the tone bench (DEV) **and** the owner's listening check before it becomes a default.
4. **Licences:**
   - CC0 needs no attribution; record provenance anyway (`docs/LICENSES/manifest.json`, with SHA-256 per pack).
   - MIT (MuseScore General) keeps its notice.
5. **Sealed TEST for tone recreation:**
   - **Iowa MIS real recordings** (never shipped, never tuned on).
   - FluidR3 was used once per method on 2 Nov.
   - If MuseScore General is not shipped, it can serve as a second sealed bank.

## 4. Sources (accessed 2 Nov 2026)

- https://github.com/sgossner/VSCO-2-CE (LICENSE: CC0 1.0; README)
- https://github.com/sgossner/VCSL (LICENSE: CC0 1.0; README)
- MuseScore handbook (SoundFonts and SFZ files): https://musescore.org/fr/manuel/soundfonts-et-fichiers-sfz · Fedora: https://src.fedoraproject.org/rpms/mscore/blob/f36/f/MuseScore_General_License.md
- University of Iowa MIS: https://theremin.music.uiowa.edu/MIS.html (licence quote via https://os.zynthian.org/factory_sfz/Other/VPO3-perf/Documentation/license.htm)
- Indian sample libraries survey: https://loststoriesacademy.com/blogs-and-tutorials/7-sample-libraries-for-indian-instruments-free-paid-in-2025
