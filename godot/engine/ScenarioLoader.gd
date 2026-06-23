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

	# ─── Parametri ──────────────────────────────────────────────────────────
	state.scenario_number = num
	state.scenario_name = String(e.get("nome", "Scenario %d" % num))
	state.axis_nation = String(e.get("fazione_axis", "german"))
	state.allied_nation = String(e.get("fazione_allies", "russian"))
	state.sudden_death_space = int(e.get("sudden_death", 7))
	# Casella iniziale del segnalino Tempo (6.1.1: «di solito 0»). Campo opzionale
	# del catalogo per scenari che partono da una casella diversa (es. anno).
	state.time_marker = int(e.get("tempo_iniziale", 0))
	state.vp_tracker = int(e.get("vp_iniziali", 0))  # >0 Axis(GER), <0 Allied(RUS)
	var init_axis := String(e.get("iniziativa", "axis")) == "axis"
	state.initiative_holder = Domain.Faction.GERMAN if init_axis else Domain.Faction.RUSSIAN
	state.active_faction = state.initiative_holder

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


## Piazza le forze di un lato nelle sue caselle di setup.
static func _place_side(state: GameState, e: Dictionary, side: String, faction: int) -> void:
	var hexes := _setup_hexes(state, e, side)
	if hexes.is_empty():
		hexes.append(Vector2i(0, 0))
	# Nazione reale del lato → statistiche esatte (l'arte resta stand-in).
	var nat := UnitChart.nation_code(String(e.get("fazione_%s" % side, "")))
	var forces: Array = e.get("forze_%s" % side, [])
	var idx := 0
	var fox := 0
	var seq := 0
	for f in forces:
		var label := String(f.get("tipo", ""))
		var count := int(f.get("n", 1))
		var cat := UnitChart.category(label)
		if cat == UnitChart.Cat.SKIP:
			continue
		for k in count:
			if cat == UnitChart.Cat.FOXHOLE:
				var fh: GameState.HexData = state.hex_at(hexes[fox % hexes.size()].x, hexes[fox % hexes.size()].y)
				if fh:
					fh.has_foxhole = true
				fox += 1
				continue
			var pos: Vector2i = hexes[idx % hexes.size()]
			idx += 1
			var id := "%s-%d" % [Domain.FACTION_SHORT.get(faction, "U"), seq]
			seq += 1
			state.units[id] = UnitChart.build_unit(id, faction, label, pos.x, pos.y, nat)


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
