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


def _srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _hexlin(h):
    h = h.lstrip("#")
    return [_srgb_to_linear(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4)]


def main():
    man = json.load(open(os.path.join(REPO, "art", "assets.json")))
    era = lock.PALETTE_ERA
    stale, missing, ok = [], [], []

    # The era is defined by the REMAP TARGET, not by what was typed into Tripo
    # and not by a hand-written string. Where an asset carries remap anchors,
    # verify their stored targets against the locked palette - that is the
    # actual thing the correction aims at, so it is what the gate must check.
    def target_matches(asset):
        rm = asset.get("albedo_remap") or {}
        anchors = rm.get("anchors") or []
        if not anchors:
            return None  # nothing to verify against
        for an in anchors:
            hexcode = lock.PALETTE.get(an["member"])
            if hexcode is None:
                return False
            want = _hexlin(hexcode)
            got = an.get("target") or []
            if len(got) != 3 or max(abs(w - g) for w, g in zip(want, got)) > 1e-3:
                return False
        return True

    for a in man["assets"]:
        if a.get("status") == "proxy":
            continue
        declared = a.get("palette_era")
        verified = target_matches(a)

        if declared is None:
            missing.append(a["name"])
        elif declared != era:
            stale.append((a["name"], declared))
        elif verified is False:
            stale.append((a["name"], f"{declared} (declared) but its remap targets "
                                     f"do not match the locked palette"))
        else:
            ok.append(a["name"] + ("" if verified else "  [declared only - no remap anchors to verify]"))

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
