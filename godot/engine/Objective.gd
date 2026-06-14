## Un obiettivo sulla mappa.
class_name Objective
extends RefCounted

var id: int
var q: int
var r: int
var vp: int
var secret: bool = false
var controller: int = -1  # -1 = neutro, altrimenti Domain.Faction


func _init(p_id: int, p_q: int, p_r: int, p_vp: int) -> void:
	id = p_id
	q = p_q
	r = p_r
	vp = p_vp


func controller_name() -> String:
	if controller == Domain.Faction.GERMAN:
		return "GER"
	elif controller == Domain.Faction.RUSSIAN:
		return "RUS"
	return "—"
