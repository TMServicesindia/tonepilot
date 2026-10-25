# Casio CT-X870IN hardware test checklist

Tick each item on a real iPhone. Note the iPhone model, iOS version and adapters you used.

## A. MIDI input
- [ ] Casio on, USB TO HOST → cable → camera adapter / USB-C → iPhone.
- [ ] Settings › MIDI & audio diagnostics lists the Casio (the name usually contains "CASIO"). If not, power the adapter and tap **Rescan**.
- [ ] Pressing a key logs `Note On` with a velocity that changes with how hard you play (touch response on).
- [ ] Releasing logs `Note Off` (or Note On vel 0, shown as Note Off).
- [ ] Sustain pedal (if connected to the Casio) logs `CC 64 (Sustain) = 127/0`. **Record whether the CT-X870IN sends it over USB.**
- [ ] Pitch bend wheel logs `Pitch bend`. **Record whether it is sent.**
- [ ] Keyboard Transpose/Octave on the Casio: record whether it shifts the transmitted notes.
- [ ] Unplug the cable while holding a chord: the sound stops (auto panic) and no note stays stuck.
- [ ] Replug: the device reappears and plays without restarting the app.

## B. Audio output to the Casio
- [ ] 3.5 mm cable from the iPhone's audio output (hub/DAC) into Casio AUDIO IN.
- [ ] Diagnostics › Audio output shows the expected route (not "Speaker").
- [ ] Audition strip notes are audible through the Casio speakers.
- [ ] No hum or distortion at ~60 % iPhone volume. Record the comfortable volume.
- [ ] The Casio's own voice is silenced (tone volume down or Local Control off). Record which method works on this model.

## C. Playing
- [ ] Piano + Strings + Bell starter tone: all three sound, and the bell only from C4 up.
- [ ] Measured latency in Diagnostics: ____ ms. Playing feels immediate (target < 15 ms).
- [ ] 6 layers × 10-note chords with sustain: no dropouts or crackle. Record the max layer count that stays clean.
- [ ] CLIP light stays off at normal playing. Hard chords with 4+ layers: the limiter prevents harsh distortion.
- [ ] PANIC silences everything instantly.

## D. Engine & tones
- [ ] Settings › Sound engine = TonePilot engine. Diagnostics shows a voice count while you play.
- [ ] Layer envelope override: a long attack audibly fades in; release changes the tail.
- [ ] Filter, EQ, chorus and reverb sliders change the sound while you hold a chord.
- [ ] Bansuri-like Flute: legato playing glides between notes; vibrato fades in on held notes; the pitch wheel bends ±2 semitones.
- [ ] 8 layers × 10-note chords with sustain: no crackle. Record the max clean layer count: ____ (iPhone model ____).
- [ ] Legacy Apple sampler engine still plays (fallback).

## E. One-click song workflow
- [ ] Import an MP3 you own with *Analyse & arrange automatically* on; it completes (4-min song: ____ s) and every section has a tone.
- [ ] Sections with singing get a right-hand lead; instrumental interludes get a motif tone. Note any wrong labels.
- [ ] *Play on My Casio* opens Perform with the first section's tone.
- [ ] Left hand: the guide's Root → Fifth → Root matches the song for most chords; corrections stick after re-analysis.
- [ ] Right hand: the melody guide's keys match the tune for most phrases (note the octave shift for male voices).
- [ ] Automatic switching with the backing track changes tone at each section; held notes don't cut off.
- [ ] Assisted mode highlights the next section and switches on tap. Timer mode works when started on beat 1.
- [ ] Bass, drums, metronome and melody guide each switch on and off independently; with everything off only your tones sound.
- [ ] Reference Learning plays the melody; Live Play doesn't.
- [ ] Regenerate this section changes only that section; Restore AI Original undoes your edits.
- [ ] Listen Mode with a link: paste a YouTube link → title fills in → *Open & listen* opens YouTube, TonePilot keeps listening in the background (orange mic dot), and the song appears analysed when it ends. Repeat with Spotify playing on the same iPhone.
- [ ] Listen Mode quality: compare BPM/key/chords against a known song; note the volume/room that works best.
- [ ] Analysis server (optional): the upload asks first; stems and vocal melody arrive; the server job folder is deleted afterwards.
- [ ] BPM is right or off by exactly ×2/÷2 (the fix buttons work).
- [ ] Section buttons in Perform switch tones instantly while playing; held notes release cleanly.
- [ ] Section play/loop plays the song section through the Casio while you play along.
- [ ] Phone call / Siri interruption: sound stops, and comes back after the interruption without restarting the app.
- [ ] Kill the app mid-analysis, relaunch: analysis resumes.
