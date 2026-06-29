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


## Vicino nella direzione `dir` (0-5, bussola esagonale). Usato dalla deriva
## della granata d'artiglieria (O18.2.2).
static func step_dir(q: int, r: int, dir: int) -> Vector2i:
	var dirs := _DIRS_ODD if (q & 1) else _DIRS_EVEN
	var d: Vector2i = dirs[dir % 6]
	return Vector2i(q + d.x, r + d.y)


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


# Tipo di linea di vista (per la "Modalità LOS" dell'interfaccia).
const LOS_CLEAR := 0     ## libera (verde)
const LOS_HINDERED := 1  ## libera ma con ostacolo/hindrance (giallo)
const LOS_BLOCKED := 2   ## bloccata (rosso)


## Classifica la LOS tra due esagoni in libera / ostacolata / bloccata.
static func los_kind(q1: int, r1: int, q2: int, r2: int, state: GameState) -> int:
	if not has_los(q1, r1, q2, r2, state):
		return LOS_BLOCKED
	if los_hindrance(q1, r1, q2, r2, state) > 0:
		return LOS_HINDERED
	return LOS_CLEAR


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


## Hindrance lungo la LOS (10.3.3): NON cumulativo — si usa il modificatore
## SINGOLO più grande, non la somma (due Brush = −3, non −6). Considera il
## terreno degli esagoni intermedi e il fumo, che ostacola anche entrando/
## uscendo (10.3.4): quindi conta anche sull'esagono del tiratore e del bersaglio.
const SMOKE_HINDRANCE := 3   ## modello a fumo booleano: valore rappresentativo

static func los_hindrance(q1: int, r1: int, q2: int, r2: int, state: GameState) -> int:
	var best := 0
	# Fumo sull'esagono del tiratore o del bersaglio (10.3.4).
	for p in [Vector2i(q1, r1), Vector2i(q2, r2)]:
		var ehd: GameState.HexData = state.hex_at(p.x, p.y)
		if ehd != null and ehd.has_smoke:
			best = maxi(best, SMOKE_HINDRANCE)
	var dist := distance(q1, r1, q2, r2)
	if dist <= 1:
		return best
	var path := line(q1, r1, q2, r2)
	for i in range(1, dist):
		var hd: GameState.HexData = state.hex_at(path[i].x, path[i].y)
		if hd != null:
			best = maxi(best, int(Domain.TERRAIN_HINDRANCE.get(hd.terrain, 0)))
			if hd.has_smoke:
				best = maxi(best, SMOKE_HINDRANCE)
	return best


# ─── BFS — esagoni raggiungibili ─────────────────────────────────────────────

## Costo per entrare in (tq,tr) venendo da (fq,fr): terreno + attraversamento
## del lato (muro/siepe/bocage/torrente = +1, dirupo = impassabile) e tariffa
## strada (1 PM se entrambi gli esagoni sono su strada). -1 se impraticabile.
static func step_cost(state: GameState, fq: int, fr: int, tq: int, tr: int) -> int:
	var hd: GameState.HexData = state.hex_at(tq, tr)
	if hd == null:
		return -1
	if hd.has_blaze:
		return -1  # incendio (E46): esagono impassabile
	var base: int = Domain.TERRAIN_MOVE_COST.get(hd.terrain, 1)
	if base >= 99:
		return -1
	var fhd: GameState.HexData = state.hex_at(fq, fr)
	if fhd != null and ((hd.has_road and fhd.has_road) \
			or (hd.has_trail and fhd.has_trail) \
			or (hd.has_railway and fhd.has_railway)):
		base = 1  # tariffa strada lungo strada/sentiero/ferrovia
	var feat := state.side_feature_between(Vector2i(fq, fr), Vector2i(tq, tr))
	if feat == Domain.HexsideFeature.CLIFF:
		return -1
	if feat == Domain.HexsideFeature.WALL or feat == Domain.HexsideFeature.BOCAGE \
			or feat == Domain.HexsideFeature.HEDGE or feat == Domain.HexsideFeature.STREAM_SIDE:
		base += 1
	# Salita (T88.1): +1 PM per entrare in un esagono a quota SUPERIORE. La quota è
	# il campo `elevation`, con un minimo implicito dal terreno collina (HILL1/2).
	var to_elev: int = maxi(hd.elevation, _terrain_elevation(hd.terrain))
	var from_elev: int = maxi(fhd.elevation, _terrain_elevation(fhd.terrain)) if fhd != null else 0
	if to_elev > from_elev:
		base += 1
	return base


