"""Development server: real Basic Pitch, fake Demucs (stems = the uploaded audio as 'vocals').
Used for client integration tests where Demucs weights can't be downloaded.
    python -m tests.dev_server  (from server/)"""
import shutil
from pathlib import Path

import uvicorn

from tonepilot_server.app import create_app


def passthrough_separator(audio: Path, out: Path, model: str):
    vocals = out / "vocals.wav"
    shutil.copy(audio, vocals)
    return {"vocals": vocals}


if __name__ == "__main__":
    uvicorn.run(create_app(data_dir=Path("data-dev"), token="dev-token", separator=passthrough_separator),
                host="127.0.0.1", port=8765, log_level="warning")
