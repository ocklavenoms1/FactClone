"""Import + normalization helpers shared by the render scripts.

Tripo hands back arbitrary scale, arbitrary yaw, arbitrary origin, and PBR
values chosen by nobody. Everything here exists to make two independently
generated meshes agree with each other.
"""

import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lock  # noqa: E402


# --------------------------------------------------------------- importing --

def import_glb(path):
    """Import a GLB and return its top-level objects, euler-safe.

    THE TRAP: the glTF importer leaves objects with rotation_mode
    'QUATERNION'. Writing rotation_euler on such an object is silently
    discarded, because the matrix is driven by rotation_quaternion instead.
    Every Tripo mesh arrives this way, and the failure is invisible - an 8-way
    turnaround renders eight identical images and reports no error. Force
    'XYZ' on import, before anything touches a rotation.
    """
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(path))
    new = [o for o in bpy.context.scene.objects if o not in before]

    for o in list(new):
        if o.type in {"CAMERA", "LIGHT"}:
            bpy.data.objects.remove(o, do_unlink=True)
            continue
        o.rotation_mode = "XYZ"

    return [o for o in bpy.context.scene.objects
            if o in set(new) and o.name in bpy.data.objects]


def mesh_objects(roots):
    out = []
    stack = list(roots)
    while stack:
        o = stack.pop()
        stack.extend(o.children)
        if o.type == "MESH":
            out.append(o)
    return out


def world_coords(objs):
    """All world-space vertex positions as one (N,3) array.

    numpy + foreach_get, because a 1.95M-triangle Tripo mesh iterated in pure
    Python takes minutes.
    """
    chunks = []
    deps = bpy.context.evaluated_depsgraph_get()
    for o in objs:
        ev = o.evaluated_get(deps)
        me = ev.to_mesh()
        n = len(me.vertices)
        if n:
            buf = np.empty(n * 3, dtype=np.float64)
            me.vertices.foreach_get("co", buf)
            co = buf.reshape(n, 3)
            m = np.array(ev.matrix_world.to_4x4())
            co = co @ m[:3, :3].T + m[:3, 3]
            chunks.append(co)
        ev.to_mesh_clear()
    if not chunks:
        raise RuntimeError("no mesh vertices found")
    return np.concatenate(chunks, axis=0)


def bounds(objs):
    co = world_coords(objs)
    return co.min(axis=0), co.max(axis=0)


# ------------------------------------------------------------ normalization --

def normalize(roots, footprint, fit="footprint", height_tiles=None,
              yaw_correction_deg=0.0, footprint_fill=None):
    """Apply the locked normalization, in order.

    1. euler rotation mode + apply existing transforms
    2. yaw so the model's front faces -Y (toward camera)
    3. uniform scale, by footprint extent or by height
    4. centre on the footprint centre in XY, sit bbox.min.z on the ground
    """
    fill = lock.FOOTPRINT_FILL if footprint_fill is None else footprint_fill

    parent = bpy.data.objects.new("ASSET_ROOT", None)
    bpy.context.scene.collection.objects.link(parent)
    parent.rotation_mode = "XYZ"
    for o in roots:
        if o.parent is None:
            o.parent = parent

    meshes = mesh_objects([parent])
    if not meshes:
        raise RuntimeError("import produced no meshes")

    # 2. yaw correction. Tripo's idea of "front" is arbitrary; the value comes
    #    from looking at an 8-way turnaround, not from guessing.
    parent.rotation_euler = (0.0, 0.0, math.radians(yaw_correction_deg))
    bpy.context.view_layer.update()

    lo, hi = bounds(meshes)
    size = hi - lo

    # 3. uniform scale only - non-uniform would make this asset's proportions
    #    disagree with every other asset.
    if fit == "height":
        if not height_tiles:
            raise ValueError("fit='height' requires height_tiles")
        s = float(height_tiles) / max(size[2], 1e-9)
    elif fit == "footprint":
        s = (footprint * fill) / max(size[0], size[1], 1e-9)
    else:
        raise ValueError(f"unknown fit mode {fit!r}")

    parent.scale = (s, s, s)
    bpy.context.view_layer.update()

    # 4. centre XY on the footprint centre, base on the ground
    lo, hi = bounds(meshes)
    cx, cy = (lo[0] + hi[0]) * 0.5, (lo[1] + hi[1]) * 0.5
    parent.location = (parent.location.x - cx,
                       parent.location.y - cy,
                       parent.location.z - lo[2])
    bpy.context.view_layer.update()

    lo, hi = bounds(meshes)
    return {
        "root": parent,
        "meshes": meshes,
        "scale": float(s),
        "size_tiles": [float(v) for v in (hi - lo)],
        "bbox_min": [float(v) for v in lo],
        "bbox_max": [float(v) for v in hi],
    }


