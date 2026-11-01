"""Scores approaches A (each model's own labels, mapped) and C (frozen embeddings + TonePilot head)
on the TEST bank; anything tuned (thresholds, heads) uses the TRAIN bank only. Research only.
Usage: evaluate.py <render dir> <outputs dir> <report.md>
Outputs dir holds <model>.npz/.json from embed.py and optionally apple.npz/.json."""
import glob, json, os, sys
from collections import Counter, defaultdict
import numpy as np
from common import taxonomy, load_clips, HOP, WIN

TAX, INSTRUMENTS, FAMILIES, FAM_OF = taxonomy()
KEYS = TAX["keys"]
SOURCES = ["acoustic", "electronic", "imitation"]


def load_model(path):
    z = np.load(path, allow_pickle=False)
    files = list(z["files"])
    out = {}
    for i, f in enumerate(files):
        out[f] = {k: z[f"{i}|{k}"].astype(np.float32) for k in ("starts", "inst", "fam", "src", "emb")}
    return out


def truth_at(clip, t):
    """Instrument keys sounding at time t (window centre)."""
    return [e["key"] for e in clip["events"] if e["start"] <= t < e["end"]]


def truth_window(clip, start, win):
    """Instrument keys sounding in the window [start, start+win]: events that overlap it by at least
    half of the shorter of the window and the event (works for 1 s and 10 s windows alike)."""
    out = []
    for e in clip["events"]:
        ov = min(start + win, e["end"]) - max(start, e["start"])
        if ov > 0 and ov >= 0.5 * min(win, e["end"] - e["start"]):
            out.append(e["key"])
    return out


def solo_truth(clip):
    k = clip["events"][0]["key"]
    v = KEYS[k]
    return k, v["instrument"], v["family"], v["source"]


# ---------- decisions ----------
def decide_solo(inst_score, fam_score, t_inst, t_fam):
    """Pooled clip scores → (level, label): exact instrument if confident, else family, else unknown."""
    i = int(np.argmax(inst_score))
    if inst_score[i] >= t_inst:
        return "instrument", INSTRUMENTS[i]
    f = int(np.argmax(fam_score))
    if fam_score[f] >= t_fam:
        return "family", FAMILIES[f]
    return "unknown", None


def pick_thresholds(train_items):
    """Choose instrument/family thresholds on TRAIN clips: maximise exact-or-correct-family score while
    penalising wrong answers (a wrong label costs more than an 'unknown')."""
    best = (-1e9, 0.5, 0.5)
    for ti in np.linspace(0.05, 0.95, 19):
        for tf in np.linspace(0.05, 0.95, 19):
            s = 0.0
            for inst, fam, (_, ti_true, tf_true, _) in train_items:
                lvl, lab = decide_solo(inst, fam, ti, tf)
                if lvl == "instrument":
                    s += 1.0 if lab == ti_true else (-0.5 if FAM_OF.get(lab) == tf_true else -2.0)
                elif lvl == "family":
                    s += 0.5 if lab == tf_true else -2.0
            if s > best[0]:
                best = (s, ti, tf)
    return best[1], best[2]


def pick_window_thresholds(clips, scores_for):
    """Per-window thresholds for layered detection, chosen for best F1 on TRAIN layered tracks."""
    best = {}
    for kind, labels, idx, keyf in (("inst", INSTRUMENTS, 1, "instrument"), ("fam", FAMILIES, 2, "family")):
        top = (-1, 0.5)
        for t in np.linspace(0.05, 0.95, 19):
            tp = fp = fn = 0
            for c in clips:
                if c["split"] != "train" or c["kind"] != "layered":
                    continue
                d = scores_for(c["file"])
                for w, s0 in enumerate(d[0]):
                    tr = {KEYS[k][keyf] for k in truth_window(c, s0, WIN)}
                    pr = {labels[j] for j in np.where(d[idx][w] >= t)[0]}
                    tp += len(pr & tr); fp += len(pr - tr); fn += len(tr - pr)
            f1 = prf(tp, fp, fn)[2]
            if f1 > top[0]:
                top = (f1, t)
        best[kind] = top[1]
    return best["inst"], best["fam"]


