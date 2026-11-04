extends Camera3D
## Side-on follow camera (web: fixed z offset, smoothed, looks ahead in the facing direction).
## Phase 2: foreground occluders fade out when they cover the player; lake framing raised; tighter framing in caves.
var target: Node3D
var level: Node
var look := 0.0
var off := Vector3(0, 2.8, 11.5)
var cave := 0.0
func _ready() -> void: fov = 42.0; near = .1; far = 220.0
func snap() -> void:
	global_position = target.global_position + off; look_at(target.global_position + Vector3(0, 1.0, 0))
func _process(dt: float) -> void:
	if target == null: return
	var p := target.global_position
	look = lerp(look, float(target.face) * 1.6 + target.velocity.x * .15, min(1.0, dt * 1.6))
	var swim: bool = target.state == target.S.SWIM
	var under: bool = swim and target.dive
	cave = move_toward(cave, 1.0 if (level and level.zone_k > .5) else 0.0, dt * 2.0)
	var base := p
	# at the lake the body sits ~.8 below the surface: frame from the water line so the shore stays in view
	if swim and target.water != null and not under: base.y = max(p.y, target.water.top - .2)
	var o := off.lerp(Vector3(0, 1.6, 10.0), cave)
	var want := base + o + Vector3(look, -0.3 if under else 0.6 if swim else 0.0, -1.5 if under else 0.0)
	global_position = global_position.lerp(want, min(1.0, dt * 4.5))
	var f := global_position - o
	look_at(Vector3(f.x, f.y + 1.0 - .3 * cave, 0))
	_fade(dt)
func _fade(dt: float) -> void:
	if level == null: return
	var px: float = target.global_position.x
	for oc in level.occluders:
		# anything in front of the play line whose footprint covers the player (or the gap to the camera) fades
		var hide: bool = abs(oc.x - px) < oc.r + .9 or abs(oc.x - global_position.x) < oc.r * .6
		var nf: float = move_toward(oc.f, .82 if hide else 0.0, dt * 3.0)
		if nf != oc.f: oc.f = nf; _set_t(oc.node, nf)
func _set_t(n: Node, v: float) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).transparency = v
	for c in n.get_children(): _set_t(c, v)
