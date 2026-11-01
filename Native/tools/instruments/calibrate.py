"""Gate 1 — calibrated abstention and reliability report (research only, synthetic proxy data).
Splits: TRAIN = FluidR3 phrases 0–1 + layered tracks 0–15 (heads learn here)
        DEV   = FluidR3 phrase 2 + layered tracks 16–23 (thresholds chosen here, nothing else)
        TEST  = GeneralUser GS (untouched; reported only)
Target: wrong-family rate ≤ 5% on DEV with the highest coverage. Reported together on TEST:
selective accuracy, coverage, unknown rate, wrong-family rate — per condition — plus a
coverage curve, source-type confusion, and layered onset/offset error distributions.
Usage: calibrate.py <render dir> <outputs dir> <report.md>"""
import glob, json, os, re, sys
from collections import Counter, defaultdict
import numpy as np
from common import load_clips, WIN
from evaluate import (INSTRUMENTS, FAMILIES, FAM_OF, KEYS, SOURCES, load_model, truth_at, truth_window, solo_truth,
                      train_heads, head_scores, prf)

TARGET_WRONG = 0.05


LAYERED_TRAIN_COUNT = [24]


def role(c):
    if c["split"] in ("test", "test_nsynth"):
        return c["split"]
    if c["split"] == "dev_nsynth":
        return "dev"
    m = re.search(r"_(\d+)\.wav$", c["file"]) if c["kind"] == "solo" else re.search(r"track_(\d+)\.wav$", c["file"])
    idx = int(m.group(1)) if m else 0
    cut = int(0.8 * LAYERED_TRAIN_COUNT[0])
    return "dev" if (c["kind"] == "solo" and idx == 2) or (c["kind"] == "layered" and idx >= cut) else "train"


def decide(pi, pf, ti, tf):
    i = int(np.argmax(pi))
    if pi[i] >= ti:
        return "instrument", INSTRUMENTS[i], FAM_OF[INSTRUMENTS[i]]
    f = int(np.argmax(pf))
    if pf[f] >= tf:
        return "family", None, FAMILIES[f]
    return "unknown", None, None


def solo_stats(items, ti, tf):
    n = len(items); s = Counter()
    for pi, pf, (_, inst, fam, _) in items:
        lvl, lab, pfam = decide(pi, pf, ti, tf)
        s["answered"] += lvl != "unknown"
        s["family_ok"] += pfam == fam
        s["wrong_family"] += lvl != "unknown" and pfam != fam
        s["inst_answered"] += lvl == "instrument"
        s["exact_ok"] += lvl == "instrument" and lab == inst
    return {"n": n, "coverage": s["answered"] / n if n else 0, "unknown": 1 - s["answered"] / n if n else 0,
            "wrong_family": s["wrong_family"] / n if n else 0,
            "selective_family_acc": s["family_ok"] / s["answered"] if s["answered"] else None,
            "selective_exact_acc": s["exact_ok"] / s["inst_answered"] if s["inst_answered"] else None,
            "exact_overall": s["exact_ok"] / n if n else 0, "instrument_level_share": s["inst_answered"] / n if n else 0}


def calibrate(dev_items):
    grid = np.linspace(0.05, 0.99, 48)
    best, fallback = None, None
    for ti in grid:
        for tf in grid:
            st = solo_stats(dev_items, ti, tf)
            key = (st["coverage"], st["exact_overall"])
            if st["wrong_family"] <= TARGET_WRONG and (best is None or key > best[0]):
                best = (key, ti, tf, st)
            if fallback is None or st["wrong_family"] < fallback[0]:
                fallback = (st["wrong_family"], ti, tf, st)
    if best:
        return best[1], best[2], best[3], True
    return fallback[1], fallback[2], fallback[3], False


