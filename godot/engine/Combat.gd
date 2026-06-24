## Risoluzione del fuoco in Combat Commander: Europe.
## Logica pura — nessuna dipendenza dalla scena grafica.
##
## Modello CC:E: la potenza di fuoco del gruppo (tutte le unità efficienti
## nell'esagono dello sparatore in gittata) più il Comando di un leader nello
## stesso esagono, meno la copertura del terreno, più 2d6. Ogni unità nemica
## nel bersaglio con punteggio ≥ Morale si ROMPE; se era già rotta, è ELIMINATA.
class_name Combat
extends RefCounted


## Risultato di una risoluzione di fuoco.
class FireResult:
	var attacker_id: String
	var target_q: int
	var target_r: int
	var fp_total: int      ## Potenza di fuoco netta dopo modificatori
	var dice_roll: int     ## Somma dei due dadi (2d6)
	var final_score: int   ## fp_total + dice_roll
	var broken: Array[String] = []      ## IDs unità rotte in questo attacco
	var eliminated: Array[String] = []  ## IDs unità eliminate (erano già rotte)
	var suppressed: Array[String] = []  ## IDs unità soppresse in questo attacco
	var log_line: String


## Unità che concorrono al fuoco da un esagono: tutte le unità efficienti della
## fazione dello sparatore nell'esagono, con gittata sufficiente per il bersaglio.
static func fire_group(attacker: Unit, tq: int, tr: int, state: GameState) -> Array[Unit]:
	var group: Array[Unit] = []
	# Ordnance (11.5): non può partecipare a un gruppo di fuoco — spara da sola.
	if attacker.ordnance:
		group.append(attacker)
		return group
	# Raggio di Comando del miglior leader nell'esagono dell'attaccante: estende
	# il gruppo di fuoco alle unità idonee negli esagoni vicini (O20.3.1 / 3.3).
	# Senza leader cmd_range = 0 → solo unità co-locate (comportamento base).
	var cmd_range := 0
	for u in state.units_at(attacker.q, attacker.r):
		if u.faction == attacker.faction and u.is_leader() and u.efficient:
			cmd_range = maxi(cmd_range, u.command)
	for u in state.units.values():
		if u.faction != attacker.faction or not u.efficient or u.fp <= 0 or u.ordnance:
			continue
		# Co-locata oppure entro il raggio di comando dall'esagono attaccante.
		if HexGrid.distance(attacker.q, attacker.r, u.q, u.r) > cmd_range:
			continue
		# Deve poter colpire il bersaglio dal proprio esagono (gittata + LOS).
		var d := HexGrid.distance(u.q, u.r, tq, tr)
		if d < 1 or d > Rules.range_with_command(state, u):
			continue
		if not HexGrid.has_los(u.q, u.r, tq, tr, state):
			continue
		group.append(u)
	return group


## Colpisce un'unità: efficiente → rotta; già rotta → eliminata.
static func _apply_hit(t: Unit, res: FireResult) -> void:
	if t.efficient:
		t.break_unit()
		res.broken.append(t.id)
	else:
		res.eliminated.append(t.id)


