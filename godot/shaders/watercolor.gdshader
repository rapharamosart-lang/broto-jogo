// Watercolor surface: wash + granulation + paper grain over a flat-shaded base.
// No rim/edge darkening, no pigment rings (matches web v16). Lighting/shadows stay default (crisp).
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;
uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, hint_default_white;
uniform bool use_tex = false;
uniform float wash = 0.22;      // large soft pigment variation
uniform float grain = 0.10;     // granulation in the paper tooth
uniform float tint_shift = 0.08;// warm/cool hue drift
uniform float sat = 1.12;
uniform vec3 glow = vec3(0.0);
varying vec3 wp;
varying vec3 wn;
float h3(vec3 p){ p = fract(p*0.3183099+0.1); p *= 17.0; return fract(p.x*p.y*p.z*(p.x+p.y+p.z)); }
float n3(vec3 x){ vec3 i=floor(x), f=fract(x); f=f*f*(3.0-2.0*f);
	return mix(mix(mix(h3(i),h3(i+vec3(1,0,0)),f.x),mix(h3(i+vec3(0,1,0)),h3(i+vec3(1,1,0)),f.x),f.y),
	           mix(mix(h3(i+vec3(0,0,1)),h3(i+vec3(1,0,1)),f.x),mix(h3(i+vec3(0,1,1)),h3(i+vec3(1,1,1)),f.x),f.y),f.z); }
float fbm(vec3 p){ float a=.5,s=0.; for(int i=0;i<4;i++){ s+=a*n3(p); p*=2.03; a*=.5; } return s; }
void vertex(){ wp = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment(){
	vec3 c = albedo.rgb;
	if (use_vertex_color) c *= COLOR.rgb;
	if (use_tex) c *= texture(albedo_tex, UV).rgb;
	float w = fbm(wp*0.35);
	c *= 1.0 + (w-0.5)*2.0*wash;                                   // wash
	c = mix(c, c*vec3(1.06,1.0,0.9), smoothstep(.4,.8,fbm(wp*.12+7.)) * tint_shift*6.); // warm bloom
	c = mix(c, c*vec3(.9,1.0,1.08), smoothstep(.45,.85,fbm(wp*.09-3.)) * tint_shift*5.);// cool bloom
	float g = n3(wp*9.0)*.6 + n3(wp*23.0)*.4;
	c *= 1.0 - grain*(g-.5)*2.0;                                    // granulation
	float l = dot(c, vec3(.299,.587,.114)); c = mix(vec3(l), c, sat);
	ALBEDO = clamp(c, 0.0, 1.0);
	ROUGHNESS = 1.0;
	EMISSION = glow;
}