# ---------- approach C ----------
def train_heads(train_rows, C=0.5, balanced=True):
    """Multi-label logistic heads on embeddings: instruments, families; multi-class source (solo only).
    C / balanced: regularisation strength and class weighting (calibrate.py also tries a stronger-regularised head)."""
    from sklearn.linear_model import LogisticRegression
    from sklearn.preprocessing import StandardScaler
    X = np.stack([r[0] for r in train_rows]); sc = StandardScaler().fit(X); Xs = sc.transform(X)
    heads = {}
    for name, labels in (("inst", INSTRUMENTS), ("fam", FAMILIES)):
        Y = np.array([[1 if lab in r[1 if name == "inst" else 2] else 0 for lab in labels] for r in train_rows])
        hs = []
        for j in range(len(labels)):
            if Y[:, j].sum() < 3:
                hs.append(None); continue
            hs.append(LogisticRegression(max_iter=2000, C=C, class_weight="balanced" if balanced else None).fit(Xs, Y[:, j]))
        heads[name] = hs
    solo = [r for r in train_rows if r[3] is not None]
    heads["src"] = LogisticRegression(max_iter=2000, C=C).fit(sc.transform(np.stack([r[0] for r in solo])), [r[3] for r in solo])
    return sc, heads


def head_scores(sc, heads, emb):
    Xs = sc.transform(emb)
    def ml(hs):
        return np.stack([h.predict_proba(Xs)[:, 1] if h is not None else np.zeros(len(Xs)) for h in hs], 1)
    src_p = heads["src"].predict_proba(Xs)
    src = np.zeros((len(Xs), 3)); cls = list(heads["src"].classes_)
    for k, s in enumerate(SOURCES):
        if s in cls: src[:, k] = src_p[:, cls.index(s)]
    return ml(heads["inst"]), ml(heads["fam"]), src


# ---------- metrics ----------
def prf(tp, fp, fn):
    p = tp / (tp + fp) if tp + fp else 0.0; r = tp / (tp + fn) if tp + fn else 0.0
    return p, r, (2 * p * r / (p + r) if p + r else 0.0)


