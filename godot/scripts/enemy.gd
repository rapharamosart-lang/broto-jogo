extends CharacterBody3D
## Generic enemy for every web type, grouped into archetypes. Each attack has a readable telegraph
## (shake + warm flash + wind-up pose) before it commits. Data: level.json world.enemies / enemies2, world.xp, world.drops.
const KIND := {
	"beetle": "walker", "kingbeetle": "charger", "cabra": "charger", "caranguejo": "walker", "bufa": "walker", "gelin": "walker",
	"cobra": "walker", "serpente": "charger", "sapo": "hopper", "saporei": "hopper",
	"insect": "flyer", "falcao": "flyer", "corvo": "flyer", "corvorei": "flyer", "morcego": "flyer", "wisp": "flyer",
	"moth": "flyer", "gaviao": "flyer", "geada": "flyer", "prisma": "shooter", "plant": "shooter", "aranha": "shooter",
	"shadow": "chaser", "eel": "swimmer"}
const HPT := {"beetle": 2, "plant": 2, "shadow": 2, "eel": 2, "kingbeetle": 10, "moth": 30, "insect": 1}
const COL := {"beetle": "#3d6f7a", "plant": "#a04f86", "shadow": "#3b3266", "eel": "#4f9a7a", "kingbeetle": "#8a5a24", "moth": "#9a7fc8",
	"insect": "#c8b04a", "cabra": "#d8cdb8", "falcao": "#8a6a48", "gaviao": "#6a4a30", "sapo": "#5f8a3a", "saporei": "#4a7a2a", "bufa": "#a0a07a",
	"corvo": "#2a2a35", "corvorei": "#1a1a28", "caranguejo": "#c0603a", "morcego": "#4a3a50", "wisp": "#b8e8ff", "gelin": "#a8d8e8",
	"prisma": "#90d8ff", "geada": "#c8f0ff", "cobra": "#6a8a3a", "aranha": "#3a2a2a", "serpente": "#3a6a4a"}
var t := "beetle"
var kind := "walker"
var boss := false
var alive := true
var hp_v := 2.0
var hp_max := 2.0
var radius := .5
var face := -1
var home := Vector3.ZERO
var st := "idle"         # idle | tele | atk | cool | stun
var st_t := 0.0
var flash := 0.0
var level: Node
var player: CharacterBody3D
var water = null
var body: Node3D
var mat: ShaderMaterial
var base_col := Color.WHITE
var die_t := 0.0
var shots: Array = []
var aggro := 6.5
var contact := .5
var tele_shake := 0.0

func setup(d: Dictionary, lvl: Node, pl: CharacterBody3D) -> void:
	level = lvl; player = pl; t = d.t; kind = KIND.get(t, "walker"); boss = d.has("boss")
	var xpv: int = int(level.L.world.xp.get(t, 10))
	hp_max = float(HPT.get(t, 20 if boss else (3 if xpv >= 14 else 2))); hp_v = hp_max
	radius = (1.1 if boss else .45) * (1.3 if t in ["kingbeetle", "moth", "serpente"] else 1.0)
	aggro = float(level.L.combat.get("aggro", 6.5)) * (1.5 if boss else 1.0)
	contact = float(level.L.combat.get("contact", .5))
	collision_layer = 4; collision_mask = 1
	var cs := CollisionShape3D.new(); var sh := SphereShape3D.new(); sh.radius = radius * .9; cs.shape = sh; cs.position.y = radius; add_child(cs)
	base_col = Color(COL.get(t, "#7a6a5a"))
	mat = level.wc(base_col, {"wash": .25, "grain": .12}).duplicate()
	body = _make_body(); add_child(body)
	home = Vector3(float(d.x), float(d.y), 0)
	if d.has("w"):
		for w in level.waters:
			if w.id == d.w: water = w
	position = home + (Vector3(0, .4, 0) if kind in ["walker", "charger", "hopper", "chaser"] else Vector3.ZERO)
	add_to_group("enemy")

