"""Sound-engine phase 2 DEV bench: does the blend search (one sound, or as many layers as help)
recreate a part better than the best single sound? Rendered GM audio (DEV banks), not real songs.

Steps (see .github/workflows/tone-blend.yml):
  shortlist <dump> --eat <repo>   rank the library for each target with the app's bundled tone tables
                                  (harmonic table, target masked with its extracted notes) -> shortlist.json (top 8)
  judge <dump> <out.md> --eat <repo>
                                  run the blend search (a line-for-line port of BlendSearch.swift, same
                                  parameters) on the Swift renders of the shortlist, then judge the result
                                  against the CLEAN part with models the search never uses: PANNs CNN10
                                  (primary) and MFCC distance; EfficientAT reported for reference.

PRE-REGISTERED GATE (written before the first run):
  A. "blend" targets (lead doubled by a second instrument at 70 %): the search's tone is closer than the
     best single sound (CNN10 gain > 0.002) on >= 50 % of them;
  B. "single" targets: no target worse than the best single sound by > 0.01 (CNN10);
  C. no target at all worse by > 0.02.
"""
import json, math, os, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import read_wav  # noqa: E402
from tone_t1 import device_logmel, mfcc_embed, model_embedder  # noqa: E402

SR = 32000
P = dict(wHook=0.6, wMain=0.3, lam=0.02, delta=0.02, hookSlack=0.01, shortlist=8, perRound=2,
         balances=[0.35, 0.55, 0.8], maxLayers=8, maxWindows=6)
PAD = float((np.log(1e-5) + 4.5) / 5)


def make_model(eat):
    import embed as E
    import torch
    m = E.EfficientAT(eat)
    def run(wins):
        with torch.no_grad():
            _, feats = m.m(torch.from_numpy(np.stack(wins).astype(np.float32))[:, None])
        return feats.reshape(len(wins), -1).numpy()
    return run


def embedding(model, x, notes=None, max_windows=None):
    """PerceptualToneSearch.embedding: device front-end (+ harmonic mask), 1 s windows (hop 50), optional
    evenly spaced subset (BlendSearch's maxWindows), mean of window embeddings."""
    if len(x) < SR:
        x = np.pad(x, (0, SR - len(x)))
    mel = device_logmel(x.astype(np.float64), notes)
    n = mel.shape[1]
    starts = [0] if n <= 101 else list(range(0, n - 101 + 1, 50))
    wins = []
    for s0 in starts:
        w = np.full((128, 101), PAD, np.float32)
        k = min(101, n - s0); w[:, :k] = mel[:, s0:s0 + k]
        wins.append(w)
    if max_windows and len(wins) > max_windows:
        step = (len(wins) - 1) / (max_windows - 1)
        wins = [wins[min(len(wins) - 1, int(math.floor(i * step + 0.5)))] for i in range(max_windows)]
    return model(wins).mean(0)


def cos(a, b):
    return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-12))


def shortlist(dump, eat):
    model = make_model(eat)
    table = json.load(open(os.path.join(HERE, "../../../App/Resources/ML/tone_table_harmonic.json")))
    ents = table["entries"]
    E = np.array([e["embedding"] for e in ents], np.float64)
    E /= np.linalg.norm(E, axis=1, keepdims=True) + 1e-12
    out = []
    for t in json.load(open(os.path.join(dump, "targets.json"))):
        x, _ = read_wav(os.path.join(dump, "targets", f"{t['id']}_stem.wav"))
        e = embedding(model, x, t["notes"])
        s = E @ (e / (np.linalg.norm(e) + 1e-12))
        best = {}
        for i, ent in enumerate(ents):
            best[ent["patch"]] = max(best.get(ent["patch"], -2), float(s[i]))
        ranked = sorted(best, key=lambda k: -best[k])[:P["shortlist"]]
        out.append({"id": t["id"], "candidates": ranked})
    json.dump(out, open(os.path.join(dump, "shortlist.json"), "w"), indent=1)
    print(f"SHORTLIST {len(out)} targets x {P['shortlist']} candidates")


