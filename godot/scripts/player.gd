extends CharacterBody3D
## Broto — 2.5D wooden-puppet player. Movement is locked to the XZ plane at z=0 (x = along the path, y = up), as in the web game.
## Origin is at the feet. Numbers come from level.json "player" + the web v16 controller.

signal landed(speed: float)

@export var level_path: NodePath
var level: Node
var cfg: Dictionary

# tuning (web v16 / HK-style)
var WALK := 3.6
var RUN := 6.4
var JUMP_V := 9.4
var GRAV := 22.0
const COYOTE := 0.10
const JUMP_BUF := 0.13
const JUMP_CUT := 0.45        # variable jump: vy multiplier when the button is released early
const FALL_MAX := 20.0
const FALL_GRAV_MUL := 1.35   # heavier on the way down (puppet weight)
const DASH_V := 12.5
const DASH_T := 0.17
const DASH_CD := 0.42
const ACC_G := 38.0
const ACC_A := 22.0
const CLIMB_REACH := 1.8      # how high a wall-top can be for auto-climb/mantle (= web airReach)
const STEP_UP := 0.6
const PH := 1.2

enum S { GROUND, AIR, SWIM, ROPE, CLIMB, DASH }
var state := S.AIR
var face := 1
var coyote := 0.0
var jbuf := 0.0
var jheld := false
var dash_t := 0.0
var dash_cd := 0.0
var air_dash := 0
var block_t := 0.0
var land_t := 0.0
var jump_anim_t := 0.0
# swim
var water = null
var dive := false
var dive_t := 0.0
# rope
var rope = null
var rope_d := 0.0
var rope_cd := 0.0
# climb
var climb_from := Vector3.ZERO
var climb_to := Vector3.ZERO
var climb_t := 0.0
var climb_dur := 0.35
var climb_anim := "mantle"
# input (can be overridden by the test bot: `bot` dictionary)
var bot = null
var _prev := {}

@onready var puppet: Node3D = $Puppet
var model: Node3D
var anim_tree: AnimationTree
var anim_names: PackedStringArray = []
var cur_anim := ""

# wooden-puppet secondary motion springs
var lean := 0.0; var lean_v := 0.0
var sq := 1.0; var sq_v := 0.0
var clack := 0.0; var clack_v := 0.0
var head_bob := 0.0
var turn := 1.0

func init() -> void:  # called by main.gd after the level is built
	level = get_node(level_path)
	cfg = level.L.player
	WALK = cfg.walk; RUN = cfg.run; JUMP_V = cfg.jumpV; GRAV = cfg.gravity
	floor_max_angle = deg_to_rad(cfg.maxSlopeDeg); floor_snap_length = cfg.snap
	axis_lock_linear_z = true
	_setup_model()

# ---------------------------------------------------------------- model + AnimationTree
func _setup_model() -> void:
	var ps: PackedScene = load("res://assets/char/broto.glb")
	model = ps.instantiate(); puppet.add_child(model)
	var wood: ShaderMaterial = level.wc(Color("#f0e2cc"), {"wash": .18, "grain": .16})
	for mi in model.find_children("*", "MeshInstance3D", true, false): (mi as MeshInstance3D).material_override = wood
	# normalise height to PH
	var aabb := _aabb(model, Transform3D.IDENTITY)
	var k: float = PH / max(aabb.size.y, 0.01)
	model.scale = Vector3.ONE * k; model.position.y = -aabb.position.y * k
	var ap: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	if ap == null: push_warning("broto.glb has no AnimationPlayer"); return
	for n in ap.get_animation_list():
		var a := ap.get_animation(n)
		if n in ["walk", "run", "idle", "rest", "air", "push", "push_heavy", "push_struggle", "hang", "swim_surface", "swim_under", "charge"]:
			a.loop_mode = Animation.LOOP_LINEAR
		anim_names.append(n)
	anim_tree = AnimationTree.new(); anim_tree.name = "AnimationTree"
	var bt := AnimationNodeBlendTree.new()
	var tr := AnimationNodeTransition.new(); tr.xfade_time = 0.14
	var ts := AnimationNodeTimeScale.new()
	bt.add_node("state", tr, Vector2(200, 0)); bt.add_node("speed", ts, Vector2(400, 0))
	var i := 0
	for n in anim_names:
		var an := AnimationNodeAnimation.new(); an.animation = n
		bt.add_node(n, an, Vector2(0, i * 80)); tr.add_input(n); bt.connect_node("state", i, n); i += 1
	bt.connect_node("speed", 0, "state"); bt.connect_node("output", 0, "speed")
	anim_tree.tree_root = bt
	model.add_child(anim_tree)
	anim_tree.anim_player = anim_tree.get_path_to(ap)
	anim_tree.active = true
	play("idle")

