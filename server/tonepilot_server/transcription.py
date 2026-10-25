"""Vocal/lead melody transcription with Spotify Basic Pitch (Apache-2.0).

Basic Pitch is polyphonic and instrument-agnostic. On a vocal stem it also reports quieter
overtone "ghost" notes (an octave, a twelfth or two octaves above the sung note), so
`to_melody` reduces its note events to one playable top line and converts its pitch-bend
curves (1/3-semitone bins at ~86 frames/s) to the app's cents-per-20 ms format.
"""
from __future__ import annotations

import uuid
from dataclasses import dataclass
from typing import Callable, Iterable, Sequence

# Basic Pitch contour resolution: 3 bins per semitone, ANNOTATIONS_FPS frames per second.
BENDS_PER_SEMITONE = 3
BASIC_PITCH_FPS = 22050 // 256  # = 86, basic_pitch.constants.ANNOTATIONS_FPS (AUDIO_SAMPLE_RATE // FFT_HOP)
BEND_STEP = 0.02  # seconds, matches MelodyNote.bendStep in TonePilotCore
OVERTONE_INTERVALS = (12, 19, 24, 28, 31)


@dataclass
class NoteEvent:
    start: float
    end: float
    pitch: int
    amplitude: float
    bends: list[int] | None = None


def available() -> bool:
    try:
        import basic_pitch  # noqa: F401
        return True
    except Exception:
        return False


def run_basic_pitch(wav_path: str, min_hz: float = 80.0, max_hz: float = 1400.0) -> list[NoteEvent]:
    """Runs Basic Pitch on a file and returns its note events (vocal range by default)."""
    from basic_pitch.inference import predict  # imported lazily: heavy (TensorFlow/ONNX)

    _, _, events = predict(wav_path, minimum_frequency=min_hz, maximum_frequency=max_hz, multiple_pitch_bends=False)
    return [NoteEvent(float(s), float(e), int(p), float(a), list(b) if b is not None else None)
            for s, e, p, a, b in events]


def _overlap(a: NoteEvent, b: NoteEvent) -> float:
    return max(0.0, min(a.end, b.end) - max(a.start, b.start))


def remove_overtones(events: Sequence[NoteEvent]) -> list[NoteEvent]:
    """Drops notes that sit an overtone interval above a louder, overlapping note."""
    keep = []
    for n in events:
        is_ghost = any(
            (n.pitch - o.pitch) in OVERTONE_INTERVALS
            and o.amplitude >= n.amplitude * 1.2
            and _overlap(n, o) >= 0.6 * (n.end - n.start)
            for o in events if o is not n
        )
        if not is_ghost:
            keep.append(n)
    return keep


def top_line(events: Iterable[NoteEvent], min_duration: float = 0.06) -> list[NoteEvent]:
    """Monophonic reduction: at any moment keep the loudest note; trim overlaps."""
    notes = sorted((e for e in events if e.end - e.start >= min_duration), key=lambda e: (e.start, -e.amplitude))
    line: list[NoteEvent] = []
    for n in notes:
        if line and n.start < line[-1].end:
            prev = line[-1]
            if n.amplitude > prev.amplitude * 1.1:
                prev.end = n.start
                if prev.end - prev.start < min_duration:
                    line.pop()
                line.append(n)
            # else: quieter overlapping note is accompaniment/bleed — skip
            continue
        line.append(n)
    return line


def bends_to_cents(bends: list[int] | None, duration: float) -> list[int]:
    """Basic Pitch bins (1/3 semitone at ~86 fps) -> cents every 20 ms."""
    if not bends:
        return []
    out = []
    steps = max(1, int(round(duration / BEND_STEP)))
    for i in range(steps):
        idx = min(len(bends) - 1, int(i * BEND_STEP * BASIC_PITCH_FPS))
        out.append(int(round(bends[idx] * 100 / BENDS_PER_SEMITONE)))
    return out


def to_melody(events: Sequence[NoteEvent], source: str = "vocalStem") -> dict:
    """JSON matching TonePilotCore.MelodyTrack."""
    line = top_line(remove_overtones(events))
    max_amp = max((n.amplitude for n in line), default=1.0) or 1.0
    notes = []
    for n in line:
        cents = bends_to_cents(n.bends, n.end - n.start)
        moving = any(abs(c) > 40 for c in cents)
        notes.append({
            "id": str(uuid.uuid4()).upper(),
            "start": round(n.start, 4),
            "duration": round(n.end - n.start, 4),
            "midi": n.pitch,
            "bendCents": cents if moving else [],
            "confidence": round(min(1.0, n.amplitude / max_amp), 3),
            "isOrnamented": moving,
            "userEdited": False,
        })
    total = sum(n["duration"] for n in notes)
    span = (line[-1].end - line[0].start) if line else 0
    return {
        "notes": notes,
        "source": source,
        "voicedRatio": round(total / span, 3) if span > 0 else 0,
        "difficultPhrases": [],
    }


Transcriber = Callable[[str], list[NoteEvent]]