def evaluate_system(name, clips, scores_for, t_inst, t_fam, has_imitation, tw=None):
    """scores_for(file) → (starts, inst[W×I], fam[W×F], src[W×S])."""
    rep = {"system": name}
    # Solo clips (original + variants).
    by_variant = defaultdict(Counter); fam_conf = Counter(); per_family = defaultdict(Counter)
    for c in clips:
        if c["split"] != "test" or c["kind"] != "solo":
            continue
        key, ti, tf, ts = solo_truth(c)
        st, inst, fam, src = scores_for(c["file"])
        lvl, lab = decide_solo(inst.mean(0), fam.mean(0), t_inst, t_fam)
        pred_fam = FAM_OF.get(lab) if lvl == "instrument" else lab if lvl == "family" else "unknown"
        v = by_variant[c["variant"]]; v["n"] += 1
        group = "imitation" if ts == "imitation" else "real"
        g = by_variant[c["variant"] + ":" + group]; g["n"] += 1
        for cnt in (v, g):
            cnt["exact"] += int(lvl == "instrument" and lab == ti)
            cnt["answered_exact"] += int(lvl == "instrument")
            cnt["family"] += int(pred_fam == tf)
            cnt["unknown"] += int(lvl == "unknown")
            cnt["wrong_family"] += int(pred_fam not in (tf, "unknown"))
            src_pred = SOURCES[int(np.argmax(src.mean(0)))] if src.shape[1] else "acoustic"
            cnt["source"] += int(src_pred == ts)
        if c["variant"] == "original":
            fam_conf[(tf, pred_fam)] += 1
            per_family[tf]["n"] += 1; per_family[tf]["family"] += int(pred_fam == tf)
            per_family[tf]["exact"] += int(lvl == "instrument" and lab == ti)
    rep["solo"] = {k: dict(v) for k, v in by_variant.items()}
    rep["per_family"] = {k: dict(v) for k, v in per_family.items()}
    rep["family_confusion"] = {f"{a} -> {b}": n for (a, b), n in sorted(fam_conf.items())}
    # Layered: window-level and track-level multi-label, timing.
    win = Counter(); winf = Counter(); trk = Counter(); timing = []
    tw_inst, tw_fam = tw if tw else (t_inst, t_fam)
    for c in clips:
        if c["split"] != "test" or c["kind"] != "layered":
            continue
        st, inst, fam, _ = scores_for(c["file"])
        present = {}
        for w, s in enumerate(st):
            mid = s + WIN / 2
            tk = truth_window(c, s, WIN)
            ti = {KEYS[k]["instrument"] for k in tk}; tf = {KEYS[k]["family"] for k in tk}
            pi = {INSTRUMENTS[j] for j in np.where(inst[w] >= tw_inst)[0]}
            pf = {FAMILIES[j] for j in np.where(fam[w] >= tw_fam)[0]}
            win["tp"] += len(pi & ti); win["fp"] += len(pi - ti); win["fn"] += len(ti - pi)
            winf["tp"] += len(pf & tf); winf["fp"] += len(pf - tf); winf["fn"] += len(tf - pf)
            for i in pi: present.setdefault(i, []).append(mid)
        ti_all = {KEYS[e["key"]]["instrument"] for e in c["events"]}
        # Track level: an instrument counts as reported if seen in ≥ 3 windows.
        pi_all = {i for i, ts in present.items() if len(ts) >= 3}
        trk["tp"] += len(pi_all & ti_all); trk["fp"] += len(pi_all - ti_all); trk["fn"] += len(ti_all - pi_all)
        for e in c["events"]:
            i = KEYS[e["key"]]["instrument"]
            ts = [t for t in present.get(i, []) if e["start"] - 1 <= t <= e["end"] + 1]
            if ts:
                timing.append(abs(min(ts) - WIN / 2 - e["start"]) + abs(max(ts) + WIN / 2 - e["end"]))
    rep["layered_window_instrument_prf"] = prf(win["tp"], win["fp"], win["fn"])
    rep["layered_window_family_prf"] = prf(winf["tp"], winf["fp"], winf["fn"])
    rep["layered_track_instrument_prf"] = prf(trk["tp"], trk["fp"], trk["fn"])
    rep["timing_error_s"] = float(np.median(timing)) if timing else None
    rep["timing_events_found"] = len(timing)
    rep["thresholds"] = [round(float(t_inst), 2), round(float(t_fam), 2), round(float(tw_inst), 2), round(float(tw_fam), 2)]
    rep["imitation_source_possible"] = has_imitation
    return rep


def main(root, outdir, report_path):
    clips = load_clips(root)["clips"]
    reports, infos = [], {}
    for path in sorted(glob.glob(os.path.join(outdir, "*.npz"))):
        name = os.path.basename(path)[:-4]
        data = load_model(path)
        info = json.load(open(path[:-4] + ".json")) if os.path.exists(path[:-4] + ".json") else {}
        infos[name] = info
        global WIN
        WIN = float(info.get("window_s", 1.0))
        train_solo = [c for c in clips if c["split"] == "train" and c["kind"] == "solo" and c["file"] in data]
        # A: mapped labels; thresholds from TRAIN only.
        items = [(data[c["file"]]["inst"].mean(0), data[c["file"]]["fam"].mean(0), solo_truth(c)) for c in train_solo]
        ti, tf = pick_thresholds(items)
        sfa = lambda f: (data[f]["starts"], data[f]["inst"], data[f]["fam"], data[f]["src"])
        reports.append(evaluate_system(f"A · {name}", clips, sfa, ti, tf, info.get("source_classes", []) == SOURCES,
                                       pick_window_thresholds(clips, sfa)))
        # C: heads on embeddings (not for Apple: no embeddings exposed).
        if name == "apple" or data[train_solo[0]["file"]]["emb"].shape[1] == 0:
            continue
        rows = []
        for c in clips:
            if c["split"] != "train" or c["file"] not in data:
                continue
            d = data[c["file"]]
            for w, s in enumerate(d["starts"]):
                tk = truth_window(c, s, WIN)
                rows.append((d["emb"][w], {KEYS[k]["instrument"] for k in tk}, {KEYS[k]["family"] for k in tk},
                             KEYS[tk[0]]["source"] if c["kind"] == "solo" and tk else None))
        sc, heads = train_heads(rows)
        cache = {}
        def sf(f):
            if f not in cache:
                d = data[f]; inst, fam, src = head_scores(sc, heads, d["emb"]); cache[f] = (d["starts"], inst, fam, src)
            return cache[f]
        items = [(sf(c["file"])[1].mean(0), sf(c["file"])[2].mean(0), solo_truth(c)) for c in train_solo]
        ti, tf = pick_thresholds(items)
        reports.append(evaluate_system(f"C · {name} + head", clips, sf, ti, tf, True, pick_window_thresholds(clips, sf)))
    json.dump({"reports": reports, "models": infos}, open(report_path.replace(".md", ".json"), "w"), indent=1)
    write_md(reports, infos, report_path)


