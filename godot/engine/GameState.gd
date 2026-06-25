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
	var has_blaze: bool = false    # incendio (E46): terreno impassabile
	var fortification: int = 0     # Domain.Fort: trincea/casamatta/bunker/filo/mine

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
## Difensore dello scenario (postura "defend"): riceve +1 VP a ogni Tempo!
## (6.1.2). -1 se nessuno dei due lati difende (es. scontro recon/recon).
var defender_faction: int = -1
var scenario_number: int = 1
var scenario_name: String = ""
## Nazioni reali dei due lati (per mazzo, statistiche e arte). Lo slot "german_*"
## tiene l'Asse, "russian_*" gli Alleati (stand-in degli enum di fazione).
var axis_nation: String = "german"
var allied_nation: String = "russian"
var turn_number: int = 1
var order_count: int = 0
var max_orders: int = 2
var ai_max_orders: int = 2  ## Ordini giocati dall'IA nel suo turno


# ─── Traccia del tempo ────────────────────────────────────────────────────────

var time_marker: int = 2
var sudden_death_space: int = 7


# ─── Punti Vittoria ──────────────────────────────────────────────────────────

var vp_tracker: int = 0  ## >0 Germania in vantaggio, <0 Russia
## VP non legati agli obiettivi (positivi = Germania): VP iniziali dello scenario,
## +1 del Tempo! al difensore e VP da eliminazione/uscita (7.1/7.2). Vengono
## sommati alla bilancia degli obiettivi in Game._update_objectives.
var bonus_vp: int = 0

## Chit Obiettivo "[open]" attivi (7.3.2): W = VP d'uscita raddoppiati,
## X = VP da eliminazione raddoppiati.
var chit_double_exit: bool = false
var chit_double_elim: bool = false


# ─── Iniziativa ──────────────────────────────────────────────────────────────

var initiative_holder: int = Domain.Faction.GERMAN


# ─── Selezione UI ────────────────────────────────────────────────────────────

var selected_unit_id: String = ""
var selected_card_index: int = -1
var highlighted_hexes: Array[String] = []

# Strumento "Modalità LOS" (solo interfaccia, NON salvato): due estremità
# trascinabili e la loro linea di vista (verde/giallo/rosso). Vedi HexGrid.los_kind.
var los_mode: bool = false
var los_a: Vector2i = Vector2i(-1, -1)
var los_b: Vector2i = Vector2i(-1, -1)


# ─── Ordine in corso ─────────────────────────────────────────────────────────

## Domain.OrderType dell'ordine attualmente in esecuzione (-1 = nessuno).
## Determina come la mappa interpreta i click (movimento / fuoco / avanzata).
var current_order: int = -1


# ─── Movimento passo per passo ───────────────────────────────────────────────

var moving_unit_id: String = ""
var moving_remaining_mp: int = 0
var moving_card_index: int = -1

# ─── Gruppo di comando (3.3) ─────────────────────────────────────────────────
# Un ordine di Mossa dato a un leader attiva il leader e le unità idonee entro
# il suo raggio di Comando: il giocatore le muove una alla volta nello stesso
# ordine. `ordered_group` = id attivati; `group_mp` = id → PM rimasti per
# ciascuno; `move_committed` = almeno un passo di movimento è già avvenuto.
var ordered_group: Array[String] = []
var group_mp: Dictionary = {}
var move_committed: bool = false

# ─── Assemblaggio gruppo di fuoco (O20.3.1) ──────────────────────────────────
# Quando il giocatore sceglie un bersaglio col FUOCO, si entra nella fase di
# assemblaggio: `fire_target_*` = esagono bersaglio (-1 = nessuno);
# `fire_eligible_ids` = pezzi che possono colpirlo; `fire_group_ids` = pezzi
# attualmente inclusi nel gruppo (il pezzo base resta sempre incluso).
var fire_target_q: int = -1
var fire_target_r: int = -1
var fire_eligible_ids: Array[String] = []
var fire_group_ids: Array[String] = []
# Modificatori di fuoco (carte Azione) applicati all'attacco in assemblaggio:
# `fire_modifiers` = nomi azione, `fire_modifier_cards` = riferimenti alle carte
# (consumate alla conferma, restituite all'annullamento).
var fire_modifiers: Array[String] = []
var fire_modifier_cards: Array = []
# Sventagliata (A40): l'attacco colpisce anche un secondo esagono adiacente.
var spray_active: bool = false
# Fuoco d'Assalto (A26): un attacco di fuoco già usato nell'ordine di Mossa corrente.
var assault_fired: bool = false
# Richiesta d'Artiglieria (O18): spotter/radio durante la scelta del bersaglio.
var artillery_radio_id: String = ""
var artillery_spotter_id: String = ""
var artillery_smoke: bool = false  # barrage fumogeno invece che esplosivo (O18.2.1.1)
# Ultimo impatto d'artiglieria (per il marker visivo sulla mappa): esagoni colpiti.
var last_impact_hexes: Array = []

