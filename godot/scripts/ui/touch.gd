extends CanvasLayer
## On-screen touch controls (shown on touch devices or with the `--touch` user arg). Each button presses an InputMap action.
const BTN := [
	# action, label, anchor(0=left,1=right), offset from bottom corner, radius
	["left", "◀", 0, Vector2(110, 120), 62], ["right", "▶", 0, Vector2(250, 120), 62],
	["up", "▲", 0, Vector2(180, 250), 44], ["down", "▼", 0, Vector2(40, 250), 40],
	["jump", "⤒", 1, Vector2(110, 120), 70], ["dash", "»", 1, Vector2(250, 95), 50],
	["grab", "✋", 1, Vector2(200, 230), 44], ["run", "correr", 1, Vector2(90, 280), 44],
]
func _ready() -> void:
	visible = DisplayServer.is_touchscreen_available() or "--touch" in OS.get_cmdline_user_args()
	layer = 10
	get_viewport().size_changed.connect(_layout); _build(); _layout()
var _nodes := []
func _tex(r: int) -> Texture2D:
	var g := Gradient.new(); g.set_color(0, Color(1, 1, 1, .32)); g.set_color(1, Color(1, 1, 1, .0)); g.add_point(.8, Color(1, 1, 1, .22)); g.add_point(.84, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new(); t.gradient = g; t.fill = GradientTexture2D.FILL_RADIAL; t.fill_from = Vector2(.5, .5); t.fill_to = Vector2(1, .5); t.width = r * 2; t.height = r * 2
	return t
func _build() -> void:
	for b in BTN:
		var t := TouchScreenButton.new(); t.action = b[0]; t.texture_normal = _tex(b[4]); t.passby_press = true
		var sh := CircleShape2D.new(); sh.radius = b[4]; t.shape = sh; t.shape_centered = true
		var l := Label.new(); l.text = b[1]; l.add_theme_font_size_override("font_size", 30 if b[1].length() < 3 else 18)
		l.size = Vector2(b[4] * 2, b[4] * 2); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.modulate = Color(1, 1, 1, .85); t.add_child(l); add_child(t); _nodes.append([t, b])
func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	for n in _nodes:
		var b = n[1]; var r: float = b[4]; var o: Vector2 = b[3]
		n[0].position = Vector2(o.x - r if b[2] == 0 else vs.x - o.x - r, vs.y - o.y - r)
