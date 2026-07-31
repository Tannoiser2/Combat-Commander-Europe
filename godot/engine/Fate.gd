## Mazzo del Fato di Combat Commander: Europe.
## In CC:E ogni tiro di dadi si ottiene PESCANDO la carta in cima al proprio
## mazzo: si usano i due dadi stampati e si applica l'eventuale conseguenza
## (Tempo!, Cecchino, Inceppamento, Evento). Questo modulo fornisce la pescata
## e la risoluzione delle conseguenze; i dadi vengono passati alle funzioni pure
## di Combat/Rules.
class_name Fate
extends RefCounted


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
		# 6.1.2: aver pescato l'ULTIMA carta del proprio mazzo innesca un
		# avanzamento del Tempo (come un «Tempo!»). Game processa la coda a
		# fine risoluzione (non qui: siamo dentro una pescata).
		state.pending_time_factions.append(faction)
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
			# Tempo! (6.1.2): la sequenza (rimescolo dell'innescante, Morte
			# Subitanea, +1 VP al difensore, fumo, rinforzi) è orchestrata da
			# Game._advance_time: qui si accoda soltanto l'innesco.
			state.pending_time_factions.append(faction)
			lines.append("TEMPO!")
		"sniper":
			_consequence_sniper(state, card, faction, lines)
		"jam":
			_consequence_jam(state, context, lines)
		"event":
			lines.append_array(Events.fire(state, card, faction))
	return lines


# ─── Conseguenze ─────────────────────────────────────────────────────────────

## Cecchino (1.9.1): rompe UNA unità nemica in o adiacente all'esagono indicato
## (se già rotta, la elimina).
static func _consequence_sniper(
	state: GameState, card: Card, faction: int, lines: Array[String]
) -> void:
	var qr := Domain.label_to_qr(card.random_hex_label)
	if qr.x < 0:
		return
	var victim: Unit = null
	for u in state.units.values():
		if u.faction == faction or not u.is_man():
			continue
		if HexGrid.distance(qr.x, qr.y, u.q, u.r) <= 1:
			victim = u
			break
	if victim == null:
		lines.append("Cecchino in %s: nessun bersaglio in o adiacente." % card.random_hex_label)
		return
	if victim.efficient:
		victim.break_unit()
		lines.append("Cecchino: %s rotta (vicino a %s)." % [victim.unit_name, card.random_hex_label])
	else:
		state.eliminate_unit(victim.id)
		lines.append("Cecchino: %s eliminata (vicino a %s)." % [victim.unit_name, card.random_hex_label])


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
