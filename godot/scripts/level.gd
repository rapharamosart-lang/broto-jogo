extends Node3D
## Builds the playable world from the web game's level.json (same numbers, same terrain math).
## Phase 1: the surface route (floresta → clareira → lago → penhascos). Caves/underground rooms come later.

const WC := preload("res://shaders/watercolor.gdshader")
const WATER := preload("res://shaders/water.gdshader")

var L: Dictionary
var TR: Dictionary
var waters: Array = []      # [{x0,x1,top,bottom,id}]
var ropes: Array = []       # Rope nodes
var _mat_cache := {}
# Rope spots from web index.html (RP SPOTS): [x, groundY|null, bottom, side, top]
const ROPE_SPOTS := [[39.2,null,2.2,-1,3.2],[127.6,null,1.4,-1,3.6],[116.5,null,2.3,1,3.0],[291,null,2.3,1,3.0]]

func load_level(path := "res://data/level.json") -> void:
	L = JSON.parse_string(FileAccess.get_file_as_string(path))
	TR = L.terrain
	_build_lights()
	_build_terrain()
	_build_walls()
	_build_solids()
	_build_waters()
	_build_trunks()
	_build_props()
	_build_dynamics()
	_build_ropes()

# ---------------- terrain math (port of web hp/H/Hx) ----------------
static func sm(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0); return t * t * (3.0 - 2.0 * t)
func seg_at(x: float):
	for s in TR.segments:
		if x >= s.x0 and x < s.x1: return s
	return null
func _damp(x: float) -> float:
	var d := 9.0
	for z in TR.flatZones:
		d = min(d, z[0] - x if x < z[0] else (x - z[1] if x > z[1] else 0.0))
	return min(1.0, d / 1.5)
func hp(x: float) -> float:
	var s = seg_at(x)
	if s != null: return s.h
	var h := 0.0
	for n in TR.noise: h += n[0] * sin(x * n[1] + n[2])
	h *= _damp(x)
	for hl in TR.hills: h += hl.h * sm(hl.x[0], hl.x[1], x) * (1.0 - sm(hl.x[2], hl.x[3], x))
	return h
static func n2(x: float, z: float) -> float:
	return sin(x*.37+z*.9)*.5 + sin(x*1.13-z*.71+3.0)*.25 + sin(x*2.3+z*1.9)*.12
func is_pit(x: float) -> bool:
	var s = seg_at(x); return s != null and s.h < 0
func H(x: float, z: float) -> float:
	var a := absf(z); var w := sm(TR.offPath.bandStart, TR.offPath.bandEnd, a); var o := 0.0
	if z < 0: o = n2(x, z)*.45 + .25 + max(0.0, -z-6.0)*.22 + (0.0 if is_pit(x) else max(0.0, -z-3.0)*.04)
	else: o = n2(x+7.0, z)*.35 - .15 - max(0.0, z-4.0)*.25
	return hp(x) + w * o
var _brk: Array = []
func hx(x: float) -> float:
	for b in _brk:
		if x > b - .03 and x < b: return hp(b - .05)
	return hp(x)
func Hx(x: float, z: float) -> float:
	return hx(x) + (0.0 if is_pit(x) else H(x, z) - hp(x))
func ground_y(x: float) -> float: return hp(x)

func splash(at: Vector3, power: float) -> void:
	var fx := CPUParticles3D.new(); fx.one_shot = true; fx.emitting = true; fx.amount = int(14 + power * 20)
	fx.lifetime = .7; fx.explosiveness = .9; fx.direction = Vector3.UP; fx.spread = 35.0
	fx.initial_velocity_min = 1.5 + power; fx.initial_velocity_max = 3.0 + power * 2.0; fx.gravity = Vector3(0, -12, 0)
	var m := SphereMesh.new(); m.radius = .04; m.height = .08; fx.mesh = m
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color(.85, .97, 1.0); mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.material = mat
	fx.position = at; add_child(fx)
	get_tree().create_timer(1.5).timeout.connect(fx.queue_free)

func water_at(x: float, y: float):
	for w in waters:
		if x >= w.x0 and x <= w.x1 and y <= w.top and y >= w.bottom - 1.0: return w
	return null

