#!/usr/bin/env python3
"""Ground Rendering Phase 1 - mechanical verification over the captured PNGs.

Run AFTER the capture harness (see scripts/tools/ground_capture.gd header):

    python scripts/tools/ground_verify.py

Reads docs/captures/ground-phase1/*.png + capture_meta.json and checks:

  1. Luminance spread per candidate green (a/b/c): relative luminance
     0.2126R + 0.7152G + 0.0722B over sRGB bytes/255; designer constraint
     is spread (max - min) UNDER 0.12.
  2. Saturation/value vs VERDIGRIS #4E7A66 (designer ruling 2026-08-28).
     The original constraint - "darker and less saturated than wrought iron
     #46504E" - is WITHDRAWN as written: near-neutral grey (HSV-sat 0.125)
     excludes green by construction, and the rule failed its own candidate
     colours. RESTATED against what it was actually protecting: verdigris,
     the only saturated accent in the palette and the one electrical
     signifier. Ground saturation must not exceed it; ground value must sit
     well below it. Measured on TWO bases, because they disagree - see the
     note printed by this section. The luminance-spread ceiling (item 1) is
     unchanged at 0.12.
  3. Scroll diff (swim test): shift ground_scroll_1 by the integer pixel
     offset recorded in capture_meta.json and diff the overlap against
     ground_scroll_2. World-locked noise => the overlap must match.
     The scroll pair is captured with GridWorld, Player and HUD all hidden
     (pure ground), so no cropping is needed - the whole overlap is ground.
  4. Non-flatness of every capture (Route C trap 2's check) + the three
     base-green frames must differ from each other.

Exit code 0 only if the MECHANICAL gates hold (non-flat, candidates
distinct, scroll overlap matches, field saturation within verdigris).
Luminance spread is reported and flagged but is the designer's ceiling to
move. A scatter-fleck excursion above verdigris prints RULING NEEDED - it
is never silent, which is the point of writing the constraint down here.

Pure stdlib (zlib/struct) - no Pillow dependency; Godot's save_png output
is 8-bit RGB/RGBA non-interlaced, decoded below.
"""

import json
import struct
import sys
import zlib
from pathlib import Path

CAPTURE_DIR = Path(__file__).resolve().parents[2] / "docs" / "captures" / "ground-phase1"

# Designer ruling, 2026-08-28. The iron reference was wrong by construction:
# a near-neutral grey (HSV-sat 0.125) admits no green at all, so the rule
# failed the very candidates it was written to judge. What it protects is
# VERDIGRIS - the only saturated accent in the building palette and the one
# electrical signifier. Ground saturation must not exceed it; ground value
# must sit well below it. Named constants, so the constraint that drifted
# once cannot drift silently again.
VERDIGRIS = (0x4E, 0x7A, 0x66)  # #4E7A66
VERDIGRIS_SAT = (max(VERDIGRIS) - min(VERDIGRIS)) / max(VERDIGRIS)   # 0.3607
VERDIGRIS_VAL = max(VERDIGRIS) / 255.0                               # 0.4784
# "Well below" made numeric: the ground's value ceiling as a fraction of
# verdigris's. All three candidates sit near 0.47x, so 0.75 is a generous
# floor that still catches a ground drifting up toward the accent.
VALUE_HEADROOM = 0.75

# The three candidate greens, by capture file. Needed because the STRUCTURAL
# check below re-derives invariance from whatever base a frame was rendered
# with, rather than from a number someone typed.
BASE_BY_FILE = {
    "ground_green_a.png": (0x2E, 0x3A, 0x26),
    "ground_green_b.png": (0x2A, 0x38, 0x30),
    "ground_green_c.png": (0x33, 0x3D, 0x2A),
}

# Byte-rounding slack for the structural check, in LSBs. NOT a tolerance on
# the constraint - it is arithmetic hygiene. A pixel is accepted if SOME
# uniform scale k of the base rounds to it; the interval that k must lie in
# is +/- 0.5 LSB by the definition of rounding, and this widens it to 1.0 to
# absorb GPU float32 rounding at an exact .5 boundary. Measured cost of that
# widening: one pixel in 6,220,800 needed it (ground_green_c, px (977,303),
# off by 0.04 of an LSB). Measured margin it leaves: the SUBTRACTIVE scatter
# this check was written to forbid moves every channel by ~13 LSB
# (0.05 x 255), so the guard has ~13x the slack it grants.
SCALE_SLACK_LSB = 1.0