def coverage_curve(items):
    """Risk–coverage on TEST (reporting only): answer the most confident clips first (family level)."""
    rows = []
    for pi, pf, (_, inst, fam, _) in items:
        f = int(np.argmax(pf)); rows.append((pf[f], FAMILIES[f] == fam))
    rows.sort(key=lambda r: -r[0]); out = {}
    for cov in (1.0, 0.9, 0.8, 0.7, 0.6, 0.5, 0.3):
        k = max(1, int(round(cov * len(rows))))
        out[f"{int(cov * 100)}%"] = sum(r[1] for r in rows[:k]) / k
    return out


def layered_report(clips, sf, roleset, tw_i, tw_f, win=WIN):
    wc = Counter(); winf = Counter(); on, off = [], []; found = total = 0; by_n = defaultdict(Counter)
    for c in clips:
        if c["kind"] != "layered" or role(c) not in roleset:
            continue
        st, inst, fam, _ = sf(c["file"]); n_inst = len(c["events"]); present = defaultdict(list)
        for w, s in enumerate(st):
            mid = s + win / 2; tk = truth_window(c, s, win)
            ti = {KEYS[k]["instrument"] for k in tk}; tf = {KEYS[k]["family"] for k in tk}
            pi = {INSTRUMENTS[j] for j in np.where(inst[w] >= tw_i)[0]}; pf = {FAMILIES[j] for j in np.where(fam[w] >= tw_f)[0]}
            for cnt in (wc, by_n[n_inst]):
                cnt["tp"] += len(pi & ti); cnt["fp"] += len(pi - ti); cnt["fn"] += len(ti - pi)
            winf["tp"] += len(pf & tf); winf["fp"] += len(pf - tf); winf["fn"] += len(tf - pf)
            for i in pi: present[i].append(mid)
        for e in c["events"]:
            total += 1; i = KEYS[e["key"]]["instrument"]
            ts = [t for t in present.get(i, []) if e["start"] - 1 <= t <= e["end"] + 1]
            if len(ts) >= 2:
                found += 1; on.append(abs(min(ts) - win / 2 - e["start"])); off.append(abs(max(ts) + win / 2 - e["end"]))
    q = lambda v, p: float(np.percentile(v, p)) if v else None
    return {"window_instrument_prf": prf(wc["tp"], wc["fp"], wc["fn"]), "window_family_prf": prf(winf["tp"], winf["fp"], winf["fn"]),
            "events_detected": f"{found}/{total}", "onset_err_median": q(on, 50), "onset_err_p90": q(on, 90),
            "offset_err_median": q(off, 50), "offset_err_p90": q(off, 90),
            "window_instrument_f1_by_count": {k: prf(v["tp"], v["fp"], v["fn"])[2] for k, v in sorted(by_n.items())}}


def pick_window(clips, sf, win=WIN):
    best = {}
    for kind, idx, labels, keyf in (("inst", 1, INSTRUMENTS, "instrument"), ("fam", 2, FAMILIES, "family")):
        top = (-1, 0.5)
        for t in np.linspace(0.05, 0.95, 19):
            c_ = Counter()
            for c in clips:
                if c["kind"] != "layered" or role(c) != "dev":
                    continue
                d = sf(c["file"])
                for w, s in enumerate(d[0]):
                    tr = {KEYS[k][keyf] for k in truth_window(c, s, win)}; pr = {labels[j] for j in np.where(d[idx][w] >= t)[0]}
                    c_["tp"] += len(pr & tr); c_["fp"] += len(pr - tr); c_["fn"] += len(tr - pr)
            f1 = prf(c_["tp"], c_["fp"], c_["fn"])[2]
            if f1 > top[0]: top = (f1, t)
        best[kind] = top[1]
    return best["inst"], best["fam"]