def spectral_shape(x):
    """Long-term average log-mel spectrum with its overall level removed (device front-end, no mask):
    reacts directly to how much of each instrument is in a blend."""
    if len(x) < SR:
        x = np.pad(x, (0, SR - len(x)))
    v = device_logmel(x.astype(np.float64), None).mean(1)
    return v - v.mean()


def blend_search(model, hook, notes, cands, p=None):
    """Port of BlendSearch.search. cands: [(patch_id, audio)] best single first (shortlist order).
    `p` overrides the parameters (sweep); wSpec > 0 adds the spectral-shape term."""
    P = {**globals()["P"], **(p or {})}
    wspec = P.get("wSpec", 0.0)
    emb = lambda x, masked: embedding(model, x, notes if masked else None, P["maxWindows"])
    hookT, mainT = emb(hook, True), emb(hook, False)
    specT = spectral_shape(hook) if wspec else None
    C = []
    for pid, a in cands:
        rms = float(np.sqrt(np.mean(a.astype(np.float64) ** 2)))
        if rms <= 1e-5:
            continue
        a = (a * (0.1 / rms)).astype(np.float32)
        C.append({"id": pid, "audio": a, "eh": emb(a, True), "em": emb(a, False), "sp": spectral_shape(a) if wspec else None})
    def score(h, m, n, sp=0.0):
        return P["wHook"] * h + P["wMain"] * m + wspec * sp - P["lam"] * (n - 1)
    spc = lambda x_sp: cos(x_sp, specT) if wspec else 0.0
    singles = sorted(({**c, "h": cos(c["eh"], hookT), "m": cos(c["em"], mainT), "s": spc(c["sp"])} for c in C),
                     key=lambda c: -score(c["h"], c["m"], 1, c["s"]))
    first = singles[0]
    chosen, bal = [first], [1.0]
    mix = first["audio"].copy(); cur_h, cur_m = first["h"], first["m"]; cur_s = score(cur_h, cur_m, 1, first["s"])
    cur_eh, cur_em = first["eh"], first["em"]
    floor = first["h"] - P["hookSlack"]
    diag = None
    while len(chosen) < min(P["maxLayers"], len(C)):
        rest = [c for c in C if all(c["id"] != k["id"] for k in chosen)]
        approx = lambda c: score(cos(cur_eh + 0.55 * c["eh"], hookT), cos(cur_em + 0.55 * c["em"], mainT), len(chosen) + 1,
                                 spc(spectral_shape(mix + np.float32(0.55) * c["audio"])) if wspec else 0.0)
        short = sorted(rest, key=lambda c: -approx(c))[:P["perRound"]]
        best = None
        for c in short:
            for v in P["balances"]:
                x = mix + np.float32(v) * c["audio"]
                eh, em = emb(x, True), emb(x, False)
                h, m = cos(eh, hookT), cos(em, mainT)
                s = score(h, m, len(chosen) + 1, spc(spectral_shape(x)) if wspec else 0.0)
                if best is None or s > best[5]:
                    best = (c, v, x, h, m, s, eh, em)
        if diag is None and best is not None:
            diag = {"gain": best[5] - cur_s, "hook_delta": best[3] - first["h"], "main_delta": best[4] - cur_m, "tried": best[0]["id"]}
        if best is None or not (best[5] > cur_s + P["delta"] and best[3] >= floor):
            break
        chosen.append(best[0]); bal.append(best[1])
        mix, cur_h, cur_m, cur_s, cur_eh, cur_em = best[2], best[3], best[4], best[5], best[6], best[7]
    return {"layers": [(c["id"], b) for c, b in zip(chosen, bal)], "audio": mix, "single_audio": first["audio"],
            "single": first["id"], "hook": cur_h, "score": cur_s, "single_score": score(first["h"], first["m"], 1, first["s"]), "diag": diag or {}}


