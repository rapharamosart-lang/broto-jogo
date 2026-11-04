extends CanvasLayer
## Skill tree (web v16 TREE): 3 branches + capstone, buy with ✧ points, "refazer" respec. Toggle: Tab / N / Select.
var panel: PanelContainer
var header: Label
var cols := {}
var buttons := {}
var open := false
func _ready() -> void:
	layer = 10; process_mode = Node.PROCESS_MODE_ALWAYS
	panel = PanelContainer.new(); panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(.12, .1, .09, .82); panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var mg := MarginContainer.new(); for k in ["left", "right", "top", "bottom"]: mg.add_theme_constant_override("margin_" + k, 48)
	panel.add_child(mg)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 18); mg.add_child(v)
	var top := HBoxContainer.new(); v.add_child(top)
	header = Label.new(); header.add_theme_font_size_override("font_size", 28); header.add_theme_color_override("font_color", Color("#fff2d8"))
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top.add_child(header)
	var rs := Button.new(); rs.text = "refazer"; rs.name = "Respec"; rs.pressed.connect(func(): Prog.respec()); top.add_child(rs)
	var cl := Button.new(); cl.text = "fechar ✕"; cl.pressed.connect(toggle); top.add_child(cl)
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 28); h.size_flags_vertical = Control.SIZE_EXPAND_FILL; v.add_child(h)
	for b in ["c", "m", "v"]:
		var col := VBoxContainer.new(); col.size_flags_horizontal = Control.SIZE_EXPAND_FILL; col.add_theme_constant_override("separation", 8)
		var t := Label.new(); t.text = Prog.BRANCH[b]; t.add_theme_font_size_override("font_size", 24); t.add_theme_color_override("font_color", Color("#ffe39a")); col.add_child(t)
		h.add_child(col); cols[b] = col
	var xr := HBoxContainer.new(); v.add_child(xr); cols["x"] = xr
	for t in Prog.TREE:
		var bt := Button.new(); bt.name = t[0]; bt.alignment = HORIZONTAL_ALIGNMENT_LEFT; bt.tooltip_text = t[3]
		bt.custom_minimum_size = Vector2(0, 46); bt.add_theme_font_size_override("font_size", 16)
		bt.pressed.connect(func(): Prog.buy(t[0])); cols[t[1]].add_child(bt); buttons[t[0]] = bt
	Prog.changed.connect(refresh)
	panel.visible = false; refresh()
func toggle() -> void:
	open = not open; panel.visible = open; get_tree().paused = open; refresh()
func refresh() -> void:
	if header == null: return
	header.text = "Nv %d/%d  ·  ✧ %d ponto%s" % [Prog.LVL(), Prog.LMAX, Prog.SV.sp, "" if Prog.SV.sp == 1 else "s"]
	for t in Prog.TREE:
		var bt: Button = buttons[t[0]]; var r := Prog.rank(t[0])
		var req := "" if Prog.LVL() >= t[5] else "  · Nv %d" % t[5]
		var pre := ""
		if t[6] == "*": pre = "  · precisa dos 3 ramos"
		elif t[6] != "" and Prog.rank(t[6]) < 1: pre = "  · precisa " + Prog.row(t[6])[2]
		bt.text = "%s  %d/%d%s%s\n%s" % [t[2], r, t[4], req, pre, t[3]]
		bt.disabled = not Prog.can(t[0])
		bt.modulate = Color("#ffe9b0") if r > 0 else (Color.WHITE if Prog.can(t[0]) else Color(1, 1, 1, .55))
func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("tree"): toggle(); get_viewport().set_input_as_handled()
