## Risoluzione del fuoco in Combat Commander: Europe.
## Logica pura — nessuna dipendenza dalla scena grafica.
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
	var suppressed: Array[String] = []  ## IDs unità soppresse
	var broken: Array[String] = []      ## IDs unità eliminate / rotte
	var log_line: String

	func _init() -> void:
		pass


## Effettua un attacco di fuoco.
## attacker: unità che spara
## tq, tr: esagono bersaglio
## state: stato corrente (modificato in-place per soppressione/eliminazione)
## rng: generatore random (null → usa RandomNumberGenerator interno)
static func resolve_fire(
	attacker: Unit, tq: int, tr: int,
	state: GameState,
	rng: RandomNumberGenerator = null
) -> FireResult:
	var res := FireResult.new()
	res.attacker_id = attacker.id
	res.target_q = tq
	res.target_r = tr

	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	# ─── Potenza di fuoco base ────────────────────────────────────────────────
	var fp := attacker.fp

	# Modificatore distanza
	var dist := HexGrid.distance(attacker.q, attacker.r, tq, tr)
	if dist > attacker.range:
		res.log_line = "Fuoco fuori gittata (%d > %d)" % [dist, attacker.range]
		return res
	if dist == 0:
		# Corpo a corpo — non gestito qui
		res.log_line = "Fuoco a distanza 0: usa corpo a corpo."
		return res

	# Modificatore terreno difensore (copertura)
	var hd: GameState.HexData = state.hex_at(tq, tr)
	var cover: int = 0
	if hd:
		cover = Domain.TERRAIN_COVER.get(hd.terrain, 0)

	# LOS
	if not HexGrid.has_los(attacker.q, attacker.r, tq, tr, state):
		res.log_line = "Nessuna linea di vista verso (%d,%d)" % [tq, tr]
		return res

	# FP netto
	fp = max(1, fp - cover)
	res.fp_total = fp

	# ─── Tiro dei dadi (2d6) ─────────────────────────────────────────────────
	var d1 := rng.randi_range(1, 6)
	var d2 := rng.randi_range(1, 6)
	res.dice_roll = d1 + d2
	res.final_score = fp + res.dice_roll

	# ─── Effetti sulle unità bersaglio ───────────────────────────────────────
	var targets := state.men_at(tq, tr)
	for t in targets:
		var threshold := t.morale
		if res.final_score >= threshold + 4:
			# Eliminata / rotta
			res.broken.append(t.id)
		elif res.final_score >= threshold:
			# Soppressa
			if not t.suppressed:
				t.suppressed = true
				res.suppressed.append(t.id)

	# ─── Log ─────────────────────────────────────────────────────────────────
	res.log_line = (
		"%s spara su (%d,%d): FP%d – cop.%d = %d + dadi(%d+%d)=%d → totale %d" % [
			attacker.unit_name, tq, tr,
			attacker.fp, cover, fp,
			d1, d2, res.dice_roll, res.final_score
		]
	)
	if res.broken.size() > 0:
		res.log_line += " ⇒ ROTTE: %s" % ", ".join(res.broken)
	elif res.suppressed.size() > 0:
		res.log_line += " ⇒ SOPPRESSE: %s" % ", ".join(res.suppressed)
	else:
		res.log_line += " ⇒ nessun effetto"

	# Rimuove le unità rotte dallo stato
	for uid in res.broken:
		state.units.erase(uid)

	return res


## Verifica se un'unità può sparare legalmente.
static func can_fire(attacker: Unit, tq: int, tr: int, state: GameState) -> bool:
	if attacker.activated:
		return false
	if attacker.suppressed:
		return false
	var dist := HexGrid.distance(attacker.q, attacker.r, tq, tr)
	if dist == 0 or dist > attacker.range:
		return false
	if not HexGrid.has_los(attacker.q, attacker.r, tq, tr, state):
		return false
	# Deve esserci almeno un'unità nemica
	var enemies := state.men_at(tq, tr).filter(
		func(u: Unit) -> bool: return u.faction != attacker.faction
	)
	return enemies.size() > 0