# ------------------------------------------------------ material normalization --

def _srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _hex_to_linear(h):
    h = h.lstrip("#")
    return tuple(_srgb_to_linear(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4))


def normalize_materials(meshes, enabled=True, hsv=None):
    """Clamp Tripo's near-random PBR into a consistent band.

    The biggest consistency lever available. Tripo bakes lighting into base
    colour and returns roughness/metallic values that vary wildly between
    generations, so two assets lit by the same rig still read as different
    material sets. Returns a report so the effect can be measured with the
    pass on and off.
    """
    seen, report = set(), []
    for ob in meshes:
        for slot in ob.material_slots:
            m = slot.material
            if not m or m.name in seen:
                continue
            seen.add(m.name)
            if not m.use_nodes:
                continue
            bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
            if not bsdf:
                continue

            entry = {"material": m.name}
            r_in = bsdf.inputs.get("Roughness")
            m_in = bsdf.inputs.get("Metallic")
            e_in = bsdf.inputs.get("Emission Strength")

            # Tripo ships roughness AND metallic as a packed _rm texture, so
            # these sockets are LINKED and their default_value is ignored.
            # Clamping the scalar therefore does nothing at all - the clamp has
            # to be inserted into the node chain instead.
            if r_in is not None:
                if r_in.is_linked:
                    entry["roughness_src"] = "texture"
                    if enabled:
                        _remap_socket(m, r_in, lock.ROUGHNESS_RANGE[0], lock.ROUGHNESS_RANGE[1])
                        entry["roughness_after"] = list(lock.ROUGHNESS_RANGE)
                else:
                    entry["roughness_src"] = "scalar"
                    entry["roughness_before"] = round(r_in.default_value, 4)
                    if enabled:
                        r_in.default_value = min(max(r_in.default_value, lock.ROUGHNESS_RANGE[0]),
                                                 lock.ROUGHNESS_RANGE[1])
                    entry["roughness_after"] = round(r_in.default_value, 4)

            if m_in is not None:
                if m_in.is_linked:
                    entry["metallic_src"] = "texture"
                    if enabled:
                        _ceil_socket(m, m_in, lock.METALLIC_CEILING)
                        entry["metallic_after"] = f"<= {lock.METALLIC_CEILING}"
                else:
                    entry["metallic_src"] = "scalar"
                    entry["metallic_before"] = round(m_in.default_value, 4)
                    if enabled:
                        m_in.default_value = min(m_in.default_value, lock.METALLIC_CEILING)
                    entry["metallic_after"] = round(m_in.default_value, 4)

            if e_in is not None and not e_in.is_linked:
                if enabled:
                    e_in.default_value = min(e_in.default_value, lock.EMISSION_CEILING)

            if enabled and hsv:
                _inject_hsv(m, bsdf, hsv)
                entry["hsv"] = hsv

            report.append(entry)
    return report


