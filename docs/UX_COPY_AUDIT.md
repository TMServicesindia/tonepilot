# TonePilot — Interface copy audit

*6 Nov 2026 · 235 `Text(...)` strings in `App/Sources/Views`. Principles (apple-ux-writing, content-copy-designer):*
- short;
- one idea per sentence;
- action labels as verbs;
- no developer terms;
- no repeated instructions;
- advanced context behind disclosure.

Below are the significant rewrites. Replacements are applied during implementation and checked again against the after screenshots.

| Where | Original | Proposed | Reason |
|---|---|---|---|
| Play intro tip | "**1.** Press play. **2.** In **Mix**, switch off the part you want to play. **3.** Play it on your Casio — the song plays the rest." | Remove the card. Mix page empty-mute hint: "Mute a part to play it yourself." | A one-time tutorial card pushes content down on every visit |
| Mix › split | "Separates the interlude melodies (flute, strings, nadaswaram) from the pads and chords, so the original can play just the lead parts for you." | Button "Split Music into Lead & Backing"; no paragraph (info button for detail) | The button label already says it |
| Mix › difficult parts | "Can't play a passage yet? The recording's own part plays in the sections you pick. Everywhere else, it's you." | "Original plays hard parts" + toggle; detail in info | Shorter; same meaning |
| Chord guide empty | "RIGHT HAND — No melody estimate for this song" (full card) | Hide the right-hand row when there's no melody | Empty states shouldn't take a card |
| Tone mode | "Your keys · Main tone / Per section" | "Tone: One for the song / Per section" | "Your keys" is unclear |
| My keys | "Connect the Casio's USB TO HOST port to the iPhone. Settings › Connect your Casio shows how." | Connection chip "No keyboard" → tap opens the guide | Instructions repeated on a performance screen |
| My keys | "Sound is coming from the iPhone speaker. Connect the audio cable to the Casio's AUDIO IN to hear it there." | Chip "iPhone speaker" (tap: "Connect to the Casio's AUDIO IN") | Same |
| My keys | "One tone for the whole song." / "The tone changes with each section." | Remove (the segmented control shows it) | Duplicate |
| Tone editor | "WHY THE AI BUILT THIS — AI main tone from Chorus: …" | Card subtitle "From the chorus — the song's hook" | Jargon; truncated |
| Tone editor | "Layers on the same keys sound together. Use key ranges for splits (e.g. bass on the left hand) and velocity ranges to switch sounds by how hard you play." | Under Details › Key range only | Advanced; shown to everyone |
| Tone editor | "SoundFont" badge on each layer | Source shown in Details ("Built-in", "Real instrument", "My sample") | Developer term |
| Tone editor | "M" / "S" | Mute / Solo icon buttons with labels for VoiceOver | Letters are cryptic and small |
| Blind compare | "Pick today's tone and a real-instrument tone (download them in Settings › Real instrument sounds). The test hides which is which." | "Choose two sounds. TonePilot hides which is which." | Shorter; the path changes with the Sound browser |
| Record | "Records TonePilot's own sound straight from the app (your tones, the arpeggio fill, and the song parts if included) — nothing from the room." | "Records TonePilot's sound — not the room." | One idea |
| Record | "Your recordings appear here as MP3 files. They're also in the Files app › On My iPhone › TonePilot › Recordings." | Empty state: "No recordings yet" + "Saved as MP3 in Files." | Empty-state pattern |
| Settings | "After a song is separated, it is separated again with the other model in the background (about twice the time; downloads that model once). Where both hear the same instrument the tone is surer; where they differ you can choose." | "Check tones with both models" + footer "Takes about twice as long." | Detail belongs in the info sheet |
| Settings | "The TonePilot engine supports per-layer envelope, filter, EQ, chorus, glide/vibrato, and the generated accompaniment. The Apple sampler is a simpler fallback." | "Recommended. The Apple sampler is a simpler fallback." | Feature list not needed |
| Settings | "Downloaded the first time you separate a song (Wi-Fi recommended)…" | "Downloads when first needed (Wi-Fi recommended)." | Shorter |
| Settings | "Recorded instruments from free, public-domain (CC0) libraries…" | Moves to the Sound browser footer: "Free, public-domain recordings (VSCO, VCSL)." | Shorter |
| Settings | "Everything is stored on this iPhone (Files › On My iPhone › TonePilot). Songs are analysed on-device; audio is only sent…" | "Stored on this iPhone. Analysed on-device." + "Learn more" | Privacy detail behind disclosure |
| First run | "Install sounds — Default SoundFont installed" | Remove the step | Nothing to do |
| First run | "Import songs you own as MP3s and TonePilot analyses them on-device to help you build a tone for each intro, interlude and chorus." | "Import a song you own. TonePilot finds its sounds." | One idea |
| Songs | "Title, film, composer, language, tag" (search prompt) | "Search songs" | Shorter; the scope is implied |
| Song row | "Parts ready" | Keep | Clear |
| Errors | "Lead/backing split: …", "Second separation: …" (raw error text) | "Couldn't split the music. Try again." with details on tap | Actionable first |

## Terms

| Avoid | Use |
|---|---|
| SoundFont, sample zone, stem | Built-in sound, recording, part |
| Separation model, Demucs | 4 parts / 6 parts |
| Perceptual, embedding, fingerprint | Closest sound, match |
| Analysis server (vocal separation) | Your analysis server |
