"""Server tests. Demucs is replaced by a fake separator (its weights download from
dl.fbaipublicfiles.com on first use). Basic Pitch runs for real when installed."""
import json
import time
import wave
from pathlib import Path

import numpy as np
import pytest
from fastapi.testclient import TestClient

from tonepilot_server import transcription
from tonepilot_server.app import create_app
from tonepilot_server.transcription import NoteEvent

SR = 22050


def write_wav(path: Path, x: np.ndarray, sr: int = SR):
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(data.tobytes())


def melody_audio(notes, seconds=3.0):
    t = np.arange(int(SR * seconds)) / SR
    x = np.zeros_like(t)
    for midi, start, dur in notes:
        f = 440 * 2 ** ((midi - 69) / 12)
        w = (t >= start) & (t < start + dur)
        x += w * sum(np.sin(2 * np.pi * f * h * t) / h for h in range(1, 5)) * 0.2
    return x


TUNE = [(64, 0.2, 0.5), (67, 0.8, 0.5), (69, 1.4, 0.5), (72, 2.0, 0.7)]


def fake_separator(audio: Path, out: Path, model: str):
    stems = {}
    for name in ["vocals", "drums", "bass", "other"]:
        p = out / f"{name}.wav"
        write_wav(p, melody_audio(TUNE) if name == "vocals" else np.zeros(SR))
        stems[name] = p
    return stems


def fake_transcriber(path: str):
    return [NoteEvent(m, m + d, p, 0.7, [0] * int(d * 86)) for p, m, d in [(64, 0.2, 0.5), (67, 0.8, 0.5)]] + \
        [NoteEvent(0.8, 1.3, 79, 0.3, None)]  # overtone ghost of the G


@pytest.fixture
def client(tmp_path):
    app = create_app(data_dir=tmp_path, token="secret", separator=fake_separator, transcriber=fake_transcriber,
                     synchronous=True)
    return TestClient(app), app


def upload(c, consent="true", name="song.mp3", headers=None):
    return c.post("/v1/jobs", files={"file": (name, b"ID3fake-audio", "audio/mpeg")},
                  data={"consent": consent, "model": "htdemucs"},
                  headers={"Authorization": "Bearer secret"} if headers is None else headers)


def test_health_reports_capabilities(client):
    c, _ = client
    h = c.get("/v1/health").json()
    assert h["authRequired"] is True
    assert set(h["models"]) == {"htdemucs", "htdemucs_6s"}


def test_requires_token_and_consent(client):
    c, _ = client
    assert upload(c, headers={}).status_code == 401
    assert upload(c, consent="false").status_code == 400
    assert upload(c, name="song.exe").status_code == 415


def test_full_job_lifecycle_and_deletion(client, tmp_path):
    c, app = client
    r = upload(c)
    assert r.status_code == 202
    job = r.json()["id"]
    auth = {"Authorization": "Bearer secret"}
    assert c.get(f"/v1/jobs/{job}", headers=auth).json()["status"] == "done"
    result = c.get(f"/v1/jobs/{job}/result", headers=auth).json()
    assert {s["kind"] for s in result["stems"]} == {"vocals", "drums", "bass", "other"}
    assert [n["midi"] for n in result["melody"]["notes"]] == [64, 67], "overtone ghost removed"
    assert all({"id", "start", "duration", "midi", "bendCents", "confidence", "isOrnamented", "userEdited"} <= n.keys()
               for n in result["melody"]["notes"])
    wav = c.get(f"/v1/jobs/{job}/stems/vocals.wav", headers=auth)
    assert wav.status_code == 200 and wav.content[:4] == b"RIFF"
    job_dir = tmp_path / "jobs" / job
    assert not any(p.name.startswith("input") for p in job_dir.iterdir()), "upload deleted after processing"
    assert c.delete(f"/v1/jobs/{job}", headers=auth).status_code == 204
    assert not job_dir.exists()
    assert c.get(f"/v1/jobs/{job}", headers=auth).status_code == 404


def test_rejects_path_traversal_and_unknown_stems(client):
    c, _ = client
    auth = {"Authorization": "Bearer secret"}
    assert c.get("/v1/jobs/..%2F..%2Fetc", headers=auth).status_code == 404
    job = upload(c).json()["id"]
    assert c.get(f"/v1/jobs/{job}/stems/../../job.json", headers=auth).status_code == 404
    assert c.get(f"/v1/jobs/{job}/stems/secret.wav", headers=auth).status_code == 404


def test_retention_purges_old_jobs(client):
    c, app = client
    job = upload(c).json()["id"]
    store = app.state.store
    assert store.purge_expired(now=time.time() + 25 * 3600) == 1
    assert c.get(f"/v1/jobs/{job}", headers={"Authorization": "Bearer secret"}).status_code == 404


def test_failed_separation_is_reported(tmp_path):
    def broken(audio, out, model):
        raise RuntimeError("model weights unavailable")
    c = TestClient(create_app(data_dir=tmp_path, token="", separator=broken, transcriber=fake_transcriber, synchronous=True))
    job = c.post("/v1/jobs", files={"file": ("a.wav", b"RIFF", "audio/wav")}, data={"consent": "true"}).json()["id"]
    s = c.get(f"/v1/jobs/{job}").json()
    assert s["status"] == "failed" and "weights" in s["error"]
    assert c.get(f"/v1/jobs/{job}/result").status_code == 409


def test_top_line_and_bend_conversion():
    events = [NoteEvent(0, 1, 60, 0.8, [3] * 86), NoteEvent(0, 1, 72, 0.3), NoteEvent(0.5, 1.5, 64, 0.9)]
    melody = transcription.to_melody(events)
    assert [n["midi"] for n in melody["notes"]] == [60, 64]
    assert melody["notes"][0]["duration"] == pytest.approx(0.5)
    assert melody["notes"][0]["bendCents"][0] == 100, "3 bins = 1 semitone = 100 cents"
    assert melody["notes"][0]["isOrnamented"] is True


@pytest.mark.skipif(not transcription.available(), reason="basic-pitch not installed")
def test_real_basic_pitch_transcribes_melody(tmp_path):
    p = tmp_path / "mel.wav"
    write_wav(p, melody_audio(TUNE))
    melody = transcription.to_melody(transcription.run_basic_pitch(str(p)))
    assert [n["midi"] for n in melody["notes"]] == [64, 67, 69, 72]
    for n, (_, start, dur) in zip(melody["notes"], TUNE):
        assert n["start"] == pytest.approx(start, abs=0.06)
