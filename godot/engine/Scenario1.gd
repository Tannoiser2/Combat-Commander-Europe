## Scenario 1: "Fat Lipki" — Fronte Orientale, Russia 1941
## Germania (AXIS, destra) contro Russia (ALLIES, sinistra)
## Mappa A: 15 colonne × 10 righe, esagoni flat-top
class_name Scenario1
extends RefCounted

const MAP_COLS := 15
const MAP_ROWS := 10
const SCENARIO_ID := "fat_lipki"
const SCENARIO_NAME := "FAT LIPKI"

# ─── Griglia terreno ─────────────────────────────────────────────────────────
# O=aperto  W=bosco  B=edificio  R=strada  P=torrente  G=grano(aperto)
# q=colonna (0=sinistra), r=riga (0=alto, lato ALLIES)

const _RAW := [
	#      r0   r1   r2   r3   r4   r5   r6   r7   r8   r9
	["O","O","W","W","O","O","O","O","O","O"],  # q0
	["O","O","W","W","O","O","O","O","O","O"],  # q1
	["G","G","W","W","O","O","O","O","O","O"],  # q2
	["G","G","O","W","W","O","O","O","O","O"],  # q3
	["O","O","O","O","R","W","W","O","O","O"],  # q4
	["O","B","O","O","R","O","O","B","O","O"],  # q5
	["O","O","O","O","R","P","P","O","O","O"],  # q6
	["O","O","O","O","R","P","O","O","O","O"],  # q7
	["O","O","O","R","O","O","O","O","W","O"],  # q8
	["O","O","R","O","O","O","O","W","W","O"],  # q9
	["O","O","O","O","O","O","W","W","W","O"],  # q10
	["O","O","O","O","O","W","W","W","O","O"],  # q11
	["O","O","O","O","O","O","W","W","O","O"],  # q12
	["O","O","O","O","O","O","O","W","O","O"],  # q13
	["O","O","O","O","O","O","O","O","O","O"],  # q14
]

const _CODE := {
	"O": Domain.TerrainType.OPEN,
	"W": Domain.TerrainType.WOODS,
	"B": Domain.TerrainType.BUILDING,
	"R": Domain.TerrainType.ROAD,
	"P": Domain.TerrainType.STREAM,
	"G": Domain.TerrainType.OPEN,
}

# ─── Parametri scenario ───────────────────────────────────────────────────────

const SETUP := {
	"time_start":         2,
	"sudden_death":       7,
	"german_surrender":   5,
	"russian_surrender":  7,
	"initiative_holder":  Domain.Faction.GERMAN,
	"german_orders":      2,
	"russian_orders":     3,
}

# ─── Metodi di costruzione ────────────────────────────────────────────────────

static func build_map() -> Dictionary:
	var hexes := {}
	for q in MAP_COLS:
		var col: Array = _RAW[q] if q < _RAW.size() else []
		for r in MAP_ROWS:
			var code: String = col[r] if r < col.size() else "O"
			var terrain: int = _CODE.get(code, Domain.TerrainType.OPEN)
			var hd := GameState.HexData.new(terrain)
			hexes["%d,%d" % [q, r]] = hd
	return hexes


static func build_objectives() -> Array[Objective]:
	var objs: Array[Objective] = []
	objs.append(_obj(1, 5, 1, 2))  # edificio in alto
	objs.append(_obj(2, 5, 7, 2))  # edificio in basso
	objs.append(_obj(3, 7, 4, 3))  # incrocio centrale
	return objs


static func _obj(id: int, q: int, r: int, vp: int) -> Objective:
	return Objective.new(id, q, r, vp)


static func build_units() -> Dictionary:
	var units := {}
	var all := _german_units() + _russian_units()
	for u in all:
		units[u.id] = u
	return units


# ─── Unità tedesche (dalla scheda scenario1.png) ─────────────────────────────
# Lt. v. Karstens (ldr 9/②, 2/1/6), Cpl. Winkler (ldr 6/①, 1/1/6)
# Rifle ×4 (5/[5]/4 mor.7), Light MG ([4]/8/-2)

static func _german_units() -> Array[Unit]:
	var G := Domain.Faction.GERMAN
	var LD := Domain.UnitType.LEADER
	var SQ := Domain.UnitType.SQUAD
	var WP := Domain.UnitType.WEAPON
	var RI := Domain.UnitClass.RIFLE
	var EL := Domain.UnitClass.ELITE
	var MG := Domain.UnitClass.MG

	var list: Array[Unit] = []

	list.append(_u("ger-0", G, LD, EL, "Lt. v. Karstens", "Lieutenant Y",
		2,false, 1,false, 6, 9, 2, 0,   13, 4))
	list.append(_u("ger-1", G, LD, RI, "Cpl. Winkler", "Corporal X",
		1,false, 1,false, 6, 6, 1, 0,   13, 6))
	list.append(_u("ger-2", G, SQ, RI, "Rifle 1", "Rifle",
		5,false, 5,true,  4, 7, 0, 0,   12, 3))
	list.append(_u("ger-3", G, SQ, RI, "Rifle 2", "Rifle",
		5,false, 5,true,  4, 7, 0, 0,   14, 3))
	list.append(_u("ger-4", G, SQ, RI, "Rifle 3", "Rifle",
		5,false, 5,true,  4, 7, 0, 0,   12, 5))
	list.append(_u("ger-5", G, SQ, RI, "Rifle 4", "Rifle",
		5,false, 5,true,  4, 7, 0, 0,   14, 5))
	list.append(_u("ger-6", G, WP, MG, "Light MG", "Light MG",
		4,true,  8,false, -2, 7, 0, -2, 12, 4))

	return list


