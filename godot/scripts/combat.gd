extends Node3D
## HK-style combat for Broto (port of web v16): 4-direction nail (side/up/down), pogo, recoil, hitstop,
## i-frames with blink, soul meter + focus heal, charged attack (tree: carga/furia). Lives under the player.
signal hit_landed(n: int, dir: String)
signal hurt(hp: int)
signal died
var p: CharacterBody3D          # player
var C: Dictionary               # level.json "combat"
var hp := 3
var soul := 0
var atk_cd := 0.0
var inv := 0.0
var foc_t := 0.0
var chg_t := 0.0
var hitstop_left := 0.0
var slash: MeshInstance3D
var slash_t := 0.0
var last_dir := ""
var hits_total := 0
var pogos := 0
const RANGE := 1.6

func setup(player: CharacterBody3D, cfg: Dictionary) -> void:
	p = player; C = cfg
	hp = Prog.max_hp() if int(Prog.SV.get("hp", -1)) < 0 else min(int(Prog.SV.hp), Prog.max_hp())
	slash = MeshInstance3D.new(); var tm := TorusMesh.new(); tm.inner_radius = .95; tm.outer_radius = 1.12; tm.rings = 24; tm.ring_segments = 4
	slash.mesh = tm; var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, .97, .86, .85); m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.cull_mode = BaseMaterial3D.CULL_DISABLED
	slash.material_override = m; slash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; slash.visible = false
	add_child(slash)

func max_hp() -> int: return Prog.max_hp()

func step(dt: float) -> void:
	atk_cd = max(0.0, atk_cd - dt); inv = max(0.0, inv - dt)
	# i-frame blink
	p.puppet.visible = inv <= 0 or fmod(inv, .14) > .06
	if slash_t > 0:
		slash_t -= dt; var a: float = clamp(slash_t / .12, 0.0, 1.0)
		(slash.material_override as StandardMaterial3D).albedo_color.a = .85 * a
		slash.scale = Vector3.ONE * (1.0 + (1.0 - a) * .25) * (RANGE + Prog.reach()) / 1.6
		if slash_t <= 0: slash.visible = false
	# attack: tap = normal, hold (carga) = charged on release
	var can_chg := Prog.rank("carga") > 0
	if p.I("attack") and can_chg: chg_t += dt
	if p.P("attack") and not can_chg: attack(false)
	elif can_chg and not p.I("attack") and p._prev.get("attack", false):
		attack(chg_t > .55); chg_t = 0.0
	# focus heal (hold focus on the ground, soul >= 33, not full)
	if p.I("focus") and p.is_on_floor() and soul >= 33 and hp < max_hp() and abs(p.velocity.x) < .5:
		foc_t += dt
		if foc_t >= Prog.focus_t(): hp += 1; soul -= 33; foc_t = 0.0; hurt.emit(hp); p.sq_v += 2.0
	else: foc_t = 0.0

func attack(charged: bool) -> void:
	if atk_cd > 0 or p.state == p.S.CLIMB or p.state == p.S.ROPE: return
	atk_cd = float(C.get("cooldown", .4)) * Prog.atk_m()
	var air := not p.is_on_floor()
	var dir := "s"
	if p.I("up"): dir = "u"
	elif p.I("down") and air: dir = "d"
	last_dir = dir
	var reach := RANGE + Prog.reach() + (.7 if charged else 0.0)
	var o := p.global_position + Vector3(0, .75, 0)
	var c: Vector3
	match dir:
		"u": c = o + Vector3(0, .9, 0)
		"d": c = o + Vector3(0, -.9, 0)
		_: c = o + Vector3(p.face * .9, 0, 0)
	slash.global_position = c; slash.rotation = Vector3(PI / 2, 0, 0); slash.visible = true; slash_t = .12
	var dmg: float = (3.0 * (1.0 + .5 * Prog.rank("furia")) if charged else 1.0) * Prog.dmg_m()
	var n := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if not e.alive: continue
		var ep: Vector3 = e.center()
		var d := ep - o
		var R: float = reach + e.radius
		var ok := false
		match dir:
			"u": ok = d.y > -.2 and abs(d.x) < R * .8 and d.length() < R + .3
			"d": ok = d.y < .3 and abs(d.x) < R * .8 and d.length() < R + .3
			_: ok = d.x * p.face > -.4 and abs(d.y) < R * .85 and d.length() < R + .2
		if ok and e.take_hit(dmg, Vector3(p.face if dir == "s" else 0.0, 1.0 if dir == "u" else (-1.0 if dir == "d" else 0.0), 0), charged, p.global_position.x):
			n += 1
	if n > 0:
		hits_total += n
		var gain := Prog.soul_add() * (1 + (1 if (dir == "d" and Prog.rank("eco") > 0) else 0))
		soul = min(99, soul + gain)
		hitstop(.055 if not charged else .09)
		if dir == "d":                 # pogo: bounce, refresh double jump + air dash
			p.velocity.y = p.JUMP_V * .92 * Prog.pogo_m(); p.air_dash = 0; p.dj_used = false; p.state = p.S.AIR; p.jheld = false; pogos += 1
		elif dir == "s":               # recoil
			p.velocity.x = -p.face * (4.0 if p.is_on_floor() else 3.0); p.recoil_t = .1
		hit_landed.emit(n, dir)
	elif dir == "d" and _pogo_ground_spike(c): pass

func _pogo_ground_spike(_c: Vector3) -> bool: return false

func hitstop(t: float) -> void:
	if hitstop_left > 0: return
	hitstop_left = t; Engine.time_scale = .05
	await get_tree().create_timer(t, true, false, true).timeout
	Engine.time_scale = 1.0; hitstop_left = 0.0

var god := false
func damage(from_x: float, amount := 1) -> bool:
	if god: return false
	if inv > 0 or p.state == p.S.CLIMB: return false
	hp -= amount; inv = float(C.get("invuln", 1.3)) + Prog.inv_add()
	var k := signf(p.global_position.x - from_x); if k == 0: k = -p.face
	p.velocity = Vector3(k * float(C.get("knockback", 5.0)), 6.0, 0); p.state = p.S.AIR; p.recoil_t = .25
	if Prog.rank("espinhos") > 0:
		for e in get_tree().get_nodes_in_group("enemy"):
			if e.alive and e.center().distance_to(p.global_position) < 2.5: e.take_hit(1.0, Vector3(signf(e.global_position.x - p.global_position.x), 0, 0), true, p.global_position.x)
	hitstop(.12)
	hurt.emit(hp)
	if hp <= 0: died.emit()
	return true