## Quota implicita di un terreno collina, se l'esagono non porta già un valore di
## `elevation` esplicito (così la regola di salita vale anche sulle mappe che
## codificano le colline solo come tipo di terreno).
static func _terrain_elevation(terrain: int) -> int:
	match terrain:
		Domain.TerrainType.HILL1:
			return 1
		Domain.TerrainType.HILL2:
			return 2
	return 0


## Restituisce tutti gli esagoni raggiungibili dall'unità u in questo stato.
## Rispetta i costi di movimento e i confini della mappa.
## Esagoni raggiungibili dall'unità. `budget_override` >= 0 usa quei PM (per i
## passi successivi di una mossa già avviata); altrimenti l'allowance pieno.
static func reachable(u: Unit, state: GameState, budget_override: int = -1) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for key in reachable_costs(u, state, budget_override):
		var p := String(key).split(",")
		result.append(Vector2i(int(p[0]), int(p[1])))
	return result


## Come reachable(), ma restituisce una mappa "q,r" → PM minimi necessari per
## raggiungere quell'esagono (per mostrare il costo del movimento sulla mappa).
## L'esagono di partenza non è incluso. Stessa BFS con costo di reachable().
static func reachable_costs(u: Unit, state: GameState, budget_override: int = -1, out_came: Dictionary = {}) -> Dictionary:
	var costs := {}
	var budget := u.move if budget_override < 0 else budget_override
	if budget <= 0:
		return costs
	# BFS con costo: dizionario "q,r" → PM spesi fin qui
	var visited := {}
	var frontier := [{"q": u.q, "r": u.r, "spent": 0}]
	visited["%d,%d" % [u.q, u.r]] = 0

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
			# Controllo impilamento: max 7 soldier icons (8.1)
			if u.is_man() and state.soldier_icons_at(nb.x, nb.y) + u.soldier_icons() > 7:
				continue
			visited[key] = total
			costs[key] = total
			out_came[key] = "%d,%d" % [cq, cr]
			# Filo (F106) / Mine (F103): entrando, il movimento si ferma qui —
			# non espandere oltre, così l'anteprima riflette lo stop reale.
			var nhd: GameState.HexData = state.hex_at(nb.x, nb.y)
			var stops := nhd != null and (nhd.fortification == Domain.Fort.WIRE \
				or nhd.fortification == Domain.Fort.MINES)
			if not stops:
				frontier.append({"q": nb.x, "r": nb.y, "spent": total})

	return costs


## Percorso a costo minimo da u fino a (tq,tr) entro `budget` PM: lista ordinata
## di esagoni ATTRAVERSATI (passi adiacenti), partenza esclusa, destinazione
## inclusa; vuota se irraggiungibile. Serve a muovere passo-passo, così costo del
## terreno, Mine, Filo e Fuoco di Opportunità scattano a OGNI esagono entrato.
static func path_to(u: Unit, state: GameState, tq: int, tr: int, budget_override: int = -1) -> Array[Vector2i]:
	var came := {}
	var costs := reachable_costs(u, state, budget_override, came)
	var path: Array[Vector2i] = []
	var dest := "%d,%d" % [tq, tr]
	if not costs.has(dest):
		return path
	var start := "%d,%d" % [u.q, u.r]
	var k := dest
	while k != start and came.has(k):
		var p := String(k).split(",")
		path.insert(0, Vector2i(int(p[0]), int(p[1])))
		k = String(came[k])
	return path


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
