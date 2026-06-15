## Mazzo del Fato di Combat Commander: Europe.
## In CC:E ogni tiro di dadi si ottiene PESCANDO la carta in cima al proprio
## mazzo: si usano i due dadi stampati e si applica l'eventuale conseguenza
## (Tempo!, Cecchino, Inceppamento, Evento). Questo modulo fornisce la pescata
## e la risoluzione delle conseguenze; i dadi vengono passati alle funzioni pure
## di Combat/Rules.
class_name Fate
extends RefCounted

const SNIPER_FP := 2  ## Potenza di fuoco del cecchino (oltre ai dadi della carta)


## Pesca la carta in cima al mazzo della fazione (rimescolando gli scarti se
## necessario). La carta finisce negli scarti. null se mazzo e scarti sono vuoti.
static func draw(state: GameState, faction: int) -> Card:
	var is_ger := faction == Domain.Faction.GERMAN
	var deck := state.german_deck if is_ger else state.russian_deck
	var discard := state.german_discard if is_ger else state.russian_discard
	if deck.is_empty():
		if discard.is_empty():
			return null
		deck.append_array(discard)
		discard.clear()
		Cards.shuffle(deck)
	if deck.is_empty():
		return null
	var c: Card = deck.pop_back()
	discard.append(c)
	return c


## I due dadi della carta (fallback (3,4) se la carta è null).
static func dice(card: Card) -> Vector2i:
	if card == null:
		return Vector2i(3, 4)
	return Vector2i(card.dice_white, card.dice_red)


## Applica la conseguenza della carta pescata. Restituisce le righe di log.
## context (per l'inceppamento): { "kind": "fire", "weapons": [unit_id, ...] }.
static func apply_consequence(
	state: GameState, card: Card, faction: int, context: Dictionary = {}
) -> Array[String]:
	var lines: Array[String] = []
	if card == null:
		return lines
	match card.consequence:
		"time":
			_consequence_time(state, lines)
		"sniper":
			_consequence_sniper(state, card, faction, lines)
		"jam":
			_consequence_jam(state, context, lines)
		"event":
			lines.append("Evento pescato: %s (non ancora gestito)" % card.event_name)
	return lines


# ─── Conseguenze ─────────────────────────────────────────────────────────────

## Tempo!: avanza la traccia del tempo, +1 VP al difensore (euristica: la
## fazione senza iniziativa) e rimescola mazzo+scarti di entrambe le fazioni.
static func _consequence_time(state: GameState, lines: Array[String]) -> void:
	state.time_marker += 1
	lines.append("TEMPO! La traccia avanza a %d/%d" % [state.time_marker, state.sudden_death_space])
	var defender := Domain.Faction.RUSSIAN if state.initiative_holder == Domain.Faction.GERMAN else Domain.Faction.GERMAN
	if defender == Domain.Faction.GERMAN:
		state.vp_tracker += 1
	else:
		state.vp_tracker -= 1
	_reshuffle(state, Domain.Faction.GERMAN)
	_reshuffle(state, Domain.Faction.RUSSIAN)


## Cecchino: ripara le armi inceppate di chi pesca e colpisce i nemici
## nell'esagono indicato dalla carta.
static func _consequence_sniper(
	state: GameState, card: Card, faction: int, lines: Array[String]
) -> void:
	for w in state.units_of(faction):
		if w.is_weapon() and not w.efficient:
			w.efficient = true
			lines.append("Cecchino: %s riparata" % w.unit_name)
	var qr := Domain.label_to_qr(card.random_hex_label)
	if qr.x < 0:
		return
	var hit := card.dice_white + card.dice_red + SNIPER_FP
	for t in state.men_at(qr.x, qr.y):
		if t.faction == faction:
			continue
		if hit >= t.morale:
			if t.efficient:
				t.break_unit()
				lines.append("Cecchino rompe %s in %s" % [t.unit_name, card.random_hex_label])
			else:
				state.units.erase(t.id)
				lines.append("Cecchino elimina %s in %s" % [t.unit_name, card.random_hex_label])


## Inceppamento: se la conseguenza arriva da un fuoco, le armi del gruppo si
## inceppano (fuori uso finché non vengono riparate, es. da un Cecchino).
static func _consequence_jam(
	state: GameState, context: Dictionary, lines: Array[String]
) -> void:
	if String(context.get("kind", "")) != "fire":
		return
	for wid in context.get("weapons", []):
		var w := state.unit_by_id(String(wid))
		if w != null and w.is_weapon():
			w.efficient = false
			lines.append("Inceppamento: %s fuori uso" % w.unit_name)


## Rimescola mazzo + scarti di una fazione (lascia invariata la mano).
static func _reshuffle(state: GameState, faction: int) -> void:
	var is_ger := faction == Domain.Faction.GERMAN
	var deck := state.german_deck if is_ger else state.russian_deck
	var discard := state.german_discard if is_ger else state.russian_discard
	deck.append_array(discard)
	discard.clear()
	Cards.shuffle(deck)
