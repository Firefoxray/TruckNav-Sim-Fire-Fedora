#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch-trucksim-maps-south-dakota.py <trucksim-maps-dir>")

root = Path(sys.argv[1]).resolve()
constants = root / "packages" / "libs" / "map" / "constants.ts"
if not constants.is_file():
    raise SystemExit(f"missing expected file: {constants}")

text = constants.read_text(encoding="utf-8")

replacements = [
    (
        "export type AtsSelectableDlc = Exclude<AtsDlc, AtsDlc.SouthDakota>;",
        "export type AtsSelectableDlc = AtsDlc;",
    ),
    (
        "  AtsDlc.Illinois,\n]);",
        "  AtsDlc.Illinois,\n  AtsDlc.SouthDakota,\n]);",
    ),
    (
        "  [AtsDlc.Illinois]: 'Illinois',\n};",
        "  [AtsDlc.Illinois]: 'Illinois',\n  [AtsDlc.SouthDakota]: 'South Dakota',\n};",
    ),
    (
        "  'dlc_il.scs': 50,\n};",
        "  'dlc_il.scs': 50,\n  'dlc_sd.scs': 53,\n};",
    ),
]

changed = False
for old, new in replacements:
    if new in text:
        continue
    if old not in text:
        raise SystemExit(
            "truckermudgeon/maps changed unexpectedly; could not find:\n" + old
        )
    text = text.replace(old, new, 1)
    changed = True

constants.write_text(text, encoding="utf-8")

if changed:
    print("Patched truckermudgeon/maps for South Dakota.")
else:
    print("South Dakota patch already applied.")