## Effettua un attacco di fuoco (O20). `atk_dice` = dadi del Fato dell'attaccante,
## `def_dice` = dadi del Fire Defense Roll del difensore (entrambi pescati dal
## chiamante). Attacco = (FP gruppo − hindrance) + dadi att.; Difesa = Morale +
## copertura + dadi dif. Difesa < Attacco → colpita; pari → colpita se in
## movimento, altrimenti soppressa; Difesa > Attacco → nessun effetto.
static func resolve_fire(
	attacker: Unit, tq: int, tr: int,
	state: GameState,
	atk_dice: Vector2i, def_dice: Vector2i,
	group_override: Array[Unit] = [],
	fp_bonus: int = 0,
	spray_q: int = -1, spray_r: int = -1
) -> FireResult:
	var res := FireResult.new()
	res.attacker_id = attacker.id
	res.target_q = tq
	res.target_r = tr

	var dist := HexGrid.distance(attacker.q, attacker.r, tq, tr)
	if dist == 0:
		res.log_line = "Fuoco a distanza 0: usa il corpo a corpo (Avanzata)."
		return res
	var atk_range := Rules.range_with_command(state, attacker)
	if dist > atk_range:
		res.log_line = "Fuoco fuori gittata (%d > %d)" % [dist, atk_range]
		return res
	if attacker.ordnance and dist < attacker.min_range:
		res.log_line = "Sotto la gittata minima dell'ordnance (%d < %d)" % [dist, attacker.min_range]
		return res
	if not HexGrid.has_los(attacker.q, attacker.r, tq, tr, state):
		res.log_line = "Nessuna linea di vista verso (%d,%d)" % [tq, tr]
		return res

	# Ostacolo (hindrance) lungo la LOS. Per le armi normali riduce la potenza di
	# fuoco; per l'ordnance modifica invece il Targeting Roll (O20.2.3/10.3.1).
	var hd: GameState.HexData = state.hex_at(tq, tr)
	var hind := HexGrid.los_hindrance(attacker.q, attacker.r, tq, tr, state)
	if hd != null and hd.has_smoke:
		hind += 1  # fumo sul bersaglio

	# ─── Ordnance: Targeting Roll (O20.2.3) ──────────────────────────────────
	# I due dadi si MOLTIPLICANO (non si sommano): per colpire il prodotto deve
	# superare la gittata + hindrance. Mancato → attacco annullato senza effetto.
	if attacker.ordnance:
		var product := atk_dice.x * atk_dice.y
		if product <= dist + hind:
			res.fp_total = 0
			res.dice_roll = product
			res.log_line = "%s targeting su (%d,%d): %d×%d=%d ≤ gittata%d+h%d ⇒ MANCATO" % [
				attacker.unit_name, tq, tr, atk_dice.x, atk_dice.y, product, dist, hind]
			return res

	# ─── Potenza di fuoco del gruppo (O20.3.1.2) ─────────────────────────────
	# Gruppo esplicito (scelto dal giocatore) o, in assenza, quello automatico.
	var group := group_override if not group_override.is_empty() else fire_group(attacker, tq, tr, state)
	# FP del pezzo base = migliore FP già comprensivo del Comando del leader
	# co-locato (3.3.1.2 squadre/team, 3.3.1.3 armi), + 1 per ogni pezzo
	# aggiuntivo (NON la somma di tutti gli FP). L'ordnance non è mai modificata.
	var fp := 0
	for u in group:
		fp = maxi(fp, Rules.fp_with_command(state, u))
	if group.size() > 1:
		fp += group.size() - 1
	# Modificatori di fuoco (Mirato/Sostenuto/Incrociato, A37/A41/A30): +FP.
	fp += fp_bonus
	var attack_fp := maxi(1, fp) if attacker.ordnance else maxi(1, fp - hind)
	res.fp_total = attack_fp
	res.dice_roll = atk_dice.x + atk_dice.y
	var attack_total := attack_fp + res.dice_roll
	res.final_score = attack_total

	# ─── Fire Defense Roll per ogni difensore (O20.3.4) ──────────────────────
	var def_roll := def_dice.x + def_dice.y
	var cover := _resolve_hex_defenders(state, attacker, tq, tr, attack_total, def_roll, res)

	# Sventagliata (A40 Spray Fire): lo stesso totale d'attacco colpisce anche un
	# secondo esagono nemico adiacente; i suoi difensori tirano la difesa a parte.
	var spray_cover := -1
	if spray_q >= 0 and spray_r >= 0:
		spray_cover = _resolve_hex_defenders(state, attacker, spray_q, spray_r, attack_total, def_roll, res)

	# ─── Log ─────────────────────────────────────────────────────────────────
	res.log_line = "%s (×%d) spara su (%d,%d): ATT %d (FP%d−h%d+%d) vs DIF (mor+cop%d+%d)" % [
		attacker.unit_name, group.size(), tq, tr,
		attack_total, fp, hind, res.dice_roll, cover, def_roll
	]
	if spray_cover >= 0:
		res.log_line += " | sventagliata su (%d,%d) cop%d" % [spray_q, spray_r, spray_cover]
	if res.eliminated.size() > 0:
		res.log_line += " ⇒ ELIMINATE: %s" % ", ".join(res.eliminated)
	if res.broken.size() > 0:
		res.log_line += " ⇒ ROTTE: %s" % ", ".join(res.broken)
	if res.suppressed.size() > 0:
		res.log_line += " ⇒ SOPPRESSE: %s" % ", ".join(res.suppressed)
	if res.eliminated.is_empty() and res.broken.is_empty() and res.suppressed.is_empty():
		res.log_line += " ⇒ nessun effetto"

	# Rimuove dallo stato le unità eliminate (contandole sul Casualty Track).
	for uid in res.eliminated:
		state.eliminate_unit(uid)

	return res


