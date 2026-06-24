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
			best = maxi(best, u.command)
	return best


## True se esiste un leader efficiente della fazione entro il suo raggio di
## Comando (= valore di comando) dall'esagono (q,r).
static func has_command_at(state: GameState, q: int, r: int, faction: int) -> bool:
	for u in state.units.values():
		if u.faction == faction and u.is_leader() and u.efficient and u.command > 0:
			if HexGrid.distance(u.q, u.r, q, r) <= u.command:
				return true
	return false


## Bonus di Comando per una Squadra/Team co-locata con un leader efficiente
## (3.3.1.2): si applica a FP, Gittata, Movimento e Morale. Non vale per leader
## né per le armi (i leader non influenzano sé stessi o altri leader, 3.3.1.1).
static func unit_command_bonus(state: GameState, u: Unit) -> int:
	if u.is_leader() or u.is_weapon():
		return 0
	return command_bonus_at(state, u.q, u.r, u.faction)


## Bonus di Comando per un'arma co-locata con un leader (3.3.1.3): si applica a
## FP e Gittata di ogni arma senza barra bianca (l'ordnance è esclusa).
static func weapon_command_bonus(state: GameState, u: Unit) -> int:
	if not u.is_weapon() or u.ordnance:
		return 0
	return command_bonus_at(state, u.q, u.r, u.faction)


## Gittata effettiva includendo il Comando del leader co-locato (3.3.1.2/.3).
static func range_with_command(state: GameState, u: Unit) -> int:
	return u.range + (weapon_command_bonus(state, u) if u.is_weapon() else unit_command_bonus(state, u))


## Movimento effettivo includendo il Comando del leader co-locato (3.3.1.2).
static func move_with_command(state: GameState, u: Unit) -> int:
	return u.move + unit_command_bonus(state, u)


## FP di base per il fuoco includendo il Comando (3.3.1.2 squadre/team, 3.3.1.3
## armi). L'ordnance non è mai modificata dal Comando.
static func fp_with_command(state: GameState, u: Unit) -> int:
	if u.ordnance:
		return u.fp
	return u.fp + (weapon_command_bonus(state, u) if u.is_weapon() else unit_command_bonus(state, u))


# ─── Recupero (O22) ────────────────────────────────────────────────────────────

## Tiro di Morale per recuperare un'unità rotta: successo se 2d6 ≤ Morale
## (+ bonus di Comando di un leader nello stesso esagono). `dice` dal Fato.
static func try_recover(
	state: GameState, u: Unit, dice: Vector2i
) -> Dictionary:
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
## + 1 per ogni unità con FP "in riquadro" (O16.4: niente bonus Comando in melee).
## Accetta Array non tipizzato (Array.filter() restituisce Array non tipizzato).
static func _melee_strength(units: Array) -> int:
	var total := 0
	for u in units:
		total += u.effective_fp()
		if u.fp_boxed:
			total += 1
	return total


## Risolve un corpo a corpo (O16.4). attackers/defenders sono gli UOMINI nell'hex.
## Il lato col totale più basso è eliminato; in PAREGGIO entrambi i lati sono
## eliminati (salvo Bunker/Pillbox, non ancora modellati). Modifica lo stato.
static func resolve_melee(
	state: GameState,
	attackers: Array, defenders: Array,
	atk_dice: Vector2i, def_dice: Vector2i
) -> MeleeResult:
	var res := MeleeResult.new()
	if attackers.is_empty() or defenders.is_empty():
		res.log_line = "Corpo a corpo annullato: manca uno dei due lati."
		return res

	var atk_faction: int = attackers[0].faction
	var def_faction: int = defenders[0].faction

	res.atk_dice = atk_dice
	res.def_dice = def_dice
	res.atk_total = _melee_strength(attackers) + atk_dice.x + atk_dice.y
	res.def_total = _melee_strength(defenders) + def_dice.x + def_dice.y

	var losers: Array = []
	if res.atk_total > res.def_total:
		res.winner = atk_faction
		losers = defenders
	elif res.def_total > res.atk_total:
		res.winner = def_faction
		losers = attackers
	else:
		# Pareggio: entrambi i lati eliminati.
		res.winner = -1
		losers = attackers + defenders

	for u in losers:
		res.eliminated.append(u.id)
		state.eliminate_unit(u.id)

	var outcome := "PAREGGIO (entrambi eliminati)"
	if res.winner != -1:
		outcome = "vince %s" % Domain.FACTION_SHORT.get(res.winner, "?")
	res.log_line = "Corpo a corpo: ATT %d vs DIF %d → %s, eliminate %d unità" % [
		res.atk_total, res.def_total, outcome, res.eliminated.size()]
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
			best = mini(best, HexGrid.distance(q, r, u.q, u.r))
	return best


## Ritira un'unità rotta (Rotta/O23). N = (2d6 − Morale) esagoni verso il bordo
## amico, lontano dai nemici. Se non può muovere ed è adiacente a un nemico viene
## eliminata. Modifica posizione/stato dell'unità.
static func rout_unit(
	state: GameState, u: Unit, dice: Vector2i
) -> Dictionary:
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
		state.eliminate_unit(u.id)

	return {
		"unit": u.id, "roll": roll, "steps": maxi(0, steps),
		"moved": moved, "eliminated": eliminated
	}


## Punteggio di un esagono per la ritirata: minore è meglio.
## Priorità alla distanza dal bordo amico, poi alla lontananza dai nemici.
static func _rout_score(state: GameState, q: int, r: int, edge_col: int, faction: int) -> int:
	var to_edge := absi(q - edge_col)
	var enemy_dist := _nearest_enemy_dist(state, q, r, faction)
	return to_edge * 10 - mini(enemy_dist, 9)


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