func _make_body() -> Node3D:
	var n := Node3D.new(); var r := radius
	var torso := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = r; sm.height = r * 2; sm.radial_segments = 12; sm.rings = 6
	torso.mesh = sm; torso.material_override = mat; torso.position.y = r
	match kind:
		"walker", "charger":
			torso.scale = Vector3(1.25, .7, .9)
			var head := MeshInstance3D.new(); var hm := SphereMesh.new(); hm.radius = r * .45; hm.height = r * .9; head.mesh = hm
			head.material_override = mat; head.position = Vector3(r * 1.1, r * .8, 0); head.name = "Head"; n.add_child(head)
			if t in ["beetle", "kingbeetle"]:
				var horn := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0; cm.bottom_radius = r * .15; cm.height = r * .9
				horn.mesh = cm; horn.material_override = mat; horn.position = Vector3(r * 1.5, r * 1.1, 0); horn.rotation.z = -1.0; n.add_child(horn)
		"hopper": torso.scale = Vector3(1.1, .8, 1.0)
		"flyer":
			for s in [-1, 1]:
				var wing := MeshInstance3D.new(); var pm := PrismMesh.new(); pm.size = Vector3(r * 1.6, r * .9, .04)
				wing.mesh = pm; wing.material_override = mat; wing.position = Vector3(0, r * 1.3, s * r * .5); wing.name = "Wing%d" % s; n.add_child(wing)
		"shooter":
			torso.scale = Vector3(.9, 1.2, .9)
			var stem := MeshInstance3D.new(); var cm2 := CylinderMesh.new(); cm2.top_radius = r * .15; cm2.bottom_radius = r * .25; cm2.height = r
			stem.mesh = cm2; stem.material_override = level.wc(Color("#4f7a3a")); stem.position.y = r * .3; n.add_child(stem); torso.position.y = r * 1.3
		"chaser": torso.scale = Vector3(.9, 1.4, .9)
		"swimmer": torso.scale = Vector3(2.0, .45, .6)
	n.add_child(torso)
	# eyes (emissive, readable in caves)
	var em := StandardMaterial3D.new(); em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.albedo_color = Color("#fff2b0") if kind != "chaser" else Color("#c8b8ff")
	for s in [-1, 1]:
		var e := MeshInstance3D.new(); var es := SphereMesh.new(); es.radius = r * .12; es.height = r * .24; e.mesh = es; e.material_override = em
		e.position = Vector3(r * .85, r * 1.15, s * r * .3 + .3); n.add_child(e)
	return n

func center() -> Vector3: return global_position + Vector3(0, radius, 0)

func _physics_process(dt: float) -> void:
	if not alive:
		die_t -= dt; body.scale = Vector3.ONE * max(0.01, die_t / .5); body.rotation.z += dt * 8.0
		if die_t <= 0: queue_free()
		return
	if player == null: return
	var to := player.global_position - global_position
	var dist := to.length()
	if abs(to.x) > 40 and st == "idle": return   # sleep when far away
	st_t -= dt; flash = max(0.0, flash - dt * 4.0)
	match kind:
		"walker": _walker(dt, to, dist)
		"charger": _charger(dt, to, dist)
		"hopper": _hopper(dt, to, dist)
		"flyer": _flyer(dt, to, dist)
		"shooter": _shooter(dt, to, dist)
		"chaser": _chaser(dt, to, dist)
		"swimmer": _swimmer(dt, to, dist)
	global_position.z = 0
	# telegraph read: warm flash + shake
	var tele := st == "tele"
	tele_shake = (randf_range(-.06, .06) if tele else 0.0)
	body.position.x = tele_shake
	mat.set_shader_parameter("glow", Vector3(1.0, .55, .2) * (.45 + .35 * sin(Time.get_ticks_msec() * .03)) if tele else Vector3(1, 1, 1) * flash * .8)
	body.rotation.y = 0.0 if face > 0 else PI
	# contact damage
	if center().distance_to(player.global_position + Vector3(0, .6, 0)) < radius + contact and st != "stun":
		player.combat.damage(global_position.x)
	_shots(dt)

func _gravity(dt: float) -> void:
	velocity.y = max(velocity.y - 22.0 * dt, -20.0)

func _st(s: String, tt: float) -> void: st = s; st_t = tt

func _walker(dt: float, to: Vector3, dist: float) -> void:
	_gravity(dt)
	match st:
		"idle", "cool":
			var sp := 1.1
			if st == "idle" and dist < aggro and abs(to.y) < 2.0:
				face = int(signf(to.x))
				if dist < 3.2: _st("tele", .45)
			velocity.x = face * sp
			if is_on_wall() or (is_on_floor() and not _ground_ahead()): face = -face
			if abs(global_position.x - home.x) > 5 and signf(global_position.x - home.x) == face: face = -face
			if st == "cool" and st_t <= 0: st = "idle"
		"tele":
			velocity.x = 0
			if st_t <= 0: _st("atk", .35); velocity.x = face * 6.5; velocity.y = 2.5
		"atk":
			if st_t <= 0: _st("cool", .8)
		"stun":
			velocity.x *= .9
			if st_t <= 0: st = "idle"
	move_and_slide()