func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB(); var first := true
	var t: Transform3D = xf * (n.transform if n is Node3D else Transform3D.IDENTITY)
	if n is MeshInstance3D and n.mesh:
		var b: AABB = t * n.mesh.get_aabb(); out = b; first = false
	for c in n.get_children():
		var cb := _aabb(c, t)
		if cb.size != Vector3.ZERO: out = cb if first else out.merge(cb); first = false
	return out

func play(n: String, rate := 1.0) -> void:
	if anim_tree == null: return
	anim_tree.set("parameters/speed/scale", rate)
	if n == cur_anim or not anim_names.has(n): return
	cur_anim = n
	anim_tree.set("parameters/state/transition_request", n)

# ---------------------------------------------------------------- input
func I(a: String) -> bool:
	if bot != null: return bot.get(a, false)
	return Input.is_action_pressed(a)
func P(a: String) -> bool:   # just pressed
	var now := I(a); var was: bool = _prev.get(a, false); return now and not was
func _latch() -> void:
	for a in ["left", "right", "up", "down", "jump", "dash", "grab", "run"]: _prev[a] = I(a)

# ---------------------------------------------------------------- main loop
func _physics_process(dt: float) -> void:
	if level == null: return
	var dir := int(I("right")) - int(I("left"))
	if dir != 0 and state != S.ROPE and state != S.CLIMB: face = dir
	if P("jump"): jbuf = JUMP_BUF
	jbuf = max(0.0, jbuf - dt); dash_cd = max(0.0, dash_cd - dt); rope_cd = max(0.0, rope_cd - dt)
	land_t = max(0.0, land_t - dt); jump_anim_t = max(0.0, jump_anim_t - dt)

	match state:
		S.CLIMB: _climb(dt)
		S.ROPE: _rope(dt, dir)
		S.SWIM: _swim(dt, dir)
		S.DASH: _dash(dt)
		_: _move(dt, dir)
	if state != S.CLIMB and state != S.ROPE: _check_water()
	global_position.z = 0.0
	_secondary(dt)
	_animate()
	_latch()

func _move(dt: float, dir: int) -> void:
	var was_floor := is_on_floor()
	var spd := RUN if I("run") else WALK
	var acc := ACC_G if was_floor else ACC_A
	velocity.x = move_toward(velocity.x, dir * spd, acc * dt)
	# gravity (heavier when falling, variable jump cut)
	var g := GRAV * (FALL_GRAV_MUL if velocity.y < 0 else 1.0)
	velocity.y = max(velocity.y - g * dt, -FALL_MAX)
	if jheld and not I("jump") and velocity.y > 0: velocity.y *= JUMP_CUT; jheld = false
	if was_floor: coyote = COYOTE; air_dash = 0
	else: coyote = max(0.0, coyote - dt)
	# jump (buffer + coyote)
	if jbuf > 0 and coyote > 0:
		velocity.y = JUMP_V; jbuf = 0; coyote = 0; jheld = true; jump_anim_t = .18; state = S.AIR
	# dash
	if P("dash") and dash_cd <= 0 and (was_floor or air_dash == 0):
		if not was_floor: air_dash = 1
		state = S.DASH; dash_t = DASH_T; dash_cd = DASH_CD; velocity = Vector3(face * DASH_V, 0, 0); return
	var vy_before := velocity.y
	move_and_slide()
	_push_bodies()
	if is_on_floor():
		if state == S.AIR and vy_before < -6: land_t = .18; landed.emit(-vy_before); sq_v -= -vy_before * .35
		state = S.GROUND
	else: state = S.AIR
	# blocked against a wall → auto step / climb / mantle
	if dir != 0 and is_on_wall() and abs(velocity.x) < .2: block_t += dt
	else: block_t = 0.0
	if dir != 0 and block_t > (0.0 if state == S.GROUND else .05): _try_climb(dir)
	# grab a rope while airborne (or by pressing grab/up near it)
	if rope_cd <= 0 and (state == S.AIR or P("grab") or P("up")): _try_rope()

func _push_bodies() -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i); var o := c.get_collider()
		if o is RigidBody3D and abs(c.get_normal().y) < .5:
			var push: float = cfg.pushForce / 60.0 / max(o.mass, 1.0) * 6.0
			o.apply_central_impulse(Vector3(-c.get_normal().x * push, 0, 0))
			o.linear_velocity.x = clampf(o.linear_velocity.x, -cfg.pushSpeed, cfg.pushSpeed)