def neutralize_mask(meshes, neutral=(0.055, 0.045, 0.040)):
    """Replace the magenta emission mask with a dark cavity colour, ALWAYS.

    The mask is a mask, not a colour: it must never reach the screen in any
    state. An idle firebox painted #FF00FF has to render as a cold dark
    opening, and only the 'smelting' hook lights it. Doing this in
    normalization rather than in the state hook is what guarantees the idle
    state is safe too.

    Returns {material_name: mask_socket}, where the socket carries 1.0 inside
    the mask and 0.0 outside. The state hook reuses that same socket to drive
    emission, so the lit region and the neutralized region cannot disagree.
    """
    sockets = {}
    seen = set()

    for ob in meshes:
        for slot in ob.material_slots:
            mat = slot.material
            if not mat or mat.name in seen or not mat.use_nodes:
                continue
            seen.add(mat.name)
            nt = mat.node_tree
            bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
            if not bsdf:
                continue
            base = bsdf.inputs.get("Base Color")
            if base is None or not base.is_linked:
                continue
            src = base.links[0].from_socket

            # Chroma score = min(R, B) - G. Brightness-invariant, because
            # Tripo returns the mask darkened (#FF00FF painted -> #9D009A
            # returned) and an absolute colour distance misses it entirely.
            sep = nt.nodes.new("ShaderNodeSeparateColor")
            sep.mode = "RGB"
            nt.links.new(src, sep.inputs["Color"])

            minrb = nt.nodes.new("ShaderNodeMath")
            minrb.operation = "MINIMUM"
            minrb.label = "min(R,B)"
            nt.links.new(sep.outputs["Red"], minrb.inputs[0])
            nt.links.new(sep.outputs["Blue"], minrb.inputs[1])

            score = nt.nodes.new("ShaderNodeMath")
            score.operation = "SUBTRACT"
            score.label = "chroma score = min(R,B) - G"
            nt.links.new(minrb.outputs["Value"], score.inputs[0])
            nt.links.new(sep.outputs["Green"], score.inputs[1])

            # TWO masks off the same score, because the requirements differ.
            #
            # NEUTRALIZE generously. Magenta that has bled onto the hearth
            # stones is an artifact; removing it everywhere is correct. This
            # uses the score normalized by the brightest channel, so a shaded
            # dark edge of the panel (which Tripo adds despite "flat") is
            # caught as readily as the core.
            #
            # EMIT tightly. Only near-pure panel should light up - a stone with
            # a magenta tint must not glow. This uses the RAW score, whose
            # magnitude still carries how much magenta is present.
            #
            # A dark panel rim therefore ends up neutralized but unlit, which
            # is what an arch mouth edge should look like anyway.
            mx1 = nt.nodes.new("ShaderNodeMath")
            mx1.operation = "MAXIMUM"
            nt.links.new(sep.outputs["Red"], mx1.inputs[0])
            nt.links.new(sep.outputs["Green"], mx1.inputs[1])
            mx2 = nt.nodes.new("ShaderNodeMath")
            mx2.operation = "MAXIMUM"
            mx2.label = "max(R,G,B)"
            nt.links.new(mx1.outputs["Value"], mx2.inputs[0])
            nt.links.new(sep.outputs["Blue"], mx2.inputs[1])
            guard = nt.nodes.new("ShaderNodeMath")
            guard.operation = "MAXIMUM"
            guard.label = "guard /0"
            guard.inputs[1].default_value = 1e-3
            nt.links.new(mx2.outputs["Value"], guard.inputs[0])

            norm = nt.nodes.new("ShaderNodeMath")
            norm.operation = "DIVIDE"
            norm.label = "score / max(R,G,B)"
            nt.links.new(score.outputs["Value"], norm.inputs[0])
            nt.links.new(guard.outputs["Value"], norm.inputs[1])

            m_neutral = nt.nodes.new("ShaderNodeMapRange")
            m_neutral.label = f"neutralize {lock.MASK_NEUTRAL_LO}..{lock.MASK_NEUTRAL_HI}"
            m_neutral.clamp = True
            m_neutral.inputs["From Min"].default_value = lock.MASK_NEUTRAL_LO
            m_neutral.inputs["From Max"].default_value = lock.MASK_NEUTRAL_HI
            m_neutral.inputs["To Min"].default_value = 0.0
            m_neutral.inputs["To Max"].default_value = 1.0
            nt.links.new(norm.outputs["Value"], m_neutral.inputs["Value"])

            m_emit = nt.nodes.new("ShaderNodeMapRange")
            m_emit.label = f"emit {lock.MASK_SCORE_LO}..{lock.MASK_SCORE_HI}"
            m_emit.clamp = True
            m_emit.inputs["From Min"].default_value = lock.MASK_SCORE_LO
            m_emit.inputs["From Max"].default_value = lock.MASK_SCORE_HI
            m_emit.inputs["To Min"].default_value = 0.0
            m_emit.inputs["To Max"].default_value = 1.0
            nt.links.new(score.outputs["Value"], m_emit.inputs["Value"])

            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.label = "neutralize mask"
            mix.inputs["B"].default_value = (*neutral, 1.0)
            nt.links.new(m_neutral.outputs["Result"], mix.inputs["Factor"])
            nt.links.new(src, mix.inputs["A"])
            nt.links.new(mix.outputs["Result"], base)

            sockets[mat.name] = m_emit.outputs["Result"]
    return sockets


