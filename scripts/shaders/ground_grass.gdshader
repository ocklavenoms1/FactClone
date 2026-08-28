shader_type canvas_item;

// Ground Rendering Phase 1 — grass noise shader.
//
// Lives on Main/Background (the +-10000 px ColorRect). Default grass is
// never drawn per-tile: this ColorRect IS the ground plane, and every
// tile overlay, soil tint, depletion-faded ore fill and building sprite
// composites on top of what this shader produces.
//
// WORLD-COORDINATE SAMPLING IS THE CONTRACT. world_pos is computed in
// vertex() from MODEL_MATRIX and every noise/scatter sample reads it —
// never SCREEN_UV, never UV. That is what locks the pattern to the world
// so it does not swim under camera scroll (mechanically verified by the
// scroll-diff test in scripts/tools/ground_verify.py).
//
// Every parameter is a uniform so the designer tunes by eye in-editor
// with zero re-render cycles. Periods are in TILES (tile_size px each);
// amplitudes are fractional VALUE swings (+-amp), hue/saturation stable.

// Base grass colour. #2A3830 — the cool-lean candidate. The capture
// harness overrides this uniform per frame to photograph all three
// candidates (#2E3A26 / #2A3830 / #333D2A).
// THE SHIPPED GREEN: candidate A, #2E3A26 (designer pick 2026-08-28).
// Chosen over B on HUE, which no mechanical constraint expressed: B sits at
// 145.7 deg against verdigris at 152.7 deg -- a 7 deg separation that puts
// the whole map inside the accent's hue family. A is 96.0 deg (56.7 deg of
// separation). Chosen over C on the tightest adjacency: contrast 1.44 vs
// 1.37 against wrought iron, and darker overall (rel-luminance 0.0375 vs
// 0.0421), which helps the chest -- currently the weakest read.
// C is the fallback if A ever reads wrong live. B is NOT a fallback.
uniform vec4 base_color : source_color = vec4(0.180392, 0.227451, 0.149020, 1.0);

// Must match GridWorld.TILE_SIZE (verified: 32).
uniform float tile_size = 32.0;

// Three octaves of smooth value noise. period = feature size in tiles,
// amplitude = value swing (0.06 => +-6%).
uniform float low_period_tiles = 10.0;
uniform float low_amplitude = 0.06;
uniform float mid_period_tiles = 2.0;
uniform float mid_amplitude = 0.03;
uniform float fine_period_tiles = 0.5;
uniform float fine_amplitude = 0.02;

// Dark-fleck scatter. Cell-based: one candidate point per
// scatter_cell_tiles x scatter_cell_tiles tile cell, drawn only when the
// cell's hash passes scatter_density. Darkness is MULTIPLICATIVE and LOW
// contrast by default; radius is in world pixels.
//
// scatter_darkness is a FRACTION of the pixel value, not an absolute
// subtraction: 0.22 reproduces the read of the old subtractive 0.05 against
// these base values (0.05 taken off a value near 0.22 is a ~23% darkening).
// Designer ceiling: do not push past ~0.28 chasing the old look -- flecks are
// texture, not features.
uniform float scatter_cell_tiles = 6.0;
uniform float scatter_density : hint_range(0.0, 1.0) = 1.0;
uniform float scatter_darkness = 0.22;
uniform float scatter_radius = 2.5;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// Lattice hash. fract-based (Dave Hoskins style) rather than the classic
// fract(sin(dot())) because world coordinates reach +-10000 px here and
// float32 sin() loses meaningful bits at arguments that large — the sin
// hash visibly bands toward the world edge. Same cost, static output.
float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// Smooth value noise on a unit lattice: hash the four corners,
// smoothstep-interpolate. Returns 0..1.
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// One octave's signed contribution: +-amplitude.
float octave(vec2 wp, float period_tiles, float amplitude) {
	float period_px = max(tile_size * period_tiles, 0.0001);
	return (value_noise(wp / period_px) * 2.0 - 1.0) * amplitude;
}

// Scatter mask, 0..1. The candidate point is jittered inside its cell
// with a radius-wide margin so a fleck never crosses the cell boundary —
// keeps the lookup to a single cell (no neighbour scan), with no fleck
// ever clipped by an invisible cell edge.
float scatter_mask(vec2 wp) {
	float cell_px = max(tile_size * scatter_cell_tiles, 0.0001);
	vec2 cell = floor(wp / cell_px);
	if (hash21(cell + vec2(17.0, 43.0)) >= scatter_density) {
		return 0.0;
	}
	float margin = min(scatter_radius, cell_px * 0.5);
	vec2 jitter = hash22(cell + vec2(7.0, 91.0));
	vec2 point = cell * cell_px + vec2(margin) + jitter * (cell_px - 2.0 * margin);
	float dist = length(wp - point);
	return 1.0 - smoothstep(scatter_radius * 0.5, scatter_radius, dist);
}

void fragment() {
	float n = octave(world_pos, low_period_tiles, low_amplitude)
			+ octave(world_pos, mid_period_tiles, mid_amplitude)
			+ octave(world_pos, fine_period_tiles, fine_amplitude);
	// Value-only modulation THROUGHOUT: both the octaves and the scatter are
	// uniform RGB scales, so HSV saturation is invariant BY CONSTRUCTION -- no
	// pixel can out-saturate base_color, whatever the green, the amplitudes or
	// the scatter density (8-bit rounding aside; ground_verify.py pins that).
	//
	// The scatter was SUBTRACTIVE until 2026-08-28, and subtracting a constant
	// from all three channels raises (mx-mn)/mx -- the flecks were the most
	// saturated pixels in the frame, 0.04% of them above verdigris. Designer
	// ruling: a tolerance is an accidental pass; multiplicative makes the
	// saturation constraint hold by construction, with nothing to re-check
	// when the green changes or the density moves.
	vec3 col = base_color.rgb * (1.0 + n);
	col *= (1.0 - scatter_darkness * scatter_mask(world_pos));
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