# ledge probe: find the top of whatever is in front, within reach
func probe(dir: int, max_h: float):
	var space := get_world_3d().direct_space_state
	var x: float = global_position.x + dir * (cfg.radius + .3)
	var from := Vector3(x, global_position.y + max_h + .05, 0); var to := Vector3(x, global_position.y + .02, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to); q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty() or hit.normal.y < .7: return null
	var top: float = hit.position.y
	# headroom above the ledge
	var q2 := PhysicsRayQueryParameters3D.create(Vector3(x, top + .05, 0), Vector3(x, top + PH * .9, 0)); q2.exclude = [get_rid()]
	if not space.intersect_ray(q2).is_empty(): return null
	return {"top": top, "x": x + dir * .1, "h": top - global_position.y}

func _try_climb(dir: int) -> bool:
	var c = probe(dir, CLIMB_REACH)
	if c == null or c.h < .05: return false
	if state == S.GROUND and c.h > STEP_UP and block_t < .12: return false
	start_climb(c, "step_up" if c.h < STEP_UP else "mantle"); return true

func start_climb(c: Dictionary, anim: String) -> void:
	state = S.CLIMB; climb_anim = anim; climb_t = 0.0
	climb_dur = .2 if anim == "step_up" else .42
	climb_from = global_position; climb_to = Vector3(c.x, c.top + .02, 0); velocity = Vector3.ZERO
	water = null; dive = false

func _climb(dt: float) -> void:
	climb_t += dt; var t: float = clamp(climb_t / climb_dur, 0.0, 1.0)
	var up: float = clamp(t / .65, 0.0, 1.0); var fw: float = clamp((t - .4) / .6, 0.0, 1.0)
	global_position = Vector3(lerp(climb_from.x, climb_to.x, fw * fw * (3 - 2 * fw)), lerp(climb_from.y, climb_to.y, 1.0 - pow(1.0 - up, 2.0)), 0)
	if t >= 1.0: state = S.GROUND; velocity = Vector3.ZERO; sq_v -= 1.2

func _dash(dt: float) -> void:
	dash_t -= dt; velocity.y = 0; velocity.x = face * DASH_V
	move_and_slide()
	if dash_t <= 0 or is_on_wall():
		state = S.GROUND if is_on_floor() else S.AIR; velocity.x = face * RUN * .8

# ---------------------------------------------------------------- swimming (port of web swimStep)
func _check_water() -> void:
	var p := global_position
	var w2 = level.water_at(p.x, p.y + .5)
	if state != S.SWIM:
		if w2 != null and p.y + .75 < w2.top:
			water = w2; state = S.SWIM; dive = velocity.y < -9; air_dash = 0; jheld = false
			velocity.y *= .3; velocity.x *= .6
			level.splash(Vector3(p.x, w2.top, 0), min(1.5, abs(velocity.y) / 6.0))
	elif w2 == null or p.y + .25 > water.top + .05:
		state = S.AIR; water = null; dive = false

func _swim(dt: float, dir: int) -> void:
	var w = water; var p := global_position
	var head := p.y + 1.05
	if head < w.top - .3: dive = true
	var J := P("jump")
	if not dive:
		var ty: float = w.top - .82
		velocity.y += ((ty - p.y) * 16.0 - velocity.y * 5.0) * dt          # buoyancy spring to the surface line
		velocity.x += (dir * 2.4 - velocity.x) * min(1.0, dt * 3.0)
		if P("down"): dive = true; velocity.y = -2.6; dive_t = .35        # dive
		if J or (dir != 0 and block_t > .25):
			var c = probe(dir, 1.75) if dir != 0 else null
			if c != null and c.top < w.top + 1.6:
				start_climb(c, "step_up" if c.h < .6 else "mantle"); return  # climb out onto a ledge
			if J:                                                              # jump out
				velocity.y = 6.8; state = S.AIR; water = null; jheld = true; jbuf = 0
				move_and_slide(); return
	else:
		var vd := (1.0 if (I("jump") or I("up")) else 0.0) - (1.0 if I("down") else 0.0)
		velocity.x += (dir * 2.7 - velocity.x) * min(1.0, dt * 2.5)
		velocity.y += (vd * 2.5 + .3 - velocity.y) * min(1.0, dt * 2.5)    # slight natural buoyancy
		if head > w.top - .1 and velocity.y > 0: dive = false              # resurface
	if dive_t > 0: dive_t -= dt
	if P("dash") and dash_cd <= 0: dash_t = .2; dash_cd = DASH_CD
	if dash_t > 0: dash_t -= dt; velocity.x = face * 8.0; velocity.y *= .5
	move_and_slide()
	if dir != 0 and is_on_wall(): block_t += dt
	else: block_t = 0.0

