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
var occluders: Array = []    # foreground meshes that fade when they hide the player
var doors: Array = []
var levers: Array = []
var benches: Array = []
var player: CharacterBody3D
var orbs: Array = []
var env: Environment
var sun: DirectionalLight3D
var zone_k := 0.0
var cur_room := ""
const CAVE_M := Color("#5a5052")
const CAVE_D := Color("#3a3440")
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
	_build_rooms()
	_build_cave_fx()
	_build_doors()

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
	sun = DirectionalLight3D.new(); sun.name = "Sun"
	sun.light_color = Color(lt.sun.color); sun.light_energy = lt.sun.intensity * 0.75
	sun.shadow_enabled = true; sun.shadow_blur = 0.0; sun.shadow_bias = 0.03; sun.shadow_normal_bias = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 45.0
	var off: Array = lt.sun.offset
	add_child(sun); sun.look_at_from_position(Vector3(off[0], off[1], off[2]), Vector3.ZERO)
	env = Environment.new()
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
		else: _box(s[0], s[1], s[2], s[3], CAVE_M)
	for r in L.routes:
		for b in r.boxes: _box(b[0], b[1], b[2], b[3], Color("#9a7448"), 1.6)

# ---------------- water ----------------
func _build_waters() -> void:
	for w in L.world.waters:
		waters.append({"id": w.id, "x0": w.x0, "x1": w.x1, "top": w.top, "bottom": w.bottom})
		var mi := MeshInstance3D.new(); mi.name = "Water_" + w.id
		var pm := PlaneMesh.new(); pm.size = Vector2(w.x1 - w.x0, 16.0 if w.top > -20 else 3.2); pm.subdivide_width = int(w.x1 - w.x0) * 2; pm.subdivide_depth = 24
		mi.mesh = pm; mi.position = Vector3((w.x0 + w.x1) / 2.0, w.top, -3.0 if w.top > -20 else -.4)
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
		if t.z > 1.5: occluders.append({"node": mi, "x": t.x, "r": t.r * 1.2 + .8, "f": 0.0})
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
			var mn: String = src.resource_name.to_lower() if src else ""
			if mn.begins_with("leafs"): col = Color("#4f7f34")      # was cyan (Kenney palette) → sap green
			elif mn == "grass": col = Color("#7da447")
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
		if pos[2] > 1.5 and not p.asset.begins_with("grass"): occluders.append({"node": n, "x": pos[0], "r": 2.2 * n.scale.x, "f": 0.0})
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

# ================================================================ phase 2: caves, doors, fx, enemies, drops
func room_at(x: float, y: float):
	for r in L.world.rooms:
		if r.has("rect") and x >= r.rect[0] - 1 and x <= r.rect[2] + 1 and y >= r.rect[1] - 1 and y <= r.rect[3] + 1: return r
	return null
func _build_rooms() -> void:
	var root := Node3D.new(); root.name = "Rooms"; add_child(root)
	for r in L.world.rooms:
		if not r.has("rect") or not r.has("floors"): continue
		var rc: Array = r.rect; var x0: float = rc[0]; var x1: float = rc[2]
		var cm := Color(r.get("col", "")) if r.has("col") else CAVE_M
		var cd := Color(r.get("colD", "")) if r.has("colD") else CAVE_D
		for f in r.floors: _box(f[0], f[1], f[2] - 3.0, f[2], cm, 3.0)
		var top: float = rc[3]
		if r.has("ceil"):
			for c in r.ceil: _box(c[0], c[1], c[2], top + 3.0, cm.darkened(.15), 3.0)
		else: _box(x0, x1, top, top + 3.0, cm.darkened(.15), 3.0)
		_box(x0 - 1.5, x0, rc[1] - 3.0, top + 3.0, cm, 3.0)
		_box(x1, x1 + 1.5, rc[1] - 3.0, top + 3.0, cm, 3.0)
		for b in r.get("boxes", []): _box(b[0], b[1], b[2], b[3], cm.lightened(.08), 2.0)
		# wavy back wall (z = -2), soft watercolor wash
		var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var nx := int((x1 - x0) / .8) + 1; var ny := int((top - rc[1] + 4) / .8) + 1
		var pts := []
		for j in ny + 1:
			var row := []
			for i in nx + 1:
				var x := x0 - 1.5 + (x1 - x0 + 3.0) * i / nx; var y: float = rc[1] - 3.0 + (top - rc[1] + 6.0) * j / ny
				row.append(Vector3(x, y, -2.0 - .5 * (sin(x * .9 + y * .4) * .5 + sin(x * .31 - y * 1.1) * .5 + .5)))
			pts.append(row)
		for j in ny:
			for i in nx:
				var a: Vector3 = pts[j][i]; var b: Vector3 = pts[j][i + 1]; var c: Vector3 = pts[j + 1][i]; var d: Vector3 = pts[j + 1][i + 1]
				for v in [a, c, b, b, c, d]: st.set_color(cd.lerp(cm, clamp((v.y - rc[1]) / max(1.0, top - rc[1]), 0.0, 1.0) * .5)); st.add_vertex(v)
		st.generate_normals(); var mi := MeshInstance3D.new(); mi.mesh = st.commit(); mi.name = "Back_" + r.id
		mi.material_override = wc(Color.WHITE, {"use_vertex_color": true, "wash": .4, "grain": .2})
		root.add_child(mi)

