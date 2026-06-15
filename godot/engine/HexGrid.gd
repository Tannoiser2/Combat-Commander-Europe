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

## Arrotondamento cubico corretto (mantiene x+y+z=0): dà una vera linea di
## esagoni con celle consecutive adiacenti.
static func _cube_round(x: float, y: float, z: float) -> Vector3i:
	var rx := roundf(x)
	var ry := roundf(y)
	var rz := roundf(z)
	var dx := absf(rx - x)
	var dy := absf(ry - y)
	var dz := absf(rz - z)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector3i(int(rx), int(ry), int(rz))


## Elevazione di un esagono (0 se fuori mappa).
static func _elev(state: GameState, q: int, r: int) -> int:
	var hd: GameState.HexData = state.hex_at(q, r)
	return hd.elevation if hd != null else 0


## Sequenza di esagoni (adiacenti) sulla linea da (q1,r1) a (q2,r2), estremi inclusi.
static func line(q1: int, r1: int, q2: int, r2: int) -> Array[Vector2i]:
	var dist := distance(q1, r1, q2, r2)
	var result: Array[Vector2i] = []
	if dist == 0:
		result.append(Vector2i(q1, r1))
		return result
	var c1 := Vector3(_to_cube(q1, r1))
	var c2 := Vector3(_to_cube(q2, r2))
	for i in range(0, dist + 1):
		var t := float(i) / float(dist)
		var cube := _cube_round(
			lerp(c1.x, c2.x, t), lerp(c1.y, c2.y, t), lerp(c1.z, c2.z, t))
		result.append(_from_cube(cube))
	return result


## Linea di vista da (q1,r1) a (q2,r2). Bloccata da terreno opaco o elevazione
## più alta degli estremi negli esagoni intermedi, e da lati BOCAGE (sempre) o
## MURO/SIEPE su un lato NON di estremità. Un lato LOS_CLEAR è un varco libero.
static func has_los(
	q1: int, r1: int, q2: int, r2: int,
	state: GameState
) -> bool:
	var dist := distance(q1, r1, q2, r2)
	if dist == 0:
		return true
	var path := line(q1, r1, q2, r2)
	var max_end_elev := maxi(_elev(state, q1, r1), _elev(state, q2, r2))

	# Esagoni intermedi: terreno opaco o collina più alta degli estremi.
	for i in range(1, dist):
		var hd: GameState.HexData = state.hex_at(path[i].x, path[i].y)
		if hd == null:
			continue
		if Domain.TERRAIN_BLOCKS_LOS.get(hd.terrain, false):
			return false
		if hd.elevation > max_end_elev:
			return false

	# Lati di esagono attraversati.
	for i in range(0, dist):
		var feat := state.side_feature_between(path[i], path[i + 1])
		if feat == Domain.HexsideFeature.LOS_CLEAR:
			continue
		if feat == Domain.HexsideFeature.BOCAGE:
			return false
		var is_endpoint := i == 0 or i == dist - 1
		if not is_endpoint and (feat == Domain.HexsideFeature.WALL or feat == Domain.HexsideFeature.HEDGE):
			return false
	return true


## Ostacolo cumulativo (hindrance) lungo la LOS: somma degli hindrance del
## terreno negli esagoni intermedi. Riduce la potenza di fuoco.
static func los_hindrance(q1: int, r1: int, q2: int, r2: int, state: GameState) -> int:
	var dist := distance(q1, r1, q2, r2)
	if dist <= 1:
		return 0
	var path := line(q1, r1, q2, r2)
	var total := 0
	for i in range(1, dist):
		var hd: GameState.HexData = state.hex_at(path[i].x, path[i].y)
		if hd != null:
			total += int(Domain.TERRAIN_HINDRANCE.get(hd.terrain, 0))
	return total


# ─── BFS — esagoni raggiungibili ─────────────────────────────────────────────

## Costo per entrare in (tq,tr) venendo da (fq,fr): terreno + attraversamento
## del lato (muro/siepe/bocage/torrente = +1, dirupo = impassabile) e tariffa
## strada (1 PM se entrambi gli esagoni sono su strada). -1 se impraticabile.
static func step_cost(state: GameState, fq: int, fr: int, tq: int, tr: int) -> int:
	var hd: GameState.HexData = state.hex_at(tq, tr)
	if hd == null:
		return -1
	var base: int = Domain.TERRAIN_MOVE_COST.get(hd.terrain, 1)
	if base >= 99:
		return -1
	var fhd: GameState.HexData = state.hex_at(fq, fr)
	if hd.has_road and fhd != null and fhd.has_road:
		base = 1  # movimento lungo la strada
	var feat := state.side_feature_between(Vector2i(fq, fr), Vector2i(tq, tr))
	if feat == Domain.HexsideFeature.CLIFF:
		return -1
	if feat == Domain.HexsideFeature.WALL or feat == Domain.HexsideFeature.BOCAGE \
			or feat == Domain.HexsideFeature.HEDGE or feat == Domain.HexsideFeature.STREAM_SIDE:
		base += 1
	return base


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
			var cost := step_cost(state, cq, cr, nb.x, nb.y)
			if cost < 0:
				continue
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
	var cost := step_cost(state, u.q, u.r, tq, tr)
	if cost < 0 or cost > remaining_mp:
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
