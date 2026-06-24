## Salvataggio/caricamento della partita.
##
## Serializza l'intero GameState su un file JSON (`user://`) e lo ricostruisce.
## Tutto ciò che serve a riprendere la partita è incluso: mappa (terreno + lati +
## taratura), unità, obiettivi, mazzi/mani/scarti, tracce (tempo/VP/perdite/resa)
## e parametri di scenario. Le selezioni UI e il movimento in corso non si
## salvano (si azzerano al caricamento).
class_name SaveGame
extends RefCounted

const SAVE_PATH := "user://savegame.json"
const VERSION := 1


# ─── API ──────────────────────────────────────────────────────────────────────

static func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


## Salva lo stato su `path`. Restituisce true se riuscito.
static func save_state(state: GameState, path: String = SAVE_PATH) -> bool:
	if state == null:
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Salvataggio: impossibile aprire %s" % path)
		return false
	f.store_string(JSON.stringify(_state_to_dict(state)))
	f.close()
	return true


## Carica lo stato da `path`. Restituisce il GameState, o null se assente/non valido.
static func load_state(path: String = SAVE_PATH) -> GameState:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary):
		push_error("Salvataggio non valido: %s" % path)
		return null
	return _state_from_dict(data)


# ─── Serializzazione ──────────────────────────────────────────────────────────

static func _state_to_dict(s: GameState) -> Dictionary:
	var hexes := {}
	for key in s.hexes:
		var h: GameState.HexData = s.hexes[key]
		hexes[key] = {
			"terrain": h.terrain, "elevation": h.elevation, "objective_id": h.objective_id,
			"road": h.has_road, "trail": h.has_trail, "railway": h.has_railway,
			"foxhole": h.has_foxhole, "smoke": h.has_smoke, "fort": h.fortification,
			"blaze": h.has_blaze,
		}
	var sides := []
	for sf in s.side_features:
		var a: Vector2i = sf["a"]
		var b: Vector2i = sf["b"]
		sides.append({ "a": [a.x, a.y], "b": [b.x, b.y], "feature": int(sf["feature"]) })
	var units := []
	for u in s.units.values():
		units.append(_unit_to_dict(u))
	var objectives := []
	for o in s.objectives:
		objectives.append(_objective_to_dict(o))
	return {
		"version": VERSION,
		# Mappa
		"map_cols": s.map_cols, "map_rows": s.map_rows, "map_image": s.map_image,
		"cal_hex": s.cal_hex, "cal_ox": s.cal_ox, "cal_oy": s.cal_oy,
		"hexes": hexes, "side_features": sides,
		# Scenario / fazioni
		"scenario_number": s.scenario_number, "scenario_name": s.scenario_name,
		"axis_nation": s.axis_nation, "allied_nation": s.allied_nation,
		"human_faction": s.human_faction, "active_faction": s.active_faction,
		"initiative_holder": s.initiative_holder,
		# Turno / tempo / VP
		"phase": s.phase, "turn_number": s.turn_number, "order_count": s.order_count,
		"max_orders": s.max_orders, "ai_max_orders": s.ai_max_orders,
		"time_marker": s.time_marker, "sudden_death_space": s.sudden_death_space,
		"vp_tracker": s.vp_tracker, "bonus_vp": s.bonus_vp,
		# Per-fazione
		"hand_size": _faction_dict(s.hand_size),
		"casualties": _faction_dict(s.casualties),
		"surrender_threshold": _faction_dict(s.surrender_threshold),
		# Unità / obiettivi
		"units": units,
		"objectives": objectives,
		# Carte (6 pile)
		"german_deck": _cards_to(s.german_deck),
		"german_discard": _cards_to(s.german_discard),
		"german_hand": _cards_to(s.german_hand),
		"russian_deck": _cards_to(s.russian_deck),
		"russian_discard": _cards_to(s.russian_discard),
		"russian_hand": _cards_to(s.russian_hand),
		"log": s.log,
	}


