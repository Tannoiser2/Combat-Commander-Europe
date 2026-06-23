## Una carta del mazzo del Fato di Combat Commander: Europe.
## Costruita dai dati reali (mazzo_<fazione>.json) con la faccia illustrata.
class_name Card
extends RefCounted

var id: String              ## es. "german-1"
var faction: int            ## Domain.Faction
var number: int             ## 1–72, corrisponde al file immagine
var order: int              ## Domain.OrderType (mappato da orderType)
var order_label: String     ## etichetta stampata, es. "RECUPERO"
var order_count: int        ## quante unità attiva
var action_name: String     ## azione, es. "FUOCO D'ASSALTO"
var event_name: String      ## evento, es. "CRATERI"
var random_hex_label: String## es. "A3"
var random_hex_value: int   ## 1–8
var dice_white: int
var dice_red: int
var consequence: String     ## es. "jam"


## Stringa null-safe da un dizionario.
static func _s(d: Dictionary, key: String, fallback: String = "") -> String:
	var v: Variant = d.get(key)
	return fallback if v == null else str(v)


## Intero null-safe da un dizionario.
static func _n(d: Dictionary, key: String, fallback: int = 0) -> int:
	var v: Variant = d.get(key)
	return fallback if v == null else int(v)


## Costruisce una carta da un dizionario del JSON del mazzo.
static func from_dict(d: Dictionary) -> Card:
	var c := Card.new()
	c.id = _s(d, "deckCardId")
	# Le nazioni dell'Asse usano lo stile carta tedesco, le Alleate quello russo.
	c.faction = Domain.Faction.GERMAN if _s(d, "faction") in ["german", "italian", "romanian"] else Domain.Faction.RUSSIAN
	c.number = _n(d, "number")
	c.order = Domain.ORDER_TYPE_FROM_STRING.get(_s(d, "orderType"), Domain.OrderType.PASS)
	c.order_label = _s(d, "orderLabel", _s(d, "orderName"))
	c.order_count = _n(d, "orderCount", 1)
	c.action_name = _s(d, "action")
	c.event_name = _s(d, "eventName")
	c.random_hex_label = _s(d, "randomHexLabel")
	c.random_hex_value = _n(d, "randomHexValue")
	c.dice_white = _n(d, "diceWhite")
	c.dice_red = _n(d, "diceRed")
	c.consequence = _s(d, "consequence")
	return c


## Percorso della faccia illustrata della carta.
func face_path() -> String:
	var folder := "german" if faction == Domain.Faction.GERMAN else "russian"
	return "res://assets/cards/%s/%02d.jpg" % [folder, number]
