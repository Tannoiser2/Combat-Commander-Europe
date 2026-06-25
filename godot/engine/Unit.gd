## Dati di un'unità in gioco (pedina).
## RefCounted = dati puri, nessun nodo grafico allegato.
class_name Unit
extends RefCounted


var id: String
var faction: int       # Domain.Faction
var type: int          # Domain.UnitType
var unit_class: int    # Domain.UnitClass
var unit_name: String
var art_name: String = ""  ## Nome del file segnalino (senza estensione), es. "Lieutenant Y"
var nation_art: String = ""  ## Cartella arte della nazione reale (es. "Americani"); "" → stand-in

# ─── Statistiche (dalla pedina fisica) ───────────────────────────────────────
var fp: int = 0
var fp_boxed: bool = false
var range: int = 0
var range_boxed: bool = false
var move: int = 4
var morale: int = 7
var command: int = 0       # solo leader: valore in cerchio
var move_penalty: int = 0  # solo armi: malus al PM del trasportatore
var ordnance: bool = false # arma a barra bianca (mortaio/cannone): Targeting Roll
var min_range: int = 0     # gittata minima (mortai: non possono sparare troppo vicino)

# ─── Posizione sulla griglia ─────────────────────────────────────────────────
var q: int = 0
var r: int = 0

# ─── Stato ───────────────────────────────────────────────────────────────────
var efficient: bool = true    ## true = efficiente, false = inefficiente (rovesciata)
var suppressed: bool = false  ## marcatore di soppressione
var activated: bool = false   ## già attivata in questo turno
var veteran: bool = false     ## marcatore veterano
var concealed: bool = false   ## Mimetizzazione A29 armata (one-shot): sul prossimo
                              ## attacco subìto riduce il totale d'attacco della Copertura, poi si consuma
var hero: bool = false        ## Eroe (E58): leader a figura singola, mai sul Casualty Track


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


## "Soldier icons" ai fini dell'impilamento (max 7/esagono, regola 8.2):
## squadra = 4, team = 2, leader = 1, arma = 0 (le armi non contano come figure).
func soldier_icons() -> int:
	match type:
		Domain.UnitType.SQUAD:
			return 4
		Domain.UnitType.TEAM:
			return 2
		Domain.UnitType.LEADER:
			return 1
		_:
			return 0


# ─── Stato di rottura (CC:E) ───────────────────────────────────────────────────
# Un'unità è "Rotta" quando `efficient == false` (lato rovesciato della pedina).
# Le unità rotte non possono sparare, devono ritirarsi (Rotta) e si recuperano
# con un tiro di Morale (Recupero). Un colpo su un'unità già rotta la elimina.

func is_broken() -> bool:
	return not efficient


## Potenza di fuoco effettiva: dimezzata (lato rovesciato) se rotta.
func effective_fp() -> int:
	return fp if efficient else int(fp / 2)


## Rompe l'unità (lato rovesciato). Stato distinto dalla soppressione.
func break_unit() -> void:
	efficient = false


## Sopprime l'unità (marcatore; resta sul lato efficiente).
func suppress() -> void:
	suppressed = true


## Recupera l'unità: toglie rottura e soppressione (Recupero O22).
func recover() -> void:
	efficient = true
	suppressed = false


func pos() -> Vector2i:
	return Vector2i(q, r)


func hex_key() -> String:
	return "%d,%d" % [q, r]


func clone() -> Unit:
	var u := Unit.new(id, faction, type, unit_class, unit_name)
	u.art_name = art_name
	u.nation_art = nation_art
	u.fp = fp; u.fp_boxed = fp_boxed
	u.range = range; u.range_boxed = range_boxed
	u.move = move; u.morale = morale
	u.command = command; u.move_penalty = move_penalty
	u.ordnance = ordnance; u.min_range = min_range
	u.q = q; u.r = r
	u.efficient = efficient; u.suppressed = suppressed
	u.activated = activated; u.veteran = veteran
	u.concealed = concealed; u.hero = hero
	return u
