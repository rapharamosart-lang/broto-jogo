// Water: fresnel tint + animated ripples; reflection comes from SSR (Forward+) and the sky/fallback probe.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx;
uniform vec4 shallow : source_color = vec4(0.35, 0.78, 0.80, 0.55);
uniform vec4 deep : source_color = vec4(0.10, 0.38, 0.52, 0.85);
uniform float wave = 0.06;
varying vec3 wp;
void vertex(){
	wp = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	if (NORMAL.y > 0.5) VERTEX.y += sin(wp.x*1.7+TIME*1.6)*wave + sin(wp.z*2.3+wp.x*.6+TIME*1.1)*wave*.6;
}
void fragment(){
	vec2 p = wp.xz;
	vec3 n = normalize(vec3(cos(p.x*1.7+TIME*1.6)*.12 + sin(p.y*5.0+TIME*2.1)*.05, 1.0, cos(p.y*2.3+p.x*.6+TIME*1.1)*.10));
	NORMAL = normalize((VIEW_MATRIX*vec4(n,0.0)).xyz);
	float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(shallow.rgb, deep.rgb, fr*.5);
	ALPHA = mix(shallow.a, deep.a, fr);
	METALLIC = 0.0; ROUGHNESS = 0.04; SPECULAR = 0.7;
}