func _glow_mat(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = c; m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = e
	m.roughness = .4; return m

func _build_cave_fx() -> void:
	var W: Dictionary = L.world; var rng := RandomNumberGenerator.new(); rng.seed = 7
	# light anchors (web pools 2–3 lights; Forward+ handles all of them, no shadows)
	for lt in W.lights:
		var o := OmniLight3D.new(); o.position = Vector3(lt[0], lt[1], 1.2); o.light_color = Color(lt[2])
		o.omni_range = float(lt[3]) * 1.3; o.light_energy = 1.6; o.omni_attenuation = 1.2; o.shadow_enabled = false; add_child(o)
	# crystals (Gruta de Cristal) — glowing octahedra
	var oct := PrismMesh.new(); oct.size = Vector3(.3, .6, .3)
	var cmat := _glow_mat(Color("#7fe0ff"), 1.4)
	for i in 40:
		var mi := MeshInstance3D.new(); mi.mesh = oct; mi.material_override = cmat
		var x := rng.randf_range(177, 213); var top := rng.randf() < .35
		mi.position = Vector3(x, (-74.3 if top else -80.0 + .25), rng.randf_range(-1.6, -.4))
		mi.rotation = Vector3(PI if top else 0.0, rng.randf() * TAU, rng.randf_range(-.4, .4)); mi.scale = Vector3.ONE * rng.randf_range(.6, 1.8)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(mi)
	# glowing fungi (Caverna dos Fungos)
	var cap := SphereMesh.new(); cap.radius = .18; cap.height = .2; var fmat := _glow_mat(Color("#9fe8b0"), 1.1)
	var stem := CylinderMesh.new(); stem.top_radius = .04; stem.bottom_radius = .06; stem.height = .3; var smat := wc(Color("#d8e0c8"))
	for i in 60:
		var x := rng.randf_range(235, 289); var r = room_at(x, -59)
		var fy := -60.0
		if r != null:
			for f in r.floors:
				if x >= f[0] and x <= f[1]: fy = f[2]
		var g := Node3D.new(); g.position = Vector3(x, fy, rng.randf_range(-1.7, -.6)); g.scale = Vector3.ONE * rng.randf_range(.7, 1.9)
		var c := MeshInstance3D.new(); c.mesh = cap; c.material_override = fmat; c.position.y = .32; g.add_child(c)
		var s := MeshInstance3D.new(); s.mesh = stem; s.material_override = smat; s.position.y = .15; g.add_child(s); add_child(g)
	# light shafts (soft additive columns)
	var grad := GradientTexture2D.new(); var gr := Gradient.new(); gr.set_color(0, Color(1, 1, 1, .0)); gr.set_color(1, Color(1, 1, 1, 1))
	gr.add_point(.5, Color(1, 1, 1, .7)); grad.gradient = gr; grad.fill_from = Vector2(0, 1); grad.fill_to = Vector2(0, 0)
	for sft in W.shafts:
		var q := MeshInstance3D.new(); var qm := QuadMesh.new(); var h: float = abs(float(sft[1]) - float(sft[2])); qm.size = Vector2(1.8, h); q.mesh = qm
		var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.albedo_texture = grad; m.albedo_color = Color(sft[3]) * Color(1, 1, 1, .22); m.cull_mode = BaseMaterial3D.CULL_DISABLED
		q.material_override = m; q.position = Vector3(sft[0], (float(sft[1]) + float(sft[2])) / 2.0, -.8); q.rotation.z = .12
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(q)
	# fireflies: forest band on the surface + a swarm in each cave room
	var F: Dictionary = L.forest
	_fireflies(Vector3((F.x0 + F.x1) / 2.0, hp((F.x0 + F.x1) / 2.0) + 2.0, -1.0), Vector3((F.x1 - F.x0) / 2.0, 1.8, 3.0), int(F.fireflies) / 2, Color(F.fireflyColor))
	for r in W.rooms:
		if not r.has("rect") or not r.has("floors"): continue
		var rc: Array = r.rect
		_fireflies(Vector3((rc[0] + rc[2]) / 2.0, (rc[1] + rc[3]) / 2.0, -.8), Vector3((rc[2] - rc[0]) / 2.0, (rc[3] - rc[1]) / 2.0 - .5, .9), 26, Color(F.fireflyColor).lerp(Color("#9fe8ff"), .4))
func _fireflies(c: Vector3, ext: Vector3, n: int, col: Color) -> void:
	var p := CPUParticles3D.new(); p.amount = max(4, n); p.lifetime = 6.0; p.preprocess = 6.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX; p.emission_box_extents = ext; p.gravity = Vector3(0, .05, 0)
	p.direction = Vector3(1, .3, 0); p.spread = 180.0; p.initial_velocity_min = .05; p.initial_velocity_max = .35
	var sm := SphereMesh.new(); sm.radius = .035; sm.height = .07; sm.radial_segments = 6; sm.rings = 3; p.mesh = sm
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.albedo_color = col
	m.emission_enabled = true; m.emission = col; m.emission_energy_multiplier = 3.0; sm.material = m
	var curve := Curve.new(); curve.add_point(Vector2(0, 0)); curve.add_point(Vector2(.2, 1)); curve.add_point(Vector2(.8, 1)); curve.add_point(Vector2(1, 0)); p.scale_amount_curve = curve
	p.position = c; p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(p)

func door_pos(d: Dictionary) -> Vector3:
	var x: float = d.x
	return Vector3(x, hp(x) if d.get("y") == null else float(d.y), 0)
func _build_doors() -> void:
	var dm := wc(Color("#2a2228"), {"wash": .2})
	for d in L.world.doors:
		var p := door_pos(d); doors.append(d)
		if d.get("auto", false): continue
		var arch := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(1.2, 2.0, .2); arch.mesh = bm; arch.material_override = dm
		arch.position = p + Vector3(0, 1.0, -1.1); add_child(arch)
		var frame := MeshInstance3D.new(); var fm := BoxMesh.new(); fm.size = Vector3(1.5, 2.3, .15); frame.mesh = fm; frame.material_override = wc(Color("#8a7458"))
		frame.position = p + Vector3(0, 1.1, -1.25); add_child(frame)
		if d.has("label"):
			var lb := Label3D.new(); lb.text = d.label; lb.position = p + Vector3(0, 2.6, -1.0); lb.font_size = 48; lb.pixel_size = .006
			lb.modulate = Color("#fff4dc"); lb.outline_size = 0; add_child(lb)
	for lv in L.world.levers:
		var p := Vector3(lv.x, lv.y, 0); levers.append(lv)
		var m := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = .05; cm.bottom_radius = .05; cm.height = .9; m.mesh = cm
		m.material_override = wc(Color("#c8a060")); m.position = p + Vector3(0, .45, -.6); m.rotation.z = -.5; m.name = "Lever_" + lv.id; add_child(m)
	for s in L.world.saves:
		var x: float = s[0]; var y: float = hp(x) if s[1] == null else float(s[1])
		benches.append(Vector3(x, y, 0))
		var b := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(1.4, .35, .6); b.mesh = bm; b.material_override = wc(Color("#a27a4e"))
		b.position = Vector3(x, y + .45, -1.0); add_child(b)
		var g := MeshInstance3D.new(); var gs := SphereMesh.new(); gs.radius = .09; gs.height = .18; g.mesh = gs; g.material_override = _glow_mat(Color("#ffe8a0"), 2.0)
		g.position = Vector3(x, y + 1.0, -1.0); add_child(g)

func spawn_enemies() -> void:
	var E := preload("res://scripts/enemy.gd")
	var root := Node3D.new(); root.name = "Enemies"; add_child(root)
	var list: Array = L.world.enemies + L.world.get("enemies2", [])
	for ins in L.get("insects", []): list.append({"t": "insect", "x": ins.x, "y": ins.y})
	for d in list:
		if d.has("boss") and Prog.SV.doors.has("boss_" + d.t): continue
		var e: CharacterBody3D = E.new(); root.add_child(e); e.setup(d, self, player)

# ---------------- drops (soul shards + hearts), xp popups, sparks
func drop(e: Node) -> void:
	var D: Dictionary = L.world.drops
	var key: String = "boss" if e.boss else (e.t if D.has(e.t) else "default")
	var dd: Dictionary = D[key]; var n := randi_range(int(dd.n[0]), int(dd.n[1]))
	var c: Vector3 = e.center()
	for i in n: _orb(c, "soul")
	if randf() < float(dd.get("heart", D.default.heart)): _orb(c, "heart")
func _orb(at: Vector3, kind: String) -> void:
	var m := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = .11 if kind == "soul" else .18; sm.height = sm.radius * 2; m.mesh = sm
	m.material_override = _glow_mat(Color("#e8f4ff") if kind == "soul" else Color("#ff8a8a"), 1.6); m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m); m.global_position = at
	orbs.append({"n": m, "k": kind, "v": Vector3(randf_range(-2.5, 2.5), randf_range(3, 6), 0), "t": 0.0})
