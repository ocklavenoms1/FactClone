"""The lock: every constant that must never drift, in one place.

Changing ANY value here invalidates every sprite already rendered. The lock
stamp is a hash of these values; it is written into each asset's metadata JSON,
so a sprite rendered under a different camera or rig is detectable rather than
silently wrong.

Imported by both Blender scripts and system-Python tools, so it must depend on
nothing but the standard library.
"""

import hashlib
import json
import math

# ---------------------------------------------------------------- geometry --
TILE_PX = 32                 # matches TILE_SIZE in the Godot project
SUPERSAMPLE = 4              # render at 4x, downsample to TILE_PX

# Camera. Azimuth 0 -> the ground grid stays axis-aligned squares, which is
# what Factorio does and what the existing draw_one() rects assume. A 45deg
# azimuth would project tiles to diamonds (isometric) and would not sit on the
# game's grid. Pitch 60deg above the ground plane gives the shallow 3/4 look.
CAM_AZIMUTH_DEG = 0.0
CAM_PITCH_DEG = 60.0         # above the ground plane, NOT from vertical

TILT_FROM_VERTICAL_DEG = 90.0 - CAM_PITCH_DEG          # 30
GROUND_SQUASH = math.sin(math.radians(CAM_PITCH_DEG))  # 0.86603 tile depth on screen
WALL_RATIO = 1.0 / math.tan(math.radians(CAM_PITCH_DEG))  # 0.57735 screen-height per world-height

# ---------------------------------------------------------------- lighting --
# Key from screen upper-left so shadows fall lower-right.
KEY_ELEV_DEG = 50.0
KEY_PLAN_DEG = 135.0
KEY_ENERGY = 3.2
KEY_COLOR = (1.0, 0.965, 0.912)
KEY_ANGLE_DEG = 8.0          # soft-but-defined shadow edge

FILL_ELEV_DEG = 25.0
FILL_PLAN_DEG = 300.0
FILL_ENERGY = 0.85
FILL_COLOR = (0.80, 0.87, 1.0)

RIM_ELEV_DEG = 55.0
RIM_PLAN_DEG = 330.0
RIM_ENERGY = 1.15
RIM_COLOR = (0.88, 0.93, 1.0)

WORLD_COLOR = (0.42, 0.47, 0.55)
WORLD_STRENGTH = 0.22        # keeps shadow sides off pure black

# ------------------------------------------------------------------ render --
ENGINE = "CYCLES"            # Blender 5.x renamed EEVEE_NEXT; Cycles CPU is
CYCLES_DEVICE = "CPU"        # dependable headless and fast at these sizes
CYCLES_SAMPLES = 96
VIEW_TRANSFORM = "Standard"  # NOT AgX: it mutes the locked palette at 32px
VIEW_LOOK = "None"

# ------------------------------------------------------------- framing/norm --
FRAME_PAD_TILES = 0.04       # 0.10 pushed a 1x1 chest into a 2-tile cell
FOOTPRINT_FILL = 0.92        # fraction of footprint an XY-fitted model spans

# ------------------------------------------- material normalization clamps --
ROUGHNESS_RANGE = (0.34, 0.86)
METALLIC_CEILING = 0.55
EMISSION_CEILING = 2.5

# ----------------------------------------------------------- locked palette --
# CLOSED SET. Nothing is added to this to solve a masking problem - see
# MASK_MAGENTA below for why that would be the wrong layer.
#
# `forge_brown` was called `hot_iron` and was expected to signal emission. It
# never does again: it means "warm-toned metal" and nothing more. Heat is a
# STATE, and states are keyed on the mask colour, not on a palette member.
PALETTE = {
    "fieldstone": "#5A5E58",
    "fired_clay": "#8A6A4F",
    "weathered_oak": "#6B4E32",
    "wrought_iron": "#46504E",
    "leather": "#7A5A42",
    "forge_brown": "#8C4A32",
}

# The emission mask. Painted flat, unshaded, into the concept image on any
# region that should glow while the machine runs; Blender keys on it and
# substitutes the real fire colour at render time. It is a MASK, never a colour
# that survives to screen.
#
# Magenta is chosen because it appears in no real material in this set.
# Measured separation in linear RGB:
#     nearest palette member (fired_clay)   1.194
#     widest  pair inside the palette       0.206
#     the distance that killed the old key  0.079
# so the mask sits 15x clear of the failure threshold and ~6x outside the
# palette's own internal spread. The tolerance stops being a knife-edge:
# anything up to ~0.60 is safe.
MASK_MAGENTA = "#FF00FF"
MASK_TOLERANCE = 0.45        # well inside the 1.194 margin, wide enough for JPEG smear
MASK_FIRE_COLOR = (1.0, 0.42, 0.10)   # what the mask is replaced WITH


def _lock_payload():
    return {
        "tile_px": TILE_PX,
        "supersample": SUPERSAMPLE,
        "cam_azimuth_deg": CAM_AZIMUTH_DEG,
        "cam_pitch_deg": CAM_PITCH_DEG,
        "ground_squash": round(GROUND_SQUASH, 6),
        "wall_ratio": round(WALL_RATIO, 6),
        "key": [KEY_ELEV_DEG, KEY_PLAN_DEG, KEY_ENERGY, KEY_ANGLE_DEG],
        "fill": [FILL_ELEV_DEG, FILL_PLAN_DEG, FILL_ENERGY],
        "rim": [RIM_ELEV_DEG, RIM_PLAN_DEG, RIM_ENERGY],
        "world": [list(WORLD_COLOR), WORLD_STRENGTH],
        "engine": ENGINE,
        "samples": CYCLES_SAMPLES,
        "view_transform": VIEW_TRANSFORM,
        "look": VIEW_LOOK,
        "frame_pad_tiles": FRAME_PAD_TILES,
        "footprint_fill": FOOTPRINT_FILL,
        "roughness_range": list(ROUGHNESS_RANGE),
        "metallic_ceiling": METALLIC_CEILING,
        "emission_ceiling": EMISSION_CEILING,
    }


def lock_stamp():
    """Short stable hash of every locked value."""
    blob = json.dumps(_lock_payload(), sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()[:12]


def render_px(cell_w_tiles, cell_h_tiles):
    """Pixel dimensions of the 4x master.

    The vertical squash is baked into the render height and undone by the
    downsample. pixel_aspect_y does NOT work here: Blender ignores pixel aspect
    when framing an orthographic camera (verified - renders at 0.866 and 1.0
    came back byte-identical), because with square pixels the camera frame
    aspect is forced to equal the resolution aspect.
    """
    x = int(round(cell_w_tiles * TILE_PX * SUPERSAMPLE))
    y = int(round(cell_h_tiles * TILE_PX * SUPERSAMPLE * GROUND_SQUASH))
    return x, y


def sprite_px(cell_w_tiles, cell_h_tiles):
    return int(round(cell_w_tiles * TILE_PX)), int(round(cell_h_tiles * TILE_PX))


if __name__ == "__main__":
    print(f"lock_stamp   {lock_stamp()}")
    print(f"ground_squash {GROUND_SQUASH:.5f}")
    print(f"wall_ratio    {WALL_RATIO:.5f}")
    print(f"1x1 render    {render_px(1, 1)} -> sprite {sprite_px(1, 1)}")
    print(f"2x2 render    {render_px(2, 2)} -> sprite {sprite_px(2, 2)}")
