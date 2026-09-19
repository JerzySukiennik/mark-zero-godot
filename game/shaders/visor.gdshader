shader_type canvas_item;
// The HUD seen from inside a helmet.
//
// Jurek: the interface should be "trochę wygięte, jakby było od środka hełmu, i ruszać się
// w stosunku do ekranu trochę". Both halves matter and they do different jobs.
//
// THE CURVE bends the HUD INWARD — concave, the way the inside of a visor wraps around your
// face — and never the 3D behind it. The first version bowed it outward like a CRT bulging
// at the viewer, which is the opposite shape: a screen you are looking AT rather than a
// surface wrapped AROUND you. Jurek: "zbyt wygięte i w złą stronę, powinno być do środka."
//
// It is also much weaker now. At 0.085 the corners read as a broken screen; a visor a few
// centimetres from the eye barely bends at all across the middle, and the shape is meant to
// be felt rather than seen.
//
// THE SCANLINE and the vignette are what make it a SCREEN rather than a decal. Without
// them the curve alone just looks like the text is bent.

uniform float curve : hint_range(0.0, 0.2) = 0.028;
uniform float vignette : hint_range(0.0, 1.0) = 0.38;
uniform float scan_strength : hint_range(0.0, 0.5) = 0.035;
uniform float scan_density = 620.0;
uniform float aberration : hint_range(0.0, 4.0) = 0.6;
uniform float flicker : hint_range(0.0, 1.0) = 0.018;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	// Barrel: push each point out by the square of its distance from centre.
	float r2 = dot(uv, uv);
	// MINUS, not plus. Sampling nearer the centre as you move out spreads the edges of the
	// image outward, which is the concave read — the panel wrapping away from you. Plus did
	// the reverse and bulged it towards the viewer.
	vec2 warped = uv * (1.0 - curve * r2);
	vec2 suv = warped * 0.5 + 0.5;

	if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) {
		COLOR = vec4(0.0);
	} else {
		// Chromatic separation grows towards the edges, the way a real curved lens does.
		// A constant offset reads as a printing error instead.
		vec2 dir = warped * aberration * 0.0012 * r2;
		float cr = texture(TEXTURE, suv + dir).r;
		vec4 cg = texture(TEXTURE, suv);
		float cb = texture(TEXTURE, suv - dir).b;
		COLOR = vec4(cr, cg.g, cb, cg.a);

		float v = 1.0 - vignette * r2 * 0.5;
		COLOR.rgb *= v;

		float scan = 1.0 - scan_strength * (0.5 + 0.5 * sin(suv.y * scan_density));
		COLOR.rgb *= scan;

		COLOR.rgb *= 1.0 - flicker * fract(sin(TIME * 37.0) * 43758.5453);
	}
}