# ─── Unità russe ─────────────────────────────────────────────────────────────
# Sgt. Kovalev (ldr 8/②, 2/1/6), Cpl. Koylov (ldr 7/①, 1/1/6)
# Rifle ×8 (5/3/4 mor.7), Medium MG ×2 ([6]/10/-2), Light MG ([3]/6/-1)

static func _russian_units() -> Array[Unit]:
	var R := Domain.Faction.RUSSIAN
	var LD := Domain.UnitType.LEADER
	var SQ := Domain.UnitType.SQUAD
	var WP := Domain.UnitType.WEAPON
	var RI := Domain.UnitClass.RIFLE
	var EL := Domain.UnitClass.ELITE
	var MG := Domain.UnitClass.MG

	var list: Array[Unit] = []

	list.append(_u("rus-0", R, LD, EL, "Sgt. Kovalev", "Sergeant Y",
		2,false, 1,false, 6, 8, 2, 0,   1, 4))
	list.append(_u("rus-1", R, LD, RI, "Cpl. Koylov", "Corporal Y",
		1,false, 1,false, 6, 7, 1, 0,   1, 6))
	list.append(_u("rus-2", R, SQ, RI, "Rifle 1", "Rifle",
		5,false, 3,false, 4, 8, 0, 0,   0, 2))
	list.append(_u("rus-3", R, SQ, RI, "Rifle 2", "Rifle",
		5,false, 3,false, 4, 8, 0, 0,   0, 3))
	list.append(_u("rus-4", R, SQ, RI, "Rifle 3", "Rifle",
		5,false, 3,false, 4, 8, 0, 0,   0, 5))
	list.append(_u("rus-5", R, SQ, RI, "Rifle 4", "Rifle",
		5,false, 3,false, 4, 8, 0, 0,   0, 6))
	list.append(_u("rus-6", R, SQ, RI, "Rifle 5", "Rifle",
		5,false, 3,false, 4, 8, 0, 0,   1, 2))
	list.append(_u("rus-7", R, SQ, RI, "Rifle 6", "Rifle",
		5,false, 3,false, 4, 8, 0, 0,   1, 3))
	list.append(_u("rus-8", R, SQ, RI, "Rifle 7", "Rifle",
		5,false, 3,false, 4, 8, 0, 0,   2, 3))
	list.append(_u("rus-9", R, SQ, RI, "Rifle 8", "Rifle",
		5,false, 3,false, 4, 8, 0, 0,   2, 5))
	list.append(_u("rus-10", R, WP, MG, "Medium MG 1", "Medium MG",
		6,true, 10,false, -2, 7, 0, -2, 1, 5))
	list.append(_u("rus-11", R, WP, MG, "Medium MG 2", "Medium MG",
		6,true, 10,false, -2, 7, 0, -2, 2, 4))
	list.append(_u("rus-12", R, WP, MG, "Light MG", "Light MG",
		3,true,  6,false, -1, 7, 0, -1, 0, 4))

	return list


static func _u(
	id: String, faction: int, type: int, cls: int, name: String, art: String,
	fp: int, fp_b: bool, rng: int, rng_b: bool,
	mv: int, mor: int, cmd: int, mv_pen: int,
	q: int, r: int
) -> Unit:
	var u := Unit.new(id, faction, type, cls, name)
	u.art_name = art
	u.fp = fp;  u.fp_boxed = fp_b
	u.range = rng; u.range_boxed = rng_b
	u.move = mv; u.morale = mor
	u.command = cmd; u.move_penalty = mv_pen
	u.q = q; u.r = r
	return u


## Popola uno GameState con i dati dello scenario.
static func setup(state: GameState) -> void:
	# Mappa, terreno, lati e obiettivi dai dati recuperati (dipinti a mano)
	if not MapLoader.load_into(state, "res://assets/maps/map1.json"):
		# Ripiego: griglia minima
		state.map_cols = MAP_COLS
		state.map_rows = MAP_ROWS
		state.hexes = build_map()
		state.objectives = build_objectives()
		for obj in state.objectives:
			var hd: GameState.HexData = state.hex_at(obj.q, obj.r)
			if hd:
				hd.objective_id = obj.id
	state.units = build_units()
	state.time_marker       = SETUP["time_start"]
	state.sudden_death_space = SETUP["sudden_death"]
	state.initiative_holder = SETUP["initiative_holder"]
	state.max_orders        = SETUP["german_orders"]
	state.ai_max_orders     = SETUP["russian_orders"]
	state.active_faction    = Domain.Faction.GERMAN