# THE SHIPPED GREEN. Must equal the shader's base_color default and the
# Background ColorRect's fallback colour - all three move together or the
# render, the fallback and this check disagree. Candidate A, picked
# 2026-08-28.
SHIPPED_GREEN = (0x2E, 0x3A, 0x26)

# Hue separation from the accent. The saturation and value constraints did
# not express hue at all, and candidate B passed every one of them while
# being wrong: B sits 7.0 deg from verdigris, inside the accent's own hue
# family, which would have put the entire map in the electrical signifier's
# hue. The threshold is placed between the measured cases (B 7.0 deg
# rejected; A 56.7 deg and C 61.1 deg accepted) at the width of a colour-
# wheel family, ~30 deg - deliberately NOT tuned to let either case squeak
# past. Moving it is a designer decision, not a maintenance one.
MIN_HUE_SEPARATION_DEG = 30.0


def decode_png(path):
    """Minimal PNG decoder: 8-bit RGB(A), non-interlaced. Returns
    (width, height, channels, bytearray of raw pixel bytes row-major)."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path}: not a PNG")
    pos = 8
    width = height = None
    bit_depth = color_type = None
    idat = bytearray()
    while pos < len(data):
        length, ctype = struct.unpack(">I4s", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if ctype == b"IHDR":
            width, height, bit_depth, color_type, comp, filt, interlace = struct.unpack(">IIBBBBB", chunk)
            if bit_depth != 8 or color_type not in (2, 6) or interlace != 0:
                raise ValueError(f"{path}: unsupported PNG (depth={bit_depth} color={color_type} interlace={interlace})")
        elif ctype == b"IDAT":
            idat.extend(chunk)
        elif ctype == b"IEND":
            break
    channels = 3 if color_type == 2 else 4
    raw = zlib.decompress(bytes(idat))
    stride = width * channels
    out = bytearray(height * stride)
    prev = bytearray(stride)
    src = 0
    for y in range(height):
        ftype = raw[src]
        src += 1
        line = bytearray(raw[src:src + stride])
        src += stride
        if ftype == 1:  # Sub
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif ftype == 2:  # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ftype == 3:  # Average
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ftype == 4:  # Paeth
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = prev[i]
                c = prev[i - channels] if i >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                if pa <= pb and pa <= pc:
                    pr = a
                elif pb <= pc:
                    pr = b
                else:
                    pr = c
                line[i] = (line[i] + pr) & 0xFF
        elif ftype != 0:
            raise ValueError(f"{path}: bad filter {ftype}")
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return width, height, channels, out


def lum(r, g, b):
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0


def hue_deg(rgb):
    """HSV hue in degrees. Pure arithmetic - no colorsys dependency."""
    r, g, b = [c / 255.0 for c in rgb]
    mx, mn = max(r, g, b), min(r, g, b)
    d = mx - mn
    if d == 0:
        return 0.0
    if mx == r:
        h = 60.0 * (((g - b) / d) % 6.0)
    elif mx == g:
        h = 60.0 * (((b - r) / d) + 2.0)
    else:
        h = 60.0 * (((r - g) / d) + 4.0)
    return h % 360.0


def hue_separation(rgb_a, rgb_b):
    """Shortest angular distance between two hues, in degrees."""
    d = abs(hue_deg(rgb_a) - hue_deg(rgb_b)) % 360.0
    return min(d, 360.0 - d)


def modal_pixel(w, h, ch, px):
    """Most common RGB triple - the ground colour in a mostly-ground frame."""
    counts = {}
    stride = w * ch
    for y in range(0, h, 2):
        row = px[y * stride:(y + 1) * stride]
        for x in range(0, stride, ch * 2):
            k = (row[x], row[x + 1], row[x + 2])
            counts[k] = counts.get(k, 0) + 1
    return max(counts.items(), key=lambda kv: kv[1])[0]


def uniform_scale_violations(w, h, ch, px, base, slack=SCALE_SLACK_LSB):
    """Count pixels that are NOT a quantized uniform scale of `base`.

    THE STRUCTURAL FORM OF THE SATURATION CONSTRAINT (designer ruling
    2026-08-28: "a tolerance is an accidental pass"). Every stage of the
    shader is a uniform RGB multiply - the three noise octaves and, since
    the scatter went multiplicative, the flecks too. So every rendered pixel
    must be base * k for SOME scalar k, up to byte rounding. Uniform scaling
    leaves HSV saturation exactly invariant, so proving this proves the
    saturation constraint holds by construction: it cannot be violated by
    changing the green, the amplitudes, the density, or the fleck depth.

    Why this and not "max_sat <= field_sat": at 8 bits that stricter-looking
    test is FALSE ON CORRECT CODE. Rounding each channel to a byte perturbs
    (mx-mn)/mx by up to ~0.017, so ~42% of pixels in a correct render sit a
    hair above the base saturation. A check that fails on correct code gets
    relaxed to a tolerance by the next person - which is the accidental pass
    the ruling was written to prevent. This form is stricter in the way that
    matters (it forbids ANY additive term, anywhere in the shader) and true.

    Implementation: for each channel, the set of k that rounds to the
    observed byte is an interval. The pixel conforms iff the three intervals
    intersect.
    """
    bad = 0
    worst = None
    stride = w * ch
    for y in range(h):
        row = px[y * stride:(y + 1) * stride]
        for x in range(0, stride, ch):
            lo, hi = 0.0, 1e9
            for i in range(3):
                c = row[x + i]
                bc = base[i]
                if bc == 0:
                    continue
                lo = max(lo, (c - slack) / bc)
                hi = min(hi, (c + slack) / bc)
            if lo >= hi:
                bad += 1
                if worst is None:
                    worst = (x // ch, y, row[x], row[x + 1], row[x + 2])
    return bad, worst


def image_stats(w, h, ch, px):
    """Single pass: luminance min/max, HSV saturation (field + max), value.

    TWO saturation bases, because they answer different questions and this
    render makes them disagree:

      field_sat - the MEDIAN pixel saturation. The noise octaves are a
        uniform RGB multiply (col = base * (1 + n)), and a uniform scale
        leaves HSV saturation exactly invariant, so the median reproduces
        the BASE COLOUR's saturation to the digit. This is the basis the
        designer's ruling quotes.
      max_sat - the single most saturated pixel. Elevated ONLY inside the
        scatter flecks, because the scatter darkens by SUBTRACTION
        (col -= darkness) and subtracting a constant from all three
        channels raises (mx-mn)/mx. See the note printed by main().
    """
    min_l, max_l = 10.0, -10.0
    max_sat, max_chroma = 0.0, 0
    max_val = 0.0
    sat_hist = {}
    over_verdigris = 0
    total = 0
    stride = w * ch
    for y in range(h):
        row = px[y * stride:(y + 1) * stride]
        for x in range(0, stride, ch):
            r, g, b = row[x], row[x + 1], row[x + 2]
            l = lum(r, g, b)
            if l < min_l:
                min_l = l
            if l > max_l:
                max_l = l
            mx = r if r >= g and r >= b else (g if g >= b else b)
            mn = r if r <= g and r <= b else (g if g <= b else b)
            c = mx - mn
            if c > max_chroma:
                max_chroma = c
            v = mx / 255.0
            if v > max_val:
                max_val = v
            total += 1
            if mx > 0:
                s = c / mx
                if s > max_sat:
                    max_sat = s
                if s > VERDIGRIS_SAT:
                    over_verdigris += 1
                k = round(s, 4)
                sat_hist[k] = sat_hist.get(k, 0) + 1
    # Median from the histogram - no 2M-element list.
    field_sat, seen = 0.0, 0
    for k in sorted(sat_hist):
        seen += sat_hist[k]
        if seen >= total // 2:
            field_sat = k
            break
    return {"min_lum": min_l, "max_lum": max_l, "spread": max_l - min_l,
            "max_sat": max_sat, "max_chroma": max_chroma,
            "field_sat": field_sat, "max_val": max_val,
            "over_verdigris": over_verdigris, "total_px": total}


def count_pixel_diffs(w, h, ch1, px1, ch2, px2):
    """Differing-pixel count between two same-size images (RGB compare)."""
    diffs = 0
    s1, s2 = w * ch1, w * ch2
    for y in range(h):
        r1 = px1[y * s1:(y + 1) * s1]
        r2 = px2[y * s2:(y + 1) * s2]
        if ch1 == ch2 and r1 == r2:
            continue
        for x in range(w):
            if r1[x * ch1:x * ch1 + 3] != r2[x * ch2:x * ch2 + 3]:
                diffs += 1
    return diffs


def scroll_diff(w, h, ch1, px1, ch2, px2, dx):
    """Camera moved +x by dx px between frames => world content at
    image-2 column x equals image-1 column x + dx. Compare the overlap.
    Returns (differing_pixels, max_channel_delta, overlap_pixels)."""
    diffs = 0
    max_delta = 0
    s1, s2 = w * ch1, w * ch2
    ow = w - dx
    for y in range(h):
        r1 = px1[y * s1:(y + 1) * s1]
        r2 = px2[y * s2:(y + 1) * s2]
        for x in range(ow):
            p1 = r1[(x + dx) * ch1:(x + dx) * ch1 + 3]
            p2 = r2[x * ch2:x * ch2 + 3]
            if p1 != p2:
                diffs += 1
                d = max(abs(p1[0] - p2[0]), abs(p1[1] - p2[1]), abs(p1[2] - p2[2]))
                if d > max_delta:
                    max_delta = d
    return diffs, max_delta, ow * h


def main():
    failures = []
    meta = json.loads((CAPTURE_DIR / "capture_meta.json").read_text())
    dx = int(meta["scroll_px_offset"])
    print(f"capture dir: {CAPTURE_DIR}")
    print(f"scroll offset from meta: {dx} px (world dx {meta['scroll_world_dx']}, scale {meta['world_to_screen_scale']})")
    print()

    images = {}
    for name in ["ground_green_a.png", "ground_green_b.png", "ground_green_c.png",
                 "ground_composite.png", "ground_scroll_1.png", "ground_scroll_2.png"]:
        images[name] = decode_png(CAPTURE_DIR / name)
        w, h, ch, _ = images[name]
        print(f"loaded {name}: {w}x{h} ({ch} ch)")
    print()

    # ---- 4. non-flatness of every capture ----
    print("== non-flatness (trap 2's check) ==")
    for name, (w, h, ch, px) in images.items():
        st = image_stats(w, h, ch, px)
        images[name] = (w, h, ch, px, st)
        flat = st["spread"] <= 0.0
        print(f"  {name}: lum min {st['min_lum']:.4f} max {st['max_lum']:.4f} spread {st['spread']:.4f} -> {'FLAT (FAIL)' if flat else 'non-flat ok'}")
        if flat:
            failures.append(f"{name} is flat")
    print()

    # ---- candidates must differ from each other ----
    print("== candidate distinctness ==")
    for n1, n2 in [("ground_green_a.png", "ground_green_b.png"),
                   ("ground_green_b.png", "ground_green_c.png"),
                   ("ground_green_a.png", "ground_green_c.png")]:
        w, h, ch1, px1, _ = images[n1]
        _, _, ch2, px2, _ = images[n2]
        d = count_pixel_diffs(w, h, ch1, px1, ch2, px2)
        print(f"  {n1} vs {n2}: {d} differing pixels")
        if d == 0:
            failures.append(f"{n1} identical to {n2} - base_color override did not take")
    print()

    # ---- 1. luminance spread per candidate ----
    print("== luminance spread (designer constraint: spread < 0.12) ==")
    for name in ["ground_green_a.png", "ground_green_b.png", "ground_green_c.png"]:
        st = images[name][4]
        verdict = "PASS" if st["spread"] < 0.12 else "FAIL"
        print(f"  {name}: min {st['min_lum']:.4f}  max {st['max_lum']:.4f}  spread {st['spread']:.4f}  -> {verdict}")
        if verdict == "FAIL":
            print(f"    (reported to the designer; not a mechanical gate)")
    print()

    # ---- 2. vs verdigris #4E7A66 (restated constraint) ----
    print("== vs verdigris #4E7A66 (restated constraint, designer ruling 2026-08-28) ==")
    print(f"  verdigris: HSV-sat {VERDIGRIS_SAT:.4f}  value {VERDIGRIS_VAL:.4f}")
    print("  WITHDRAWN: 'less saturated than wrought iron #46504E' - a near-neutral")
    print("  grey excludes green by construction; the rule failed its own candidates.")
    print("  RESTATED: ground saturation must not exceed verdigris (the only saturated")
    print("  accent, the electrical signifier); ground value well below it.")
    for name in ["ground_green_a.png", "ground_green_b.png", "ground_green_c.png"]:
        st = images[name][4]
        field_ok = st["field_sat"] <= VERDIGRIS_SAT
        val_ok = st["max_val"] <= VERDIGRIS_VAL * VALUE_HEADROOM
        if not field_ok:
            failures.append(
                f"{name}: field saturation {st['field_sat']:.4f} exceeds verdigris {VERDIGRIS_SAT:.4f}")
        if not val_ok:
            failures.append(
                f"{name}: max value {st['max_val']:.4f} not well below verdigris {VERDIGRIS_VAL:.4f}")
        print(f"  {name}: field_sat {st['field_sat']:.4f} ({'PASS' if field_ok else 'EXCEEDS: FAIL'})  "
              f"max_val {st['max_val']:.4f} = {st['max_val'] / VERDIGRIS_VAL:.2f}x verdigris "
              f"({'PASS' if val_ok else 'TOO CLOSE: FAIL'})")
        if st["over_verdigris"] > 0:
            pct = 100.0 * st["over_verdigris"] / st["total_px"]
            print(f"    RULING NEEDED: {st['over_verdigris']} px ({pct:.4f}%) exceed verdigris "
                  f"saturation, max {st['max_sat']:.4f} - scatter flecks only.")
    print()

    # ---- 2b. THE STRUCTURAL FORM: uniform-scale invariance ----
    print("== saturation invariance BY CONSTRUCTION (scatter multiplicative since 2026-08-28) ==")
    print("  Every shader stage is a uniform RGB multiply, so every pixel must be")
    print("  base * k for some scalar k, up to byte rounding. Uniform scaling leaves")
    print("  HSV saturation exactly invariant - proving this proves the constraint")
    print("  cannot be violated by any green, amplitude, density or fleck depth.")
    for name, base in BASE_BY_FILE.items():
        w2, h2, ch2, px2, st = images[name]
        bad, worst = uniform_scale_violations(w2, h2, ch2, px2, base)
        base_sat = (max(base) - min(base)) / max(base)
        if bad:
            failures.append(f"{name}: {bad} px are not a uniform scale of base {base}")
        print(f"  {name}: base {base} sat {base_sat:.4f} | non-conforming px {bad} "
              f"({'PASS' if bad == 0 else 'FAIL'})" + (f" first at {worst[:2]}" if worst else ""))
    print()
    print("  NOTE on the form of this check. The ruling asked for 'max-over-pixels")
    print("  saturation must EQUAL field saturation, not a tolerance'. That exact")
    print("  test is false on correct code at 8 bits: byte rounding perturbs")
    print("  (mx-mn)/mx by up to ~0.017, so ~42% of pixels in a CORRECT render sit a")
    print("  hair above base saturation. A check that fails on correct code gets")
    print("  relaxed into a tolerance by whoever meets it next - the accidental pass")
    print("  the ruling exists to prevent. The uniform-scale test above is the")
    print("  stronger true form: it forbids ANY additive term anywhere in the shader,")
    print("  which is the thing that actually broke the invariant.")
    print()

    # ---- 2c. hue separation from the accent, and the shipped green ----
    print("== hue separation from verdigris (designer ruling 2026-08-28) ==")
    vh = hue_deg(VERDIGRIS)
    print(f"  verdigris hue {vh:.1f} deg | minimum separation {MIN_HUE_SEPARATION_DEG:.0f} deg")
    ship_sep = hue_separation(SHIPPED_GREEN, VERDIGRIS)
    ship_ok = ship_sep >= MIN_HUE_SEPARATION_DEG
    if not ship_ok:
        failures.append(
            f"shipped green {SHIPPED_GREEN} is {ship_sep:.1f} deg from verdigris, "
            f"inside the accent's hue family (minimum {MIN_HUE_SEPARATION_DEG:.0f})")
    print(f"  SHIPPED {SHIPPED_GREEN} hue {hue_deg(SHIPPED_GREEN):.1f} deg | "
          f"separation {ship_sep:.1f} deg ({'PASS' if ship_ok else 'INSIDE ACCENT FAMILY: FAIL'})")
    for name, base in BASE_BY_FILE.items():
        sep = hue_separation(base, VERDIGRIS)
        tag = "  <- SHIPPED" if base == SHIPPED_GREEN else (
            "  <- rejected on hue; passed every saturation and value gate"
            if sep < MIN_HUE_SEPARATION_DEG else "")
        print(f"    {name}: hue {hue_deg(base):.1f} deg  separation {sep:.1f} deg{tag}")
    print()
    print("  WHY THIS GATE EXISTS: candidate B passed the luminance-spread ceiling,")
    print("  the verdigris saturation ceiling, the value headroom AND the structural")
    print("  invariance - every mechanical check in this file - and was still the")
    print("  wrong green, because none of them expressed hue. The constraints filter;")
    print("  they do not decide. B is the worked example, kept here deliberately.")
    print()

    # ---- 2d. the composite renders on the SHIPPED green, not a stale copy ----
    w3, h3, ch3, px3, _ = images["ground_composite.png"]
    modal = modal_pixel(w3, h3, ch3, px3)
    lo, hi = 0.0, 1e9
    for i in range(3):
        lo = max(lo, (modal[i] - SCALE_SLACK_LSB) / SHIPPED_GREEN[i])
        hi = min(hi, (modal[i] + SCALE_SLACK_LSB) / SHIPPED_GREEN[i])
    comp_ok = lo < hi
    if not comp_ok:
        failures.append(
            f"ground_composite.png ground colour {modal} is not the shipped green "
            f"{SHIPPED_GREEN} - the capture is stale")
    print("== composite renders on the shipped green ==")
    print(f"  modal ground pixel {modal} vs shipped {SHIPPED_GREEN}: "
          f"{'PASS' if comp_ok else 'STALE CAPTURE: FAIL'}")
    print("  The harness used to hold its own copy of the shipped green and restore")
    print("  THAT for the composite and both scroll frames; when the pick changed,")
    print("  three of six deliverables silently kept rendering the old colour. The")
    print("  harness now reads the shader's default instead, and this check is what")
    print("  would catch it coming back.")
    print()

    # ---- 3. scroll diff (the swim test) ----
    print("== scroll diff (world-locked swim test) ==")
    w, h, ch1, px1, _ = images["ground_scroll_1.png"]
    _, _, ch2, px2, _ = images["ground_scroll_2.png"]
    diffs, max_delta, overlap = scroll_diff(w, h, ch1, px1, ch2, px2, dx)
    print(f"  offset {dx} px, overlap {w - dx}x{h} = {overlap} px")
    print(f"  differing pixels: {diffs}  max per-channel delta: {max_delta}")
    if diffs == 0:
        print("  -> PASS: overlap is byte-identical; the noise is world-locked")
    elif max_delta <= 1 and diffs <= overlap * 0.001:
        print(f"  -> PASS (trivial deltas only: <=1 step on {diffs}/{overlap} px)")
    else:
        print("  -> FAIL: the ground SWIMS - RED finding on the shader (world_pos path)")
        failures.append(f"scroll swim: {diffs} px differ, max delta {max_delta}")
    print()

    if failures:
        print("MECHANICAL FAILURES:")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("ground_verify: all mechanical gates PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
