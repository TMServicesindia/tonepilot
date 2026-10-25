"""TonePilot analysis server: optional heavy analysis for the iPhone app.

Runs on your Mac or a server you control. The app uploads an audio file *only* after the
user consents; the server separates stems (Demucs) and transcribes the vocal melody
(Basic Pitch), then the app downloads the results and analyses them on-device. Files are
deleted on request (DELETE) and automatically after TONEPILOT_RETENTION_HOURS.

Environment:
  TONEPILOT_DATA_DIR         where jobs are stored (default ./data)
  TONEPILOT_TOKEN            if set, clients must send "Authorization: Bearer <token>"
  TONEPILOT_RETENTION_HOURS  default 24
"""
from __future__ import annotations

import json
import os
import shutil
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Optional

from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse, JSONResponse, Response

from . import separation, transcription

VERSION = "0.2.0"
ALLOWED_SUFFIXES = {".mp3", ".m4a", ".wav", ".aiff", ".aif", ".flac"}
MAX_UPLOAD_BYTES = 200 * 1024 * 1024

LICENSES = [
    {"name": "Demucs", "license": "MIT", "url": "https://github.com/adefossez/demucs"},
    {"name": "Basic Pitch", "license": "Apache-2.0", "url": "https://github.com/spotify/basic-pitch"},
]


class JobStore:
    def __init__(self, root: Path, retention_hours: float):
        self.root = root
        self.retention = retention_hours * 3600
        self.lock = threading.Lock()
        root.mkdir(parents=True, exist_ok=True)

    def dir(self, job_id: str) -> Path:
        # Job ids are server-generated UUIDs; reject anything else to prevent path traversal.
        try:
            uuid.UUID(job_id)
        except ValueError:
            raise HTTPException(404, "job not found")
        return self.root / job_id

    def write(self, job_id: str, **fields) -> dict:
        with self.lock:
            path = self.root / job_id / "job.json"
            state = json.loads(path.read_text()) if path.exists() else {}
            state.update(fields, updated=time.time())
            path.write_text(json.dumps(state))
            return state

    def read(self, job_id: str) -> dict:
        path = self.dir(job_id) / "job.json"
        if not path.exists():
            raise HTTPException(404, "job not found")
        return json.loads(path.read_text())

    def purge_expired(self, now: Optional[float] = None) -> int:
        now = now or time.time()
        removed = 0
        for d in self.root.iterdir():
            meta = d / "job.json"
            if meta.exists() and now - json.loads(meta.read_text()).get("created", now) > self.retention:
                shutil.rmtree(d, ignore_errors=True)
                removed += 1
        return removed


