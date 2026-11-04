extends Camera3D
## Side-on follow camera (web: fixed z offset, smoothed, looks ahead in the facing direction).
var target: Node3D
var look := 0.0
var off := Vector3(0, 2.8, 11.5)
func _ready() -> void: fov = 42.0; near = .1; far = 220.0
func snap() -> void:
	global_position = target.global_position + off; look_at(target.global_position + Vector3(0, 1.0, 0))
func _process(dt: float) -> void:
	if target == null: return
	var p := target.global_position
	look = lerp(look, float(target.face) * 1.6 + target.velocity.x * .15, min(1.0, dt * 1.6))
	var under: bool = target.state == target.S.SWIM and target.dive
	var want := p + off + Vector3(look, -0.6 if under else 0.0, -1.5 if under else 0.0)
	global_position = global_position.lerp(want, min(1.0, dt * 4.5))
	var f := global_position - off
	look_at(Vector3(f.x, f.y + 1.0, 0))
