## Costruzione e gestione dei mazzi di CC:E.
## Per il prototipo usa un mazzo semplificato (solo ordini fondamentali).
class_name Cards
extends RefCounted

const HAND_SIZE := 4  ## Carte in mano per fazione


## Costruisce il mazzo tedesco (semplificato).
static func build_german_deck() -> Array[Card]:
	return _build_deck(Domain.Faction.GERMAN, "GER")


## Costruisce il mazzo russo (semplificato).
static func build_russian_deck() -> Array[Card]:
	return _build_deck(Domain.Faction.RUSSIAN, "RUS")


static func _build_deck(faction: int, prefix: String) -> Array[Card]:
	var deck: Array[Card] = []
	var id := 0

	# 4× MOVE
	for _i in range(4):
		deck.append(_card(
			"%s-%02d" % [prefix, id], faction, id,
			"Movimento", Domain.OrderType.MOVE, 2,
			-1, randi_range_static(1, 8), randi_range_static(1, 6)
		))
		id += 1

	# 3× FIRE
	for _i in range(3):
		deck.append(_card(
			"%s-%02d" % [prefix, id], faction, id,
			"Fuoco", Domain.OrderType.FIRE, 1,
			-1, randi_range_static(1, 8), randi_range_static(1, 6)
		))
		id += 1

	# 2× ADVANCE
	for _i in range(2):
		deck.append(_card(
			"%s-%02d" % [prefix, id], faction, id,
			"Avanzata", Domain.OrderType.ADVANCE, 1,
			-1, randi_range_static(1, 8), randi_range_static(1, 6)
		))
		id += 1

	# 2× RECOVER
	for _i in range(2):
		deck.append(_card(
			"%s-%02d" % [prefix, id], faction, id,
			"Recupero", Domain.OrderType.RECOVER, 1,
			-1, randi_range_static(1, 8), randi_range_static(1, 6)
		))
		id += 1

	# 1× PASS
	deck.append(_card(
		"%s-%02d" % [prefix, id], faction, id,
		"Passo", Domain.OrderType.PASS, 0,
		-1, randi_range_static(1, 8), randi_range_static(1, 6)
	))

	return deck


static func _card(
	cid: String, faction: int, number: int, name: String,
	order: int, order_count: int,
	action: int, random_hex: int, dice_value: int
) -> Card:
	return Card.new(cid, faction, number, name, order, order_count, action, random_hex, dice_value)


## GDScript non ha Random statico globale: usiamo un RNG condiviso al livello modulo.
static var _rng: RandomNumberGenerator = null

static func randi_range_static(from: int, to: int) -> int:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	return _rng.randi_range(from, to)


## Mescola un mazzo in-place (Fisher-Yates).
static func shuffle(deck: Array[Card]) -> void:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	for i in range(deck.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := deck[i]
		deck[i] = deck[j]
		deck[j] = tmp


## Pesca `count` carte dal mazzo nella mano, rimescolando gli scarti se necessario.
static func draw(
	deck: Array[Card], discard: Array[Card], hand: Array[Card],
	count: int = 1
) -> void:
	for _i in range(count):
		if deck.is_empty():
			if discard.is_empty():
				return
			# Rimescola gli scarti nel mazzo
			deck.append_array(discard)
			discard.clear()
			shuffle(deck)
		if deck.is_empty():
			return
		hand.append(deck.pop_back())


## Distribuisce le mani iniziali per entrambe le fazioni.
static func deal_initial(state: GameState) -> void:
	draw(state.german_deck, state.german_discard, state.german_hand, HAND_SIZE)
	draw(state.russian_deck, state.russian_discard, state.russian_hand, HAND_SIZE)


## Scarta la carta all'indice `idx` dalla mano della fazione.
static func discard_from_hand(
	hand: Array[Card], discard: Array[Card], idx: int
) -> Card:
	if idx < 0 or idx >= hand.size():
		return null
	var c: Card = hand[idx]
	hand.remove_at(idx)
	discard.append(c)
	return c