def judge(dump, out_md, eat):
    model = make_model(eat)
    cnn = model_embedder("panns10", eat)
    targets = {t["id"]: t for t in json.load(open(os.path.join(dump, "targets.json")))}
    rows = []
    for sl in json.load(open(os.path.join(dump, "shortlist.json"))):
        t = targets[sl["id"]]
        hook, _ = read_wav(os.path.join(dump, "targets", f"{t['id']}_stem.wav"))
        clean, _ = read_wav(os.path.join(dump, "targets", f"{t['id']}_clean.wav"))
        cands = []
        for pid in sl["candidates"]:
            p = os.path.join(dump, "renders", f"{t['id']}_{pid}.wav")
            if os.path.exists(p):
                cands.append((pid, read_wav(p)[0]))
        if not cands:
            continue
        r = blend_search(model, hook.astype(np.float32), t["notes"], cands)
        ce = cnn(clean, SR)
        g_cnn = cos(cnn(r["audio"], SR), ce) - cos(cnn(r["single_audio"], SR), ce)
        mc = mfcc_embed(clean, SR)
        g_mfcc = float(np.linalg.norm(mfcc_embed(r["single_audio"], SR) - mc) - np.linalg.norm(mfcc_embed(r["audio"], SR) - mc))
        ids = [k for k, _ in r["layers"]]
        rows.append({"id": t["id"], "bank": t["bank"], "variant": t["variant"], "layers": len(ids), "ids": ids,
                     "balances": [b for _, b in r["layers"]], "cnn_gain": g_cnn, "mfcc_gain": g_mfcc,
                     "lead_found": t["lead_patch"] in ids, "partner_found": bool(t["partner_patch"]) and t["partner_patch"] in ids,
                     "score_gain": r["score"] - r["single_score"], "diag": r["diag"],
                     "partner_in_shortlist": bool(t["partner_patch"]) and t["partner_patch"] in sl["candidates"],
                     "lead_in_shortlist": t["lead_patch"] in sl["candidates"]})
        print(f"ROW {t['id']}: {len(ids)} layer(s), CNN10 gain {g_cnn:+.4f}, MFCC gain {g_mfcc:+.3f}", flush=True)

    def stats(rs):
        n = len(rs); multi = sum(r["layers"] > 1 for r in rs)
        better = sum(r["cnn_gain"] > 0.002 for r in rs); worse1 = sum(r["cnn_gain"] < -0.01 for r in rs)
        worse2 = sum(r["cnn_gain"] < -0.02 for r in rs)
        return n, multi, better, worse1, worse2, (min(r["cnn_gain"] for r in rs) if rs else 0.0), \
            (float(np.mean([r["cnn_gain"] for r in rs])) if rs else 0.0), sum(r["mfcc_gain"] > 0 for r in rs), \
            sum(r["partner_found"] for r in rs)

    lines = ["# Blend search (phase 2) on the DEV bench — independent judges", "",
             "Rendered GM audio (DEV banks), not real songs. Judged against the part alone (no leakage), best single sound vs the search's tone.", "",
             "| Group | Targets | Chose > 1 layer | CNN10 better | Worse (< −0.01) | Worse (< −0.02) | Worst | Mean CNN10 gain | MFCC closer | True 2nd instrument found |",
             "|---|---|---|---|---|---|---|---|---|---|"]
    groups = {}
    for r in rows:
        groups.setdefault(f"{r['bank']} · {r['variant']}", []).append(r)
    for k in sorted(groups):
        n, multi, b, w1, w2, worst, mean, mf, pf = stats(groups[k])
        lines.append(f"| {k} | {n} | {multi} | {b}/{n} | {w1} | {w2} | {worst:+.3f} | {mean:+.4f} | {mf}/{n} | {pf} |")
    blend = [r for r in rows if r["variant"] == "blend"]; single = [r for r in rows if r["variant"] == "single"]
    bn, _, bb, _, _, _, _, _, _ = stats(blend)
    _, _, _, sw1, _, _, _, _, _ = stats(single)
    _, _, _, _, aw2, _, _, _, _ = stats(rows)
    A = bn > 0 and bb >= 0.5 * bn; B = sw1 == 0; C = aw2 == 0
    passed = A and B and C
    lines += ["", f"**Pre-registered gate:** A blend targets better in ≥ 50 %: {bb}/{bn} {'✓' if A else '✗'} · "
              f"B single targets none worse by > 0.01: {sw1} {'✓' if B else '✗'} · C none worse by > 0.02: {aw2} {'✓' if C else '✗'} → **{'PASS' if passed else 'FAIL'}**"]
    # Diagnostics: the best extra layer tried in round 1 (before the margin and the hook rule).
    lines += ["", "**Diagnostics (round 1, best extra layer tried):**", "",
              "| Group | Score gain p50 / p90 / max | Gain > 0 | Gain > 0.01 | Gain > 0.02 | Hook change p50 | Blocked by the hook rule | 2nd instrument in shortlist | Lead in shortlist |",
              "|---|---|---|---|---|---|---|---|---|"]
    for k in sorted(groups):
        rs = groups[k]; g = np.array([r["diag"].get("gain", -1) for r in rs]); hd = np.array([r["diag"].get("hook_delta", 0) for r in rs])
        blocked = sum(1 for r in rs if r["diag"].get("gain", -1) > P["delta"] and r["diag"].get("hook_delta", 0) < -P["hookSlack"])
        lines.append(f"| {k} | {np.median(g):+.4f} / {np.percentile(g, 90):+.4f} / {g.max():+.4f} | {(g > 0).sum()} | {(g > 0.01).sum()} | {(g > 0.02).sum()} | "
                     f"{np.median(hd):+.4f} | {blocked} | {sum(r['partner_in_shortlist'] for r in rs)} | {sum(r['lead_in_shortlist'] for r in rs)} |")
    open(out_md, "w").write("\n".join(lines) + "\n")
    json.dump(rows, open(out_md.replace(".md", ".json"), "w"), indent=1)
    print("\n".join(lines))
    print(f"RESULT blend gate {'PASS' if passed else 'FAIL'}: blend targets better {bb}/{bn}; single targets worse>0.01: {sw1}; any worse>0.02: {aw2}")