func _orbs(dt: float) -> void:
	for o in orbs.duplicate():
		o.t += dt; var n: MeshInstance3D = o.n
		var tp: Vector3 = player.global_position + Vector3(0, .7, 0); var d: Vector3 = tp - n.global_position
		if o.t > .45 and d.length() < 3.5: o.v = o.v.lerp(d.normalized() * 9.0, min(1.0, dt * 6.0))
		else: o.v.y -= 14.0 * dt; o.v.x *= 1.0 - dt * 1.5
		var np: Vector3 = n.global_position + o.v * dt
		var q := PhysicsRayQueryParameters3D.create(n.global_position, np); q.collision_mask = 1
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		var magnet: bool = o.t > .45 and d.length() < 3.5
		if not hit.is_empty() and not magnet:
			o.v = o.v.bounce(hit.normal) * .4; np = hit.position + hit.normal * .12
		n.global_position = np
		if o.t > .3 and d.length() < .6:
			if o.k == "soul": player.combat.soul = min(99, player.combat.soul + 4)
			else: player.combat.hp = min(player.combat.max_hp(), player.combat.hp + 1)
			player.combat.hurt.emit(player.combat.hp); n.queue_free(); orbs.erase(o)
		elif o.t > 14.0: n.queue_free(); orbs.erase(o)
