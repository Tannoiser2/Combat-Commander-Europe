## Costruzione e gestione dei mazzi di CC:E.
## Per il prototipo usa un mazzo semplificato (solo ordini fondamentali).
class_name Cards
extends RefCounted

const HAND_SIZE := 4  ## Carte in mano per fazione


## Carica il mazzo tedesco dai dati reali (72 carte del Fato).
static func build_german_deck() -> Array[Card]:
	return _load_deck("res://assets/cards/german_deck.json")


## Carica il mazzo russo dai dati reali (72 carte del Fato).
static func build_russian_deck() -> Array[Card]:
	return _load_deck("res://assets/cards/russian_deck.json")


## Routing fazione → file mazzo. Le 6 nazioni hanno un mazzo proprio; le minori
## usano la capofila (come stat e counter): rumeni→italiano, Commonwealth→
## inglese, brasiliani→americano, polacchi/jugoslavi→francese.
const DECK_FILE := {
	"german": "german", "italian": "italian", "romanian": "italian",
	"american": "american", "brazilian": "american",
	"british": "british", "canadian": "british", "anzac": "british",
	"french": "french", "polish": "french", "yugoslav": "french",
	"russian": "russian",
}


## Carica il mazzo del Fato della nazione indicata (default tedesco).
static func build_deck(nation: String) -> Array[Card]:
	var file := String(DECK_FILE.get(nation, "german"))
	return _load_deck("res://assets/cards/%s_deck.json" % file)


static func _load_deck(path: String) -> Array[Card]:
	var deck: Array[Card] = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Mazzo non trovato: " + path)
		return deck
	var text := f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(text)
	if not (data is Array):
		push_error("Formato mazzo non valido: " + path)
		return deck
	for entry in data:
		if entry is Dictionary:
			deck.append(Card.from_dict(entry))
	return deck


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


## Distribuisce le mani iniziali per entrambe le fazioni, ciascuna alla sua
## dimensione di mano (qualità truppe). Il refill dopo ogni carta giocata
## (scarta 1 / pesca 1) mantiene poi la mano a questa dimensione.
static func deal_initial(state: GameState) -> void:
	draw(state.german_deck, state.german_discard, state.german_hand,
		state.hand_size_of(Domain.Faction.GERMAN))
	draw(state.russian_deck, state.russian_discard, state.russian_hand,
		state.hand_size_of(Domain.Faction.RUSSIAN))


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