# ---------------- materials ----------------
func wc(color: Color, opts := {}) -> ShaderMaterial:
	var key := str(color) + str(opts)
	if _mat_cache.has(key): return _mat_cache[key]
	var m := ShaderMaterial.new(); m.shader = WC
	m.set_shader_parameter("albedo", color)
	for k in opts: m.set_shader_parameter(k, opts[k])
	_mat_cache[key] = m; return m
func bright(hex: String, k := 1.0) -> Color:
	var c := Color(hex); return Color(min(1.0, c.r*k), min(1.0, c.g*k), min(1.0, c.b*k))

# ---------------- lights / environment ----------------
func _build_lights() -> void:
	var lt: Dictionary = L.lighting
	var sun := DirectionalLight3D.new(); sun.name = "Sun"
	sun.light_color = Color(lt.sun.color); sun.light_energy = lt.sun.intensity * 0.75
	sun.shadow_enabled = true; sun.shadow_blur = 0.0; sun.shadow_bias = 0.03; sun.shadow_normal_bias = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 45.0
	var off: Array = lt.sun.offset
	add_child(sun); sun.look_at_from_position(Vector3(off[0], off[1], off[2]), Vector3.ZERO)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new(); var sm_ := ProceduralSkyMaterial.new()
	sm_.sky_top_color = Color("#7ec4f0"); sm_.sky_horizon_color = Color("#d8f0e6")
	sm_.ground_horizon_color = Color("#cfe6dc"); sm_.ground_bottom_color = Color(lt.hemi.ground)
	sm_.sun_angle_max = 20.0; sky.sky_material = sm_; env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(lt.hemi.sky).lerp(Color(lt.hemi.ground), 0.25)
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC; env.tonemap_exposure = lt.exposure
	env.fog_enabled = true; env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color("#cfe6dc"); env.fog_depth_begin = 22.0; env.fog_depth_end = 110.0; env.fog_density = 0.6
	env.adjustment_enabled = true; env.adjustment_saturation = 1.18; env.adjustment_contrast = 1.06; env.adjustment_brightness = 0.97
	env.ssr_enabled = true; env.ssr_max_steps = 48   # water reflection (Forward+ only; ignored on Compatibility)
	env.glow_enabled = true; env.glow_intensity = 0.25; env.glow_bloom = 0.0
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)

# ---------------- terrain ----------------
func _xs() -> Array:
	var xs := []; var x: float = TR.xRange[0]
	while x <= TR.xRange[1] + .001: xs.append(snappedf(x, .001)); x += TR.step
	for s in TR.segments:
		for b in [s.x0, s.x1]:
			if not _brk.has(b): _brk.append(b)
	for b in _brk: xs.append(b - .02)
	xs.sort(); return xs
