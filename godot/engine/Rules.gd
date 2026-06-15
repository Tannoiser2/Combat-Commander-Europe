## Regole pure di Combat Commander: Europe non legate al fuoco diretto.
## Tiri di morale (Recupero), comando dei leader, corpo a corpo (Avanzata/O21)
## e ritirata (Rotta/O23). Logica pura, nessuna dipendenza dalla scena grafica.
##
## Riferimento: ROADMAP.md (cross-check col rulebook 20th Anniversary).
class_name Rules
extends RefCounted


# ─── Dadi ──────────────────────────────────────────────────────────────────────

## Tira due dadi e restituisce (d1, d2).
static func roll_dice(rng: RandomNumberGenerator) -> Vector2i:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	return Vector2i(rng.randi_range(1, 6), rng.randi_range(1, 6))


# ─── Comando dei leader ──────────────────────────────────────────────────────

## Miglior bonus di Comando tra i leader efficienti della fazione nell'esagono.
## 0 se non vi sono leader. Usato come bonus FP/morale "nello stesso esagono".
static func command_bonus_at(state: GameState, q: int, r: int, faction: int) -> int:
	var best := 0
	for u in state.units_at(q, r):
		if u.faction == faction and u.is_leader() and u.efficient:
			best = max(best, u.command)
	return best


## True se esiste un leader efficiente della fazione entro il suo raggio di
## Comando (= valore di comando) dall'esagono (q,r).
static func has_command_at(state: GameState, q: int, r: int, faction: int) -> bool:
	for u in state.units.values():
		if u.faction == faction and u.is_leader() and u.efficient and u.command > 0:
			if HexGrid.distance(u.q, u.r, q, r) <= u.command:
				return true
	return false


# ─── Recupero (O22) ────────────────────────────────────────────────────────────

## Tiro di Morale per recuperare un'unità rotta: successo se 2d6 ≤ Morale
## (+ bonus di Comando di un leader nello stesso esagono). Modifica l'unità.
static func try_recover(
	state: GameState, u: Unit, rng: RandomNumberGenerator
) -> Dictionary:
	var dice := roll_dice(rng)
	var roll := dice.x + dice.y
	var target := u.morale + command_bonus_at(state, u.q, u.r, u.faction)
	var success := roll <= target
	if success:
		u.recover()
	return { "unit": u.id, "roll": roll, "target": target, "success": success }


# ─── Corpo a corpo / Avanzata (O21) ──────────────────────────────────────────

class MeleeResult:
	var atk_total: int = 0
	var def_total: int = 0
	var atk_dice: Vector2i = Vector2i.ZERO
	var def_dice: Vector2i = Vector2i.ZERO
	var winner: int = -1            ## Domain.Faction vincitrice
	var eliminated: Array[String] = []
	var log_line: String = ""


## Somma FP di un gruppo per il corpo a corpo: FP effettivo (dimezzato se rotto)
## + 1 per ogni unità con FP "in riquadro" + miglior Comando dei leader del gruppo.
## Accetta Array non tipizzato (Array.filter() restituisce Array non tipizzato).
static func _melee_strength(units: Array) -> int:
	var total := 0
	var best_cmd := 0
	for u in units:
		total += u.effective_fp()
		if u.fp_boxed:
			total += 1
		if u.is_leader():
			best_cmd = max(best_cmd, u.command)
	return total + best_cmd


