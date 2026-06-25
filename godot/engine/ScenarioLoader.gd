## Loader generico degli scenari (data-driven).
##
## Legge assets/scenarios/catalog.json (catalogo dei 24 scenari + ordini di
## battaglia, recuperati dalla versione precedente) e popola uno GameState:
## mappa, parametri (ordini, sudden death, VP, iniziativa) e forze piazzate
## nelle zone di setup. Le statistiche unità vengono da UnitChart.
##
## Stand-in fazioni: Axis → Tedeschi, Allied → Russi (finché non ci sono mazzi
## e artwork delle singole nazioni).
class_name ScenarioLoader
extends RefCounted

const CATALOG_PATH := "res://assets/scenarios/catalog.json"

static var _catalog: Array = []


## Carica (una volta) il catalogo. Restituisce l'array di scenari.
static func catalog() -> Array:
	if _catalog.is_empty():
		var f := FileAccess.open(CATALOG_PATH, FileAccess.READ)
		if f == null:
			push_error("Catalogo scenari non trovato: " + CATALOG_PATH)
			return []
		var data: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if data is Array:
			_catalog = data
	return _catalog


## Voce di catalogo per numero scenario (o {} se assente).
static func entry(num: int) -> Dictionary:
	for s in catalog():
		if int(s.get("numero", 0)) == num:
			return s
	return {}


## Popola lo stato con lo scenario `num`. Restituisce true se riuscito.
static func setup(state: GameState, num: int) -> bool:
	var e := entry(num)
	if e.is_empty():
		push_error("Scenario %d non nel catalogo" % num)
		return false

	# ─── Mappa (con i suoi obiettivi) ───────────────────────────────────────
	var map_id := String(e.get("mappa", "map1"))
	if not MapLoader.load_into(state, "res://assets/maps/%s.json" % map_id):
		return false

	# Chit Obiettivo (7.3.2): se lo scenario li richiede, i VP degli obiettivi
	# vengono estratti a sorte (cumulativi) sostituendo quelli stampati sulla mappa.
	var chits := int(e.get("objective_chits", 0))
	if chits > 0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		ObjectiveChits.assign(state, chits, rng)

	# ─── Parametri ──────────────────────────────────────────────────────────
	state.scenario_number = num
	state.scenario_name = String(e.get("nome", "Scenario %d" % num))
	state.axis_nation = String(e.get("fazione_axis", "german"))
	state.allied_nation = String(e.get("fazione_allies", "russian"))
	state.sudden_death_space = int(e.get("sudden_death", 7))
	# Casella iniziale del segnalino Tempo (6.1.1: «di solito 0»). Campo opzionale
	# del catalogo per scenari che partono da una casella diversa (es. anno).
	state.time_marker = int(e.get("tempo_iniziale", 0))
	# VP iniziali come bonus non-obiettivo (così non vengono sovrascritti dal
	# ricalcolo degli obiettivi). >0 Axis(GER), <0 Allied(RUS).
	state.bonus_vp = int(e.get("vp_iniziali", 0))
	state.vp_tracker = state.bonus_vp
	var init_axis := String(e.get("iniziativa", "axis")) == "axis"
	state.initiative_holder = Domain.Faction.GERMAN if init_axis else Domain.Faction.RUSSIAN
	state.active_faction = state.initiative_holder
	# Difensore (6.1.2): il lato con postura "defend"; -1 se nessuno difende.
	if String(e.get("posture_axis", "")) == "defend":
		state.defender_faction = Domain.Faction.GERMAN
	elif String(e.get("posture_allies", "")) == "defend":
		state.defender_faction = Domain.Faction.RUSSIAN
	else:
		state.defender_faction = -1

	# Mano per fazione (qualità truppe) e soglie di resa (Casualty Track).
	# Stand-in: axis → Tedeschi (GERMAN), allies → Russi (RUSSIAN).
	state.hand_size[Domain.Faction.GERMAN] = int(e.get("mano_axis", Cards.HAND_SIZE))
	state.hand_size[Domain.Faction.RUSSIAN] = int(e.get("mano_allies", Cards.HAND_SIZE))
	state.surrender_threshold[Domain.Faction.GERMAN] = int(e.get("resa_axis", 0))
	state.surrender_threshold[Domain.Faction.RUSSIAN] = int(e.get("resa_allies", 0))

	# Ordini: max_orders è dell'umano, ai_max_orders dell'IA.
	var ord_axis := int(e.get("ordini_axis", 2))
	var ord_allies := int(e.get("ordini_allies", 2))
	if state.human_faction == Domain.Faction.GERMAN:
		state.max_orders = ord_axis
		state.ai_max_orders = ord_allies
	else:
		state.max_orders = ord_allies
		state.ai_max_orders = ord_axis

	# ─── Forze ──────────────────────────────────────────────────────────────
	state.units.clear()
	_place_side(state, e, "axis", Domain.Faction.GERMAN)
	_place_side(state, e, "allies", Domain.Faction.RUSSIAN)
	return true