def main(root, outdir, report_path):
    clips = load_clips(root)["clips"]; results = []
    LAYERED_TRAIN_COUNT[0] = max(1, sum(1 for c in clips if c["split"] == "train" and c["kind"] == "layered"))
    for path in sorted(glob.glob(os.path.join(outdir, "*.npz"))):
        name = os.path.basename(path)[:-4]; data = load_model(path)
        info = json.load(open(path[:-4] + ".json")) if os.path.exists(path[:-4] + ".json") else {}
        win = float(info.get("window_s", WIN))
        has_emb = data[next(iter(data))]["emb"].shape[1] > 0
        systems = [("A", lambda f, d=data: (d[f]["starts"], d[f]["inst"], d[f]["fam"], d[f]["src"]))]
        if has_emb:
            rows = []
            for c in clips:
                if role(c) != "train" or c["file"] not in data: continue
                d = data[c["file"]]
                for w, s in enumerate(d["starts"]):
                    tk = truth_window(c, s, win)
                    rows.append((d["emb"][w], {KEYS[k]["instrument"] for k in tk}, {KEYS[k]["family"] for k in tk},
                                 KEYS[tk[0]]["source"] if c["kind"] == "solo" and tk else None))
            sc, heads = train_heads(rows); cache = {}
            def sfc(f, d=data, sc=sc, heads=heads, cache=cache):
                if f not in cache:
                    inst, fam, src = head_scores(sc, heads, d[f]["emb"]); cache[f] = (d[f]["starts"], inst, fam, src)
                return cache[f]
            systems.append(("C", sfc))
        for kind, sf in systems:
            label = f"{kind} · {name}" + (" + head" if kind == "C" else "")
            items = lambda r, v=None: [(sf(c["file"])[1].mean(0), sf(c["file"])[2].mean(0), solo_truth(c)) for c in clips
                                        if c["kind"] == "solo" and role(c) == r and c["file"] in data and (v is None or c["variant"] == v or (v == "imitation" and solo_truth(c)[3] == "imitation"))]
            ti, tf, dev_st, reached = calibrate(items("dev"))
            if kind == "A":   # best-guess variant: always answer (no abstention)
                results.append({"system": f"A-argmax · {name}", "thresholds": [0, 0], "dev": solo_stats(items("dev"), 0, 0), "target_reached_on_dev": None,
                                "test": {v: solo_stats(items("test", v), 0, 0) for v in ("original", "reverb", "compressed", "short", "imitation")},
                                "test_nsynth": solo_stats(items("test_nsynth"), 0, 0), "coverage_curve_test": coverage_curve(items("test", "original"))})
            rep = {"system": label, "thresholds": [round(float(ti), 3), round(float(tf), 3)], "dev": dev_st, "target_reached_on_dev": reached,
                   "test": {v: solo_stats(items("test", v), ti, tf) for v in ("original", "reverb", "compressed", "short", "imitation")},
                   "coverage_curve_test": coverage_curve(items("test", "original")),
                   "test_nsynth": solo_stats(items("test_nsynth"), ti, tf), "dev_nsynth_only": solo_stats([(sf(c["file"])[1].mean(0), sf(c["file"])[2].mean(0), solo_truth(c)) for c in clips if c["split"] == "dev_nsynth" and c["file"] in data], ti, tf)}
            # Source type (C only: A has no imitation class).
            if kind == "C":
                conf = Counter()
                for c in clips:
                    if c["kind"] == "solo" and role(c) == "test" and c["variant"] == "original":
                        pred = SOURCES[int(np.argmax(sf(c["file"])[3].mean(0)))]; conf[(solo_truth(c)[3], pred)] += 1
                rep["source_confusion_test"] = {f"{a} -> {b}": n for (a, b), n in sorted(conf.items())}
            twi, twf = pick_window(clips, sf, win)
            rep["layered_test"] = layered_report(clips, sf, {"test"}, twi, twf, win); rep["window_thresholds"] = [round(float(twi), 2), round(float(twf), 2)]
            results.append(rep)
            print("CALIB", label, json.dumps({"dev": dev_st, "test_original": rep["test"]["original"]}))
    json.dump(results, open(report_path.replace(".md", ".json"), "w"), indent=1)
    write_md(results, report_path)


def p(x):
    return "–" if x is None else f"{100 * x:.0f}%"