# ---------------------------------------------------------------- ropes
func _try_rope() -> void:
	var hand := global_position + Vector3(0, PH * 1.05, 0)
	for r in level.ropes:
		var rel: Vector3 = hand - r.anchor
		var d := -rel.y
		if d < .3 or d > r.length + .1: continue
		var rx: float = r.point(d).x
		if abs(hand.x - rx) < .45:
			rope = r; rope_d = clamp(d, .6, r.length); r.held = true; state = S.ROPE
			r.ang_vel = velocity.x / max(rope_d, .5) * .8; velocity = Vector3.ZERO; air_dash = 0
			return

func _rope(dt: float, dir: int) -> void:
	var r = rope
	r.ang_vel += (-GRAV / max(rope_d, .5) * sin(r.angle) * .55 + dir * 2.4) * dt
	r.ang_vel *= 1.0 - .6 * dt; r.angle = clamp(r.angle + r.ang_vel * dt, -1.2, 1.2)
	if I("up"): rope_d = max(.6, rope_d - 1.6 * dt)
	if I("down"): rope_d = min(r.length, rope_d + 2.2 * dt)
	var hand: Vector3 = r.point(rope_d)
	global_position = hand - Vector3(0, PH * 1.05, 0)
	if dir != 0: face = dir
	if P("jump") or P("grab"):
		var tv: float = r.ang_vel * rope_d
		velocity = Vector3(tv * cos(r.angle) + face * 2.5, 7.2 + max(0.0, tv * sin(r.angle) * face), 0)
		r.held = false; rope = null; rope_cd = .35; state = S.AIR; jheld = true; air_dash = 0

# ---------------------------------------------------------------- wooden-puppet secondary motion
func _secondary(dt: float) -> void:
	# lean into acceleration with an under-damped spring (stiff wooden joints → small overshoot + clack)
	var target := -velocity.x * .035 * (0.4 if state == S.SWIM else 1.0)
	if state == S.AIR: target += clamp(velocity.y * .015, -.15, .15) * face
	lean_v += ((target - lean) * 140.0 - lean_v * 11.0) * dt; lean += lean_v * dt
	sq_v += ((1.0 - sq) * 220.0 - sq_v * 13.0) * dt; sq += sq_v * dt * .05
	sq = clamp(sq, .82, 1.12)
	# footstep clacks: tiny rigid jolts when walking
	if state == S.GROUND and abs(velocity.x) > .5:
		head_bob += dt * abs(velocity.x) * 2.2
		if fmod(head_bob, PI) < dt * abs(velocity.x) * 2.2: clack_v += randf_range(-1.6, 1.6)
	clack_v += (-clack * 260.0 - clack_v * 9.0) * dt; clack += clack_v * dt
	turn = move_toward(turn, float(face), dt * 9.0)
	var yaw: float = PI / 2.0 * turn
	var roll := lean + clack * .05
	var tilt := 0.0
	if state == S.SWIM and dive:
		var sp := Vector2(velocity.x, velocity.y)
		if sp.length() > .4: tilt = clamp(PI / 2.0 - atan2(velocity.y, abs(velocity.x)), .2, 2.8)
		else: tilt = .5
	if state == S.ROPE and rope: roll = rope.angle
	puppet.basis = Basis(Vector3.BACK, roll - float(face) * tilt) * Basis(Vector3.UP, yaw)
	puppet.scale = Vector3(1.0 / sqrt(sq), sq, 1.0 / sqrt(sq))

func _animate() -> void:
	var sx: float = abs(velocity.x)
	match state:
		S.CLIMB: play(climb_anim, 1.3)
		S.ROPE: play("hang")
		S.DASH: play("dash", 1.4)
		S.SWIM:
			if dive_t > 0: play("dive")
			elif dive: play("swim_under", .6 + Vector2(velocity.x, velocity.y).length() / 2.5)
			else: play("swim_surface", .7 + sx / 3.0)
		S.AIR:
			if jump_anim_t > 0: play("jump_start", 1.4)
			else: play("air")
		_:
			if land_t > 0: play("land", 1.3)
			elif block_t > .1 and _pushing(): play("push")
			elif sx > WALK + .4: play("run", sx / RUN)
			elif sx > .3: play("walk", max(.6, sx / WALK))
			else: play("idle")
func _pushing() -> bool:
	for i in get_slide_collision_count():
		if get_slide_collision(i).get_collider() is RigidBody3D: return true
	return false

func state_name() -> String: return S.keys()[state]
