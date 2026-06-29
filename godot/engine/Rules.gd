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


## Miglior leader efficiente della fazione di `u` che la comanda (3.3.1.2):
## `u` stessa se è un leader con Comando, altrimenti il leader col Comando più
## alto entro il suo raggio dalla posizione di `u`. null se nessuno la comanda.
## `require_orderable` = true scarta i leader già attivati/soppressi (per emettere
## un nuovo ordine); false li accetta (es. dirigere un gruppo di fuoco).
static func commanding_leader(state: GameState, u: Unit, require_orderable: bool = false) -> Unit:
	if u == null:
		return null
	if u.is_leader() and u.efficient and u.command > 0:
		if not require_orderable or can_be_ordered(u):
			return u
	var best: Unit = null
	for L in state.units_of(u.faction):
		if not (L.is_leader() and L.efficient and L.command > 0):
			continue
		if require_orderable and not can_be_ordered(L):
			continue
		if HexGrid.distance(L.q, L.r, u.q, u.r) > L.command:
			continue
		if best == null or L.command > best.command:
			best = L
	return best


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


## Penalità del Filo spinato (F106.1): -1 a FP/Gittata/Morale per un'unità che
## condivide l'esagono con un marker Filo (il Comando non ne è influenzato).
static func wire_penalty(state: GameState, u: Unit) -> int:
	var hd: GameState.HexData = state.hex_at(u.q, u.r)
	return 1 if (hd != null and hd.fortification == Domain.Fort.WIRE) else 0


## Copertura dell'esagono per il tiro di difesa (T78.3 + fortificazioni). Buca e
## Trincea/Casamatta/Bunker danno una copertura ALTERNATIVA non cumulativa col
## terreno: si usa la migliore. La buca vale 3 (4 vs ordnance/artiglieria, F102),
## le fortificazioni FORT_COVER (+1 vs ordnance).
static func cover_at(state: GameState, q: int, r: int, vs_ordnance: bool) -> int:
	var hd: GameState.HexData = state.hex_at(q, r)
	if hd == null:
		return 0
	var cov: int = Domain.TERRAIN_COVER.get(hd.terrain, 0)
	if hd.has_foxhole:
		cov = maxi(cov, 3 + (1 if vs_ordnance else 0))
	var fc := int(Domain.FORT_COVER.get(hd.fortification, 0))
	if fc > 0:
		cov = maxi(cov, fc + (1 if vs_ordnance else 0))
	return cov


## Gittata effettiva includendo il Comando del leader co-locato (3.3.1.2/.3) e la
## penalità del Filo spinato.
static func range_with_command(state: GameState, u: Unit) -> int:
	var cmd := weapon_command_bonus(state, u) if u.is_weapon() else unit_command_bonus(state, u)
	return u.range + cmd - wire_penalty(state, u)


## Movimento effettivo includendo il Comando del leader co-locato (3.3.1.2).
static func move_with_command(state: GameState, u: Unit) -> int:
	return u.move + unit_command_bonus(state, u)


## PM effettivi disponibili per la Mossa: base + Comando, meno il malus
## dell'eventuale arma trasportata (11.1). Mai negativo.
static func move_allowance(state: GameState, u: Unit) -> int:
	var mp := move_with_command(state, u)
	var w := state.weapon_carried_by(u.id)
	if w != null:
		mp += w.move_penalty  # move_penalty è negativo (es. -2)
	return maxi(0, mp)


## FP di base per il fuoco includendo il Comando (3.3.1.2 squadre/team, 3.3.1.3
## armi) e la penalità del Filo. L'ordnance non è mai modificata dal Comando.
static func fp_with_command(state: GameState, u: Unit) -> int:
	if u.ordnance:
		return u.fp - wire_penalty(state, u)
	var cmd := weapon_command_bonus(state, u) if u.is_weapon() else unit_command_bonus(state, u)
	return u.fp + cmd - wire_penalty(state, u)


## Deriva della granata d'artiglieria (O18.2.2). Partendo da (q,r):
## - HIT: si sposta 1 esagono nella direzione del dado bianco, poi 1 in quella
##   del dado colorato;
## - MISS: si sposta di `cd` esagoni (dado colorato) nella direzione del dado
##   bianco.
## Se in qualsiasi momento esce dalla mappa restituisce (-1,-1) (O18.2.2.3).
static func artillery_drift(state: GameState, q: int, r: int, hit: bool, wd: int, cd: int) -> Vector2i:
	var dir_w := (wd - 1) % 6
	var dir_c := (cd - 1) % 6
	var cur := Vector2i(q, r)
	if hit:
		cur = HexGrid.step_dir(cur.x, cur.y, dir_w)
		if _off_map(state, cur):
			return Vector2i(-1, -1)
		cur = HexGrid.step_dir(cur.x, cur.y, dir_c)
		if _off_map(state, cur):
			return Vector2i(-1, -1)
	else:
		for _i in cd:
			cur = HexGrid.step_dir(cur.x, cur.y, dir_w)
			if _off_map(state, cur):
				return Vector2i(-1, -1)
	return cur