def apply_albedo_gain(meshes, gain, clamp=True):
    """Correct a whole asset's albedo by the inverse of its measured gain.

    Tripo does not return the palette it was given, and the shift is NOT
    consistent between generations - measured per-channel gain was
    R 0.99 / G 1.27 / B 1.17 on one asset and R 0.42 / G 0.54 / B 0.53 on
    another. Prompting cannot fix that, so the material pass has to own value
    and exposure rather than only roughness and metallic.

    `gain` is what palette_drift.py measured (palette -> observed), so the
    correction is its reciprocal. The point is not to hit the locked hexes
    exactly - albedo is not a lit appearance - but to put every asset through
    the SAME transform to a common reference, which is what cross-asset
    consistency actually needs.
    """
    inv = [1.0 / max(g, 1e-3) for g in gain]
    seen, n = set(), 0
    for ob in meshes:
        for slot in ob.material_slots:
            mat = slot.material
            if not mat or mat.name in seen or not mat.use_nodes:
                continue
            seen.add(mat.name)
            nt = mat.node_tree
            bsdf = next((x for x in nt.nodes if x.type == "BSDF_PRINCIPLED"), None)
            if not bsdf:
                continue
            base = bsdf.inputs.get("Base Color")
            if base is None or not base.is_linked:
                continue
            src = base.links[0].from_socket

            mul = nt.nodes.new("ShaderNodeVectorMath")
            mul.operation = "MULTIPLY"
            mul.label = f"albedo gain^-1 {inv[0]:.2f},{inv[1]:.2f},{inv[2]:.2f}"
            mul.inputs[1].default_value = inv
            nt.links.new(src, mul.inputs[0])

            out = mul.outputs["Vector"]
            if clamp:
                # albedo above 1.0 is not physical and blows out on the render
                cl = nt.nodes.new("ShaderNodeVectorMath")
                cl.operation = "MINIMUM"
                cl.label = "clamp albedo <= 1"
                cl.inputs[1].default_value = (1.0, 1.0, 1.0)
                nt.links.new(out, cl.inputs[0])
                out = cl.outputs["Vector"]

            nt.links.new(out, base)
            n += 1
    return {"gain": list(gain), "inverse": inv, "materials": n}


def _remap_socket(mat, socket, lo, hi):
    """Insert a clamped Map Range so a linked 0..1 input lands in [lo, hi]."""
    nt = mat.node_tree
    src = socket.links[0].from_socket
    n = nt.nodes.new("ShaderNodeMapRange")
    n.label = f"clamp {socket.name} -> [{lo}, {hi}]"
    n.clamp = True
    n.inputs["From Min"].default_value = 0.0
    n.inputs["From Max"].default_value = 1.0
    n.inputs["To Min"].default_value = lo
    n.inputs["To Max"].default_value = hi
    nt.links.new(src, n.inputs["Value"])
    nt.links.new(n.outputs["Result"], socket)


def _ceil_socket(mat, socket, ceiling):
    """Insert a Math MINIMUM so a linked input can never exceed `ceiling`.

    A Map Range would compress the whole span; MINIMUM genuinely clamps, which
    is what a ceiling means.
    """
    nt = mat.node_tree
    src = socket.links[0].from_socket
    n = nt.nodes.new("ShaderNodeMath")
    n.operation = "MINIMUM"
    n.label = f"ceil {socket.name} <= {ceiling}"
    n.inputs[1].default_value = ceiling
    nt.links.new(src, n.inputs[0])
    nt.links.new(n.outputs["Value"], socket)


