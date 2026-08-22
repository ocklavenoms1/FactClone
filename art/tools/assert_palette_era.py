"""Build gate: every asset must declare the CURRENT palette era.

    python art/tools/assert_palette_era.py

Three assets across two palette eras is not a consistency test - it is a
demonstration that palette eras differ. So a mismatch is a hard failure, not a
note: an asset generated against a superseded palette cannot enter the verdict,
and the correction cannot rescue it either (the albedo remap is a drift
corrector, not a recolouring tool - retargeting a legacy asset onto a new
palette recolours it, measured).

Proxies are exempt: they carry no Tripo texture and are re-materialed directly
from the locked palette, so they are always current by construction.
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "blender"))
import lock  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))


def main():
    man = json.load(open(os.path.join(REPO, "art", "assets.json")))
    era = lock.PALETTE_ERA
    stale, missing, ok = [], [], []

    for a in man["assets"]:
        if a.get("status") == "proxy":
            continue
        declared = a.get("palette_era")
        if declared is None:
            missing.append(a["name"])
        elif declared != era:
            stale.append((a["name"], declared))
        else:
            ok.append(a["name"])

    print(f"locked palette era: {era}")
    if ok:
        print(f"  current: {', '.join(ok)}")
    for n, d in stale:
        print(f"  STALE:   {n} declares '{d}'")
    for n in missing:
        print(f"  MISSING: {n} declares no palette_era")

    if stale or missing:
        print("\nPALETTE ERA ASSERTION FAILED")
        for n, d in stale:
            print(f"  {n}: generated against '{d}', locked era is '{era}'. Regenerate it.")
        for n in missing:
            print(f"  {n}: add \"palette_era\": \"{era}\" once generated against the locked palette.")
        print("An asset from a superseded palette cannot enter the consistency "
              "verdict, and the albedo correction cannot retarget it - that "
              "recolours rather than corrects.")
        return 1

    print("\npalette era assertion: all real assets on the locked palette")
    return 0


if __name__ == "__main__":
    sys.exit(main())