UNMIX = dict(min_share=0.15, max_layers=8)


def power_mel(x):
    """Mel power spectrogram (device front-end, linear power, no mask): layers add in this domain."""
    if len(x) < SR:
        x = np.pad(x, (0, SR - len(x)))
    return np.exp(device_logmel(x.astype(np.float64), None) * 5 - 4.5)   # undo (log(p+1e-5)+4.5)/5 (ignoring the 1e-5)


def nnls(A, b, iters=500):
    """Non-negative least squares by projected gradient (no SciPy needed in the app's Swift port)."""
    w = np.zeros(A.shape[1]); L = np.linalg.norm(A, 2) ** 2 + 1e-12
    for _ in range(iters):
        w = np.maximum(0, w - (A.T @ (A @ w - b)) / L)
    return w


def unmix_search(hook, cands, others=None):
    """Spectral unmixing: which candidates, in what amounts, add up to the part's mel power over time.
    Candidates play exactly the part's notes at the same times, so the decomposition is aligned.
    Layers = candidates with >= min_share of the largest weight; balance = sqrt(weight ratio)."""
    T = power_mel(hook)
    C = []
    for pid, a in cands:
        rms = float(np.sqrt(np.mean(a.astype(np.float64) ** 2)))
        if rms > 1e-5:
            C.append((pid, (a * (0.1 / rms)).astype(np.float32)))
    S = [power_mel(a) for _, a in C]
    # Leakage-aware: the song's other separated parts join as fixed components. They absorb the bleed
    # in this part's stem, but can never become layers.
    O = [power_mel(x) for x in (others or []) if float(np.abs(x).max()) > 1e-6]
    n = min(T.shape[1], *(m.shape[1] for m in S + O))
    A = np.stack([m[:, :n].ravel() for m in S + O], 1); b = T[:, :n].ravel()
    scale = A.max() + 1e-12
    w = nnls(A / scale, b / scale)[:len(S)]
    order = np.argsort(-w)
    top = w[order[0]]
    keep = [i for i in order if top > 0 and w[i] >= UNMIX["min_share"] * top][:UNMIX["max_layers"]] or [int(order[0])]
    bal = [float(np.sqrt(w[i] / top)) if top > 0 else 1.0 for i in keep]
    mix = sum(np.float32(bv) * C[i][1] for i, bv in zip(keep, bal))
    return {"layers": [(C[i][0], bv) for i, bv in zip(keep, bal)], "audio": mix, "single_audio": C[int(order[0])][1]}


