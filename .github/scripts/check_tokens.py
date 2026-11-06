#!/usr/bin/env python3
"""Fails if App/Sources/DesignSystem/Tokens.swift drifts from design/tokens/tonepilot.tokens.json
(colour hex values for dark/light, spacing, radius and size). The JSON is the source of truth."""
import json, re, sys
tok = json.load(open("design/tokens/tonepilot.tokens.json"))
swift = open("App/Sources/DesignSystem/Tokens.swift").read()
bad = []
for name, v in tok["color"].items():
    if not isinstance(v, dict) or "dark" not in v or len(v["dark"]) != 7: continue
    m = re.search(rf"static let {name} = dynamic\(dark: 0x([0-9A-F]+), light: 0x([0-9A-F]+)", swift)
    if not m: bad.append(f"colour {name} missing in Tokens.swift"); continue
    if m.group(1) != v["dark"][1:].upper() or m.group(2) != v["light"][1:].upper():
        bad.append(f"colour {name}: swift {m.group(1)}/{m.group(2)} vs json {v['dark']}/{v['light']}")
for group, enum in (("space", "Space"), ("radius", "Radius"), ("size", "Size")):
    block = swift[swift.index(f"enum {enum} {{"):]
    block = block[:block.index("\n    }")]
    for k, val in tok[group].items():
        if k == "full": continue
        m = re.search(rf"static let {k}: CGFloat = ([0-9.]+)", block)
        if not m or float(m.group(1)) != float(val): bad.append(f"{group}.{k}: swift {m.group(1) if m else 'missing'} vs json {val}")
for b in bad: print(f"::error title=Design tokens out of sync::{b}")
print("tokens in sync" if not bad else f"{len(bad)} token mismatches")
sys.exit(1 if bad else 0)
