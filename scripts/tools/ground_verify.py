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
    print("  WHY TWO BASES, and why they disagree: the noise octaves are a uniform")
    print("  RGB multiply, which leaves HSV saturation exactly invariant - so the")
    print("  FIELD (median) saturation reproduces the base colour's to the digit,")
    print("  and that is the basis the ruling's own numbers are quoted on. The")
    print("  scatter layer darkens by SUBTRACTION, and subtracting a constant from")
    print("  all three channels RAISES (mx-mn)/mx: the flecks are the most saturated")
    print("  pixels in the frame. Making the scatter multiplicative would leave the")
    print("  whole field saturation-invariant BY CONSTRUCTION - the constraint could")
    print("  then not be violated at all, rather than being checked after the fact.")
    print("  That changes the look, so it is the designer's call, not this script's.")
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
