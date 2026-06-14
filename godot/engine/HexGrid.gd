## Matematica esagonale per griglia flat-top con offset di colonna.
## Tutte le funzioni sono statiche — nessuno stato interno.
class_name HexGrid
extends RefCounted

# Coordinate cubiche dei sei vicini (flat-top, offset colonna pari/dispari).
# Usare neighbors() che gestisce l'offset automaticamente.
const _DIRS_EVEN := [
	Vector2i(1, 0),  Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, -1),Vector2i(-1, 0), Vector2i(0, 1),
]
const _DIRS_ODD := [
	Vector2i(1, 1),  Vector2i(1, 0),  Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]


# ─── Topologia ────────────────────────────────────────────────────────────────

static func neighbors(q: int, r: int) -> Array[Vector2i]:
	var dirs := _DIRS_ODD if (q & 1) else _DIRS_EVEN
	var result: Array[Vector2i] = []
	for d in dirs:
		result.append(Vector2i(q + d.x, r + d.y))
	return result


## Distanza in esagoni tra due celle (metrica cubica convertita da offset).
static func distance(q1: int, r1: int, q2: int, r2: int) -> int:
	var c1 := _to_cube(q1, r1)
	var c2 := _to_cube(q2, r2)
	return (abs(c1.x - c2.x) + abs(c1.y - c2.y) + abs(c1.z - c2.z)) / 2


## Converte coordinate offset (q, r) in coordinate cubiche (x, y, z).
static func _to_cube(q: int, r: int) -> Vector3i:
	var x := q
	var z := r - (q - (q & 1)) / 2
	var y := -x - z
	return Vector3i(x, y, z)


## Converte coordinate cubiche in offset.
static func _from_cube(cube: Vector3i) -> Vector2i:
	var q := cube.x
	var r := cube.z + (cube.x - (cube.x & 1)) / 2
	return Vector2i(q, r)


# ─── Linea di vista (LOS) ────────────────────────────────────────────────────

## Restituisce true se non vi sono ostacoli tra (q1,r1) e (q2,r2).
## Usa interpolazione lineare sulle coordinate cubiche.
static func has_los(
	q1: int, r1: int, q2: int, r2: int,
	state: GameState
) -> bool:
	var dist := distance(q1, r1, q2, r2)
	if dist == 0:
		return true
	var c1 := Vector3(_to_cube(q1, r1))
	var c2 := Vector3(_to_cube(q2, r2))
	# Controlla solo le celle intermedie (non sorgente né destinazione)
	for i in range(1, dist):
		var t := float(i) / float(dist)
		var cx := int(round(lerp(c1.x, c2.x, t)))
		var cy := int(round(lerp(c1.y, c2.y, t)))
		var cz := int(round(lerp(c1.z, c2.z, t)))
		var off := _from_cube(Vector3i(cx, cy, cz))
		var hd: GameState.HexData = state.hex_at(off.x, off.y)
		if hd and Domain.TERRAIN_BLOCKS_LOS.get(hd.terrain, false):
			return false
	return true


# ─── BFS — esagoni raggiungibili ─────────────────────────────────────────────

## Restituisce tutti gli esagoni raggiungibili dall'unità u in questo stato.
## Rispetta i costi di movimento e i confini della mappa.
static func reachable(u: Unit, state: GameState) -> Array[Vector2i]:
	if u.move <= 0:
		return []
	var budget := u.move
	# BFS con costo: dizionario "q,r" → PM spesi fin qui
	var visited := {}
	var frontier := [{"q": u.q, "r": u.r, "spent": 0}]
	visited["%d,%d" % [u.q, u.r]] = 0
	var result: Array[Vector2i] = []

	while frontier.size() > 0:
		var current = frontier.pop_front()
		var cq: int = current["q"]
		var cr: int = current["r"]
		var spent: int = current["spent"]

		for nb in neighbors(cq, cr):
			if nb.x < 0 or nb.x >= state.map_cols or nb.y < 0 or nb.y >= state.map_rows:
				continue
			var hd: GameState.HexData = state.hex_at(nb.x, nb.y)
			if hd == null:
				continue
			var cost: int = Domain.TERRAIN_MOVE_COST.get(hd.terrain, 1)
			var total := spent + cost
			if total > budget:
				continue
			var key := "%d,%d" % [nb.x, nb.y]
			if visited.has(key) and visited[key] <= total:
				continue
			# Non entrare in esagoni occupati dal nemico
			var occupants := state.men_at(nb.x, nb.y)
			var enemy_present := false
			for occ in occupants:
				if occ.faction != u.faction:
					enemy_present = true
					break
			if enemy_present:
				continue
			# Controllo stacking: max 8 uomini
			if u.is_man():
				var men_count := state.men_at(nb.x, nb.y).size()
				if men_count >= 8:
					continue
			visited[key] = total
			frontier.append({"q": nb.x, "r": nb.y, "spent": total})
			result.append(Vector2i(nb.x, nb.y))

	return result


## Costo effettivo per muovere u dall'esagono corrente a (tq, tr).
## Restituisce -1 se irraggiungibile entro i PM disponibili rimasti.
static func move_cost(
	u: Unit, tq: int, tr: int, remaining_mp: int, state: GameState
) -> int:
	var hd: GameState.HexData = state.hex_at(tq, tr)
	if hd == null:
		return -1
	var cost: int = Domain.TERRAIN_MOVE_COST.get(hd.terrain, 1)
	if cost > remaining_mp:
		return -1
	return cost


## Esagoni entro raggio r da (q0,r0), bordi mappa esclusi.
static func hexes_in_range(
	q0: int, r0: int, max_range: int, state: GameState
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dq in range(-max_range, max_range + 1):
		for dr in range(-max_range, max_range + 1):
			var q := q0 + dq
			var r := r0 + dr
			if q < 0 or q >= state.map_cols or r < 0 or r >= state.map_rows:
				continue
			if distance(q0, r0, q, r) <= max_range:
				result.append(Vector2i(q, r))
	return result
