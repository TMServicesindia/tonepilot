# Tamil cinema acceptance dataset — source survey

**Date:** 1 November 2026 (IST). **No audio was downloaded or used.**
Method:
- GitHub: repository search, README text and file names read; no file contents.
- Hugging Face and Zenodo: public APIs read from CI (`dataset-survey.yml`, results on branch
  `research/dataset-survey`). 205 Hugging Face datasets and 123 Zenodo records were checked.

**Incident:** while listing files in `AMAAI-Lab/singapore-music-classifier`, a `git ls-tree -l` call
fetched about 108 MB of file contents (asking git for file sizes triggers on-demand downloads).
It was stopped, only the file names were read (all spectrogram images, no audio), and everything
was deleted unopened. File lists are now read only from README text or APIs that report names.

## 1. Sources the owner suggested

| Source | What it actually contains | Licence / permission | Verdict |
|---|---|---|---|
| masstamilan.dev | Commercial film songs | None (unauthorised download site) | **Excluded** (standing rule) |
| github.com/sajeevan16/tamil-songs-corpus | **Text only**: lyrics and metadata for ~4,217 songs scraped from tamilpaa.com; no audio | No licence file; lyrics are copyrighted | **Metadata only — excluded** |
| github.com/code-mohanprakash/tamil | **Features only**: per-song librosa statistics (tempo, energy, MFCC means) and scene tags for 221 Anirudh songs; no audio. Folder names (`jailer_320kbps_masstamilan_dev`, …) show they were computed from MassTamilan rips | No licence; derived from pirated files | **Features only, pirated origin — excluded** |
| huggingface.co/datasets/Thanushs25/tamil-audio-emotion-classification | **Audio: 195 WAV files of Tamil *speech*** in emotion folders (angry, …); not music | **No licence declared** | **Speech, UNVERIFIED — excluded** |

## 2. Other candidates found

| Source | Contents | Licence | Verdict |
|---|---|---|---|
| github.com/AMAAI-Lab/singapore-music-classifier | 15,390 spectrogram images (Malay/Hindi/Tamil/Chinese excerpts) + code; no audio | None | Features only — excluded |
| github.com/rajkumar-dhanasekaran/tamil-film-songs-metadata | **Metadata only**: 3,033 Tamil film songs (film, title, composer, singers, lyricists) with sources | **CC0** | **Usable for catalogue fields** (not audio) |
| github.com/Sam-Kon/KritiSamhita… (+ Mendeley DOI 10.17632/nkdm57hvw3.1) | Code; dataset = 20 s Carnatic classical snippets, tonic labels | Dataset licence and recording rights **not verified** | UNVERIFIED — excluded |
| Hugging Face: bollywood4u/dataset, sathyavgc/bollywood-romantic-30s, AIniruddh/fma-indian-music-merged, rojin254/PP4-indian-music-csi, King758/tamil-raw-audio, Patil/tamil-audios, carnatic-* sets, … | Audio present (files or parquet audio columns) | **No licence declared** (most look like scraped commercial music) | UNVERIFIED — excluded |
| Hugging Face: shivareddy-03 / svanitha tamil-audio-dataset (20 files), InfoBayAI call-centre/podcast (gated) | Speech | CC BY 4.0 | Not music — not useful |
| Zenodo 19986940 "Indian songs_Tonic_Dataset" | Zip (1.45 GB) | CC BY 4.0 declared by uploader | **UNVERIFIED**: uploader's right to licence film songs not shown — excluded unless evidence appears |
| **Zenodo 17405610 / 16411600 "Saraga Audiovisual" (+ Mini, 519 MB)** | Carnatic and Hindustani concert recordings with rich annotations (tala/sama, sections, melody, tonic) | **CC BY 4.0** declared | **Candidate for rhythm-cycle acceptance (Phase 2 S6)**, after reading the record text to confirm the licence covers the audio. Classical, not cinema |
| Zenodo 4301737 Saraga (original), Mridangam/Tonic/Varnam sets | Classical audio + annotations | CC BY-NC / NC-SA / NC-ND | Non-commercial — evaluation only, never training; excluded from commercial-path data |

## 3. Conclusion

1. **No source provides lawful audio of the requested Tamil cinema songs.** These are commercial
   recordings owned by labels; nothing found carries permission for analysis or model development.
2. Lawful routes for the cinema set, in order of preference:
   - **a. Owner recordings:** the owner plays the songs' accompaniment (and optionally the melody)
     on the Casio CT-X870IN and records it. The owner owns the recording and knows the true chords
     and patterns, so annotation is easy and accurate. (The songs themselves remain copyrighted;
     keep these recordings private to development and do not publish them.)
   - **b. Written permission** from a rights holder (label, composer or musician) for the stated use.
   - **c. Owner-purchased copies** (legitimate stores) for **private evaluation only**: marked
     `Personal only` and never used for training. Get legal advice before relying on this.
3. For classical rhythm cycles, Saraga Audiovisual (CC BY 4.0) can supplement Phase 2 acceptance
   once its licence text is confirmed.
4. 10–20 songs are an **acceptance and development benchmark**, not enough to train a
   general-purpose music model.