static func _state_from_dict(d: Dictionary) -> GameState:
	var s := GameState.new()
	s.map_cols = int(d.get("map_cols", 15)); s.map_rows = int(d.get("map_rows", 10))
	s.map_image = String(d.get("map_image", "map1"))
	s.cal_hex = float(d.get("cal_hex", 59.2)); s.cal_ox = float(d.get("cal_ox", 129.0)); s.cal_oy = float(d.get("cal_oy", 69.0))
	s.hexes = {}
	for key in d.get("hexes", {}):
		var hd: Dictionary = d["hexes"][key]
		var h := GameState.HexData.new(int(hd.get("terrain", 0)), int(hd.get("elevation", 0)))
		h.objective_id = int(hd.get("objective_id", -1))
		h.has_road = bool(hd.get("road", false)); h.has_trail = bool(hd.get("trail", false))
		h.has_railway = bool(hd.get("railway", false)); h.has_foxhole = bool(hd.get("foxhole", false))
		h.has_smoke = bool(hd.get("smoke", false))
		h.fortification = int(hd.get("fort", 0))
		h.has_blaze = bool(hd.get("blaze", false))
		s.hexes[key] = h
	var sides: Array[Dictionary] = []
	for sf in d.get("side_features", []):
		sides.append({ "a": Vector2i(int(sf["a"][0]), int(sf["a"][1])),
			"b": Vector2i(int(sf["b"][0]), int(sf["b"][1])), "feature": int(sf["feature"]) })
	s.side_features = sides

	s.scenario_number = int(d.get("scenario_number", 1)); s.scenario_name = String(d.get("scenario_name", ""))
	s.axis_nation = String(d.get("axis_nation", "german")); s.allied_nation = String(d.get("allied_nation", "russian"))
	s.human_faction = int(d.get("human_faction", 0)); s.active_faction = int(d.get("active_faction", 0))
	s.initiative_holder = int(d.get("initiative_holder", 0))
	s.phase = int(d.get("phase", Domain.Phase.PLAYER_TURN)); s.turn_number = int(d.get("turn_number", 1))
	s.order_count = int(d.get("order_count", 0)); s.max_orders = int(d.get("max_orders", 2)); s.ai_max_orders = int(d.get("ai_max_orders", 2))
	s.time_marker = int(d.get("time_marker", 0)); s.sudden_death_space = int(d.get("sudden_death_space", 7))
	s.vp_tracker = int(d.get("vp_tracker", 0)); s.bonus_vp = int(d.get("bonus_vp", 0))
	s.hand_size = _faction_dict_from(d.get("hand_size", {}), 4)
	s.casualties = _faction_dict_from(d.get("casualties", {}), 0)
	s.surrender_threshold = _faction_dict_from(d.get("surrender_threshold", {}), 0)

	for ud in d.get("units", []):
		var u := _unit_from_dict(ud)
		s.units[u.id] = u
	var objs: Array[Objective] = []
	for od in d.get("objectives", []):
		objs.append(_objective_from_dict(od))
	s.objectives = objs

	s.german_deck = _cards_from(d.get("german_deck", []))
	s.german_discard = _cards_from(d.get("german_discard", []))
	s.german_hand = _cards_from(d.get("german_hand", []))
	s.russian_deck = _cards_from(d.get("russian_deck", []))
	s.russian_discard = _cards_from(d.get("russian_discard", []))
	s.russian_hand = _cards_from(d.get("russian_hand", []))
	for line in d.get("log", []):
		s.log.append(String(line))
	return s


# ─── Helper per tipo ──────────────────────────────────────────────────────────

static func _faction_dict(dd: Dictionary) -> Dictionary:
	return { "german": int(dd.get(Domain.Faction.GERMAN, 0)), "russian": int(dd.get(Domain.Faction.RUSSIAN, 0)) }


static func _faction_dict_from(dd: Dictionary, deflt: int) -> Dictionary:
	return {
		Domain.Faction.GERMAN: int(dd.get("german", deflt)),
		Domain.Faction.RUSSIAN: int(dd.get("russian", deflt)),
	}


