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
    if c["split"] == "train_nsynth":
        return "train"
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


def agree(pi, pf):
    """Abstain (all-zero scores) unless the instrument head's best guess is in the family head's best family."""
    if FAM_OF[INSTRUMENTS[int(np.argmax(pi))]] != FAMILIES[int(np.argmax(pf))]:
        return np.zeros_like(pi), np.zeros_like(pf)
    return pi, pf


OFFICIAL_HEAD = {}


def export_head(rows, thresholds, out_path, source):
    """The official candidate (EfficientAT + head C, DEV thresholds) as plain JSON for the app's
    developer-only shadow mode: scaler, per-label logistic weights, family map, thresholds."""
    sc, heads = train_heads(rows, 0.5, True)
    def lin(hs, labels):
        D = len(sc.mean_)
        return {"labels": labels,
                "weights": [[round(float(v), 6) for v in h.coef_[0]] if h is not None else [] for h in hs],
                "bias": [round(float(h.intercept_[0]), 6) if h is not None else 0.0 for h in hs], "dim": D}
    json.dump({"version": 1, "source": source, "model": "EfficientAT mn10_as (embedding output)", "embeddingDim": int(len(sc.mean_)),
               "mean": [round(float(v), 6) for v in sc.mean_], "scale": [round(float(v), 6) for v in sc.scale_],
               "inst": lin(heads["inst"], INSTRUMENTS), "fam": lin(heads["fam"], FAMILIES), "familyOf": FAM_OF,
               "thresholds": [round(float(t), 4) for t in thresholds],
               "note": "SYNTHETIC-proxy-trained research head. Developer shadow mode only; never shown to users."},
              open(out_path, "w"))