func _charger(dt: float, to: Vector3, dist: float) -> void:   # kingbeetle: idle → tele(.9 shake) → charge → stun 2.4
	_gravity(dt)
	match st:
		"idle":
			velocity.x = move_toward(velocity.x, 0, dt * 10)
			if dist < aggro and abs(to.y) < 3:
				face = int(signf(to.x)); _st("tele", .9)
		"tele":
			velocity.x = 0
			if st_t <= 0: _st("atk", 2.2)
		"atk":
			velocity.x = face * (10.5 if hp_v < hp_max * .5 else 8.5)
			if is_on_wall(): _st("stun", 2.4); velocity.x = -face * 2; velocity.y = 4; flash = 1
			elif st_t <= 0: _st("cool", .9)
		"cool":
			velocity.x = move_toward(velocity.x, 0, dt * 14)
			if st_t <= 0: st = "idle"
		"stun":
			velocity.x = move_toward(velocity.x, 0, dt * 6)
			if st_t <= 0: st = "idle"
	move_and_slide()

func _hopper(dt: float, to: Vector3, dist: float) -> void:
	_gravity(dt)
	if is_on_floor(): velocity.x = move_toward(velocity.x, 0, dt * 20)
	match st:
		"idle":
			if is_on_floor() and dist < aggro: face = int(signf(to.x)); _st("tele", .5)
		"tele":
			if st_t <= 0: _st("atk", .6); velocity = Vector3(face * clamp(abs(to.x) * 1.4, 2.0, 6.0), 9.0 if boss else 7.5, 0)
		"atk":
			if st_t <= 0 and is_on_floor(): _st("cool", .7)
		"cool", "stun":
			if st_t <= 0: st = "idle"
	move_and_slide()

func _flyer(dt: float, to: Vector3, dist: float) -> void:
	var tt := Time.get_ticks_msec() * .001
	for w in body.get_children():
		if w.name.begins_with("Wing"): w.rotation.x = sin(tt * 22.0) * .7 * (1 if w.name.ends_with("1") else -1)
	match st:
		"idle":
			var hover := home + Vector3(sin(tt * .7 + home.x) * 2.0, sin(tt * 1.3) * .5, 0)
			if dist < aggro:
				hover = player.global_position + Vector3(-signf(to.x) * 2.5, 2.2, 0); face = int(signf(to.x))
			velocity = (hover - global_position) * 2.0
			if dist < 4.0 and st_t <= 0: _st("tele", .5)
		"tele": velocity *= .85
		"atk":
			if st_t <= 0: _st("cool", 1.0)
		"cool", "stun":
			velocity *= .95
			if st_t <= 0: st = "idle"; st_t = .4
	if st == "tele" and st_t <= 0:
		_st("atk", .45); velocity = (player.global_position + Vector3(0, .6, 0) - center()).normalized() * (9.0 if boss else 7.0)
	move_and_slide()

func _shooter(dt: float, to: Vector3, dist: float) -> void:
	if t != "aranha" and t != "prisma": _gravity(dt)
	velocity.x = 0
	face = int(signf(to.x)) if to.x != 0 else face
	match st:
		"idle":
			if dist < aggro + 1 and st_t <= 0: _st("tele", .6)
		"tele":
			if st_t <= 0: _fire(to); _st("cool", 1.6)
		"cool", "stun":
			if st_t <= 0: st = "idle"
	move_and_slide()

func _chaser(dt: float, to: Vector3, dist: float) -> void:   # shadow: drifts, then lunges low
	_gravity(dt)
	match st:
		"idle":
			velocity.x = move_toward(velocity.x, (signf(to.x) * 1.6 if dist < aggro else 0.0), dt * 6)
			if dist < aggro: face = int(signf(to.x))
			if dist < 3.0: _st("tele", .4)
		"tele":
			velocity.x = 0
			if st_t <= 0: _st("atk", .3); velocity.x = face * 9.0
		"atk":
			if st_t <= 0: _st("cool", .9)
		"cool", "stun":
			velocity.x = move_toward(velocity.x, 0, dt * 12)
			if st_t <= 0: st = "idle"
	move_and_slide()

