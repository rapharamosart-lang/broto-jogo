extends Node3D
## Boots the level, player, camera, leaf, HUD, skill tree and touch UI. Test hooks via user args (after `--`):
##   --x=39 --y=2        spawn position     --shot=res://shots/a.png --frames=90   save a frame and quit
##   --bot=right,run     hold actions        --botjump=0.5,1.2   tap jump at these times (s)
##   --botatk=0.5,1.0    tap attack at times --botup=1.0        tap up (doors/benches/levers) at a time
##   --botdown=t         tap down             --botfocus=t0-t1  hold focus between times
##   --xp=N  grant xp    --buy=a,b  buy skills   --tree  open the skill tree   --fresh  ignore save file
##   --save=user://x.json  save path          --savetest  save→reset→load round trip
##   --hp=N --soul=N     start values         --quit=5  quit after N seconds (prints a status line)   --touch
@onready var level: Node3D = $Level
@onready var player: CharacterBody3D = $Player
@onready var cam: Camera3D = $Camera
var hud: CanvasLayer
var tree_ui: CanvasLayer
var args := {}
var frame := 0
var tsec := 0.0
var kills := 0
var doors_used: Array = []
func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1); args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not args.has("fresh"): Prog.load_game()
	level.load_level()
	player.init()
	level.player = player
	var x := float(args.get("x", level.L.player.spawnX)); var y := float(args.get("y", level.hp(x) + .05))
	if not args.has("x") and Prog.SV.pos != null: x = float(Prog.SV.pos[0]); y = float(Prog.SV.pos[1]) + .05
	player.global_position = Vector3(x, y, 0)
	cam.target = player; cam.level = level; cam.snap()
	var leaf := preload("res://scripts/leaf.gd").new(); add_child(leaf); leaf.setup(level, player)
	level.spawn_enemies()
	hud = preload("res://scripts/ui/hud.gd").new(); add_child(hud); hud.combat = player.combat
	tree_ui = preload("res://scripts/ui/tree.gd").new(); add_child(tree_ui)
	player.combat.died.connect(_on_died)
	Prog.leveled.connect(func(_l): Prog.save_game())
	if args.has("xp"): Prog.add_xp(int(args.xp))
	if args.has("hp"): player.combat.hp = int(args.hp)
	if args.has("soul"): player.combat.soul = int(args.soul)
	if args.has("god"): player.combat.god = true
	if args.has("buy"):
		for k in args.buy.split(","): print("[broto] buy %s -> %s rank=%d sp=%d" % [k, Prog.buy(k), Prog.rank(k), Prog.SV.sp])
	if args.has("tree"):
		tree_ui.toggle()
		if args.tree != "1":
			var b := tree_ui.find_child(args.tree, true, false) as Button
			if b: b.pressed.emit()
			print("[broto] tree ui open=%s pressed=%s found=%s rank=%d sp=%d paused=%s" % [tree_ui.visible, args.tree, b != null, Prog.rank(args.tree), Prog.SV.sp, get_tree().paused])
	if args.has("savetest"): _savetest()
	for k in args.keys():
		if str(k).begins_with("bot") and player.bot == null: player.bot = {}
	if args.has("bot"):
		for a in args.bot.split(","): player.bot[a] = true
	for e in get_tree().get_nodes_in_group("enemy"): e.tree_exiting.connect(func(): kills += 1)
	print("[broto] ready x=%.1f y=%.2f lv=%d xp=%d renderer=%s enemies=%d" % [x, y, Prog.LVL(), Prog.SV.xp, RenderingServer.get_current_rendering_method(), get_tree().get_nodes_in_group("enemy").size()])

func _savetest() -> void:
	Prog.SV.xp = 0; Prog.SV.sp = 0; Prog.SV.tree = {}
	Prog.add_xp(1000); Prog.buy("forca"); Prog.buy("vida")
	var before: String = JSON.stringify(Prog.SV)
	Prog.save_game(Vector3(187, -60, 0), 4)
	Prog.reset(); var mid: int = Prog.SV.xp
	var ok: bool = Prog.load_game()
	print("[broto] savetest path=%s ok=%s xp_after_reset=%d lv=%d sp=%d tree=%s pos=%s match=%s" % [Prog.save_path, ok, mid, Prog.LVL(), Prog.SV.sp, Prog.SV.tree, Prog.SV.pos, str(int(Prog.SV.xp), int(Prog.SV.tree.get("forca", 0)), int(Prog.SV.tree.get("vida", 0))) == str(int(JSON.parse_string(before).xp), 1, 1)])

func _tap(key: String, t: float, w := .06) -> bool:
	if not args.has(key): return false
	for s in args[key].split(","):
		if s.contains("-"):
			var ab: PackedStringArray = s.split("-"); if tsec > float(ab[0]) and tsec < float(ab[1]): return true
		elif tsec > float(s) and tsec < float(s) + w: return true
	return false