## Risolve un corpo a corpo (O21). attackers/defenders sono gli UOMINI nell'hex.
## In pareggio vince chi NON detiene l'iniziativa. Il lato perdente perde TUTTE
## le unità partecipanti (rulebook 20th Anniversary). Modifica lo stato.
static func resolve_melee(
	state: GameState,
	attackers: Array, defenders: Array,
	initiative_faction: int,
	rng: RandomNumberGenerator
) -> MeleeResult:
	var res := MeleeResult.new()
	if attackers.is_empty() or defenders.is_empty():
		res.log_line = "Corpo a corpo annullato: manca uno dei due lati."
		return res

	var atk_faction: int = attackers[0].faction
	var def_faction: int = defenders[0].faction

	res.atk_dice = roll_dice(rng)
	res.def_dice = roll_dice(rng)
	res.atk_total = _melee_strength(attackers) + res.atk_dice.x + res.atk_dice.y
	res.def_total = _melee_strength(defenders) + res.def_dice.x + res.def_dice.y

	var loser_faction: int
	if res.atk_total > res.def_total:
		res.winner = atk_faction
		loser_faction = def_faction
	elif res.def_total > res.atk_total:
		res.winner = def_faction
		loser_faction = atk_faction
	else:
		# Pareggio: vince chi NON ha l'iniziativa.
		res.winner = atk_faction if initiative_faction != atk_faction else def_faction
		loser_faction = def_faction if res.winner == atk_faction else atk_faction

	# Il lato perdente perde tutte le unità partecipanti.
	var losers := attackers if loser_faction == atk_faction else defenders
	for u in losers:
		res.eliminated.append(u.id)
		state.units.erase(u.id)

	res.log_line = "Corpo a corpo: ATT %d (FP+%d+%d) vs DIF %d (FP+%d+%d) → vince %s, eliminate %d unità" % [
		res.atk_total, res.atk_dice.x, res.atk_dice.y,
		res.def_total, res.def_dice.x, res.def_dice.y,
		Domain.FACTION_SHORT.get(res.winner, "?"), res.eliminated.size()
	]
	return res


# ─── Rotta (O23) ─────────────────────────────────────────────────────────────

## Colonna del bordo amico verso cui si ritirano le unità rotte.
## Convenzione scenario 1: Germania a est (destra), Russia a ovest (sinistra).
static func friendly_edge_col(state: GameState, faction: int) -> int:
	return state.map_cols - 1 if faction == Domain.Faction.GERMAN else 0


## Distanza dall'unità nemica più vicina (grande se nessun nemico).
static func _nearest_enemy_dist(state: GameState, q: int, r: int, faction: int) -> int:
	var best := 9999
	for u in state.units.values():
		if u.faction != faction and u.is_man():
			best = min(best, HexGrid.distance(q, r, u.q, u.r))
	return best


## Ritira un'unità rotta (Rotta/O23). N = (2d6 − Morale) esagoni verso il bordo
## amico, lontano dai nemici. Se non può muovere ed è adiacente a un nemico viene
## eliminata. Modifica posizione/stato dell'unità.
static func rout_unit(
	state: GameState, u: Unit, rng: RandomNumberGenerator
) -> Dictionary:
	var dice := roll_dice(rng)
	var roll := dice.x + dice.y
	var steps := roll - u.morale
	var moved := 0
	var eliminated := false

	if steps > 0:
		var edge := friendly_edge_col(state, u.faction)
		for _i in range(steps):
			var best := Vector2i(u.q, u.r)
			var best_score := _rout_score(state, u.q, u.r, edge, u.faction)
			for nb in HexGrid.neighbors(u.q, u.r):
				if not _rout_passable(state, nb, u):
					continue
				var sc := _rout_score(state, nb.x, nb.y, edge, u.faction)
				if sc < best_score:
					best_score = sc
					best = nb
			if best == Vector2i(u.q, u.r):
				break  # bloccata
			u.q = best.x
			u.r = best.y
			moved += 1

	if moved == 0 and _nearest_enemy_dist(state, u.q, u.r, u.faction) <= 1:
		# Nessuna via di fuga e nemico adiacente → eliminata.
		eliminated = true
		state.units.erase(u.id)

	return {
		"unit": u.id, "roll": roll, "steps": max(0, steps),
		"moved": moved, "eliminated": eliminated
	}


## Punteggio di un esagono per la ritirata: minore è meglio.
## Priorità alla distanza dal bordo amico, poi alla lontananza dai nemici.
static func _rout_score(state: GameState, q: int, r: int, edge_col: int, faction: int) -> int:
	var to_edge := abs(q - edge_col)
	var enemy_dist := _nearest_enemy_dist(state, q, r, faction)
	return to_edge * 10 - min(enemy_dist, 9)


## Un esagono è percorribile in ritirata: in mappa, niente nemici, terreno
## praticabile, stacking rispettato.
static func _rout_passable(state: GameState, nb: Vector2i, u: Unit) -> bool:
	if nb.x < 0 or nb.x >= state.map_cols or nb.y < 0 or nb.y >= state.map_rows:
		return false
	var hd: GameState.HexData = state.hex_at(nb.x, nb.y)
	if hd == null:
		return false
	if Domain.TERRAIN_MOVE_COST.get(hd.terrain, 1) >= 99:
		return false
	var men := state.men_at(nb.x, nb.y)
	for m in men:
		if m.faction != u.faction:
			return false
	return men.size() < 8
