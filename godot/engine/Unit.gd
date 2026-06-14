## Dati di un'unità in gioco (pedina).
## RefCounted = dati puri, nessun nodo grafico allegato.
class_name Unit
extends RefCounted


var id: String
var faction: int       # Domain.Faction
var type: int          # Domain.UnitType
var unit_class: int    # Domain.UnitClass
var unit_name: String

# ─── Statistiche (dalla pedina fisica) ───────────────────────────────────────
var fp: int = 0
var fp_boxed: bool = false
var range: int = 0
var range_boxed: bool = false
var move: int = 4
var morale: int = 7
var command: int = 0       # solo leader: valore in cerchio
var move_penalty: int = 0  # solo armi: malus al PM del trasportatore

# ─── Posizione sulla griglia ─────────────────────────────────────────────────
var q: int = 0
var r: int = 0

# ─── Stato ───────────────────────────────────────────────────────────────────
var efficient: bool = true    ## true = efficiente, false = inefficiente (rovesciata)
var suppressed: bool = false  ## marcatore di soppressione
var activated: bool = false   ## già attivata in questo turno
var veteran: bool = false     ## marcatore veterano


func _init(
	p_id: String, p_faction: int, p_type: int,
	p_class: int, p_name: String
) -> void:
	id = p_id
	faction = p_faction
	type = p_type
	unit_class = p_class
	unit_name = p_name


func is_weapon() -> bool:
	return type == Domain.UnitType.WEAPON


func is_leader() -> bool:
	return type == Domain.UnitType.LEADER


func is_man() -> bool:
	return type != Domain.UnitType.WEAPON


func pos() -> Vector2i:
	return Vector2i(q, r)


func hex_key() -> String:
	return "%d,%d" % [q, r]


func clone() -> Unit:
	var u := Unit.new(id, faction, type, unit_class, unit_name)
	u.fp = fp; u.fp_boxed = fp_boxed
	u.range = range; u.range_boxed = range_boxed
	u.move = move; u.morale = morale
	u.command = command; u.move_penalty = move_penalty
	u.q = q; u.r = r
	u.efficient = efficient; u.suppressed = suppressed
	u.activated = activated; u.veteran = veteran
	return u
