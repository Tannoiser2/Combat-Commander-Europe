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
	var has_road: bool = false     # sovrapposizione strada
	var has_trail: bool = false    # sentiero (tariffa strada in movimento)
	var has_railway: bool = false  # ferrovia (tariffa strada in movimento)
	var has_foxhole: bool = false  # buca/trincea (Trincerarsi): +3 copertura
	var has_smoke: bool = false    # fumo (Granate Fumogene): hindrance

	func _init(p_terrain: int, p_elev: int = 0) -> void:
		terrain = p_terrain
		elevation = p_elev

## Griglia: chiave "q,r" → HexData
var hexes: Dictionary = {}
var map_cols: int = 15
var map_rows: int = 10

## Visualizzazione mappa: id immagine (es. "map1") e taratura griglia dal JSON
## (`_calib`), in pixel dell'immagine a piena risoluzione.
var map_image: String = "map1"
var cal_hex: float = 59.2
var cal_ox: float = 129.0
var cal_oy: float = 69.0

## Lati di esagono: ogni voce { "a": Vector2i, "b": Vector2i, "feature": int }
var side_features: Array[Dictionary] = []


# ─── Unità ───────────────────────────────────────────────────────────────────

## Tutte le unità in gioco: chiave = unit.id
var units: Dictionary = {}


# ─── Resa / Casualty Track (regolamento 4.2 / 6.3) ────────────────────────────

## Uomini eliminati per fazione (squadre/team/leader; le armi vanno nella
## scatola centrale del Casualty Track e NON contano). Quando le perdite di una
## fazione raggiungono la sua soglia di resa, quella fazione perde la partita.
var casualties: Dictionary = {
	Domain.Faction.GERMAN: 0,
	Domain.Faction.RUSSIAN: 0,
}

## Soglia di resa per fazione (resa_axis/allies dello scenario). 0 = disattivata.
var surrender_threshold: Dictionary = {
	Domain.Faction.GERMAN: 0,
	Domain.Faction.RUSSIAN: 0,
}


# ─── Obiettivi ───────────────────────────────────────────────────────────────

var objectives: Array[Objective] = []


# ─── Carte ───────────────────────────────────────────────────────────────────

var german_deck: Array[Card] = []
var german_discard: Array[Card] = []
var german_hand: Array[Card] = []

var russian_deck: Array[Card] = []
var russian_discard: Array[Card] = []
var russian_hand: Array[Card] = []

## Carte in mano per fazione (qualità truppe: mano_axis/allies dello scenario).
var hand_size: Dictionary = {
	Domain.Faction.GERMAN: 4,
	Domain.Faction.RUSSIAN: 4,
}


# ─── Turno e fase ────────────────────────────────────────────────────────────

var phase: int = Domain.Phase.PLAYER_TURN
var active_faction: int = Domain.Faction.GERMAN
var human_faction: int = Domain.Faction.GERMAN
var scenario_number: int = 1
var scenario_name: String = ""
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


## HexData a partire dall'etichetta "A1" (null se fuori mappa).
func hex_at_label(lbl: String) -> HexData:
	var qr := Domain.label_to_qr(lbl)
	if qr.x < 0:
		return null
	return hex_at(qr.x, qr.y)


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


## Somma dei "soldier icons" nell'esagono (impilamento: max 7).
func soldier_icons_at(q: int, r: int) -> int:
	var total := 0
	for u in units_at(q, r):
		total += u.soldier_icons()
	return total


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


## Numero di carte che la fazione tiene in mano (default 4 se non impostato).
func hand_size_of(faction: int) -> int:
	return int(hand_size.get(faction, 4))


## Elimina un'unità dallo stato registrandola sul Casualty Track (4.2): se è un
## uomo (non un'arma) incrementa le perdite della sua fazione. Unico punto da cui
## le unità lasciano `units`, così il conteggio resa resta sempre coerente.
func eliminate_unit(uid: String) -> void:
	var u: Unit = units.get(uid)
	if u != null and u.is_man():
		casualties[u.faction] = int(casualties.get(u.faction, 0)) + 1
	units.erase(uid)


## Vero se le perdite della fazione hanno raggiunto la sua soglia di resa (6.3).
func has_surrendered(faction: int) -> bool:
	var thr := int(surrender_threshold.get(faction, 0))
	return thr > 0 and int(casualties.get(faction, 0)) >= thr


func objective_at(q: int, r: int) -> Objective:
	for o in objectives:
		if o.q == q and o.r == r:
			return o
	return null


# ─── Lati di esagono (indice per query veloci) ────────────────────────────────

var _side_index: Dictionary = {}
var _side_index_built: bool = false


## Caratteristica del lato condiviso tra gli esagoni a e b (Domain.HexsideFeature).
## NONE se non c'è nulla. L'indice viene costruito pigramente al primo accesso.
func side_feature_between(a: Vector2i, b: Vector2i) -> int:
	if not _side_index_built:
		_build_side_index()
	return int(_side_index.get(_side_key(a, b), Domain.HexsideFeature.NONE))


func _side_key(a: Vector2i, b: Vector2i) -> String:
	if a.x < b.x or (a.x == b.x and a.y <= b.y):
		return "%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]
	return "%d,%d|%d,%d" % [b.x, b.y, a.x, a.y]


func _build_side_index() -> void:
	_side_index.clear()
	for sf in side_features:
		var a: Vector2i = sf["a"]
		var b: Vector2i = sf["b"]
		_side_index[_side_key(a, b)] = int(sf["feature"])
	_side_index_built = true


func add_log(msg: String) -> void:
	log.push_front(msg)
	if log.size() > 50:
		log.resize(50)
