## Intelligenza artificiale di Combat Commander: Europe.
## Funzioni pure di decisione: scelgono quale ordine giocare dalla mano e con
## quali parametri. L'esecuzione (e gli effetti sullo stato) avviene in Game.gd.
class_name AI
extends RefCounted


## Sceglie il miglior ordine da giocare dalla mano della fazione.
## Restituisce un dizionario { "card_index", "order", ...parametri } oppure
## un dizionario vuoto se non c'è nulla di utile da fare.
static func choose_play(state: GameState, faction: int) -> Dictionary:
	var hand := state.hand_of(faction)
	var best: Dictionary = {}
	var best_val := 0
	for i in hand.size():
		var card: Card = hand[i]
		var val := 0
		var params: Dictionary = {}
		match card.order:
			Domain.OrderType.FIRE:
				var f := best_fire(state, faction)
				if not f.is_empty():
					val = 100 + int(f["score"])
					params = f
			Domain.OrderType.ADVANCE:
				var a := best_advance(state, faction)
				if not a.is_empty():
					val = 80 + int(a["margin"])
					params = a
			Domain.OrderType.RECOVER:
				var n := state.broken_men_of(faction).size()
				if n > 0:
					val = 50 + n
			Domain.OrderType.ROUT:
				if _has_pressured_broken(state, faction):
					val = 40
			Domain.OrderType.MOVE:
				if _has_movable(state, faction):
					val = 30
			Domain.OrderType.ARTY:
				var art := best_artillery(state, faction)
				if not art.is_empty():
					val = 85 + 10 * int(art["score"])
					params = art
			_:
				val = 0
		if val > best_val:
			best_val = val
			params["card_index"] = i
			params["order"] = card.order
			best = params
	return best


## Richiesta d'Artiglieria (O18): serve una Radio e un Leader (spotter) non rotti;
## sceglie l'esagono nemico nella LOS dello spotter col maggior numero di nemici.
## Vuoto se non realizzabile. `score` = numero di nemici nel mirino.
static func best_artillery(state: GameState, faction: int) -> Dictionary:
	var radio: Unit = null
	var spotter: Unit = null
	for u in state.units_of(faction):
		if not u.efficient:
			continue
		if radio == null and u.unit_name.contains("Radio"):
			radio = u
		if spotter == null and u.is_leader():
			spotter = u
	if radio == null or spotter == null:
		return {}
	var best: Dictionary = {}
	var best_n := 0
	for other in state.units.values():
		if other.faction == faction or not other.is_man():
			continue
		if not HexGrid.has_los(spotter.q, spotter.r, other.q, other.r, state):
			continue
		var n := 0
		for t in state.men_at(other.q, other.r):
			if t.faction != faction:
				n += 1
		if n > best_n:
			best_n = n
			best = { "spotter_id": spotter.id, "radio_id": radio.id, "q": other.q, "r": other.r, "score": n }
	return best


## Miglior coppia (sparatore, bersaglio) per la fazione. Vuoto se nessun fuoco.
static func best_fire(state: GameState, faction: int) -> Dictionary:
	var best: Dictionary = {}
	var best_score := 0
	for u in state.units_of(faction):
		if u.activated or not u.efficient:
			continue
		for h in HexGrid.hexes_in_range(u.q, u.r, u.range, state):
			if not Combat.can_fire(u, h.x, h.y, state):
				continue
			var score := _fire_score(state, u, h.x, h.y, faction)
			if score > best_score:
				best_score = score
				best = { "attacker_id": u.id, "q": h.x, "r": h.y, "score": score }
	return best


## Stima (senza dadi) del valore di un fuoco: usa la media 2d6 = 7.
static func _fire_score(state: GameState, u: Unit, tq: int, tr: int, faction: int) -> int:
	var group := Combat.fire_group(u, tq, tr, state)
	var fp := 0
	for g in group:
		fp = maxi(fp, g.fp)  # gruppo di fuoco: pezzo migliore...
	if group.size() > 1:
		fp += group.size() - 1  # ...+1 per pezzo aggiuntivo (O20.3.1)
	fp += Rules.command_bonus_at(state, u.q, u.r, faction)
	var hd: GameState.HexData = state.hex_at(tq, tr)
	var cover: int = Domain.TERRAIN_COVER.get(hd.terrain, 0) if hd else 0
	var expected := fp - cover + 7
	var score := 0
	var on_obj := state.objective_at(tq, tr) != null
	for t in state.men_at(tq, tr):
		if t.faction == faction:
			continue
		if expected >= t.morale:
			score += 3
			if not t.efficient:
				score += 4   # già rotto → eliminabile
			if t.is_leader():
				score += 3
			if on_obj:
				score += 2
	return score


## Migliore avanzata in corpo a corpo: unità adiacente a nemici con vantaggio FP.
static func best_advance(state: GameState, faction: int) -> Dictionary:
	var best: Dictionary = {}
	var best_margin := 0
	for u in state.units_of(faction):
		if not Rules.can_be_ordered(u) or u.is_weapon():
			continue
		for nb in HexGrid.neighbors(u.q, u.r):
			if nb.x < 0 or nb.x >= state.map_cols or nb.y < 0 or nb.y >= state.map_rows:
				continue
			var defenders := state.men_at(nb.x, nb.y).filter(
				func(m: Unit) -> bool: return m.faction != faction)
			if defenders.is_empty():
				continue
			# O16.4: nessun bonus di Comando nel corpo a corpo.
			var atk := u.effective_fp() + (1 if u.fp_boxed else 0)
			var deff := 0
			for d in defenders:
				deff += d.effective_fp() + (1 if d.fp_boxed else 0)
			var margin := atk - deff
			if margin > best_margin:
				best_margin = margin
				best = { "unit_id": u.id, "q": nb.x, "r": nb.y, "margin": margin }
	return best


## True se la fazione ha almeno un'unità (uomo, efficiente) ancora da attivare.
static func _has_movable(state: GameState, faction: int) -> bool:
	for u in state.units_of(faction):
		if not u.activated and u.efficient and not u.is_weapon():
			return true
	return false


## True se la fazione ha un'unità rotta adiacente a un nemico (da far ritirare).
static func _has_pressured_broken(state: GameState, faction: int) -> bool:
	for u in state.broken_men_of(faction):
		for nb in HexGrid.neighbors(u.q, u.r):
			for m in state.men_at(nb.x, nb.y):
				if m.faction != faction:
					return true
	return false
