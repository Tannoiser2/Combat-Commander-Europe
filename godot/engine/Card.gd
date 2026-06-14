## Una carta del mazzo di Combat Commander: Europe.
class_name Card
extends RefCounted

var id: String
var faction: int       # Domain.Faction
var number: int
var card_name: String
var order: int         # Domain.OrderType
var order_count: int   # quante unità può attivare (di solito 1)
var action: int        # Domain.ActionType, -1 = nessuna
var random_hex: int    # valore esagono casuale stampato sulla carta (1–8)
var dice_value: int    # valore dado stampato sulla carta


func _init(
	p_id: String, p_faction: int, p_number: int, p_name: String,
	p_order: int, p_order_count: int,
	p_action: int, p_random_hex: int, p_dice_value: int
) -> void:
	id = p_id
	faction = p_faction
	number = p_number
	card_name = p_name
	order = p_order
	order_count = p_order_count
	action = p_action
	random_hex = p_random_hex
	dice_value = p_dice_value