def create_app(data_dir: Optional[Path] = None, token: Optional[str] = None,
               separator: separation.Separator = separation.run_demucs,
               transcriber: transcription.Transcriber = transcription.run_basic_pitch,
               retention_hours: Optional[float] = None, synchronous: bool = False) -> FastAPI:
    data_dir = data_dir or Path(os.environ.get("TONEPILOT_DATA_DIR", "data"))
    token = token if token is not None else os.environ.get("TONEPILOT_TOKEN") or None
    retention = retention_hours if retention_hours is not None else float(os.environ.get("TONEPILOT_RETENTION_HOURS", "24"))
    store = JobStore(data_dir / "jobs", retention)
    pool = ThreadPoolExecutor(max_workers=1)  # one heavy job at a time
    app = FastAPI(title="TonePilot Analysis Server", version=VERSION)

    def auth(authorization: Optional[str] = Header(default=None)):
        if token and authorization != f"Bearer {token}":
            raise HTTPException(401, "missing or invalid token")

    def process(job_id: str, audio: Path, model: str, transcribe: bool):
        out = store.dir(job_id)
        try:
            store.write(job_id, status="separating", progress=0.1)
            stems = separator(audio, out, model)
            melody = None
            if transcribe:
                store.write(job_id, status="transcribing", progress=0.7)
                melody = transcription.to_melody(transcriber(str(stems["vocals"])), source="vocalStem")
            result = {
                "stems": [{"kind": k, "url": f"/v1/jobs/{job_id}/stems/{k}.wav", "model": model} for k in stems],
                "melody": melody,
                "models": LICENSES,
                "retentionHours": retention,
                "notes": [
                    "Separated stems are estimates and can contain artifacts and bleed from other instruments.",
                    "The melody is a transcription of the vocal stem's top line; check and correct it in the app.",
                ],
            }
            (out / "result.json").write_text(json.dumps(result))
            store.write(job_id, status="done", progress=1.0)
        except Exception as e:  # report, don't crash the worker
            store.write(job_id, status="failed", error=str(e)[:500])
        finally:
            audio.unlink(missing_ok=True)  # original upload is never kept after processing

    @app.get("/v1/health")
    def health():
        return {"version": VERSION, "demucs": separation.available(), "basicPitch": transcription.available(),
                "models": list(separation.MODELS), "authRequired": bool(token), "retentionHours": retention}

    @app.post("/v1/jobs", status_code=202, dependencies=[Depends(auth)])
    async def create_job(file: UploadFile = File(...), consent: str = Form(...), model: str = Form("htdemucs"),
                         transcribe: str = Form("vocals")):
        if consent.lower() != "true":
            raise HTTPException(400, "the user must consent to uploading this audio")
        if model not in separation.MODELS:
            raise HTTPException(400, f"model must be one of {list(separation.MODELS)}")
        suffix = Path(file.filename or "audio.wav").suffix.lower()
        if suffix not in ALLOWED_SUFFIXES:
            raise HTTPException(415, f"unsupported audio type {suffix}")
        store.purge_expired()
        job_id = str(uuid.uuid4())
        d = store.root / job_id
        d.mkdir(parents=True)
        audio = d / f"input{suffix}"
        size = 0
        with audio.open("wb") as f:
            while chunk := await file.read(1 << 20):
                size += len(chunk)
                if size > MAX_UPLOAD_BYTES:
                    f.close()
                    shutil.rmtree(d, ignore_errors=True)
                    raise HTTPException(413, "file too large")
                f.write(chunk)
        store.write(job_id, id=job_id, status="queued", progress=0.0, created=time.time(), model=model)
        if synchronous:
            process(job_id, audio, model, transcribe == "vocals")
        else:
            pool.submit(process, job_id, audio, model, transcribe == "vocals")
        return {"id": job_id, "status": store.read(job_id)["status"]}

    @app.get("/v1/jobs/{job_id}", dependencies=[Depends(auth)])
    def job_status(job_id: str):
        s = store.read(job_id)
        return {k: s.get(k) for k in ("id", "status", "progress", "error", "model")}

    @app.get("/v1/jobs/{job_id}/result", dependencies=[Depends(auth)])
    def job_result(job_id: str):
        s = store.read(job_id)
        if s.get("status") != "done":
            raise HTTPException(409, f"job is {s.get('status')}")
        return JSONResponse(json.loads((store.dir(job_id) / "result.json").read_text()))

    @app.get("/v1/jobs/{job_id}/stems/{name}", dependencies=[Depends(auth)])
    def stem(job_id: str, name: str):
        kind = name.removesuffix(".wav")
        if kind not in separation.MODELS["htdemucs_6s"]:
            raise HTTPException(404, "unknown stem")
        path = store.dir(job_id) / f"{kind}.wav"
        if not path.exists():
            raise HTTPException(404, "stem not found")
        return FileResponse(path, media_type="audio/wav")

    @app.delete("/v1/jobs/{job_id}", status_code=204, dependencies=[Depends(auth)])
    def delete_job(job_id: str):
        d = store.dir(job_id)
        if not d.exists():
            raise HTTPException(404, "job not found")
        shutil.rmtree(d)
        return Response(status_code=204)

    app.state.store = store
    return app


app = create_app()
