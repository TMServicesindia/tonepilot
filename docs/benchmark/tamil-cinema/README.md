# Tamil cinema acceptance set

A **development and acceptance benchmark** of 10–20 Tamil film songs, not a training corpus. Files:
- `SOURCE_SURVEY.md`: which sources contain real audio, which are metadata or features only, and their licences.
- `catalogue.json`: the 20 candidate songs with the manifest fields, split by song identity
  (11 train / 4 dev / 5 test). All are `UNVERIFIED` until lawful audio exists.

## How to add a song (owner recording, preferred)

1. Record the song's accompaniment on the CT-X870IN (line out or the app's Record tab), 30–90 s
   per section. The melody can go on a separate take.
2. Send the file here, with notes per section, for example:

   > Pallavi: adi (8), 92 BPM, chords Am | Am | G | F …, piano broken chords R-5-8-5.
   > Charanam: same cycle, strings sustained, no fill.

3. I fill in the manifest fields: audio SHA-256, duration, beats, chords, sections, accompaniment
   type, confidence. You confirm or correct them. Audio is never committed to GitHub.

Licence field for owner recordings: `owner recording; composition © rights holder; private
development use only`, with status `Personal only`.

## Not accepted

Files from download/piracy sites, YouTube rips, or anything without a licence or permission.