func xp_pop(at: Vector3, n: int) -> void:
	var lb := Label3D.new(); lb.text = "+%d xp" % n; lb.font_size = 56; lb.pixel_size = .006; lb.modulate = Color("#fff0b8"); lb.outline_size = 0
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED; lb.no_depth_test = true; add_child(lb); lb.global_position = at + Vector3(0, .8, .5)
	var tw := create_tween(); tw.tween_property(lb, "position:y", lb.position.y + 1.4, 1.2); tw.parallel().tween_property(lb, "modulate:a", 0.0, 1.2); tw.tween_callback(lb.queue_free)
func spark(at: Vector3) -> void:
	var fx := CPUParticles3D.new(); fx.one_shot = true; fx.emitting = true; fx.amount = 10; fx.lifetime = .3; fx.explosiveness = 1.0
	fx.spread = 180.0; fx.initial_velocity_min = 3.0; fx.initial_velocity_max = 6.0; fx.gravity = Vector3.ZERO
	var m := SphereMesh.new(); m.radius = .03; m.height = .06; fx.mesh = m; m.material = _glow_mat(Color("#fff2c0"), 3.0)
	fx.position = at; add_child(fx); get_tree().create_timer(.6).timeout.connect(fx.queue_free)

# ---------------- per-frame: zone lighting (caves get dark + coloured fog, lights carry the scene), orbs
var _sky_bg: Sky
func _process(dt: float) -> void:
	if player == null or env == null: return
	_orbs(dt)
	var p := player.global_position; var zone = null
	for z in L.world.zones:
		if z.has("room") and p.x >= z.rect[0] and p.x <= z.rect[2] and p.y >= z.rect[1] and p.y <= z.rect[3]: zone = z
	var r = room_at(p.x, p.y); cur_room = r.id if r != null else ""
	var want := 1.0 if zone != null or p.y < -25 else 0.0
	zone_k = move_toward(zone_k, want, dt * 1.5)
	var fog := Color(zone.fog) if zone != null else Color("#22303a")
	if zone_k > .5 and env.background_mode != Environment.BG_COLOR: _sky_bg = env.sky; env.background_mode = Environment.BG_COLOR
	elif zone_k <= .5 and env.background_mode != Environment.BG_SKY: env.background_mode = Environment.BG_SKY
	env.background_color = fog.darkened(.2)
	var dark: float = float(zone.dark) if zone != null else .4
	env.ambient_light_color = Color(L.lighting.hemi.sky).lerp(Color(L.lighting.hemi.ground), .25).lerp(fog.lerp(Color.WHITE, .6), zone_k)
	env.ambient_light_energy = lerp(.9, 1.0 + dark * .4, zone_k)
	env.fog_light_color = Color("#cfe6dc").lerp(fog.lerp(Color.WHITE, .15), zone_k)
	env.fog_depth_begin = lerp(22.0, 6.0, zone_k); env.fog_depth_end = lerp(110.0, 60.0, zone_k)
	sun.light_energy = L.lighting.sun.intensity * .75 * (1.0 - zone_k)
	env.tonemap_exposure = L.lighting.exposure * lerp(1.0, float(zone.exp) if zone != null else 1.0, zone_k)