def unmix_judge(dump, out_md, eat, leak=False):
    """Spectral unmixing judged by the SAME pre-registered gate (first run of this method, no tuning).
    leak=True (owner's option 1, 3 Nov; PRE-REGISTERED before its run): the target's other separated parts
    (backing stem, vocals, bass, as the app would have them) are added as leakage components; same
    min_share 0.15, same gate A/B/C, one run, no tuning."""
    cnn = model_embedder("panns10", eat)
    targets = {t["id"]: t for t in json.load(open(os.path.join(dump, "targets.json")))}
    rows = []
    for sl in json.load(open(os.path.join(dump, "shortlist.json"))):
        t = targets[sl["id"]]
        hook, _ = read_wav(os.path.join(dump, "targets", f"{t['id']}_stem.wav"))
        clean, _ = read_wav(os.path.join(dump, "targets", f"{t['id']}_clean.wav"))
        cands = [(pid, read_wav(os.path.join(dump, "renders", f"{t['id']}_{pid}.wav"))[0]) for pid in sl["candidates"]
                 if os.path.exists(os.path.join(dump, "renders", f"{t['id']}_{pid}.wav"))]
        if not cands:
            continue
        others = [read_wav(os.path.join(dump, "targets", f"{t['id']}_other_{k}.wav"))[0] for k in t.get("others", [])] if leak else None
        r = unmix_search(hook.astype(np.float32), cands, others)
        ce = cnn(clean, SR)
        ids = [k for k, _ in r["layers"]]
        g = 0.0 if len(ids) == 1 else cos(cnn(r["audio"], SR), ce) - cos(cnn(r["single_audio"], SR), ce)
        rows.append({"id": t["id"], "variant": t["variant"], "bank": t["bank"], "layers": len(ids), "gain": g,
                     "partner": bool(t["partner_patch"]) and t["partner_patch"] in ids, "lead": t["lead_patch"] in ids,
                     "balances": [round(b, 2) for _, b in r["layers"]]})
        print(f"ROW {t['id']}: {len(ids)} layer(s) {rows[-1]['balances']}, CNN10 gain {g:+.4f}", flush=True)
    b = [r for r in rows if r["variant"] == "blend"]; sg = [r for r in rows if r["variant"] == "single"]
    A = sum(r["gain"] > 0.002 for r in b) >= 0.5 * len(b); B = sum(r["gain"] < -0.01 for r in sg) == 0
    C_ = sum(r["gain"] < -0.02 for r in rows) == 0
    lines = [f"# Blend by {'leakage-aware ' if leak else ''}spectral unmixing — pre-registered gate (first run, no tuning)", "",
             "| Group | Targets | >1 layer | CNN10 better | Worse < −0.01 | Worse < −0.02 | Mean gain | True 2nd instrument found | True lead kept |",
             "|---|---|---|---|---|---|---|---|---|"]
    for k in sorted({f"{r['bank']} · {r['variant']}" for r in rows}):
        rs = [r for r in rows if f"{r['bank']} · {r['variant']}" == k]
        lines.append(f"| {k} | {len(rs)} | {sum(r['layers'] > 1 for r in rs)} | {sum(r['gain'] > 0.002 for r in rs)}/{len(rs)} | "
                     f"{sum(r['gain'] < -0.01 for r in rs)} | {sum(r['gain'] < -0.02 for r in rs)} | {np.mean([r['gain'] for r in rs]):+.4f} | "
                     f"{sum(r['partner'] for r in rs)} | {sum(r['lead'] for r in rs)} |")
    passed = A and B and C_
    lines += ["", f"**Gate:** A {sum(r['gain'] > 0.002 for r in b)}/{len(b)} {'✓' if A else '✗'} · B {sum(r['gain'] < -0.01 for r in sg)} {'✓' if B else '✗'} · "
              f"C {sum(r['gain'] < -0.02 for r in rows)} {'✓' if C_ else '✗'} → **{'PASS' if passed else 'FAIL'}**"]
    open(out_md, "w").write("\n".join(lines) + "\n")
    json.dump(rows, open(out_md.replace(".md", ".json"), "w"), indent=1)
    print("\n".join(lines))
    print(f"RESULT {'leakage-aware ' if leak else ''}unmix gate {'PASS' if passed else 'FAIL'}: blend better {sum(r['gain'] > 0.002 for r in b)}/{len(b)}, "
          f"single worse>0.01 {sum(r['gain'] < -0.01 for r in sg)}, any worse>0.02 {sum(r['gain'] < -0.02 for r in rows)}")


