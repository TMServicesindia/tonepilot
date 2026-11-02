# Instrument taxonomy v3: proposal (not applied)

`Native/tools/instruments/taxonomy.json` (v2: 13 families, 72 keys) is **unchanged**, so that v2–v4b results stay comparable. This proposal maps the owner's list (2 Nov) onto the v2 identifiers, keeps existing ids wherever possible, and marks each class's data status.

**Status per class (honest, 2 Nov):**
- **experimental:** permissive real data exists for it, but nothing is validated yet;
- **synthetic-only:** only GM / synthesised data available;
- **unsupported:** no usable data.

No class is validated on real Indian audio yet, so **none is "supported"**.

| v3 family | Instrument (v2 id kept) | v2 family today | Real permissive data found | Status |
|---|---|---|---|---|
| Bowed strings | violin, viola, cello, double bass, **sarangi** | Strings | Violin: **Sanidha** (Carnatic), NSynth (string family), Commons viola 17. Sarangi: none | violin experimental; viola/cello/double bass synthetic-only + NSynth; sarangi unsupported |
| Plucked strings | sitar, veena, tanpura, mandolin, guitar, **banjo (new)** | Indian plucked / Other plucked | Tanpura: **Sanidha**. Veena: Commons 28. Guitar: NSynth, OpenMIC | tanpura and veena experimental; sitar unsupported; others synthetic-only + NSynth |
| Winds | bansuri, flute, piccolo, shehnai, nadaswaram, clarinet, oboe (+ kuzhal, saxophone, pan flute, shakuhachi, duduk kept) | Indian winds / Western winds / Other winds | Flute, reed: NSynth, OpenMIC. Nadaswaram: Commons 1. Bansuri, shehnai: none | flute/clarinet/oboe NSynth + synthetic; bansuri/shehnai/nadaswaram unsupported |
| Brass | trumpet, trombone, french horn ("horn"), **tuba (new)**, kombu, brass section | Other | NSynth brass, OpenMIC trumpet | synthetic + NSynth; kombu unsupported |
| Keyboard | piano, electric piano, organ, harmonium, accordion | Keys | NSynth, OpenMIC piano/organ. Harmonium: none | synthetic + NSynth; harmonium unsupported |
| Bells and mallets | celesta, glockenspiel, music box, marimba (+ **xylophone** as an alias), vibraphone, tubular bells, kalimba, santoor | Bells | NSynth mallet; santoor: none | synthetic + NSynth; santoor unsupported |
| Indian percussion | tabla, mridangam, ghatam, kanjira, dholak, thavil, dhol | Indian percussion | Mridangam + ghatam: **Sanidha**. Tabla: Commons 21, Four-Way Tabla (CC BY 3.0, to confirm). Dholak: Commons 10 | mridangam/ghatam/tabla/dholak experimental; kanjira/thavil/dhol unsupported |
| Western percussion | drums (kit) → split into **drum kit, timpani, cymbals, snare, bass drum** (new sub-ids) | Other percussion | Slakh drums, OpenMIC drums/cymbals | synthetic-only (Slakh) + OpenMIC |
| Electronic | synth lead, synth pad, bass synth ("synth bass"), **arpeggiator (new)**, electronic percussion, orchestral synth, synth brass, ambient/hybrid texture | Electronic | NSynth synthetic, Slakh synths | synthetic-only |
| **Voice (new family)** | **lead vocal, backing vocal (new)**, choir (moved from Other) | Other (choir only) | Sanidha vocals, OpenMIC voice | lead vocal experimental |
| Bass | bass guitar (+ double bass cross-listed) | Bass | NSynth bass, Slakh bass | synthetic + NSynth |

**Fields per class (v3):**
- `id`, `family_id`, `parent` (for subtypes/variants), `aliases`;
- `status` (supported / family_only / experimental / unsupported);
- `difficult_pairs`;
- `tone_map` (kept, but used only by the Tone Maker, never by the analyser).

**Source** stays a separate prediction: acoustic / electronic / imitation / unknown. **Role** is also separate: lead / counter_melody / harmony / bass / rhythm / drone / texture / unknown.

**Difficult pairs, evaluated explicitly.** The analyser may answer with the parent, e.g. "Indian double-reed (subtype uncertain)":
- bansuri ↔ flute;
- nadaswaram ↔ shehnai (parent: Indian double reed);
- veena ↔ sitar (parent: Indian plucked lute);
- sarangi ↔ violin (parent: bowed strings);
- santoor ↔ mallets (parent: struck strings / bells);
- tabla ↔ mridangam ↔ dholak (parent: Indian hand drum);
- acoustic violin ↔ synth strings (source);
- real flute ↔ flute-like synth (source).