def _inject_hsv(mat, bsdf, hsv):
    """Insert a Hue/Saturation/Value node ahead of Base Color."""
    nt = mat.node_tree
    base = bsdf.inputs.get("Base Color")
    if base is None or not base.is_linked:
        return
    src = base.links[0].from_socket
    node = nt.nodes.new("ShaderNodeHueSaturation")
    node.inputs["Hue"].default_value = hsv.get("hue", 0.5)
    node.inputs["Saturation"].default_value = hsv.get("saturation", 1.0)
    node.inputs["Value"].default_value = hsv.get("value", 1.0)
    nt.links.new(src, node.inputs["Color"])
    nt.links.new(node.outputs["Color"], base)


# ------------------------------------------------------------------ framing --

def screen_uv(co):
    """World (N,3) -> screen (u, v) in world-tile units, pre-stretch.

    With azimuth 0 and pitch P: u = x, v = sin(P)*y + cos(P)*z.
    A ground tile of depth 1 therefore spans sin(P) = GROUND_SQUASH of screen
    height, and the downsample stretches that back to 1.
    """
    p = math.radians(lock.CAM_PITCH_DEG)
    u = co[:, 0]
    v = math.sin(p) * co[:, 1] + math.cos(p) * co[:, 2]
    return u, v


def frame(meshes, footprint):
    """Cell size in whole tiles, camera centre, and the Godot anchor.

    Cell is centred on the footprint X centre and its bottom edge sits on the
    footprint's FRONT edge, so tall silhouettes overflow upward only.
    """
    co = world_coords(meshes)
    u, v = screen_uv(co)
    u0, u1 = float(u.min()), float(u.max())
    v1 = float(v.max())
    v0 = float(v.min())

    pad_v = lock.FRAME_PAD_TILES * lock.GROUND_SQUASH

    # front edge of the footprint, at y = -footprint/2, z = 0
    front_v = lock.GROUND_SQUASH * (-footprint / 2.0)
    bottom_v = min(front_v, v0 - pad_v)   # only dips lower if geometry overhangs

    # Tolerance in TILES, sized well below one pixel (1e-4 tile = 0.003 px) but
    # far above float noise. Without it a footprint-fitted 1x1 asset lands on
    # exactly 1.000 tiles (FOOTPRINT_FILL 0.92 + 2*PAD 0.04) and FP noise tips
    # ceil() to 2 - silently doubling the sprite width for nothing.
    eps = 1e-4
    half_w = max(abs(u0), abs(u1)) + lock.FRAME_PAD_TILES
    cell_w = max(int(math.ceil(footprint - eps)), math.ceil(half_w * 2.0 - eps))
    cell_h = max(1, math.ceil((v1 + pad_v - bottom_v) / lock.GROUND_SQUASH - eps))

    top_v = bottom_v + cell_h * lock.GROUND_SQUASH
    cam_u = 0.0
    cam_v = (bottom_v + top_v) * 0.5

    sw, sh = lock.sprite_px(cell_w, cell_h)
    # anchor: sprite top-left -> footprint bottom-centre, in sprite pixels
    anchor_x = sw * 0.5
    anchor_y = (top_v - front_v) / (cell_h * lock.GROUND_SQUASH) * sh

    return {
        "cell_tiles": [cell_w, cell_h],
        "sprite_px": [sw, sh],
        "render_px": list(lock.render_px(cell_w, cell_h)),
        "anchor_px": [round(anchor_x, 2), round(anchor_y, 2)],
        "cam_uv": [cam_u, cam_v],
        "overhangs_front": bool(v0 - pad_v < front_v),
    }


def place_camera(cam, cell_w, cam_u, cam_v, distance=30.0):
    cam.data.sensor_fit = "HORIZONTAL"
    cam.data.ortho_scale = float(cell_w)
    rot = cam.rotation_euler.to_matrix()
    cam.location = rot.col[0] * cam_u + rot.col[1] * cam_v + rot.col[2] * distance
