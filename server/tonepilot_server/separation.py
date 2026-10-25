"""Source separation with Demucs (MIT), run through its stable command-line interface.

Models (from the Demucs README):
  htdemucs     4 stems: drums, bass, other, vocals (default)
  htdemucs_6s  6 stems: adds guitar and piano — the README warns the piano stem
               "is not working great" and guitar shows bleeding/artifacts.
Model weights are downloaded by Demucs on first use (needs network access to
dl.fbaipublicfiles.com). Separation is approximate: stems contain artifacts and bleed.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Callable

MODELS = {
    "htdemucs": ["drums", "bass", "other", "vocals"],
    "htdemucs_6s": ["drums", "bass", "other", "vocals", "guitar", "piano"],
}


def available() -> bool:
    try:
        import demucs  # noqa: F401
        return True
    except Exception:
        return False


def run_demucs(audio: Path, out_dir: Path, model: str = "htdemucs") -> dict[str, Path]:
    """Separates `audio` into WAV stems in `out_dir`; returns {stem name: path}."""
    if model not in MODELS:
        raise ValueError(f"unknown model {model}")
    work = out_dir / "_demucs"
    cmd = [sys.executable, "-m", "demucs", "-n", model, "-o", str(work), str(audio)]
    proc = subprocess.run(cmd, capture_output=True, text=True, env={**os.environ, "PYTHONUNBUFFERED": "1"})
    if proc.returncode != 0:
        raise RuntimeError(f"demucs failed: {proc.stderr[-800:]}")
    produced = work / model / audio.stem
    stems = {}
    for name in MODELS[model]:
        src = produced / f"{name}.wav"
        if src.exists():
            dst = out_dir / f"{name}.wav"
            shutil.move(str(src), dst)
            stems[name] = dst
    shutil.rmtree(work, ignore_errors=True)
    if "vocals" not in stems:
        raise RuntimeError("demucs produced no vocal stem")
    return stems


Separator = Callable[[Path, Path, str], dict[str, Path]]
