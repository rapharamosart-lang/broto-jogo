extends Node3D
## Boots the level, player, camera, leaf and touch UI. Test hooks via user args (after `--`):
##   --x=39 --y=2        spawn position     --shot=res://shots/a.png --frames=90   save a frame and quit
##   --bot=right,run     hold actions        --botjump=0.5,1.2   tap jump at these times (s)
##   --quit=5            quit after N seconds (smoke test)     --touch   show touch controls
@onready var level: Node3D = $Level
@onready var player: CharacterBody3D = $Player
@onready var cam: Camera3D = $Camera
var args := {}
var frame := 0
var tsec := 0.0
func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1); args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	level.load_level()
	player.init()
	var x := float(args.get("x", level.L.player.spawnX))
	var y := float(args.get("y", level.hp(x) + .05))
	player.global_position = Vector3(x, y, 0)
	cam.target = player; cam.snap()
	var leaf := preload("res://scripts/leaf.gd").new(); add_child(leaf); leaf.setup(level, player)
	if args.has("bot"):
		player.bot = {}
		for a in args.bot.split(","): player.bot[a] = true
	print("[broto] ready x=%.1f y=%.2f renderer=%s" % [x, y, RenderingServer.get_current_rendering_method()])
func _physics_process(dt: float) -> void:
	tsec += dt
	if args.has("botjump") and player.bot != null:
		var on := false
		for s in args.botjump.split(","):
			if tsec > float(s) and tsec < float(s) + .25: on = true
		player.bot["jump"] = on
	if args.has("botdash") and player.bot != null:
		player.bot["dash"] = abs(tsec - float(args.botdash)) < .05
	if args.has("botdown") and player.bot != null:
		player.bot["down"] = abs(tsec - float(args.botdown)) < .1
	if args.has("quit") and tsec > float(args.quit):
		print("[broto] state=%s pos=%s" % [player.state_name(), player.global_position])
		if args.has("probe"): print("[broto] probe ", player.probe(1, 6.0), " wall=", player.is_on_wall())
		get_tree().quit()
func _process(_dt: float) -> void:
	frame += 1
	if args.has("shot") and frame == int(args.get("frames", "90")):
		var img := get_viewport().get_texture().get_image()
		img.save_png(args.shot)
		print("[broto] shot %s state=%s pos=%s anim=%s" % [args.shot, player.state_name(), player.global_position, player.cur_anim])
		get_tree().quit()
