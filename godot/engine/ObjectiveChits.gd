## Chit Obiettivo (7.3.2): all'inizio dello scenario si estraggono dei "chit" che
## assegnano valori in VP agli obiettivi sulla mappa. Più chit possono cadere sullo
## stesso obiettivo: i valori si SOMMANO (esempio del regolamento: i chit C+G+K
## sull'Obiettivo #3 lo rendono da 1+2+3 = 6 VP).
##
## Mix REALE dei 22 chit (A–X, senza I/O). Tre tipi:
##  · "obj"  → assegna `vp` all'obiettivo numerato `target`;
##  · "all"  → assegna `vp` a OGNI obiettivo (chit S/T/U);
##  · "rule" → chit "[open]" con effetto globale (V/W/X).
class_name ObjectiveChits
extends RefCounted

const CHITS := [
	{ "id": "A", "type": "obj", "target": 1, "vp": 1 },
	{ "id": "B", "type": "obj", "target": 2, "vp": 1 },
	{ "id": "C", "type": "obj", "target": 3, "vp": 1 },
	{ "id": "D", "type": "obj", "target": 4, "vp": 1 },
	{ "id": "E", "type": "obj", "target": 5, "vp": 1 },
	{ "id": "F", "type": "obj", "target": 2, "vp": 2 },
	{ "id": "G", "type": "obj", "target": 3, "vp": 2 },
	{ "id": "H", "type": "obj", "target": 4, "vp": 2 },
	{ "id": "J", "type": "obj", "target": 5, "vp": 2 },
	{ "id": "K", "type": "obj", "target": 3, "vp": 3 },
	{ "id": "L", "type": "obj", "target": 4, "vp": 3 },
	{ "id": "M", "type": "obj", "target": 5, "vp": 3 },
	{ "id": "N", "type": "obj", "target": 4, "vp": 4 },
	{ "id": "P", "type": "obj", "target": 5, "vp": 4 },
	{ "id": "Q", "type": "obj", "target": 5, "vp": 5 },
	{ "id": "R", "type": "obj", "target": 5, "vp": 10 },   # [open]
	{ "id": "S", "type": "all", "vp": 1 },
	{ "id": "T", "type": "all", "vp": 2 },
	{ "id": "U", "type": "all", "vp": 3 },
	{ "id": "V", "type": "rule", "rule": "control_all_sd" },  # [open]
	{ "id": "W", "type": "rule", "rule": "double_exit" },     # [open]
	{ "id": "X", "type": "rule", "rule": "double_elim" },     # [open]
]


## Estrae `count` chit SENZA rimpiazzo dal sacchetto da 22 e li applica, azzerando
## prima i VP stampati. No-op se non ci sono obiettivi o `count` <= 0.
## Restituisce { "drawn": Array[String] (lettere), "lines": Array[String] }.
static func assign(state: GameState, count: int, rng: RandomNumberGenerator, exclude: Array = []) -> Dictionary:
	var out := { "drawn": [], "lines": [] }
	if count <= 0 or state.objectives.is_empty():
		return out
	for o in state.objectives:
		o.vp = 0
	# Alcuni scenari escludono certi gettoni Obiettivo dal sacchetto (SSR).
	var bag: Array = []
	for c in CHITS:
		if not exclude.has(String(c["id"])):
			bag.append(c)
	var drawn: Array = []
	var lines: Array = []
	var n: int = mini(count, bag.size())
	for _i in n:
		var bi := rng.randi_range(0, bag.size() - 1)
		var chit: Dictionary = bag[bi]
		bag.remove_at(bi)
		drawn.append(String(chit["id"]))
		_apply_chit(state, chit, lines)
	# Riepilogo VP per obiettivo.
	for o in state.objectives:
		lines.append("Obiettivo #%d -> %d VP" % [o.id, o.vp])
	out["drawn"] = drawn
	out["lines"] = lines
	return out


## Estrae UN solo chit casuale (con rimpiazzo) e lo applica — per gli eventi che
## pescano un chit aggiuntivo in partita (E65/E74). Restituisce la lettera.
static func draw_one(state: GameState, rng: RandomNumberGenerator, lines: Array) -> String:
	if state.objectives.is_empty():
		return ""
	var chit: Dictionary = CHITS[rng.randi_range(0, CHITS.size() - 1)]
	_apply_chit(state, chit, lines)
	return String(chit["id"])


## Applica il chit con lettera `chit_id` (utile per i test). True se esiste.
static func apply(state: GameState, chit_id: String, lines: Array) -> bool:
	for c in CHITS:
		if String(c["id"]) == chit_id:
			_apply_chit(state, c, lines)
			return true
	return false


static func _apply_chit(state: GameState, chit: Dictionary, lines: Array) -> void:
	match String(chit["type"]):
		"obj":
			var target := int(chit["target"])
			var vp := int(chit["vp"])
			var found := false
			for o in state.objectives:
				if o.id == target:
					o.vp += vp
					found = true
			if found:
				lines.append("Chit %s: Obiettivo #%d +%d VP" % [chit["id"], target, vp])
			else:
				lines.append("Chit %s: Obiettivo #%d non sulla mappa (nessun effetto)" % [chit["id"], target])
		"all":
			var vp := int(chit["vp"])
			for o in state.objectives:
				o.vp += vp
			lines.append("Chit %s: ogni Obiettivo +%d VP" % [chit["id"], vp])
		"rule":
			match String(chit["rule"]):
				"double_exit":
					state.chit_double_exit = true
					lines.append("Chit %s [open]: VP RADDOPPIATI per le unità che escono dal bordo nemico." % chit["id"])
				"double_elim":
					state.chit_double_elim = true
					lines.append("Chit %s [open]: VP RADDOPPIATI per le unità eliminate." % chit["id"])
				"control_all_sd":
					# In questa implementazione controllare TUTTI gli obiettivi è già
					# una vittoria immediata (_check_end_conditions), quindi il chit V
					# è di fatto sempre attivo: lo si segnala soltanto.
					lines.append("Chit %s [open]: controllare tutti gli obiettivi è una vittoria immediata." % chit["id"])
