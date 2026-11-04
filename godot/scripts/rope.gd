extends Node3D
## Hanging vine. Swings as a pendulum; the player attaches to it (see player.gd).
var anchor := Vector3.ZERO
var length := 3.0
var angle := 0.0
var ang_vel := 0.0
var held := false
var _segs: Array = []
const SEG := 0.32
func _ready() -> void:
	var cyl := CylinderMesh.new(); cyl.top_radius = .035; cyl.bottom_radius = .045; cyl.height = SEG; cyl.radial_segments = 5
	var mat: ShaderMaterial = get_parent().wc(Color("#9a7a50"), {"wash": .2})
	var leaf := BoxMesh.new(); leaf.size = Vector3(.2, .02, .09)
	var lm: ShaderMaterial = get_parent().wc(Color("#7fbf4a"))
	for i in int(ceil(length / SEG)):
		var m := MeshInstance3D.new(); m.mesh = cyl; m.material_override = mat; add_child(m); _segs.append(m)
		if i % 2 == 0:
			var l := MeshInstance3D.new(); l.mesh = leaf; l.material_override = lm; l.position = Vector3(.1 * (1 if i % 4 == 0 else -1), 0, 0); m.add_child(l)
	var knot := MeshInstance3D.new(); var sp := SphereMesh.new(); sp.radius = .12; sp.height = .24; knot.mesh = sp
	knot.material_override = get_parent().wc(Color("#6b5236")); knot.position = anchor; add_child(knot)
func point(t: float) -> Vector3:  # t = distance from anchor along the rope
	return anchor + Vector3(sin(angle), -cos(angle), 0) * t
func bottom() -> Vector3: return point(length)
func _physics_process(dt: float) -> void:
	if not held:
		ang_vel += (-9.0 / length * sin(angle)) * dt + sin(Time.get_ticks_msec() * .0011 + anchor.x) * .02 * dt
		ang_vel *= 1.0 - 1.2 * dt; angle += ang_vel * dt
	for i in _segs.size():
		var s: MeshInstance3D = _segs[i]
		var d := (i + .5) * SEG; var bend := angle * (0.85 + 0.15 * d / length)
		s.position = anchor + Vector3(sin(bend), -cos(bend), 0) * d
		s.rotation = Vector3(0, 0, bend)
