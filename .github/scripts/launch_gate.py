"""Speed budgets on the iPhone simulator (owner decision, 1 Nov 2026):
- Launch: five launches; the gate is the MEDIAN, limit 4 s. Every individual timing is recorded and
  reported (median, mean, p90, min, max). Nothing is discarded. The old average-of-3 view (first three
  launches) is also reported, for comparison with earlier builds.
- Peak memory: limit 1.5 GB.
Runner characteristics and the build version are written alongside, so slow runners can be told
apart from slow code.
Usage: launch_gate.py <uitest.log> <out.json> <label> [--no-gate]"""
import json, os, platform, re, statistics, subprocess, sys

LAUNCH_LIMIT_S = 4.0
PEAK_LIMIT_KB = 1.5e6


def values(log, name_prefix):
    """All 'values: [...]' lists of metrics whose name starts with name_prefix (e.g. 'Duration (AppLaunch)')."""
    out = []
    for m in re.finditer(r"measured \[" + re.escape(name_prefix) + r"[^\]]*\] average: [0-9.]+, .*?values: \[([^\]]*)\]", log):
        out.append([float(v) for v in m.group(1).split(",") if v.strip()])
    return out


def p90(xs):
    """90th percentile, linear interpolation between ranks (numpy's default method)."""
    s = sorted(xs); k = 0.9 * (len(s) - 1); lo = int(k); hi = min(lo + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (k - lo)


def sh(cmd):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=20).stdout.strip()
    except Exception:
        return ""


def runner():
    return {"runner_name": os.environ.get("RUNNER_NAME"), "image": os.environ.get("ImageOS"), "image_version": os.environ.get("ImageVersion"),
            "runner_arch": os.environ.get("RUNNER_ARCH"), "cpu": sh("sysctl -n machdep.cpu.brand_string"), "cores": sh("sysctl -n hw.ncpu"),
            "memory_gb": round(int(sh("sysctl -n hw.memsize") or 0) / 1e9, 1), "macos": sh("sw_vers -productVersion") or platform.platform(),
            "xcode": sh("xcodebuild -version | head -1"), "simulator": os.environ.get("TP_SIMULATOR", "")}


def main(log_path, out_path, label, gate=True):
    log = open(log_path, errors="replace").read()
    launches = values(log, "Duration (AppLaunch)")
    peaks = values(log, "Memory Peak Physical")
    rep = {"label": label, "measured_on": "GitHub Actions iPhone simulator (NOT a physical iPhone)",
           "commit": os.environ.get("GITHUB_SHA"), "run_id": os.environ.get("GITHUB_RUN_ID"), "ref": os.environ.get("GITHUB_REF_NAME"),
           "app_version": os.environ.get("TP_APP_VERSION", ""), "runner": runner()}
    bad = []
    if launches:
        xs = launches[-1]
        rep["launch"] = {"values_s": xs, "n": len(xs), "median_s": statistics.median(xs), "mean_s": statistics.fmean(xs),
                         "p90_s": p90(xs), "min_s": min(xs), "max_s": max(xs),
                         "old_avg_of_first_3_s": statistics.fmean(xs[:3]), "limit_median_s": LAUNCH_LIMIT_S}
        L = rep["launch"]
        print(f"::notice title=Launch ({label})::median {L['median_s']:.2f} s · mean {L['mean_s']:.2f} s · p90 {L['p90_s']:.2f} s · "
              f"values {', '.join(f'{v:.2f}' for v in xs)} s · old avg-of-3 view {L['old_avg_of_first_3_s']:.2f} s")
        if L["median_s"] > LAUNCH_LIMIT_S:
            bad.append(f"launch median {L['median_s']:.2f} s over {len(xs)} launches (limit 4 s); values {', '.join(f'{v:.2f}' for v in xs)}")
    else:
        rep["launch"] = None; print(f"::warning title=Launch ({label})::no launch measurement found in the log")
    if peaks:
        pk = max(max(v) for v in peaks)
        rep["peak_memory_mb"] = pk / 1024
        print(f"::notice title=Peak memory ({label})::{pk / 1024:.0f} MB (limit 1500 MB)")
        if pk > PEAK_LIMIT_KB:
            bad.append(f"peak memory {pk / 1024:.0f} MB (limit 1500 MB)")
    r = rep["runner"]
    print(f"::notice title=Runner ({label})::{r['image']} {r['image_version']} · {r['cpu']} · {r['cores']} cores · {r['memory_gb']} GB · "
          f"macOS {r['macos']} · {r['xcode']} · {r['simulator']}")
    rep["gate_failures"] = bad
    json.dump(rep, open(out_path, "w"), indent=1)
    for b in bad:
        print(f"::error title=Speed budget::{b}")
    return 1 if (bad and gate) else 0


if __name__ == "__main__":
    a = sys.argv
    sys.exit(main(a[1], a[2], a[3] if len(a) > 3 else "build", "--no-gate" not in a))
