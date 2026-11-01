"""Licence manifest gate. Usage:
  check_manifest.py <manifest.json> --build personal|commercial
  check_manifest.py <manifest.json> --self-test
A commercial build fails if any item that ships (bundled / download / system) is not "Cleared".
SAFE* never passes. The check cannot establish legal clearance; it enforces the recorded status."""
import json, sys

STATUSES = {"Cleared", "SAFE*", "Personal only", "Rejected", "Unverified"}
RECORDS = ("code", "weights", "dependencies", "data")

def check(manifest, build):
    errors, items = [], manifest.get("items", [])
    for it in items:
        for k in ("id", "shipped", "status") + RECORDS:
            if k not in it:
                errors.append(f"{it.get('id', '?')}: missing field '{k}'")
        if it.get("status") not in STATUSES:
            errors.append(f"{it.get('id')}: unknown status {it.get('status')!r}")
        ships = it.get("shipped") in ("bundled", "download", "system")
        if build == "commercial" and ships and it.get("status") != "Cleared":
            errors.append(f"{it.get('id')}: status {it.get('status')!r} cannot ship in a commercial build")
        if it.get("status") == "Rejected" and ships:
            errors.append(f"{it.get('id')}: rejected item is shipped")
    return errors

def main():
    manifest = json.load(open(sys.argv[1]))
    if "--self-test" in sys.argv:
        probe = {"items": [{"id": "probe", "shipped": "bundled", "status": "SAFE*", "code": "MIT", "weights": "MIT", "dependencies": None, "data": "x"}]}
        assert check(probe, "commercial"), "SAFE* must fail the commercial gate"
        assert not check(probe, "personal"), "SAFE* may be used in personal builds"
        probe["items"][0]["status"] = "Cleared"
        assert not check(probe, "commercial")
        print("self-test passed: SAFE* fails the commercial gate; Cleared passes")
        return 0
    build = sys.argv[sys.argv.index("--build") + 1]
    errors = check(manifest, build)
    for e in errors:
        print(f"::error title=Licence gate ({build})::{e}")
    shipped = [f"{i['id']}={i['status']}" for i in manifest["items"] if i.get("shipped") in ("bundled", "download", "system")]
    print(f"::notice title=Licence gate ({build})::{'PASS' if not errors else 'FAIL'} · shipped: {', '.join(shipped)}")
    return 1 if errors else 0

sys.exit(main())
