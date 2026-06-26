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
