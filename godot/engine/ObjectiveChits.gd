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


## Composizione dello scenario (7.3.2/7.3.3): pesca i chit APERTI e i chit
## SEGRETI di ciascun lato dallo STESSO sacchetto (senza rimpiazzo, meno gli
## esclusi da SSR) e li registra in `state.objective_chits` col proprietario.
## `spec` = { "open": ["T"] | ["?"] (casuale) | [], "axis": [...], "allies": [...] }.
## Le lettere esplicite vengono prese dal sacchetto se disponibili; "?" pesca a
## caso. Dopo la pesca ricalcola i valori PUBBLICI degli obiettivi.
## Restituisce le righe di log PUBBLICHE (i segreti non vi compaiono).
static func setup(state: GameState, spec: Dictionary, rng: RandomNumberGenerator, exclude: Array = []) -> Array:
	var lines: Array = []
	state.objective_chits.clear()
	state.chit_excluded = exclude.duplicate()
	state.chit_double_exit = false
	state.chit_double_elim = false
	state.chit_control_all = false
	if state.objectives.is_empty():
		recompute(state)
		return lines
	var bag: Array = []
	for c in CHITS:
		if not exclude.has(String(c["id"])):
			bag.append(c)
	var plan := [
		{ "who": -1, "list": spec.get("open", []) },
		{ "who": Domain.Faction.GERMAN, "list": spec.get("axis", []) },
		{ "who": Domain.Faction.RUSSIAN, "list": spec.get("allies", []) },
	]
	for p in plan:
		var who := int(p["who"])
		for want in p["list"]:
			var chit := _take(bag, String(want), rng)
			if chit.is_empty():
				continue
			# I chit "rule" (V/W/X) e R sono [open] per definizione: anche se
			# pescati come "segreti" di un lato, valgono in chiaro (7.3.2).
			var forced_open: bool = String(chit["type"]) == "rule" or String(chit["id"]) == "R"
			var owner := -1 if forced_open else who
			state.objective_chits.append({
				"letter": String(chit["id"]), "owner": owner, "revealed": owner == -1,
			})
			if owner == -1:
				lines.append("Chit Obiettivo [aperto]: %s" % _describe(chit))
			else:
				lines.append("%s pesca un chit Obiettivo SEGRETO." % Domain.FACTION_NAMES.get(owner, "?"))
	recompute(state)
	for o in state.objectives:
		if o.vp > 0:
			lines.append("Obiettivo #%d vale %d VP (chit aperti)" % [o.id, o.vp])
	return lines


## Prende dal sacchetto la lettera richiesta ("?" = una a caso). {} se impossibile.
static func _take(bag: Array, want: String, rng: RandomNumberGenerator) -> Dictionary:
	if bag.is_empty():
		return {}
	if want == "?" or want == "random":
		var bi := rng.randi_range(0, bag.size() - 1)
		var c: Dictionary = bag[bi]
		bag.remove_at(bi)
		return c
	for i in bag.size():
		if String(bag[i]["id"]) == want:
			var c2: Dictionary = bag[i]
			bag.remove_at(i)
			return c2
	return {}


## Ricalcola i valori degli obiettivi e i flag [open] dai chit registrati.
## `Objective.vp` = somma dei SOLI chit aperti/rivelati (valore pubblico, quello
## della traccia VP e della UI). I segreti si sommano solo a fine partita
## (vedi secret_balance).
static func recompute(state: GameState) -> void:
	for o in state.objectives:
		o.vp = 0
	state.chit_double_exit = false
	state.chit_double_elim = false
	state.chit_control_all = false
	for e in state.objective_chits:
		var chit := _find(String(e["letter"]))
		if chit.is_empty():
			continue
		match String(chit["type"]):
			"rule":
				match String(chit["rule"]):
					"double_exit": state.chit_double_exit = true
					"double_elim": state.chit_double_elim = true
					"control_all_sd": state.chit_control_all = true
			_:
				if bool(e["revealed"]):
					_add_value(state, chit)