func _swimmer(dt: float, to: Vector3, dist: float) -> void:
	var tt := Time.get_ticks_msec() * .001
	var x0 := home.x - 4.0; var x1 := home.x + 4.0; var ytop := home.y + .5
	if water != null: x0 = max(x0, water.x0 + .5); x1 = min(x1, water.x1 - .5); ytop = water.top - .4
	var in_w: bool = water != null and level.water_at(player.global_position.x, player.global_position.y + .5) == water
	match st:
		"idle":
			var tgt := Vector3(home.x + sin(tt * .5 + home.x) * 3.0, home.y + sin(tt) * .3, 0)
			if in_w and dist < aggro:
				tgt = player.global_position + Vector3(0, .5, 0); face = int(signf(to.x))
				if dist < 3: _st("tele", .5)
			velocity = (tgt - global_position).limit_length(2.5)
		"tele":
			velocity *= .8
			if st_t <= 0: _st("atk", .4); velocity = (player.global_position + Vector3(0, .5, 0) - center()).normalized() * 7.0
		"atk", "cool", "stun":
			velocity *= .97
			if st_t <= 0: st = "idle" if st != "atk" else "cool"; st_t = .8
	if velocity.x != 0: face = int(signf(velocity.x))
	global_position.x = clamp(global_position.x, x0, x1); global_position.y = min(global_position.y, ytop)
	move_and_slide()

func _ground_ahead() -> bool:
	var s := get_world_3d().direct_space_state
	var f := global_position + Vector3(face * (radius + .2), .3, 0)
	var q := PhysicsRayQueryParameters3D.create(f, f + Vector3(0, -1.2, 0)); q.collision_mask = 1
	return not s.intersect_ray(q).is_empty()

# ---------------------------------------------------------------- projectiles (plant spit / spider / prism)
func _fire(to: Vector3) -> void:
	var m := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = .16; sm.height = .32; m.mesh = sm
	var mm := StandardMaterial3D.new(); mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mm.albedo_color = base_col.lightened(.45); m.material_override = mm
	get_parent().add_child(m); m.global_position = center() + Vector3(face * radius, .3, 0)
	var v := (player.global_position + Vector3(0, .7, 0) - m.global_position)
	var spd := 6.0; var tflight: float = max(.3, v.length() / spd)
	shots.append({"n": m, "v": Vector3(v.x / tflight, v.y / tflight + 4.0 * tflight, 0), "t": 2.5})
func _shots(dt: float) -> void:
	for s in shots.duplicate():
		s.t -= dt; s.v.y -= 8.0 * dt; s.n.global_position += s.v * dt
		if s.n.global_position.distance_to(player.global_position + Vector3(0, .7, 0)) < .55:
			player.combat.damage(s.n.global_position.x); s.t = 0
		if s.t <= 0: s.n.queue_free(); shots.erase(s)

# ---------------------------------------------------------------- damage / death
func take_hit(dmg: float, dir: Vector3, charged: bool, from_x: float) -> bool:
	if not alive: return false
	# beetles (and the king unless stunned) block frontal, non-charged hits
	var frontal := signf(from_x - global_position.x) == face and dir.y == 0
	if not charged and frontal and (t == "beetle" or (t == "kingbeetle" and st != "stun")):
		flash = .4; velocity.x = -face * 3.0; level.spark(center() + Vector3(face * radius, 0, 0)); return true
	hp_v -= dmg; flash = 1.0
	var kb := float(level.L.combat.get("knockback", 5.0)) * (.25 if boss else 1.0) * (1.5 if Prog.rank("impacto") > 0 else 1.0)
	velocity.x = dir.x * kb + signf(global_position.x - from_x) * kb * .3; velocity.y = 2.0 + max(0.0, dir.y) * 3.0
	if st == "tele" and not boss: _st("stun", .35)
	if hp_v <= 0: _kill()
	return true

func _kill() -> void:
	alive = false; die_t = .5; remove_from_group("enemy"); collision_layer = 0
	var xpv: int = int(level.L.world.xp.get(t, 10))
	Prog.add_xp(xpv)
	level.xp_pop(center(), xpv)
	level.drop(self)
	if boss: Prog.SV.doors["boss_" + t] = 1; Prog.save_game()
	for s in shots: s.n.queue_free()
	shots.clear()