## Applica `attack_total` ai difensori nemici di un esagono (O20.3.4) e registra
## gli effetti in `res`. Restituisce la copertura usata (per il log).
static func _resolve_hex_defenders(
	state: GameState, attacker: Unit, hq: int, hr: int,
	attack_total: int, def_roll: int, res: FireResult
) -> int:
	var cover := Rules.cover_at(state, hq, hr, attacker.ordnance)
	for t in state.men_at(hq, hr):
		if t.faction == attacker.faction:
			continue
		# Morale del difensore + copertura + Comando del leader co-locato (3.3.1.2);
		# il Filo spinato (F106) abbassa di 1 la Morale di chi è nell'esagono.
		var def_cmd := Rules.unit_command_bonus(state, t)
		var defense := t.morale + cover + def_roll + def_cmd - Rules.wire_penalty(state, t)
		if t.concealed:
			defense += 1         # mimetizzazione: più difficile da colpire
			t.concealed = false  # il fuoco la rivela comunque
		var moving := t.id == state.moving_unit_id
		if attack_total > defense:
			_apply_hit(t, res)
		elif attack_total == defense:
			if moving or t.suppressed:
				_apply_hit(t, res)   # in movimento (o già soppressa) → si rompe
			else:
				t.suppress()
				res.suppressed.append(t.id)
		# attack_total < defense → nessun effetto
	return cover


## Impatto d'artiglieria (O18.2.3): l'esagono centro (cq,cr) e i sei adiacenti
## subiscono un attacco da `fp` FP. Ogni unità presente (di QUALSIASI fazione)
## tira la difesa (Morale + copertura + 2d6) contro fp + 2d6. I dadi vengono
## dall'`rng`. Restituisce { eliminated, broken, suppressed, hexes }.
static func resolve_artillery(
	state: GameState, fp: int, cq: int, cr: int, rng: RandomNumberGenerator
) -> Dictionary:
	var res := { "eliminated": [], "broken": [], "suppressed": [], "hexes": 0, "forts": 0 }
	var blast: Array = [Vector2i(cq, cr)]
	for n in HexGrid.neighbors(cq, cr):
		blast.append(n)
	for h in blast:
		if h.x < 0 or h.x >= state.map_cols or h.y < 0 or h.y >= state.map_rows:
			continue
		res["hexes"] += 1
		# Distruzione fortificazioni (O18.2.3.3): l'artiglieria pesante (FP≥20, cioè
		# 88/105mm) spiana Trincea/Casamatta/Bunker/Filo/Mine PRIMA dei tiri di
		# difesa, togliendo così la loro copertura ai difensori.
		var hd: GameState.HexData = state.hex_at(h.x, h.y)
		if hd != null and hd.fortification != Domain.Fort.NONE and fp >= 20:
			hd.fortification = Domain.Fort.NONE
			res["forts"] += 1
		var here: Array = []
		for u in state.units.values():
			if u.q == h.x and u.r == h.y:
				here.append(u)
		var cover := Rules.cover_at(state, h.x, h.y, false)
		for u in here:
			var atk: int = fp + rng.randi_range(1, 6) + rng.randi_range(1, 6)
			var defn: int = int(u.morale) + cover + rng.randi_range(1, 6) + rng.randi_range(1, 6)
			if atk > defn:
				if u.efficient:
					u.break_unit()
					res["broken"].append(u.id)
				else:
					res["eliminated"].append(u.id)
					state.eliminate_unit(u.id)
			elif atk == defn:
				if u.efficient and not u.suppressed:
					u.suppress()
					res["suppressed"].append(u.id)
				elif u.efficient:
					u.break_unit()
					res["broken"].append(u.id)
				else:
					res["eliminated"].append(u.id)
					state.eliminate_unit(u.id)
	return res


## Verifica se un'unità può sparare legalmente.
static func can_fire(attacker: Unit, tq: int, tr: int, state: GameState) -> bool:
	if attacker.activated:
		return false
	if not attacker.efficient:
		return false  # unità rotta: non può sparare
	if attacker.suppressed:
		return false  # unità soppressa: non può sparare
	var dist := HexGrid.distance(attacker.q, attacker.r, tq, tr)
	if dist == 0 or dist > Rules.range_with_command(state, attacker):
		return false
	if attacker.ordnance and dist < attacker.min_range:
		return false  # mortai/cannoni: gittata minima
	if not HexGrid.has_los(attacker.q, attacker.r, tq, tr, state):
		return false
	# Deve esserci almeno un'unità nemica nel bersaglio.
	var enemies := state.men_at(tq, tr).filter(
		func(u: Unit) -> bool: return u.faction != attacker.faction
	)
	return enemies.size() > 0
