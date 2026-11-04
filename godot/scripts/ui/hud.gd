extends CanvasLayer
## HUD: masks (hp), soul vessel, level + xp bar, skill points, short story cards. Flat painted shapes, no outlines.
var combat: Node
var draw: Control
var card: Label
var card_t := 0.0
func _ready() -> void:
	layer = 5; process_mode = Node.PROCESS_MODE_ALWAYS
	draw = Control.new(); draw.set_anchors_preset(Control.PRESET_FULL_RECT); draw.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(draw)
	draw.draw.connect(_on_draw)
	card = Label.new(); card.set_anchors_preset(Control.PRESET_CENTER_BOTTOM); card.position = Vector2(-420, -150); card.size = Vector2(840, 60)
	card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_theme_font_size_override("font_size", 22); card.add_theme_color_override("font_color", Color("#fff6e4"))
	card.add_theme_color_override("font_shadow_color", Color(0, 0, 0, .45)); card.add_theme_constant_override("shadow_offset_y", 2)
	card.modulate.a = 0; add_child(card)
	Prog.leveled.connect(func(lv): say("nível %d. algo cresce dentro dele. (✧ ponto de habilidade — árvore: Tab / N)" % lv, 4.5))
func say(t: String, dur := 3.0) -> void: card.text = t; card_t = dur
func _process(dt: float) -> void:
	draw.queue_redraw()
	card_t -= dt; card.modulate.a = clamp(card_t * 2.0, 0.0, 1.0)
func _on_draw() -> void:
	if combat == null: return
	var o := Vector2(34, 34)
	# soul vessel
	var r := 30.0; var c := o + Vector2(r, r)
	draw.draw_circle(c, r, Color(.1, .12, .16, .45))
	var f: float = combat.soul / 99.0
	if f > 0:
		var pts := PackedVector2Array(); var h: float = c.y + r - 2 * r * f
		for i in 41:
			var a := PI * 2 * i / 40.0; var pnt := c + Vector2(cos(a), sin(a)) * (r - 3)
			pts.append(Vector2(pnt.x, max(pnt.y, h)))
		draw.draw_colored_polygon(pts, Color(.93, .95, 1.0, .9))
	if combat.foc_t > 0: draw.draw_arc(c, r + 5, -PI / 2, -PI / 2 + TAU * combat.foc_t / Prog.focus_t(), 32, Color("#fff2b0"), 4)
	# masks
	for i in combat.max_hp():
		var mc := o + Vector2(2 * r + 26 + i * 30, 16)
		var full: bool = i < combat.hp
		draw.draw_circle(mc, 11, Color("#f4ecdc") if full else Color(.1, .12, .16, .4))
		if full: draw.draw_circle(mc + Vector2(-3, -3), 4, Color("#ffffff"))
	# level / xp
	var lv := Prog.LVL(); var a0 := Prog.XPC(lv); var a1 := Prog.XPC(min(lv + 1, Prog.LMAX))
	var t: float = 1.0 if lv >= Prog.LMAX else float(Prog.SV.xp - a0) / max(1.0, float(a1 - a0))
	var bx := o + Vector2(2 * r + 14, 38)
	draw.draw_rect(Rect2(bx, Vector2(180, 7)), Color(.1, .12, .16, .4))
	draw.draw_rect(Rect2(bx, Vector2(180 * t, 7)), Color("#ffe39a"))
	var font := ThemeDB.fallback_font
	var s := "Nv %d/%d" % [lv, Prog.LMAX] + ("  ✧ %d" % Prog.SV.sp if Prog.SV.sp > 0 else "")
	draw.draw_string(font, bx + Vector2(0, 28), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#fff6e4"))
