## Stato completo della partita di Combat Commander: Europe.
## La spina dorsale: ogni regola legge e scrive questo oggetto.
## RefCounted = dati puri, niente grafica.
class_name GameState
extends RefCounted


# ─── Mappa ───────────────────────────────────────────────────────────────────

class HexData:
	var terrain: int        # Domain.TerrainType
	var elevation: int = 0
	var objective_id: int = -1  # -1 = nessun obiettivo
	var has_road: bool = false  # sovrapposizione strada

	func _init(p_terrain: int, p_elev: int = 0) -> void:
		terrain = p_terrain
		elevation = p_elev

## Griglia: chiave "q,r" → HexData
var hexes: Dictionary = {}
var map_cols: int = 15
var map_rows: int = 10

## Lati di esagono: ogni voce { "a": Vector2i, "b": Vector2i, "feature": int }
var side_features: Array[Dictionary] = []


# ─── Unità ───────────────────────────────────────────────────────────────────

## Tutte le unità in gioco: chiave = unit.id
var units: Dictionary = {}


# ─── Obiettivi ───────────────────────────────────────────────────────────────

var objectives: Array[Objective] = []


# ─── Carte ───────────────────────────────────────────────────────────────────

var german_deck: Array[Card] = []
var german_discard: Array[Card] = []
var german_hand: Array[Card] = []

var russian_deck: Array[Card] = []
var russian_discard: Array[Card] = []
var russian_hand: Array[Card] = []


# ─── Turno e fase ────────────────────────────────────────────────────────────

var phase: int = Domain.Phase.PLAYER_TURN
var active_faction: int = Domain.Faction.GERMAN
var human_faction: int = Domain.Faction.GERMAN
var turn_number: int = 1
var order_count: int = 0
var max_orders: int = 2
var ai_max_orders: int = 2  ## Ordini giocati dall'IA nel suo turno


# ─── Traccia del tempo ────────────────────────────────────────────────────────

var time_marker: int = 2
var sudden_death_space: int = 7


# ─── Punti Vittoria ──────────────────────────────────────────────────────────

var vp_tracker: int = 0  ## >0 Germania in vantaggio, <0 Russia


# ─── Iniziativa ──────────────────────────────────────────────────────────────

var initiative_holder: int = Domain.Faction.GERMAN


# ─── Selezione UI ────────────────────────────────────────────────────────────

var selected_unit_id: String = ""
var selected_card_index: int = -1
var highlighted_hexes: Array[String] = []


# ─── Ordine in corso ─────────────────────────────────────────────────────────

## Domain.OrderType dell'ordine attualmente in esecuzione (-1 = nessuno).
## Determina come la mappa interpreta i click (movimento / fuoco / avanzata).
var current_order: int = -1


# ─── Movimento passo per passo ───────────────────────────────────────────────

var moving_unit_id: String = ""
var moving_remaining_mp: int = 0
var moving_card_index: int = -1


# ─── Log ─────────────────────────────────────────────────────────────────────

var log: Array[String] = []
var last_ai_action: String = ""


# ─── Metodi di accesso ───────────────────────────────────────────────────────

static func hex_key(q: int, r: int) -> String:
	return "%d,%d" % [q, r]


func hex_at(q: int, r: int) -> HexData:
	return hexes.get(hex_key(q, r))


func unit_by_id(id: String) -> Unit:
	return units.get(id)


func units_at(q: int, r: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for u in units.values():
		if u.q == q and u.r == r:
			result.append(u)
	return result


func men_at(q: int, r: int) -> Array[Unit]:
	return units_at(q, r).filter(func(u): return u.is_man())


func units_of(faction: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for u in units.values():
		if u.faction == faction:
			result.append(u)
	return result


## Uomini rotti (lato rovesciato) di una fazione — bersagli di Recupero e Rotta.
func broken_men_of(faction: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for u in units.values():
		if u.faction == faction and u.is_man() and not u.efficient:
			result.append(u)
	return result


func hand_of(faction: int) -> Array[Card]:
	return german_hand if faction == Domain.Faction.GERMAN else russian_hand


func objective_at(q: int, r: int) -> Objective:
	for o in objectives:
		if o.q == q and o.r == r:
			return o
	return null


func add_log(msg: String) -> void:
	log.push_front(msg)
	if log.size() > 50:
		log.resize(50)