static func _unit_to_dict(u: Unit) -> Dictionary:
	return {
		"id": u.id, "faction": u.faction, "type": u.type, "class": u.unit_class, "name": u.unit_name,
		"art": u.art_name, "nation_art": u.nation_art,
		"fp": u.fp, "fp_boxed": u.fp_boxed, "range": u.range, "range_boxed": u.range_boxed,
		"move": u.move, "morale": u.morale, "command": u.command, "move_penalty": u.move_penalty,
		"ordnance": u.ordnance, "min_range": u.min_range, "q": u.q, "r": u.r,
		"efficient": u.efficient, "suppressed": u.suppressed, "activated": u.activated,
		"veteran": u.veteran, "concealed": u.concealed,
	}


static func _unit_from_dict(d: Dictionary) -> Unit:
	var u := Unit.new(String(d["id"]), int(d["faction"]), int(d["type"]), int(d["class"]), String(d.get("name", "")))
	u.art_name = String(d.get("art", "")); u.nation_art = String(d.get("nation_art", ""))
	u.fp = int(d.get("fp", 0)); u.fp_boxed = bool(d.get("fp_boxed", false))
	u.range = int(d.get("range", 0)); u.range_boxed = bool(d.get("range_boxed", false))
	u.move = int(d.get("move", 4)); u.morale = int(d.get("morale", 7))
	u.command = int(d.get("command", 0)); u.move_penalty = int(d.get("move_penalty", 0))
	u.ordnance = bool(d.get("ordnance", false)); u.min_range = int(d.get("min_range", 0))
	u.q = int(d.get("q", 0)); u.r = int(d.get("r", 0))
	u.efficient = bool(d.get("efficient", true)); u.suppressed = bool(d.get("suppressed", false))
	u.activated = bool(d.get("activated", false)); u.veteran = bool(d.get("veteran", false))
	u.concealed = bool(d.get("concealed", false))
	return u


static func _objective_to_dict(o: Objective) -> Dictionary:
	return { "id": o.id, "q": o.q, "r": o.r, "vp": o.vp, "secret": o.secret, "controller": o.controller }


static func _objective_from_dict(d: Dictionary) -> Objective:
	var o := Objective.new(int(d["id"]), int(d["q"]), int(d["r"]), int(d.get("vp", 0)))
	o.secret = bool(d.get("secret", false)); o.controller = int(d.get("controller", -1))
	return o


static func _card_to_dict(c: Card) -> Dictionary:
	return {
		"id": c.id, "faction": c.faction, "number": c.number, "order": c.order,
		"order_label": c.order_label, "order_count": c.order_count,
		"action": c.action_name, "event": c.event_name,
		"hex_label": c.random_hex_label, "hex_value": c.random_hex_value,
		"white": c.dice_white, "red": c.dice_red, "consequence": c.consequence,
	}


static func _card_from_dict(d: Dictionary) -> Card:
	var c := Card.new()
	c.id = String(d.get("id", "")); c.faction = int(d.get("faction", 0)); c.number = int(d.get("number", 0))
	c.order = int(d.get("order", Domain.OrderType.PASS)); c.order_label = String(d.get("order_label", ""))
	c.order_count = int(d.get("order_count", 1)); c.action_name = String(d.get("action", ""))
	c.event_name = String(d.get("event", "")); c.random_hex_label = String(d.get("hex_label", ""))
	c.random_hex_value = int(d.get("hex_value", 0)); c.dice_white = int(d.get("white", 1))
	c.dice_red = int(d.get("red", 1)); c.consequence = String(d.get("consequence", ""))
	return c


static func _cards_from(arr: Array) -> Array[Card]:
	var out: Array[Card] = []
	for cd in arr:
		out.append(_card_from_dict(cd))
	return out


static func _cards_to(cards: Array) -> Array:
	var out := []
	for c in cards:
		out.append(_card_to_dict(c))
	return out
