# TonePilot analysis server (optional)

Heavy analysis that an iPhone can't do well, run on **your Mac or a server you control**:

* **Stem separation**: [Demucs](https://github.com/adefossez/demucs) (MIT). `htdemucs` gives vocals/drums/bass/other; `htdemucs_6s` adds piano and guitar, which the Demucs authors say are weaker.
* **Vocal melody transcription**: [Spotify Basic Pitch](https://github.com/spotify/basic-pitch) (Apache-2.0) on the vocal stem. This is reduced to one playable top line, with Basic Pitch's overtone "ghost notes" removed and its pitch bends converted to cents.

The app works without this server: it analyses on the phone, and the melody then comes from the full mix. With the server, the melody comes from the separated vocals, and section activity uses real stem levels.

## Privacy

* The app uploads a song only when the server is enabled in Settings **and** you confirm the upload for that song. The server refuses uploads without `consent=true`.
* The uploaded file is deleted as soon as processing finishes. Stems and results are deleted when the app calls `DELETE /v1/jobs/{id}` (it does this after downloading), or automatically after `TONEPILOT_RETENTION_HOURS` (default 24).
* Set `TONEPILOT_TOKEN` so that only your phone can use the server. The token stays on your devices; there are no third-party API keys.

## Run on a Mac

```bash
cd server
python3.11 -m venv .venv && source .venv/bin/activate   # Python 3.10–3.11 (Basic Pitch 0.4.0 doesn't support 3.13)
pip install -r requirements.txt
brew install ffmpeg                                      # Demucs needs it to read MP3/M4A
export TONEPILOT_TOKEN=choose-a-long-random-string
uvicorn tonepilot_server.app:app --host 0.0.0.0 --port 8765
```

In the app, go to **Settings › Analysis server** and enter `http://<your-mac-ip>:8765` and the token. The first separation downloads the Demucs model weights (about 80 MB) from `dl.fbaipublicfiles.com`.

Rough speed: a 4-minute song takes about 1–3 minutes with `htdemucs` on an Apple Silicon Mac's CPU. That figure is an estimate and wasn't measured here.

## API

| Method | Path | Notes |
|---|---|---|
| GET | `/v1/health` | Versions, which engines are installed, whether auth is required |
| POST | `/v1/jobs` | multipart: `file`, `consent=true`, `model=htdemucs\|htdemucs_6s`, `transcribe=vocals\|none` → `202 {id}` |
| GET | `/v1/jobs/{id}` | `{status: queued\|separating\|transcribing\|done\|failed, progress, error}` |
| GET | `/v1/jobs/{id}/result` | `{stems:[{kind,url,model}], melody: MelodyTrack JSON, models:[licenses], retentionHours, notes}` |
| GET | `/v1/jobs/{id}/stems/{kind}.wav` | 16-bit WAV stem |
| DELETE | `/v1/jobs/{id}` | Removes everything for the job |

## Tests

```bash
pip install -r requirements-dev.txt
pytest tests
```

Verified in development:

* All 8 server tests pass, including one running **real Basic Pitch 0.4.0**: a test tune is transcribed exactly ([64, 67, 69, 72]), and the overtone ghosts at 79 and 91 are removed.
* A Swift ↔ Python live round trip passes (`TonePilotCore` `AnalysisServerTests.testLiveServerRoundTrip` against `python -m tests.dev_server`).
* Demucs itself **was not run**. Its weights couldn't be downloaded in the build environment, so the tests use a fake separator. Run a real separation on your Mac before relying on it.

Dependency notes found while testing: on Linux, Basic Pitch pulls TensorFlow, which needs `numpy<2`, and `resampy` still imports `pkg_resources` (`setuptools<70`). Both are pinned in `requirements.txt`.
