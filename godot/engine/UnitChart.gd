## Database statistiche unità per gli scenari "stand-in".
##
## Gli ordini di battaglia (catalog.json) elencano le unità per ETICHETTA
## (es. "Rifle", "Heavy MG", "Lt. Schrader"). Qui ogni etichetta è tradotta in
## statistiche standard di Combat Commander e in un'arte counter disponibile
## (Tedeschi/Russi). È un'approssimazione voluta: finché non ci sono i mazzi e
## l'artwork delle singole nazioni, tutte le fazioni Axis usano i Tedeschi e
## tutte le Allied i Russi.
class_name UnitChart
extends RefCounted


## Categoria di un'etichetta: come va trattata dal loader di scenario.
enum Cat { LEADER, SQUAD, WEAPON, FOXHOLE, SKIP }

## Equipaggiamenti/fortificazioni non modellati come unità (per ora ignorati).
const _SKIP := {
	"Wire": true, "Mines": true, "Bunker": true, "Bunker Complex": true,
	"Radio 75mm": true, "Radio 81mm": true, "Radio 88mm": true, "Radio 105mm": true,
	"Flamethrower": true, "Satchel Charge": true, "Molotov Cocktail": true,
}

## Squadre d'élite (alto morale, gittata piena).
const _ELITE := {
	"Elite": true, "Elite Rifle": true, "Guards": true, "Guards Rifle": true,
	"SS": true, "Parachute": true, "Paratroop": true, "Pionier": true,
	"Engineer": true, "Guastatori": true,
}
## Squadre mitra (alta potenza a corto raggio).
const _SMG := { "SMG": true, "Guards SMG": true, "Sissi": true }
## Squadre di leva/scarse.
const _CONSCRIPT := { "Conscript": true, "Militia": true, "Green": true }


## Determina la categoria dell'etichetta.
static func category(label: String) -> int:
	if _SKIP.has(label):
		return Cat.SKIP
	if label == "Foxholes" or label == "Trench":
		return Cat.FOXHOLE
	if _is_leader(label):
		return Cat.LEADER
	if _is_weapon(label):
		return Cat.WEAPON
	return Cat.SQUAD


static func _is_leader(label: String) -> bool:
	return label.begins_with("Lt.") or label.begins_with("Sgt.") \
		or label.begins_with("Cpl.") or label.begins_with("Cpt.") \
		or label.contains("Hero")


static func _is_weapon(label: String) -> bool:
	return label.ends_with("MG") or label.contains("Mortar") \
		or label.contains("Gun") or label.contains("Howitzer") or label.contains("'75")


## Costruisce una Unit per l'etichetta, fazione (GERMAN/RUSSIAN), id e posizione.
static func build_unit(id: String, faction: int, label: String, q: int, r: int) -> Unit:
	var cat := category(label)
	var u: Unit
	if cat == Cat.LEADER:
		u = _leader(id, faction, label)
	elif cat == Cat.WEAPON:
		u = _weapon(id, faction, label)
	else:
		u = _squad(id, faction, label)
	u.q = q
	u.r = r
	return u


static func _mk(id: String, faction: int, type: int, cls: int, name: String) -> Unit:
	return Unit.new(id, faction, type, cls, name)


# ─── Leader ──────────────────────────────────────────────────────────────────

static func _leader(id: String, faction: int, label: String) -> Unit:
	var fp := 1; var mor := 8; var cmd := 1; var cls := Domain.UnitClass.RIFLE
	if label.begins_with("Cpt."):
		mor = 10; cmd = 2; cls = Domain.UnitClass.ELITE
	elif label.begins_with("Lt.") or label.contains("Hero"):
		fp = 2; mor = 9; cmd = 2; cls = Domain.UnitClass.ELITE
	elif label.begins_with("Sgt."):
		mor = 8; cmd = 1
	else:  # Cpl.
		mor = 7; cmd = 1
	var u := _mk(id, faction, Domain.UnitType.LEADER, cls, label)
	u.fp = fp; u.fp_boxed = false
	u.range = 1; u.range_boxed = false
	u.move = 6; u.morale = mor; u.command = cmd; u.move_penalty = 0
	u.art_name = _leader_art(faction, label)
	return u


static func _leader_art(faction: int, label: String) -> String:
	var senior := label.begins_with("Lt.") or label.begins_with("Cpt.") \
		or label.begins_with("Sgt.") or label.contains("Hero")
	if faction == Domain.Faction.GERMAN:
		return "Lieutenant Y" if senior else "Corporal X"
	return "Sergeant Y" if senior else "Corporal Y"


# ─── Squadre ─────────────────────────────────────────────────────────────────

static func _squad(id: String, faction: int, label: String) -> Unit:
	var fp := 5; var rng := 5; var rng_b := true; var mor := 7
	var cls := Domain.UnitClass.RIFLE
	if _ELITE.has(label):
		fp = 6; rng = 6; rng_b = true; mor = 8; cls = Domain.UnitClass.ELITE
	elif _SMG.has(label):
		fp = 7; rng = 3; rng_b = false; mor = 8; cls = Domain.UnitClass.ELITE
	elif _CONSCRIPT.has(label):
		fp = 4; rng = 3; rng_b = false; mor = 6; cls = Domain.UnitClass.CONSCRIPT
	elif label == "BAR":
		fp = 6; rng = 6; rng_b = true; mor = 7
	elif label == "Fucilieri":
		fp = 4; rng = 4; rng_b = false; mor = 6
	elif label == "Weapon Team":
		fp = 2; rng = 4; rng_b = false; mor = 7
	var u := _mk(id, faction, Domain.UnitType.SQUAD, cls, label)
	u.fp = fp; u.fp_boxed = false
	u.range = rng; u.range_boxed = rng_b
	u.move = 4; u.morale = mor; u.command = 0; u.move_penalty = 0
	u.art_name = "Rifle"
	return u


# ─── Armi ────────────────────────────────────────────────────────────────────

static func _weapon(id: String, faction: int, label: String) -> Unit:
	var fp := 4; var rng := 8; var mp := -1; var cls := Domain.UnitClass.MG
	var heavy := false
	if label == "Medium MG":
		fp = 6; rng = 10; mp = -2; heavy = true
	elif label == "Heavy MG" or label == ".50cal MG":
		fp = 8; rng = 12; mp = -3; heavy = true
	elif label.contains("Mortar"):
		fp = 5; rng = 10; mp = -2; cls = Domain.UnitClass.MORTAR; heavy = true
	elif label.contains("Gun") or label.contains("Howitzer") or label.contains("'75"):
		fp = 8; rng = 14; mp = -3; cls = Domain.UnitClass.AT; heavy = true
	var u := _mk(id, faction, Domain.UnitType.WEAPON, cls, label)
	u.fp = fp; u.fp_boxed = true
	u.range = rng; u.range_boxed = false
	u.move = 0; u.morale = 0; u.command = 0; u.move_penalty = mp
	# Arte: i Tedeschi hanno solo "Light MG"; i Russi anche "Medium MG".
	if faction == Domain.Faction.RUSSIAN and heavy:
		u.art_name = "Medium MG"
	else:
		u.art_name = "Light MG"
	return u