def calibrate(dev_items):
    grid = np.concatenate([np.linspace(0.05, 0.95, 46), [0.97, 0.98, 0.99, 0.995, 0.999]])
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
                                 (KEYS[tk[0]]["source"] if KEYS[tk[0]]["source"] != "unknown" else None) if c["kind"] == "solo" and tk else None))
            def make_sf(C, balanced):
                sc, heads = train_heads(rows, C, balanced); cache = {}
                def sfc(f, d=data, sc=sc, heads=heads, cache=cache):
                    if f not in cache:
                        inst, fam, src = head_scores(sc, heads, d[f]["emb"]); cache[f] = (d[f]["starts"], inst, fam, src)
                    return cache[f]
                return sfc
            sf_c = make_sf(0.5, True)
            if name == "efficientat":
                OFFICIAL_HEAD.update(rows=rows)
            systems.append(("C", sf_c))
            # Variants aimed at confidently-wrong answers (short clips, other sound banks). Chosen on DEV only.
            systems.append(("Creg", make_sf(0.02, False)))      # stronger regularisation, unweighted
            systems.append(("Cagree", sf_c))                    # answer only when instrument and family heads agree
        for kind, sf in systems:
            label = {"C": f"C · {name} + head", "Creg": f"C-reg · {name} + head (C=0.02)", "Cagree": f"C-agree · {name} + head"}.get(kind, f"{kind} · {name}")
            post = agree if kind == "Cagree" else (lambda a, b: (a, b))
            items = lambda r, v=None, post=post: [(*post(sf(c["file"])[1].mean(0), sf(c["file"])[2].mean(0)), solo_truth(c)) for c in clips
                                        if c["kind"] == "solo" and role(c) == r and c["file"] in data and (v is None or c["variant"] == v or (v == "imitation" and solo_truth(c)[3] == "imitation"))]
            ti, tf, dev_st, reached = calibrate(items("dev"))
            # Short inputs (1 s clips) get their own DEV-calibrated thresholds.
            short_dev = [it for it, c in zip(items("dev"), [c for c in clips if c["kind"] == "solo" and role(c) == "dev" and c["file"] in data]) if c["variant"] == "short"]
            ts_i, ts_f, short_st, short_reached = calibrate(short_dev) if len(short_dev) >= 20 else (ti, tf, None, None)
            if kind == "A":   # best-guess variant: always answer (no abstention)
                results.append({"system": f"A-argmax · {name}", "thresholds": [0, 0], "dev": solo_stats(items("dev"), 0, 0), "target_reached_on_dev": None,
                                "test": {v: solo_stats(items("test", v), 0, 0) for v in ("original", "reverb", "compressed", "short", "imitation")},
                                "test_nsynth": solo_stats(items("test_nsynth"), 0, 0), "coverage_curve_test": coverage_curve(items("test", "original"))})
            if name == "efficientat" and kind == "C" and "rows" in OFFICIAL_HEAD:
                export_head(OFFICIAL_HEAD["rows"], (ti, tf), os.path.join(os.path.dirname(report_path), "efficientat_head.json"),
                            f"calibration {os.environ.get('GITHUB_RUN_ID', 'local')} · DEV thresholds")
            rep = {"system": label, "thresholds": [round(float(ti), 3), round(float(tf), 3)], "dev": dev_st, "target_reached_on_dev": reached,
                   "test": {v: solo_stats(items("test", v), *((ts_i, ts_f) if v == "short" else (ti, tf))) for v in ("original", "reverb", "compressed", "short", "imitation")},
                   "short_thresholds": [round(float(ts_i), 3), round(float(ts_f), 3)], "short_target_reached_on_dev": short_reached,
                   "coverage_curve_test": coverage_curve(items("test", "original")),
                   "test_nsynth": solo_stats(items("test_nsynth"), ti, tf), "dev_nsynth_only": solo_stats([(*post(sf(c["file"])[1].mean(0), sf(c["file"])[2].mean(0)), solo_truth(c)) for c in clips if c["split"] == "dev_nsynth" and c["file"] in data], ti, tf)}
            # Source type (C only: A has no imitation class).
            if kind in ("C", "Creg"):
                conf = Counter()
                for c in clips:
                    if c["kind"] == "solo" and role(c) == "test" and c["variant"] == "original":
                        pred = SOURCES[int(np.argmax(sf(c["file"])[3].mean(0)))]; conf[(solo_truth(c)[3], pred)] += 1
                rep["source_confusion_test"] = {f"{a} -> {b}": n for (a, b), n in sorted(conf.items())}
            if kind == "Cagree":   # window-level layered scores are identical to C
                results.append(rep); print("CALIB", label, json.dumps({"dev": dev_st, "test_original": rep["test"]["original"]})); continue
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
    # Selection uses DEV only (target met, then highest DEV coverage); TEST is shown for the chosen one, never used to choose.
    L += ["", "## DEV-selected head variant per model (C, C-reg, C-agree; chosen on DEV only)", "",
          "| Model | Chosen | DEV coverage / wrong | TEST original cov / wrong / sel. family | TEST short cov / wrong | NSynth TEST cov / wrong |", "|---|---|---|---|---|---|"]
    by_model = defaultdict(list)
    for r in results:
        if r["system"].startswith("C"):
            by_model[r["system"].split(" · ")[1].split(" ")[0]].append(r)
    for m, rs in sorted(by_model.items()):
        ok = [r for r in rs if r["target_reached_on_dev"]] or rs
        b = max(ok, key=lambda r: (r["dev"]["coverage"], -r["dev"]["wrong_family"]))
        t, sh, ns = b["test"]["original"], b["test"]["short"], b["test_nsynth"]
        L.append(f"| {m} | {b['system'].split(' · ')[0]}{'' if b['target_reached_on_dev'] else ' (DEV target NOT met)'} | {p(b['dev']['coverage'])} / {p(b['dev']['wrong_family'])} | "
                 f"{p(t['coverage'])} / {p(t['wrong_family'])} / {p(t['selective_family_acc'])} | {p(sh['coverage'])} / {p(sh['wrong_family'])} | {p(ns['coverage'])} / {p(ns['wrong_family'])} |")
    open(path, "w").write("\n".join(L) + "\n"); print("\n".join(L))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