func _build_terrain() -> void:
	var xs := _xs(); var pal: Dictionary = TR.palette
	var cm := bright(pal.mud, 1.9); var cs := bright(pal.moss, 2.3).lerp(Color("#5f8f3a"), .45)
	var cr := bright(pal.rock, 1.8); var cw := bright(pal.wet, 2.2).lerp(Color("#6b5a3e"), .3)
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var zs: Array = TR.visualZ
	for j in zs.size() - 1:
		for i in xs.size() - 1:
			var x0: float = xs[i]; var x1: float = xs[i+1]; var z0: float = zs[j]; var z1: float = zs[j+1]
			var a := Vector3(x0, Hx(x0, z0), z0); var b := Vector3(x1, Hx(x1, z0), z0)
			var c := Vector3(x0, Hx(x0, z1), z1); var d := Vector3(x1, Hx(x1, z1), z1)
			for tri in [[a, c, b], [b, c, d]]:
				var n: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0]).normalized()
				if n.y < 0: n = -n
				var cz: float = (tri[0].z + tri[1].z + tri[2].z) / 3.0; var cx: float = tri[0].x
				var k := sm(pal.rockSlope[0], pal.rockSlope[1], n.y)
				var col: Color = (cw if absf(cz) < 1.4 else (cs if sin(cx*.7+cz*1.3) > .1 else cm))
				col = col.lerp(cm, 0.0 if absf(cz) < 1.4 else .3).lerp(cr, k)
				col = col * (1.0 + (randf() - .5) * pal.faceJitter)
				for v in [tri[0], tri[2], tri[1]]:
					st.set_color(col); st.set_normal(n); st.add_vertex(v)
	var mi := MeshInstance3D.new(); mi.name = "Terrain"; mi.mesh = st.commit()
	mi.material_override = wc(Color.WHITE, {"use_vertex_color": true, "wash": .28, "grain": .14})
	add_child(mi)
	# collision: narrow strip along the play line (physicsZ)
	var faces := PackedVector3Array(); var pz: Array = TR.physicsZ
	for j in pz.size() - 1:
		for i in xs.size() - 1:
			var x0: float = xs[i]; var x1: float = xs[i+1]; var z0: float = pz[j]; var z1: float = pz[j+1]
			var a := Vector3(x0, Hx(x0, z0), z0); var b := Vector3(x1, Hx(x1, z0), z0)
			var c := Vector3(x0, Hx(x0, z1), z1); var d := Vector3(x1, Hx(x1, z1), z1)
			faces.append_array([a, b, c, b, d, c])
	var sh := ConcavePolygonShape3D.new(); sh.set_faces(faces); sh.backface_collision = true
	var body := StaticBody3D.new(); body.name = "TerrainBody"; var cs_ := CollisionShape3D.new(); cs_.shape = sh
	body.add_child(cs_); add_child(body)

func _box(x0: float, x1: float, y0: float, y1: float, color: Color, depth := 2.4, z := 0.0, collide := true) -> Node3D:
	var size := Vector3(x1 - x0, y1 - y0, depth); var pos := Vector3((x0 + x1) / 2.0, (y0 + y1) / 2.0, z)
	var mi := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = size; mi.mesh = bm
	mi.material_override = wc(color, {"wash": .3, "grain": .12})
	if not collide: mi.position = pos; add_child(mi); return mi
	var body := StaticBody3D.new(); body.position = pos; body.add_child(mi)
	var c := CollisionShape3D.new(); var b := BoxShape3D.new(); b.size = size; c.shape = b; body.add_child(c)
	add_child(body); return body

func _build_walls() -> void:
	for w in TR.walls: _box(w[0], w[1], -12, 30, bright(TR.palette.rock, 1.6), 6.0)
func _build_solids() -> void:
	var W: Dictionary = L.world
	for s in W.solids:
		if s[3] > -20: _box(s[0], s[1], s[2], s[3], Color("#8a7a62"))
	for r in L.routes:
		for b in r.boxes: _box(b[0], b[1], b[2], b[3], Color("#9a7448"), 1.6)

# ---------------- water ----------------
func _build_waters() -> void:
	for w in L.world.waters:
		if w.top < -20: continue   # underground pools: phase 3 (caves)
		waters.append({"id": w.id, "x0": w.x0, "x1": w.x1, "top": w.top, "bottom": w.bottom})
		var mi := MeshInstance3D.new(); mi.name = "Water_" + w.id
		var pm := PlaneMesh.new(); pm.size = Vector2(w.x1 - w.x0, 16.0); pm.subdivide_width = int(w.x1 - w.x0) * 2; pm.subdivide_depth = 24
		mi.mesh = pm; mi.position = Vector3((w.x0 + w.x1) / 2.0, w.top, -3.0)
		var m := ShaderMaterial.new(); m.shader = WATER; mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(mi)

# ---------------- trunks & props ----------------
func _layer_tint(layer: String) -> Color:
	return Color(L.style.layerTint.get(layer, "#ffffff")) if L.has("style") and L.style.has("layerTint") else Color.WHITE
func _darken() -> float:
	return float(L.style.get("materialDarken", .68)) if L.has("style") else .68
func _build_trunks() -> void:
	var cyl := CylinderMesh.new(); cyl.top_radius = .7; cyl.bottom_radius = 1.0; cyl.height = 1.0; cyl.radial_segments = 7
	for t in L.trunks:
		var mi := MeshInstance3D.new(); mi.mesh = cyl
		mi.scale = Vector3(t.r, t.h, t.r); mi.position = Vector3(t.x, hp(t.x) + t.h / 2.0 - .3, t.z)
		mi.material_override = wc(Color(L.style.get("trunkColor", "#4a3626") if L.has("style") else "#4a3626").lerp(_layer_tint(t.get("layer", "mid")), .6 if t.get("layer","")=="bg" else 0.), {"wash": .35})
		if t.get("layer", "") == "bg": mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
