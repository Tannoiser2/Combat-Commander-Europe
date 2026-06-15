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
	var log_line: String


## Unità che concorrono al fuoco da un esagono: tutte le unità efficienti della
## fazione dello sparatore nell'esagono, con gittata sufficiente per il bersaglio.
static func fire_group(attacker: Unit, tq: int, tr: int, state: GameState) -> Array[Unit]:
	var dist := HexGrid.distance(attacker.q, attacker.r, tq, tr)
	var group: Array[Unit] = []
	for u in state.units_at(attacker.q, attacker.r):
		if u.faction == attacker.faction and u.efficient and u.range >= dist and u.fp > 0:
			group.append(u)
	return group


## Effettua un attacco di fuoco. attacker = unità sparante (capofila del gruppo).
## `dice` sono i due dadi del Fato (pescati dal mazzo dal chiamante).
## state viene modificato in-place (rottura/eliminazione).
static func resolve_fire(
	attacker: Unit, tq: int, tr: int,
	state: GameState,
	dice: Vector2i
) -> FireResult:
	var res := FireResult.new()
	res.attacker_id = attacker.id
	res.target_q = tq
	res.target_r = tr

	var dist := HexGrid.distance(attacker.q, attacker.r, tq, tr)
	if dist == 0:
		res.log_line = "Fuoco a distanza 0: usa il corpo a corpo (Avanzata)."
		return res
	if dist > attacker.range:
		res.log_line = "Fuoco fuori gittata (%d > %d)" % [dist, attacker.range]
		return res
	if not HexGrid.has_los(attacker.q, attacker.r, tq, tr, state):
		res.log_line = "Nessuna linea di vista verso (%d,%d)" % [tq, tr]
		return res

	# ─── Potenza di fuoco del gruppo + Comando ───────────────────────────────
	var group := fire_group(attacker, tq, tr, state)
	# Gruppo di fuoco (O20.3.1): FP del pezzo migliore + 1 per ogni pezzo
	# aggiuntivo (NON la somma di tutti gli FP).
	var fp := 0
	for u in group:
		fp = maxi(fp, u.fp)
	if group.size() > 1:
		fp += group.size() - 1
	var cmd_bonus := Rules.command_bonus_at(state, attacker.q, attacker.r, attacker.faction)
	fp += cmd_bonus

	# Copertura del bersaglio + ostacolo (hindrance) lungo la LOS, entrambi
	# sottratti alla potenza di fuoco.
	var hd: GameState.HexData = state.hex_at(tq, tr)
	var cover: int = Domain.TERRAIN_COVER.get(hd.terrain, 0) if hd else 0
	if hd != null and hd.has_foxhole:
		cover += 3  # buca/foxhole (scheda Fortificazioni: copertura 3)
	var hind := HexGrid.los_hindrance(attacker.q, attacker.r, tq, tr, state)
	if hd != null and hd.has_smoke:
		hind += 1  # fumo sul bersaglio
	var fp_before := fp
	fp = maxi(1, fp - cover - hind)
	res.fp_total = fp

	# ─── Tiro (dadi del Fato) ────────────────────────────────────────────────
	res.dice_roll = dice.x + dice.y
	res.final_score = fp + res.dice_roll

	# ─── Effetti: rottura / eliminazione ─────────────────────────────────────
	for t in state.men_at(tq, tr):
		if t.faction == attacker.faction:
			continue
		var threshold := t.morale
		if t.concealed:
			threshold += 1       # più difficile colpire una unità mimetizzata
			t.concealed = false  # il fuoco la rivela comunque
		if res.final_score >= threshold:
			if t.efficient:
				t.break_unit()
				res.broken.append(t.id)
			else:
				res.eliminated.append(t.id)

	# ─── Log ─────────────────────────────────────────────────────────────────
	var cmd_str := " +cmd%d" % cmd_bonus if cmd_bonus > 0 else ""
	res.log_line = "%s (×%d%s) spara su (%d,%d): FP%d − cop.%d − hind.%d + dadi(%d+%d)=%d → tot %d" % [
		attacker.unit_name, group.size(), cmd_str, tq, tr,
		fp_before, cover, hind, dice.x, dice.y, res.dice_roll, res.final_score
	]
	if res.eliminated.size() > 0:
		res.log_line += " ⇒ ELIMINATE: %s" % ", ".join(res.eliminated)
	if res.broken.size() > 0:
		res.log_line += " ⇒ ROTTE: %s" % ", ".join(res.broken)
	if res.eliminated.is_empty() and res.broken.is_empty():
		res.log_line += " ⇒ nessun effetto"

	# Rimuove dallo stato le unità eliminate.
	for uid in res.eliminated:
		state.units.erase(uid)

	return res


## Verifica se un'unità può sparare legalmente.
static func can_fire(attacker: Unit, tq: int, tr: int, state: GameState) -> bool:
	if attacker.activated:
		return false
	if not attacker.efficient:
		return false  # unità rotta: non può sparare
	var dist := HexGrid.distance(attacker.q, attacker.r, tq, tr)
	if dist == 0 or dist > attacker.range:
		return false
	if not HexGrid.has_los(attacker.q, attacker.r, tq, tr, state):
		return false
	# Deve esserci almeno un'unità nemica nel bersaglio.
	var enemies := state.men_at(tq, tr).filter(
		func(u: Unit) -> bool: return u.faction != attacker.faction
	)
	return enemies.size() > 0