static func _off_map(state: GameState, c: Vector2i) -> bool:
	return c.x < 0 or c.x >= state.map_cols or c.y < 0 or c.y >= state.map_rows


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


## Recupero (O22): un ordine di Recupero rimuove AUTOMATICAMENTE (senza tiro) la
## soppressione da tutte le unità efficienti soppresse della fazione. Le unità
## ROTTE restano gestite a parte da try_recover (richiede il tiro di morale).
## Restituisce quante unità sono state liberate dalla soppressione.
static func clear_suppression(state: GameState, faction: int) -> int:
	var freed := 0
	for u in state.suppressed_men_of(faction):
		u.suppressed = false
		freed += 1
	return freed


## Un'unità può ricevere un ordine "attivo" (Mossa/Fuoco/Avanzata) solo se è
## efficiente, NON soppressa e NON già attivata. Le unità rotte o soppresse sono
## immobilizzate: possono solo difendersi e (le rotte) ritirarsi/recuperare.
static func can_be_ordered(u: Unit) -> bool:
	return u != null and u.efficient and not u.suppressed and not u.activated


## Vincitore alla Morte Subitanea data la bilancia VP (positiva = Germania).
## In PAREGGIO (bilancia 0) vince chi detiene la carta Iniziativa (9.2).
static func sd_winner(vp_balance: int, initiative_holder: int) -> int:
	if vp_balance > 0:
		return Domain.Faction.GERMAN
	if vp_balance < 0:
		return Domain.Faction.RUSSIAN
	return initiative_holder


## Re-Roll dell'Iniziativa (9.1): chi sta PERDENDO può annullare e rifare il tiro
## di Morte Subitanea, ma solo se detiene la carta Iniziativa. Quindi rifà se e
## solo se il detentore dell'Iniziativa NON è il vincitore corrente.
static func sd_initiative_rerolls(vp_balance: int, initiative_holder: int) -> bool:
	return initiative_holder != sd_winner(vp_balance, initiative_holder)


## FP stampato di una Radio dato il calibro nel nome (Weapon/Radio Manifest):
## 75-76→8, 81-88→9, 105-114→10, 120-140→11, 150-155→12, 183-203→13.
static func radio_fp_for(name: String) -> int:
	if name.contains("183") or name.contains("203"):
		return 13
	if name.contains("150") or name.contains("155"):
		return 12
	if name.contains("120") or name.contains("140"):
		return 11
	if name.contains("105") or name.contains("114"):
		return 10
	if name.contains("81") or name.contains("88"):
		return 9
	return 8  # 75-76mm e default


## Vulnerabilità delle Fortificazioni (O18.2.3.3, Track Display): una fortificazione
## nell'esagono bombardato è distrutta se l'Artillery Impact Roll (2d6) è ESATTAMENTE
## (20 − FP della Radio). FP8→12, FP9→11, FP10→10, FP11→9, FP12→8, FP13→7.
static func artillery_fort_vulnerability(fp: int) -> int:
	return 20 - fp


# ─── Corpo a corpo / Avanzata (O21) ──────────────────────────────────────────

class MeleeResult:
	var atk_total: int = 0
	var def_total: int = 0
	var atk_dice: Vector2i = Vector2i.ZERO
	var def_dice: Vector2i = Vector2i.ZERO
	var winner: int = -1            ## Domain.Faction vincitrice
	var eliminated: Array[String] = []
	var log_line: String = ""
	var detail: String = ""  ## Formula del calcolo (dettaglio collassabile)


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
		# Pareggio: di norma entrambi i lati eliminati. Eccezione (F101/F104): in
		# Bunker o Casamatta vince chi difende la fortificazione, cioè l'ultimo
		# occupante solitario dell'esagono (qui il difensore, che la presidiava).
		var hd: GameState.HexData = state.hex_at(defenders[0].q, defenders[0].r)
		if hd != null and (hd.fortification == Domain.Fort.BUNKER \
			or hd.fortification == Domain.Fort.PILLBOX):
			res.winner = def_faction
			losers = attackers
		else:
			res.winner = -1
			losers = attackers + defenders

	for u in losers:
		res.eliminated.append(u.id)
		state.eliminate_unit(u.id)

	var outcome := "PAREGGIO (entrambi eliminati)"
	if res.winner != -1:
		outcome = "vince %s" % Domain.FACTION_SHORT.get(res.winner, "?")
	var atk_str := res.atk_total - atk_dice.x - atk_dice.y
	var def_str := res.def_total - def_dice.x - def_dice.y
	res.log_line = "[b]Corpo a corpo[/b]: ATT %d vs DIF %d — %s ([b]%d[/b] eliminate)" % [
		res.atk_total, res.def_total, outcome, res.eliminated.size()]
	res.detail = "[b]Attaccanti[/b] = forza %d + dadi(%d+%d) = [b]%d[/b]\n" % [
			atk_str, atk_dice.x, atk_dice.y, res.atk_total] \
		+ "[b]Difensori[/b] = forza %d + dadi(%d+%d) = [b]%d[/b]\n" % [
			def_str, def_dice.x, def_dice.y, res.def_total] \
		+ "Vince il totale più alto; a pari, eliminati entrambi (salvo Casamatta/Bunker)"
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