SWEEP = {
    "V0 current (wH .6, wM .3, λ=δ=.02)": {},
    "V1 no layer cost or margin": {"lam": 0.0, "delta": 0.0},
    "V2 small cost (λ=δ=.002)": {"lam": 0.002, "delta": 0.002},
    "V3 + spectral shape (wH .3, wM .2, wS .5, λ=δ=.01)": {"wHook": 0.3, "wMain": 0.2, "wSpec": 0.5, "lam": 0.01, "delta": 0.01},
    "V4 spectral shape only (λ=δ=.01)": {"wHook": 0.0, "wMain": 0.0, "wSpec": 1.0, "lam": 0.01, "delta": 0.01},
    "V5 + spectral shape (wH .3, wM .2, wS .5, λ=δ=.02)": {"wHook": 0.3, "wMain": 0.2, "wSpec": 0.5, "lam": 0.02, "delta": 0.02},
}


def sweep(dump, out_md, eat):
    """DEV tuning (not a gate): each variant's choices judged by CNN10 vs the clean part."""
    model = make_model(eat)
    cnn = model_embedder("panns10", eat)
    targets = {t["id"]: t for t in json.load(open(os.path.join(dump, "targets.json")))}
    work = []
    for sl in json.load(open(os.path.join(dump, "shortlist.json"))):
        t = targets[sl["id"]]
        hook, _ = read_wav(os.path.join(dump, "targets", f"{t['id']}_stem.wav"))
        clean, _ = read_wav(os.path.join(dump, "targets", f"{t['id']}_clean.wav"))
        cands = [(pid, read_wav(os.path.join(dump, "renders", f"{t['id']}_{pid}.wav"))[0]) for pid in sl["candidates"]
                 if os.path.exists(os.path.join(dump, "renders", f"{t['id']}_{pid}.wav"))]
        if cands:
            work.append((t, hook.astype(np.float32), cands, cnn(clean, SR)))
    lines = ["# Blend search DEV sweep (tuning, not a gate) — CNN10 vs the clean part", "",
             "| Variant | Blend targets: >1 layer | better | 2nd instrument found | Single targets: >1 layer | worse > 0.01 | Any worse > 0.02 | Mean gain (blend) |",
             "|---|---|---|---|---|---|---|---|"]
    for name, pv in SWEEP.items():
        res = {"blend": [], "single": []}
        for t, hook, cands, ce in work:
            r = blend_search(model, hook, t["notes"], cands, pv)
            ids = [k for k, _ in r["layers"]]
            g = 0.0 if len(ids) == 1 else cos(cnn(r["audio"], SR), ce) - cos(cnn(r["single_audio"], SR), ce)
            res[t["variant"]].append({"multi": len(ids) > 1, "gain": g, "partner": bool(t["partner_patch"]) and t["partner_patch"] in ids})
        b, sg = res["blend"], res["single"]
        allr = b + sg
        lines.append(f"| {name} | {sum(r['multi'] for r in b)}/{len(b)} | {sum(r['gain'] > 0.002 for r in b)}/{len(b)} | {sum(r['partner'] for r in b)} | "
                     f"{sum(r['multi'] for r in sg)}/{len(sg)} | {sum(r['gain'] < -0.01 for r in sg)} | {sum(r['gain'] < -0.02 for r in allr)} | "
                     f"{np.mean([r['gain'] for r in b]):+.4f} |")
        print(lines[-1], flush=True)
    open(out_md, "w").write("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    mode, dump = sys.argv[1], sys.argv[2]
    eat = sys.argv[sys.argv.index("--eat") + 1]
    if mode == "shortlist":
        shortlist(dump, eat)
    elif mode == "sweep":
        sweep(dump, sys.argv[3], eat)
    elif mode == "unmix":
        unmix_judge(dump, sys.argv[3], eat)
    elif mode == "unmix_leak":
        unmix_judge(dump, sys.argv[3], eat, leak=True)
    else:
        judge(dump, sys.argv[3], eat)