func _physics_process(dt: float) -> void:
	tsec += dt
	if args.has("quit") and tsec > float(args.quit): _report(); get_tree().quit()
	if get_tree().paused: return
	if player.bot != null:
		if args.has("botjump"): player.bot["jump"] = _tap("botjump", tsec, .25)
		if args.has("botdash"): player.bot["dash"] = _tap("botdash", tsec)
		if args.has("botdown"): player.bot["down"] = _tap("botdown", tsec, .4) or args.get("bot", "").contains("down")
		if args.has("botatk"): player.bot["attack"] = _tap("botatk", tsec)
		if args.has("botup"): player.bot["up"] = _tap("botup", tsec, .1) or args.get("bot", "").contains("up")
		if args.has("botfocus"): player.bot["focus"] = _tap("botfocus", tsec)
	_interact()

func _report() -> void:
	var c = player.combat
	print("[broto] state=%s pos=%s hp=%d/%d soul=%d hits=%d pogos=%d kills=%d xp=%d lv=%d sp=%d room=%s doors=%s" % [player.state_name(), player.global_position, c.hp, c.max_hp(), c.soul, c.hits_total, c.pogos, kills, Prog.SV.xp, Prog.LVL(), Prog.SV.sp, level.cur_room, doors_used])
	if args.has("probe"): print("[broto] probe ", player.probe(1, 6.0), " wall=", player.is_on_wall())

# ---------------------------------------------------------------- doors, levers, benches (press up)
var _icd := 0.0
func _interact() -> void:
	_icd = max(0.0, _icd - get_physics_process_delta_time())
	var p := player.global_position
	var up: bool = player.P("up") or (player.I("up") and _icd <= 0 and player.bot != null)
	for d in level.doors:
		var dp: Vector3 = level.door_pos(d)
		var near: bool = abs(dp.x - p.x) < .9 and abs(dp.y - p.y) < 1.6
		if not near or _icd > 0: continue
		if d.get("auto", false) and player.state == player.S.SWIM or (up and not d.get("auto", false)):
			var lock := _locked(d)
			if lock != "": hud.say(lock, 2.5); _icd = .8; continue
			if d.has("sets"): Prog.SV.doors[d.sets] = 1
			var to = null
			for e in level.doors:
				if e.id == d.to: to = e
			if to == null: continue
			var tp: Vector3 = level.door_pos(to)
			player.global_position = tp + Vector3(0, .05 if not to.get("exitUp", false) else 1.2, 0); player.velocity = Vector3.ZERO
			player.state = player.S.AIR; player.water = null; player.dive = false
			cam.snap(); _icd = .7; doors_used.append(d.id)
			var r = level.room_at(tp.x, tp.y + .5)
			if r != null: hud.say(r.get("name", r.id), 2.5)
			return
	if not up: return
	for lv in level.levers:
		if abs(lv.x - p.x) < 1.0 and abs(lv.y - p.y) < 1.6 and not Prog.SV.doors.has(lv.id):
			Prog.SV.doors[lv.id] = 1; Prog.save_game(); hud.say("algo destrava, longe.", 2.5)
			var n := level.get_node_or_null("Lever_" + lv.id); if n: n.rotation.z = .5
			_icd = .5; return
	for b in level.benches:
		if abs(b.x - p.x) < 1.0 and abs(b.y - p.y) < 1.4:
			player.combat.hp = player.combat.max_hp(); Prog.save_game(p, player.combat.hp)
			hud.say("descansou. salvo.", 2.0); _icd = .8; return

func _locked(d: Dictionary) -> String:
	if d.has("lever") and not Prog.SV.doors.has(d.lever): return d.get("lockedMsg", "trancada.")
	if d.has("need") and not Prog.SV.doors.has("item_" + d.need): return d.get("lockedMsg", "trancada.")
	if d.has("boss") and d.id == "d_pen3" and not Prog.SV.doors.has("boss_moth"): return d.get("lockedMsg", "a pedra não se move.")
	if d.get("secret", false) and not Prog.SV.doors.has("k_secreto"): return "rachada. precisa de um golpe mais forte."
	return ""

func _on_died() -> void:
	hud.say("a madeira range. de volta ao último descanso.", 3.0)
	await get_tree().create_timer(.6).timeout
	var pos = Prog.SV.pos
	var sp := Vector3(float(level.L.player.spawnX), level.hp(float(level.L.player.spawnX)) + .05, 0) if pos == null else Vector3(float(pos[0]), float(pos[1]) + .05, 0)
	player.global_position = sp; player.velocity = Vector3.ZERO; player.combat.hp = player.combat.max_hp(); player.combat.soul = 0
	cam.snap()

func _process(_dt: float) -> void:
	frame += 1
	if args.has("shot") and frame == int(args.get("frames", "90")):
		var img := get_viewport().get_texture().get_image()
		img.save_png(args.shot)
		print("[broto] shot %s state=%s pos=%s anim=%s" % [args.shot, player.state_name(), player.global_position, player.cur_anim])
		_report()
		get_tree().quit()
