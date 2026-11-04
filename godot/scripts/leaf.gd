extends Node3D
## Leaf guide (basic): a glowing leaf that drifts ahead of Broto along the first stretch, waits if he falls behind.
var level: Node
var player: Node3D
var C: Dictionary
var x := 0.0
var t := 0.0
var mesh: MeshInstance3D
var light: OmniLight3D
func setup(lv: Node, pl: Node3D) -> void:
	level = lv; player = pl; C = lv.L.leaf; x = C.startX
	mesh = MeshInstance3D.new(); var pm := PrismMesh.new(); pm.size = Vector3(.32, .16, .04); mesh.mesh = pm
	var m := StandardMaterial3D.new(); m.albedo_color = Color(C.color); m.emission_enabled = true; m.emission = Color(C.color); m.emission_energy_multiplier = 2.0
	mesh.material_override = m; add_child(mesh)
	light = OmniLight3D.new(); light.light_color = Color(C.color); light.light_energy = 1.4; light.omni_range = 3.5; add_child(light)
	global_position = Vector3(x, level.hp(x) + C.height, 0)
func _process(dt: float) -> void:
	if player == null: return
	t += dt
	var px: float = player.global_position.x
	var goal: float = min(px + C.ahead, C.stopX)
	if abs(x - px) > C.waitDist and x > px: goal = x        # wait for him
	x = move_toward(x, max(goal, x if px < x else goal), C.speed * dt)
	var y: float = max(level.hp(x), player.global_position.y if abs(x - px) < 3 else -99.0) + C.height + sin(t * 2.1) * .18
	global_position = global_position.lerp(Vector3(x, y, .4 + sin(t * 1.3) * .3), min(1.0, dt * 3.0))
	mesh.rotation = Vector3(sin(t * 3.0) * .5, t * 1.5, sin(t * 2.0) * .4)
	visible = px < C.stopX + 6
