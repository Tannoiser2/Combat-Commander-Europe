## Effetti di setup data-driven delle regole speciali (SSR) applicabili al via:
## gettoni Obiettivo esclusi dal sacchetto e carte garantite in mano a inizio
## partita. Letti da scenario_effects.json; assenti = nessun effetto.
class_name ScenarioEffects
extends RefCounted

const PATH := "res://assets/scenarios/scenario_effects.json"

static var _data: Dictionary = {}
static var _loaded := false


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if d is Dictionary:
		_data = d


static func entry(num: int) -> Dictionary:
	_ensure()
	var e: Variant = _data.get(str(num), {})
	return e if e is Dictionary else {}


## Lettere dei gettoni Obiettivo da NON mettere nel sacchetto (7.3.2 / SSR).
static func exclude_chits(num: int) -> Array:
	var x: Variant = entry(num).get("exclude_chits", [])
	return x if x is Array else []


## Codici carta (es. "G-65") garantiti in mano al lato indicato ("axis"/"allies").
static func opening_cards(num: int, side: String) -> Array:
	var oc: Variant = entry(num).get("opening_cards", {})
	if not (oc is Dictionary):
		return []
	var c: Variant = oc.get(side, [])
	return c if c is Array else []


# ─── Modificatori di terreno/mappa (terrain_mods.json) ────────────────────────

const TERRAIN_PATH := "res://assets/scenarios/terrain_mods.json"
static var _terrain: Dictionary = {}
static var _terrain_loaded := false


static func _ensure_terrain() -> void:
	if _terrain_loaded:
		return
	_terrain_loaded = true
	var f := FileAccess.open(TERRAIN_PATH, FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if d is Dictionary:
		_terrain = d


static func terrain_mods(num: int) -> Dictionary:
	_ensure_terrain()
	var t: Variant = _terrain.get(str(num), {})
	return t if t is Dictionary else {}


## Ostacolo (Hindrance) aggiuntivo in OGNI esagono (nebbia, ecc.). 0 se assente.
static func global_hindrance(num: int) -> int:
	return int(terrain_mods(num).get("global_hindrance", 0))