def pct(a, b):
    return f"{100 * a / b:.0f}%" if b else "–"


def write_md(reports, infos, path):
    L = ["# Instrument recognition — proxy benchmark (synthetic; NOT real film-music accuracy)", "",
         "Test bank: GeneralUser GS renders (incl. TonePilot imitation tones). Train bank (thresholds, heads): FluidR3 GM (MIT).",
         "Different sample sets, same instrument names. Exact = right instrument; family = right family; unknown = abstained.", "",
         "## Solo clips (original)", "", "| System | Exact | Family | Wrong family | Unknown | Source (acoustic/electronic/imitation) |", "|---|---|---|---|---|---|"]
    for r in reports:
        o = r["solo"].get("original", {}); n = o.get("n", 0)
        L.append(f"| {r['system']} | {pct(o.get('exact',0),n)} | {pct(o.get('family',0),n)} | {pct(o.get('wrong_family',0),n)} | {pct(o.get('unknown',0),n)} | {pct(o.get('source',0),n)} |")
    L += ["", "## Robustness (family accuracy by variant; exact in brackets)", "", "| System | Original | Reverb | Compressed | Short (1 s) | Imitation tones (family) |", "|---|---|---|---|---|---|"]
    for r in reports:
        s = r["solo"]
        def cell(v):
            d = s.get(v, {}); return f"{pct(d.get('family',0),d.get('n',0))} ({pct(d.get('exact',0),d.get('n',0))})"
        im = s.get("original:imitation", {})
        L.append(f"| {r['system']} | {cell('original')} | {cell('reverb')} | {cell('compressed')} | {cell('short')} | {pct(im.get('family',0),im.get('n',0))} |")
    L += ["", "## Layered tracks (2–4 instruments, timed entries)", "", "| System | Window instrument P/R/F1 | Window family P/R/F1 | Track instrument P/R/F1 | Median start+end error | Events found |", "|---|---|---|---|---|---|"]
    for r in reports:
        f = lambda t: "/".join(f"{x:.2f}" for x in t)
        te = r["timing_error_s"]
        L.append(f"| {r['system']} | {f(r['layered_window_instrument_prf'])} | {f(r['layered_window_family_prf'])} | {f(r['layered_track_instrument_prf'])} | {'–' if te is None else f'{te:.1f} s'} | {r['timing_events_found']} |")
    L += ["", "## Per family (original solo clips; family / exact)", ""]
    fams = sorted({f for r in reports for f in r["per_family"]})
    L.append("| System | " + " | ".join(fams) + " |"); L.append("|---|" + "---|" * len(fams))
    for r in reports:
        L.append(f"| {r['system']} | " + " | ".join(f"{pct(r['per_family'].get(f,{}).get('family',0), r['per_family'].get(f,{}).get('n',0))} / {pct(r['per_family'].get(f,{}).get('exact',0), r['per_family'].get(f,{}).get('n',0))}" for f in fams) + " |")
    L += ["", "## Model facts (CI runner CPU)", "", "| Model | Parameters | Seconds per audio minute | Load s |", "|---|---|---|---|"]
    for n, i in infos.items():
        L.append(f"| {n} | {i.get('params') if i.get('params') else '–'} | {i.get('s_per_audio_min','–')} | {i.get('load_s','–')} |")
    L += ["", "Not covered (no licensed audio yet): " + ", ".join(TAX["not_covered_yet"]) + "."]
    open(path, "w").write("\n".join(L) + "\n")
    print("\n".join(L))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