def write_md(results, path):
    L = ["# Gate 1 — calibrated abstention (synthetic proxy; NOT real film-music accuracy)", "",
         f"Thresholds chosen on DEV (FluidR3 phrase 2 + layered 16–23) for wrong-family ≤ {int(TARGET_WRONG*100)}% at maximum coverage; heads trained on TRAIN (FluidR3 phrases 0–1 + layered 0–15); TEST = GeneralUser GS, untouched.", "",
         "## TEST, original solo clips", "", "| System | DEV target met | Coverage | Selective family acc. | Selective exact acc. | Exact overall | Wrong family | Unknown |", "|---|---|---|---|---|---|---|---|"]
    for r in results:
        t = r["test"]["original"]
        tgt = {True: "yes", False: "NO", None: "n/a (always answers)"}[r["target_reached_on_dev"]]
        L.append(f"| {r['system']} | {tgt} | {p(t['coverage'])} | {p(t['selective_family_acc'])} | {p(t['selective_exact_acc'])} | {p(t['exact_overall'])} | {p(t['wrong_family'])} | {p(t['unknown'])} |")
    L += ["", "## TEST by condition (coverage / wrong family / selective family accuracy)", "", "| System | Original | Reverb | Compressed | Short 1 s | Imitation tones |", "|---|---|---|---|---|---|"]
    for r in results:
        cell = lambda v: f"{p(r['test'][v]['coverage'])} / {p(r['test'][v]['wrong_family'])} / {p(r['test'][v]['selective_family_acc'])}"
        L.append(f"| {r['system']} | " + " | ".join(cell(v) for v in ("original", "reverb", "compressed", "short", "imitation")) + " |")
    L += ["", "## Coverage curve on TEST (family accuracy of the most confident share; reporting only)", "", "| System | 100% | 90% | 80% | 70% | 60% | 50% | 30% |", "|---|---|---|---|---|---|---|---|"]
    for r in results:
        cc = r["coverage_curve_test"]; L.append(f"| {r['system']} | " + " | ".join(p(cc[k]) for k in ("100%", "90%", "80%", "70%", "60%", "50%", "30%")) + " |")
    L += ["", "## NSynth TEST (real recorded/synthesised notes, CC BY 4.0; different source; family level only)", "", "| System | Coverage | Selective family acc. | Wrong family | Unknown |", "|---|---|---|---|---|"]
    for r in results:
        t = r.get("test_nsynth")
        if t and t["n"]:
            L.append(f"| {r['system']} | {p(t['coverage'])} | {p(t['selective_family_acc'])} | {p(t['wrong_family'])} | {p(t['unknown'])} |")
    L += ["", "## Layered tracks on TEST (window thresholds from DEV)", "", "| System | Window instrument P/R/F1 | Window family P/R/F1 | Events detected | Onset error median / p90 | Offset error median / p90 | Instrument F1 by #instruments |", "|---|---|---|---|---|---|---|"]
    for r in results:
        if "layered_test" not in r: continue
        l = r["layered_test"]; f = lambda t: "/".join(f"{x:.2f}" for x in t); s = lambda x: "–" if x is None else f"{x:.1f} s"
        L.append(f"| {r['system']} | {f(l['window_instrument_prf'])} | {f(l['window_family_prf'])} | {l['events_detected']} | {s(l['onset_err_median'])} / {s(l['onset_err_p90'])} | {s(l['offset_err_median'])} / {s(l['offset_err_p90'])} | " + ", ".join(f"{k}: {v:.2f}" for k, v in l["window_instrument_f1_by_count"].items()) + " |")
    L += ["", "## Source type on TEST (C heads; truth -> predicted)", ""]
    for r in results:
        if "source_confusion_test" in r:
            L.append(f"- **{r['system']}**: " + "; ".join(f"{k}: {v}" for k, v in r["source_confusion_test"].items()))
    open(path, "w").write("\n".join(L) + "\n"); print("\n".join(L))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
