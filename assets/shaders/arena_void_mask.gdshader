shader_type canvas_item;

uniform float arena_radius = 14336.0;
uniform float edge_softness = 384.0;
uniform float wobble_primary = 160.0;
uniform float wobble_secondary = 96.0;
uniform vec4 fog_color : source_color = vec4(0.02, 0.03, 0.05, 0.32);

varying vec2 local_pos;

float boundary_radius_for_angle(float angle) {
	return arena_radius
		+ sin(angle * 3.0 + 0.4) * wobble_primary
		+ cos(angle * 5.0 - 0.2) * wobble_secondary;
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float angle = atan(local_pos.y, local_pos.x);
	float dist = length(local_pos);
	float boundary_radius = boundary_radius_for_angle(angle);
	float mask = smoothstep(boundary_radius - edge_softness, boundary_radius + edge_softness, dist);
	COLOR = vec4(fog_color.rgb, fog_color.a * mask);
}