var _scenes := {}
func _asset(name: String) -> PackedScene:
	if not _scenes.has(name):
		var p := "res://assets/props/%s.glb" % name
		_scenes[name] = load(p) if ResourceLoader.exists(p) else null
	return _scenes[name]
func _paint(n: Node, tint: Color) -> void:
	if n is MeshInstance3D and n.mesh:
		for s in n.mesh.get_surface_count():
			var src = n.mesh.surface_get_material(s)
			var col := Color.WHITE; var tex: Texture2D = null
			if src is BaseMaterial3D: col = src.albedo_color; tex = src.albedo_texture
			col = col * _darken()
			if tint != Color.WHITE: col = col.lerp(tint, .75)
			var key := "p%s%s%s" % [col, tex, tint]
			if not _mat_cache.has(key):
				var m := ShaderMaterial.new(); m.shader = WC; m.set_shader_parameter("albedo", col)
				if tex: m.set_shader_parameter("albedo_tex", tex); m.set_shader_parameter("use_tex", true)
				_mat_cache[key] = m
			n.set_surface_override_material(s, _mat_cache[key])
	for c in n.get_children(): _paint(c, tint)
func _build_props() -> void:
	var root := Node3D.new(); root.name = "Props"; add_child(root)
	for p in L.props:
		var ps := _asset(p.asset)
		if ps == null: continue
		var n: Node3D = ps.instantiate()
		var pos: Array = p.pos
		n.position = Vector3(pos[0], pos[1], pos[2]); n.rotation.y = p.get("rotY", 0.0)
		var s = p.get("scale", 1.0); n.scale = Vector3.ONE * (s if typeof(s) != TYPE_ARRAY else 1.0)
		if typeof(s) == TYPE_ARRAY: n.scale = Vector3(s[0], s[1], s[2])
		_paint(n, _layer_tint(p.get("layer", "mid")))
		root.add_child(n)

# ---------------- dynamics (crates & barrels) ----------------
func _build_dynamics() -> void:
	for d in L.dynamics:
		if d.type == "debris": continue
		var rb := RigidBody3D.new(); rb.mass = d.mass
		rb.axis_lock_linear_z = true; rb.axis_lock_angular_x = true; rb.axis_lock_angular_y = true
		var pm := PhysicsMaterial.new(); pm.friction = d.friction; rb.physics_material_override = pm
		var c := CollisionShape3D.new(); var mi := MeshInstance3D.new()
		var hh: float
		if d.type == "barrel":
			var sh := CylinderShape3D.new(); sh.radius = d.r; sh.height = d.h; c.shape = sh
			var m := CylinderMesh.new(); m.top_radius = d.r; m.bottom_radius = d.r; m.height = d.h; mi.mesh = m
			mi.material_override = wc(Color("#c08a52")); hh = d.h / 2.0
		else:
			var sz := Vector3(d.w, d.h, d.get("d", d.w)); var sh := BoxShape3D.new(); sh.size = sz; c.shape = sh
			var m := BoxMesh.new(); m.size = sz; mi.mesh = m; mi.material_override = wc(Color("#e0a468")); hh = d.h / 2.0
		rb.add_child(c); rb.add_child(mi); rb.add_to_group("pushable")
		rb.position = Vector3(d.x, hp(d.x) + hh + .05, 0); add_child(rb)

# ---------------- ropes ----------------
func _build_ropes() -> void:
	var Rope := preload("res://scripts/rope.gd")
	for s in ROPE_SPOTS:
		var gy: float = max(hp(s[0] - 1.5), hp(s[0] + 1.5)) if s[1] == null else s[1]
		var r: Node3D = Rope.new()
		r.anchor = Vector3(s[0], gy + s[2] + s[4], 0); r.length = s[4]
		add_child(r); ropes.append(r)