## Bilancia VP dei chit SEGRETI non ancora rivelati (positiva = Germania), dati i
## controllori ATTUALI degli obiettivi: è la parte che si scopre a fine partita.
static func secret_balance(state: GameState) -> int:
	var bal := 0
	for e in state.objective_chits:
		if bool(e["revealed"]):
			continue
		var chit := _find(String(e["letter"]))
		if chit.is_empty() or String(chit["type"]) == "rule":
			continue
		for o in state.objectives:
			if not _applies_to(chit, o):
				continue
			if o.controller == Domain.Faction.GERMAN:
				bal += int(chit["vp"])
			elif o.controller == Domain.Faction.RUSSIAN:
				bal -= int(chit["vp"])
	return bal


## Rivela tutti i chit segreti (fine partita, 6.3.2) o quelli di una fazione.
## Restituisce le righe di log con la descrizione dei chit rivelati.
static func reveal_all(state: GameState, faction: int = -1) -> Array:
	var lines: Array = []
	for e in state.objective_chits:
		if bool(e["revealed"]) or (faction != -1 and int(e["owner"]) != faction):
			continue
		e["revealed"] = true
		var chit := _find(String(e["letter"]))
		lines.append("Rivelato chit segreto di %s: %s" % [
			Domain.FACTION_NAMES.get(int(e["owner"]), "?"),
			_describe(chit) if not chit.is_empty() else String(e["letter"])])
	recompute(state)
	return lines


## Estrae UN chit dal sacchetto RIMANENTE (senza rimpiazzo rispetto ai già
## pescati) e lo aggiunge APERTO — per gli eventi E65/E74. "" se sacchetto vuoto.
static func draw_one(state: GameState, rng: RandomNumberGenerator, lines: Array) -> String:
	if state.objectives.is_empty():
		return ""
	var used: Array = []
	for e in state.objective_chits:
		used.append(String(e["letter"]))
	var bag: Array = []
	for c in CHITS:
		var cid := String(c["id"])
		if not used.has(cid) and not state.chit_excluded.has(cid):
			bag.append(c)
	if bag.is_empty():
		lines.append("Sacchetto dei chit vuoto: nessuna pescata.")
		return ""
	var chit: Dictionary = bag[rng.randi_range(0, bag.size() - 1)]
	state.objective_chits.append({ "letter": String(chit["id"]), "owner": -1, "revealed": true })
	recompute(state)
	lines.append("Chit %s [aperto]: %s" % [chit["id"], _describe(chit)])
	return String(chit["id"])


## Aggiunge il chit con lettera `chit_id` come APERTO (utile per i test).
static func apply(state: GameState, chit_id: String, lines: Array) -> bool:
	var chit := _find(chit_id)
	if chit.is_empty():
		return false
	state.objective_chits.append({ "letter": chit_id, "owner": -1, "revealed": true })
	recompute(state)
	lines.append("Chit %s: %s" % [chit_id, _describe(chit)])
	return true


static func _find(chit_id: String) -> Dictionary:
	for c in CHITS:
		if String(c["id"]) == chit_id:
			return c
	return {}


static func _applies_to(chit: Dictionary, o: Objective) -> bool:
	match String(chit["type"]):
		"obj": return o.id == int(chit["target"])
		"all": return true
	return false


static func _add_value(state: GameState, chit: Dictionary) -> void:
	for o in state.objectives:
		if _applies_to(chit, o):
			o.vp += int(chit["vp"])


static func _describe(chit: Dictionary) -> String:
	match String(chit["type"]):
		"obj": return "%s — Obiettivo #%d +%d VP" % [chit["id"], int(chit["target"]), int(chit["vp"])]
		"all": return "%s — ogni Obiettivo +%d VP" % [chit["id"], int(chit["vp"])]
		"rule":
			match String(chit["rule"]):
				"double_exit": return "%s — VP d'uscita RADDOPPIATI" % chit["id"]
				"double_elim": return "%s — VP da eliminazione RADDOPPIATI" % chit["id"]
				"control_all_sd": return "%s — chi controlla TUTTI gli obiettivi vince (verificato prima di ogni Morte Subitanea)" % chit["id"]
	return String(chit.get("id", "?"))