## Piazza le forze di un lato nelle sue caselle di setup. Le squadre/team sono
## distribuite nella zona; i leader e le armi vanno negli stessi esagoni degli
## uomini, così ogni arma parte «posseduta» da un'unità (11.2) e nessuna resta a
## terra (niente anelli gialli al via).
static func _place_side(state: GameState, e: Dictionary, side: String, faction: int) -> void:
	var hexes := _setup_hexes(state, e, side)
	if hexes.is_empty():
		hexes.append(Vector2i(0, 0))
	# Nazione reale del lato → statistiche esatte (l'arte resta stand-in).
	var nat := UnitChart.nation_code(String(e.get("fazione_%s" % side, "")))
	# Suddividi le forze per categoria (l'ordine nel catalogo non conta).
	var squads: Array = []
	var leaders: Array = []
	var weapons: Array = []
	var fox := 0
	for f in e.get("forze_%s" % side, []):
		var label := String(f.get("tipo", ""))
		var count := int(f.get("n", 1))
		match UnitChart.category(label):
			UnitChart.Cat.SKIP:
				continue
			UnitChart.Cat.FOXHOLE:
				fox += count
			UnitChart.Cat.LEADER:
				for k in count: leaders.append(label)
			UnitChart.Cat.WEAPON:
				for k in count: weapons.append(label)
			_:
				for k in count: squads.append(label)

	var seq := 0
	var man_hexes: Array = []  # esagoni con almeno un uomo (per leader e armi)
	# Squadre/team: una per esagono lungo la zona di schieramento.
	for i in squads.size():
		var pos: Vector2i = hexes[i % hexes.size()]
		var id := "%s-%d" % [Domain.FACTION_SHORT.get(faction, "U"), seq]
		seq += 1
		state.units[id] = UnitChart.build_unit(id, faction, squads[i], pos.x, pos.y, nat)
		man_hexes.append(pos)
	if man_hexes.is_empty():
		man_hexes = hexes.duplicate()
	# Leader: insieme alle squadre (uno per gruppo, a giro).
	for i in leaders.size():
		var pos: Vector2i = man_hexes[i % man_hexes.size()]
		var id := "%s-%d" % [Domain.FACTION_SHORT.get(faction, "U"), seq]
		seq += 1
		state.units[id] = UnitChart.build_unit(id, faction, leaders[i], pos.x, pos.y, nat)
	# Armi: negli esagoni con uomini → vengono raccolte da una squadra (11.2).
	for i in weapons.size():
		var pos: Vector2i = man_hexes[i % man_hexes.size()]
		var id := "%s-%d" % [Domain.FACTION_SHORT.get(faction, "U"), seq]
		seq += 1
		state.units[id] = UnitChart.build_unit(id, faction, weapons[i], pos.x, pos.y, nat)
	# Buche.
	for i in fox:
		var hp: Vector2i = hexes[i % hexes.size()]
		var fh: GameState.HexData = state.hex_at(hp.x, hp.y)
		if fh:
			fh.has_foxhole = true


## Caselle di setup di un lato: ancore (in/adiacenti) o bordo+profondità.
static func _setup_hexes(state: GameState, e: Dictionary, side: String) -> Array:
	var anchors: Array = e.get("setup_%s_anchors" % side, [])
	var out: Array = []
	var seen := {}
	if not anchors.is_empty():
		for lbl in anchors:
			var qr := Domain.label_to_qr(String(lbl))
			_add_hex(state, out, seen, qr.x, qr.y)
			for d in _dirs(qr.x):
				_add_hex(state, out, seen, qr.x + d.x, qr.y + d.y)
		return out
	# Bordo: Axis a Est (colonne destre), Allied a Ovest (colonne sinistre).
	# Profondità della zona di schieramento per lato (dalle schede scenario).
	var depth := maxi(1, int(e.get("setup_%s_depth" % side, 3)))
	if side == "axis":
		for q in range(maxi(0, state.map_cols - depth), state.map_cols):
			for r in state.map_rows:
				_add_hex(state, out, seen, q, r)
	else:
		for q in mini(depth, state.map_cols):
			for r in state.map_rows:
				_add_hex(state, out, seen, q, r)
	return out


static func _add_hex(state: GameState, out: Array, seen: Dictionary, q: int, r: int) -> void:
	if q < 0 or r < 0 or q >= state.map_cols or r >= state.map_rows:
		return
	var key := "%d,%d" % [q, r]
	if seen.has(key):
		return
	seen[key] = true
	out.append(Vector2i(q, r))


static func _dirs(q: int) -> Array:
	return Domain.HEX_DIRS_ODD if (q % 2) == 1 else Domain.HEX_DIRS_EVEN