# ─── Finestra di reazione: Fuoco di Opportunità del giocatore (A33) ───────────
# Mentre l'IA muove, se il giocatore umano ha tiratori idonei si apre una finestra
# di scelta: `opfire_mover_id` = unità IA in movimento; `opfire_shooter_ids` =
# tiratori umani idonei tra cui scegliere (o declinare).
var opfire_mover_id: String = ""
var opfire_shooter_ids: Array[String] = []


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


## Arma (11.2) trasportata dall'unità `man_id`, oppure null se non ne porta.
func weapon_carried_by(man_id: String) -> Unit:
	if man_id == "":
		return null
	for u in units.values():
		if u.is_weapon() and u.carrier_id == man_id:
			return u
	return null


## Sposta un'unità in (q,r) portando con sé l'eventuale arma trasportata (11.1).
## Unico punto da usare per muovere le pedine, così l'arma resta sempre col
## proprietario (mossa umana, avanzata, IA).
func set_unit_pos(u: Unit, new_q: int, new_r: int) -> void:
	u.q = new_q
	u.r = new_r
	var w := weapon_carried_by(u.id)
	if w != null:
		w.q = new_q
		w.r = new_r


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


## Uomini efficienti ma soppressi (un ordine di Recupero rimuove la soppressione).
func suppressed_men_of(faction: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for u in units.values():
		if u.faction == faction and u.is_man() and u.efficient and u.suppressed:
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
	if u != null:
		# Gli Eroi (E58.1) non vanno mai sul Casualty Track.
		if u.is_man() and not u.hero:
			casualties[u.faction] = int(casualties.get(u.faction, 0)) + 1
		# VP da eliminazione (7.1): all'avversario di chi viene eliminato.
		var v := elimination_vp(u)
		if chit_double_elim:
			v *= 2  # Chit Obiettivo X [open]: VP da eliminazione raddoppiati.
		if v > 0:
			if u.faction == Domain.Faction.GERMAN:
				bonus_vp -= v  # i Russi guadagnano
			else:
				bonus_vp += v  # i Tedeschi guadagnano
		# 11.3: un'arma trasportata segue il proprietario eliminato (eliminata anch'essa).
		if u.is_man():
			var w := weapon_carried_by(uid)
			if w != null:
				units.erase(w.id)
	units.erase(uid)


## Uscita dal bordo avversario (7.2): a differenza dell'eliminazione, è il
## PROPRIETARIO a guadagnare i VP del pezzo (valori 7.1) e l'unità lascia la
## mappa SENZA finire sul Casualty Track. Restituisce i VP assegnati.
func exit_unit_for_vp(uid: String) -> int:
	var u: Unit = units.get(uid)
	if u == null:
		return 0
	var v := elimination_vp(u)
	if chit_double_exit:
		v *= 2  # Chit Obiettivo W [open]: VP d'uscita raddoppiati.
	if v > 0:
		if u.faction == Domain.Faction.GERMAN:
			bonus_vp += v  # i Tedeschi guadagnano
		else:
			bonus_vp -= v  # i Russi guadagnano
	# 11.3: l'arma trasportata lascia la mappa col proprietario.
	if u.is_man():
		var w := weapon_carried_by(uid)
		if w != null:
			units.erase(w.id)
	units.erase(uid)
	return v


## Valore in VP di un'unità eliminata (7.1): Squadra 2, Team 1,
## Leader (non Eroe) 1 + Comando, Eroe 0, Arma 0.
static func elimination_vp(u: Unit) -> int:
	if u.hero:
		return 0
	if u.is_leader():
		return 1 + u.command
	if u.is_weapon():
		return 0
	if u.type == Domain.UnitType.TEAM:
		return 1
	return 2  # squadra


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
