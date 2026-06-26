## FlipBot — bot avversario per Combat Commander (di Russ Brown), adattato al
## motore digitale. Questo modulo implementa la GESTIONE DELLA MANO e la
## DISPOSIZIONE del bot, fedeli al documento FlipBot:
##
##  • Recupero per primo: se il bot ha un'unità rotta, gioca la carta Recupero
##    più a sinistra prima di ogni altro ordine.
##  • Ordini da sinistra a destra: gioca il primo ordine giocabile partendo dalla
##    carta più a sinistra; dopo ogni ordine riparte da sinistra.
##  • Carte "dud" (inutili): Confusione d'Ordini (sempre), Artiglieria Negata se
##    il nemico non ha radio, Richiesta d'Artiglieria se il bot non ha radio.
##  • Passa e scarta: se più di metà della mano è fatta di dud, il bot passa e
##    scarta le dud (poi ripesca).
##  • Disposizione: Offensiva o Difensiva, ricalcolata a ogni avanzamento del
##    Tempo; guida le destinazioni di Mossa e Avanzata (usata nei moduli mossa).
##
## La SCELTA tattica del singolo ordine (quali unità, quali bersagli) resta nei
## moduli esistenti (AI.gd); qui decidiamo SOLO quale ordine giocare e quando
## passare. Le funzioni sono pure: l'esecuzione e gli effetti sono in Game.gd.
class_name FlipBot
extends RefCounted


## Peso di ogni obiettivo controllato nel calcolo della Disposizione. Adatta la
## formula del FlipBot (controllati × marcatori Obiettivo generici nascosti): il
## motore non modella i marcatori generici, quindi usiamo un peso costante.
const DISPOSITION_OBJ_WEIGHT := 2
## Soglia (a favore del bot) oltre la quale il bot passa in Difensiva.
const DISPOSITION_DEFEND_AT := 7


# ─── Disposizione ────────────────────────────────────────────────────────────

## Calcola la Disposizione del bot. Valore = VP del bot + (obiettivi controllati
## × peso). Se ≥ +7 a favore del bot → Difensiva, altrimenti Offensiva.
static func compute_disposition(state: GameState, faction: int) -> int:
	var own_vp := state.vp_tracker if faction == Domain.Faction.GERMAN else -state.vp_tracker
	var controlled := 0
	for o in state.objectives:
		if o.controller == faction:
			controlled += 1
	var value := own_vp + controlled * DISPOSITION_OBJ_WEIGHT
	return Domain.Disposition.DEFENSIVE if value >= DISPOSITION_DEFEND_AT \
		else Domain.Disposition.OFFENSIVE


# ─── Carte "dud" e radio ─────────────────────────────────────────────────────

## Vero se la fazione ha una Radio non rotta (per Richiesta/Negata d'Artiglieria).
static func has_radio(state: GameState, faction: int) -> bool:
	for u in state.units_of(faction):
		if u.efficient and u.unit_name.contains("Radio"):
			return true
	return false


## Vero se la carta è una "dud" (inutile) per il bot, secondo FlipBot:
##  • Confusione d'Ordini (ordine PASS) — sempre;
##  • Artiglieria Negata — se il nemico non ha radio;
##  • Richiesta d'Artiglieria — se il bot non ha radio.
static func is_dud(state: GameState, card: Card, faction: int) -> bool:
	match card.order:
		Domain.OrderType.PASS:
			return true
		Domain.OrderType.ARTY_DENIED:
			return not has_radio(state, _opponent(faction))
		Domain.OrderType.ARTY:
			return not has_radio(state, faction)
		_:
			return false


## Indici (nella mano) delle carte dud, da sinistra a destra.
static func dud_indices(state: GameState, faction: int) -> Array:
	var out: Array = []
	var hand := state.hand_of(faction)
	for i in hand.size():
		if is_dud(state, hand[i], faction):
			out.append(i)
	return out


## Vero se conviene passare e scartare: più di metà delle carte sono dud.
static func should_pass_and_discard(state: GameState, faction: int) -> bool:
	var hand := state.hand_of(faction)
	if hand.is_empty():
		return false
	var duds := dud_indices(state, faction).size()
	return duds * 2 > hand.size()


# ─── Scelta dell'ordine di turno ─────────────────────────────────────────────

## Sceglie l'ordine da giocare nel turno del bot, fedele al FlipBot:
##  1) se c'è un'unità rotta, gioca la carta Recupero più a sinistra;
##  2) altrimenti il primo ordine GIOCABILE da sinistra a destra.
## Restituisce un dizionario play { card_index, order, ...parametri } come
## AI.choose_play, oppure {} se nessun ordine è giocabile.
static func choose_turn_order(state: GameState, faction: int) -> Dictionary:
	var hand := state.hand_of(faction)
	# 1) Recupero per primo se c'è un'unità rotta.
	if not state.broken_men_of(faction).is_empty():
		for i in hand.size():
			if hand[i].order == Domain.OrderType.RECOVER:
				return { "card_index": i, "order": Domain.OrderType.RECOVER }
	# 2) Primo ordine giocabile da sinistra a destra.
	for i in hand.size():
		var play := _order_play(state, faction, hand[i])
		if not play.is_empty():
			play["card_index"] = i
			play["order"] = hand[i].order
			return play
	return {}


