extends Node
## Progression autoload ("Prog"): XP/levels (web v16 curve, Nv 1..50), 3-branch skill tree + respec, save/load to user://.
signal changed
signal leveled(lv: int)
const LMAX := 50
var save_path := "user://broto_save.json"
# [id, branch, name, desc, max, reqLv, prereq]  (web TREE)
const TREE := [
	["forca", "c", "Força", "+15% de dano por nível", 3, 2, ""],
	["ritmo", "c", "Ritmo", "golpes 8% mais rápidos por nível", 3, 4, ""],
	["alcance", "c", "Alcance", "o galho alcança mais longe", 2, 6, ""],
	["carga", "c", "Ataque carregado", "segure e solte: quebra paredes rachadas", 1, 7, ""],
	["pogo", "c", "Quique", "golpe para baixo quica mais alto", 2, 9, "forca"],
	["lanca", "c", "Lança de Luz", "PODER (V/✺): projétil de luz que atravessa", 1, 10, ""],
	["impacto", "c", "Impacto", "PODER: ↓+V no ar — mergulho que explode ao cair", 1, 14, ""],
	["raizes", "c", "Raízes", "PODER: ↓+V no chão — raízes brotam à frente", 1, 18, ""],
	["eco", "c", "Eco", "quicar no inimigo dá alma extra", 1, 28, "pogo"],
	["furia", "c", "Fúria", "ataque carregado +50% de dano", 2, 20, "carga"],
	["pena", "m", "Pulo duplo", "pule de novo no ar", 1, 3, ""],
	["ar", "m", "Controle no ar", "vira mais rápido no ar", 2, 4, ""],
	["sopro", "m", "Investida", "Q/K/» — avanço rápido", 1, 5, ""],
	["corda", "m", "Mãos de corda", "na corda, recupera pulo duplo e investida", 1, 8, ""],
	["sopro2", "m", "Vento", "investida recarrega mais rápido", 2, 12, "sopro"],
	["leve", "m", "Pés leves", "queda mais lenta segurando pulo", 1, 22, "pena"],
	["vida", "v", "Máscara", "+1 vida", 3, 2, ""],
	["alma", "v", "Alma", "mais alma por golpe", 3, 4, ""],
	["foco", "v", "Foco", "cura mais rápido", 2, 6, ""],
	["luz", "v", "Luz mais forte", "o galho ilumina mais longe", 1, 10, ""],
	["folego", "v", "Fôlego", "mais tempo debaixo d'água", 1, 10, ""],
	["casca", "v", "Casca", "PODER: toque C/✚ — casca absorve o próximo golpe", 1, 12, ""],
	["enxame", "v", "Enxame", "PODER: ↑+V — vaga-lumes giram e ferem", 1, 24, ""],
	["espinhos", "v", "Espinhos", "ao ser ferido, espinhos ferem quem está perto", 1, 16, "vida"],
	["resina", "v", "Resina", "invulnerável por mais tempo após dano", 2, 20, "vida"],
	["raiz", "x", "Raiz Antiga", "capstone: +1 vida, +25% dano, alma em dobro", 1, 48, "*"],
]
const BRANCH := {"c": "⚔ Combate", "m": "➶ Movimento", "v": "✚ Vida/Alma", "x": "✦ Raiz"}
var SV := {}
func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--save="): save_path = a.trim_prefix("--save=")
	reset()
func reset() -> void:
	SV = {"xp": 0, "sp": 0, "tree": {}, "doors": {}, "pos": null, "hp": -1}
	changed.emit()

func XPC(l: int) -> int: return 0 if l <= 1 else int(round(70.0 * pow(l - 1, 1.55)))
func LVL() -> int:
	var l := 1
	while l < LMAX and SV.xp >= XPC(l + 1): l += 1
	return l
func add_xp(n: int) -> int:
	var old := LVL(); SV.xp += n; var lv := LVL()
	if lv > old: SV.sp += lv - old; leveled.emit(lv)
	changed.emit(); return lv - old

func row(k: String) -> Array:
	for t in TREE:
		if t[0] == k: return t
	return []
func rank(k: String) -> int: return int(SV.tree.get(k, 0))
func can(k: String) -> bool:
	var t := row(k)
	if t.is_empty() or SV.sp < 1 or rank(k) >= t[4] or LVL() < t[5]: return false
	if t[6] == "*":
		for b in ["c", "m", "v"]:
			var ok := false
			for x in TREE:
				if x[1] == b and rank(x[0]) > 0: ok = true
			if not ok: return false
	elif t[6] != "" and rank(t[6]) < 1: return false
	return true
func buy(k: String) -> bool:
	if not can(k): return false
	SV.sp -= 1; SV.tree[k] = rank(k) + 1; changed.emit(); save_game(); return true
func respec() -> void:
	var n := 0
	for k in SV.tree: n += int(SV.tree[k])
	SV.tree = {}; SV.sp += n; changed.emit(); save_game()

# derived modifiers (web applyUp)
func dmg_m() -> float: return (1.0 + .15 * rank("forca")) * (1.25 if rank("raiz") > 0 else 1.0)
func atk_m() -> float: return 1.0 - .08 * rank("ritmo")
func reach() -> float: return .25 * rank("alcance")
func pogo_m() -> float: return 1.0 + .08 * rank("pogo")
func air_m() -> float: return 1.0 + .25 * rank("ar")
func dash_m() -> float: return 1.0 - .2 * rank("sopro2")
func soul_add() -> int: return int((11 + 3 * rank("alma")) * (2 if rank("raiz") > 0 else 1))
func focus_t() -> float: return .9 - .2 * rank("foco")
func inv_add() -> float: return .25 * rank("resina")
func max_hp() -> int: return 3 + rank("vida") + rank("raiz")

func save_game(pos = null, hp := -1) -> void:
	if pos != null: SV.pos = [pos.x, pos.y]
	if hp >= 0: SV.hp = hp
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(SV)); f.close()
func load_game() -> bool:
	if not FileAccess.file_exists(save_path): return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(d) != TYPE_DICTIONARY: return false
	reset()
	for k in d: SV[k] = d[k]
	SV.xp = int(SV.xp); SV.sp = int(SV.sp)
	changed.emit(); return true
