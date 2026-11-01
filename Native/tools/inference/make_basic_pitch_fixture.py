"""Generates the inference contract fixture for the Basic Pitch *test model* (Phase 1, CI only).

Runs the official nmp.tflite (spotify/basic-pitch, Apache-2.0) on a fixed 2-second test signal and
writes Packages/TonePilotCore/Tests/TonePilotCoreTests/Fixtures/inference/basic_pitch/:
  descriptor.json (logical names, shapes, per-back-end tensor names), audio.f32, note.f32,
  onset.f32, contour.f32 (little-endian float32), report.json (signature + ONNX cross-check).
Usage: python3 make_basic_pitch_fixture.py <basic-pitch checkout> <output dir>
"""
import json, math, os, sys
import numpy as np

src, out = sys.argv[1], sys.argv[2]
models = os.path.join(src, "basic_pitch", "saved_models", "icassp_2022")
SR, N = 22050, 22050 * 2 - 256  # AUDIO_N_SAMPLES (basic_pitch/constants.py)

# Fixed test signal: C-E-G chord, then A-C-E, with a short attack each second.
t = np.arange(N, dtype=np.float64) / SR
x = np.zeros(N)
for start, freqs in [(0.0, [261.63, 329.63, 392.00]), (1.0, [220.00, 261.63, 329.63])]:
    seg = (t >= start) & (t < start + 1.0)
    env = np.exp(-2.0 * (t[seg] - start))
    for f in freqs:
        x[seg] += 0.2 * env * np.sin(2 * math.pi * f * t[seg])
x = x.astype(np.float32).reshape(1, N, 1)

from ai_edge_litert.interpreter import Interpreter
it = Interpreter(model_path=os.path.join(models, "nmp.tflite"))
sigs = it.get_signature_list()
runner = it.get_signature_runner()
res = runner(input_2=x)
outs = {k: np.asarray(v, dtype=np.float32) for k, v in res.items()}

report = {"tflite_signatures": sigs, "tflite_outputs": {k: list(v.shape) for k, v in outs.items()}}

# Independent cross-check with the official ONNX conversion (same weights).
try:
    import onnxruntime as ort
    sess = ort.InferenceSession(os.path.join(models, "nmp.onnx"))
    in_name = sess.get_inputs()[0].name
    onnx_out = dict(zip([o.name for o in sess.get_outputs()], sess.run(None, {in_name: x})))
    report["onnx_inputs"] = [(i.name, i.shape) for i in sess.get_inputs()]
    report["onnx_outputs"] = {k: list(np.asarray(v).shape) for k, v in onnx_out.items()}
    # Match ONNX outputs to TFLite outputs by shape + closeness.
    diffs = {}
    for k, v in outs.items():
        best = min((float(np.max(np.abs(np.asarray(o).reshape(v.shape) - v))) for o in onnx_out.values() if np.asarray(o).size == v.size), default=None)
        diffs[k] = best
    report["onnx_vs_tflite_max_abs_diff"] = diffs
except Exception as e:  # recorded, not fatal
    report["onnx_error"] = str(e)

logical = {"note": None, "onset": None, "contour": None}
for k in outs:
    for l in logical:
        if l in k.lower():
            logical[l] = k
assert all(logical.values()), f"could not map TFLite outputs {list(outs)}"

os.makedirs(out, exist_ok=True)
x.astype("<f4").tofile(os.path.join(out, "audio.f32"))
for l, k in logical.items():
    outs[k].astype("<f4").tofile(os.path.join(out, f"{l}.f32"))
descriptor = {
    "name": "basic_pitch_test",
    "inputs": {"audio": [1, N, 1]},
    "outputs": {l: list(outs[k].shape) for l, k in logical.items()},
    "backendNames": {
        "coreml": {"audio": "input_2", "note": "Identity_1", "onset": "Identity_2", "contour": "Identity"},
        "litert": {"audio": "input_2", **{l: k for l, k in logical.items()}},
    },
}
json.dump(descriptor, open(os.path.join(out, "descriptor.json"), "w"), indent=1, sort_keys=True)
json.dump(report, open(os.path.join(out, "report.json"), "w"), indent=1, sort_keys=True, default=str)
print(json.dumps(report, indent=1, default=str))