## Verifica se l'ordine della carta è giocabile e ne restituisce i parametri
## (riusando le euristiche tattiche di AI.gd). {} se non giocabile.
static func _order_play(state: GameState, faction: int, card: Card) -> Dictionary:
	match card.order:
		Domain.OrderType.FIRE:
			return AI.best_fire(state, faction)
		Domain.OrderType.ADVANCE:
			return AI.best_advance(state, faction)
		Domain.OrderType.ARTY:
			return AI.best_artillery(state, faction)
		Domain.OrderType.RECOVER:
			if not state.broken_men_of(faction).is_empty() \
					or not state.suppressed_men_of(faction).is_empty():
				return { "ok": true }
			return {}
		Domain.OrderType.ROUT:
			return { "ok": true } if AI._has_pressured_broken(state, faction) else {}
		Domain.OrderType.MOVE:
			return { "ok": true } if AI._has_movable(state, faction) else {}
		_:
			return {}  # PASS / ARTY_DENIED non si giocano come ordine


static func _opponent(faction: int) -> int:
	return Domain.Faction.RUSSIAN if faction == Domain.Faction.GERMAN \
		else Domain.Faction.GERMAN


# ─── Mossa (O21): destinazione strategica ────────────────────────────────────

const MOVE_RANGE := 5  ## "entro 5 esagoni" nelle liste di destinazione FlipBot.


## Colonna del bordo mappa NEMICO per la fazione. L'Asse (Tedesco) schiera a Est
## e attacca verso Ovest (colonna 0); gli Alleati (Russo) il contrario.
static func enemy_edge_col(state: GameState, faction: int) -> int:
	return 0 if faction == Domain.Faction.GERMAN else state.map_cols - 1


## Colonna del bordo mappa AMICO (verso cui si ritirano le unità rotte).
static func friendly_edge_col(state: GameState, faction: int) -> int:
	return state.map_cols - 1 if faction == Domain.Faction.GERMAN else 0


## Esagono del bordo nemico alla stessa riga (per la destinazione "Bordo nemico").
static func enemy_edge_hex(state: GameState, faction: int, q: int, r: int) -> Vector2i:
	return Vector2i(enemy_edge_col(state, faction), clampi(r, 0, state.map_rows - 1))


## Destinazione strategica di un'unità (squadra/team/leader) in Mossa, secondo le
## priorità del FlipBot e la Disposizione. Restituisce un Vector2i (q,r).
static func move_destination(state: GameState, faction: int, u: Unit) -> Vector2i:
	# Unità rotta: ritirata verso il bordo amico (fuori dalla mischia).
	if not u.efficient:
		return retreat_destination(state, faction, u)
	# 1) Obiettivo non controllato e non occupato dal nemico, entro 5: conquistalo.
	var d1 := _nearest_objective_hex(state, faction, u, MOVE_RANGE, "gain")
	if d1.x >= 0:
		return d1
	# 2) Obiettivo amico entro 5 (solo in Difensiva): tienilo.
	if state.disposition == Domain.Disposition.DEFENSIVE:
		var d2 := _nearest_objective_hex(state, faction, u, MOVE_RANGE, "friendly")
		if d2.x >= 0:
			return d2
	# 3) Obiettivo occupato dal nemico entro 5.
	var d3 := _nearest_objective_hex(state, faction, u, MOVE_RANGE, "enemy")
	if d3.x >= 0:
		return d3
	# 4) Esagono occupato dal nemico entro 5.
	var d4 := _nearest_enemy_hex(state, faction, u, MOVE_RANGE)
	if d4.x >= 0:
		return d4
	# 5) Bordo mappa nemico.
	return enemy_edge_hex(state, faction, u.q, u.r)


## Esagono di ritirata di un'unità rotta: verso il bordo amico, alla sua riga.
static func retreat_destination(state: GameState, faction: int, u: Unit) -> Vector2i:
	return Vector2i(friendly_edge_col(state, faction), clampi(u.r, 0, state.map_rows - 1))


## Obiettivo più vicino entro `radius` del tipo richiesto:
##  "gain"     non controllato dal bot e senza nemici (conquistabile);
##  "friendly" controllato dal bot;
##  "enemy"    con almeno un'unità nemica.
## Restituisce (q,r) o (-1,-1).
static func _nearest_objective_hex(state: GameState, faction: int, u: Unit, radius: int, kind: String) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := radius + 1
	for o in state.objectives:
		var d := HexGrid.distance(u.q, u.r, o.q, o.r)
		if d > radius:
			continue
		var enemy_here := false
		for m in state.men_at(o.q, o.r):
			if m.faction != faction:
				enemy_here = true
				break
		var ok := false
		match kind:
			"gain":
				ok = o.controller != faction and not enemy_here
			"friendly":
				ok = o.controller == faction
			"enemy":
				ok = enemy_here
		if ok and d < best_d:
			best_d = d
			best = Vector2i(o.q, o.r)
	return best


## Esagono nemico (con un uomo) più vicino entro `radius`, o (-1,-1).
static func _nearest_enemy_hex(state: GameState, faction: int, u: Unit, radius: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := radius + 1
	for other in state.units.values():
		if other.faction == faction or not other.is_man():
			continue
		var d := HexGrid.distance(u.q, u.r, other.q, other.r)
		if d <= radius and d < best_d:
			best_d = d
			best = Vector2i(other.q, other.r)
	return best


## Vero se l'unità è l'unico uomo amico su un obiettivo controllato dal bot:
## in tal caso non lo abbandona (regola "last squad/team in objective").
static func should_hold_objective(state: GameState, faction: int, u: Unit) -> bool:
	var o := state.objective_at(u.q, u.r)
	if o == null or o.controller != faction:
		return false
	var friends := 0
	for m in state.men_at(u.q, u.r):
		if m.faction == faction:
			friends += 1
	return friends <= 1
