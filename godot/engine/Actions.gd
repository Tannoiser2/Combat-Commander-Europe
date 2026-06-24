## Azioni (carte A) di Combat Commander: Europe.
## Le azioni si giocano dalla banda inferiore della carta. Sono implementate
## quelle realizzabili con i sistemi attuali; le altre (modificatori di fuoco da
## attaccare a un tiro in corso, marker nascosti, ecc.) sono loggate.
class_name Actions
extends RefCounted

const GRENADE_BONUS := 2  ## bonus FP delle bombe a mano a distanza 1


## Azioni senza bersaglio, applicate subito. Restituisce le righe di log.
## (BOMBE A MANO richiede un bersaglio: gestita a parte in Game.)
static func play(state: GameState, card: Card, faction: int) -> Array[String]:
	var lines: Array[String] = []
	match card.action_name:
		"FERITE LEGGERE":     _light_wounds(state, faction, lines)
		"TRINCERARSI":        _entrench(state, faction, lines)
		"MIMETIZZAZIONE":     _camouflage(state, faction, lines)
		"GRANATE FUMOGENE":   _smoke(state, card, lines)
		"FILO SPINATO NASCOSTO":  _place_fort(state, faction, Domain.Fort.WIRE, lines)
		"MINE NASCOSTE":          _place_fort(state, faction, Domain.Fort.MINES, lines)
		"CASAMATTA NASCOSTA":     _place_fort(state, faction, Domain.Fort.PILLBOX, lines)
		"TRINCERAMENTI NASCOSTI": _place_fort(state, faction, Domain.Fort.TRENCH, lines)
		_:
			lines.append("Azione «%s»: non ancora simulata." % card.action_name)
	return lines


## Posa una fortificazione (F100.3: max una per esagono) sull'esagono di una
## propria unità che non ne ha già una. Versione semplificata della posa
## «nascosta» (A35): qui è giocabile come azione normale, non solo allo scarto.
static func _place_fort(state: GameState, faction: int, fort: int, lines: Array[String]) -> void:
	for u in state.units_of(faction):
		if not u.is_man():
			continue
		var hd: GameState.HexData = state.hex_at(u.q, u.r)
		if hd != null and hd.fortification == Domain.Fort.NONE and not hd.has_foxhole:
			hd.fortification = fort
			lines.append("%s posato in (%d,%d)." % [Domain.FORT_NAMES.get(fort, "?"), u.q, u.r])
			return
	lines.append("%s: nessun esagono idoneo." % Domain.FORT_NAMES.get(fort, "?"))


## Ferite leggere: recupera un'unità rotta amica.
static func _light_wounds(state: GameState, faction: int, lines: Array[String]) -> void:
	for u in state.units_of(faction):
		if u.is_man() and not u.efficient:
			u.recover()
			lines.append("Ferite leggere: %s recuperata." % u.unit_name)
			return
	lines.append("Ferite leggere: nessuna unità rotta da curare.")


## Trincerarsi: crea una buca (foxhole) sull'esagono di un'unità amica.
static func _entrench(state: GameState, faction: int, lines: Array[String]) -> void:
	for u in state.units_of(faction):
		if not u.is_man():
			continue
		var hd: GameState.HexData = state.hex_at(u.q, u.r)
		if hd != null and not hd.has_foxhole:
			hd.has_foxhole = true
			lines.append("Trincerarsi: buca creata in (%d,%d)." % [u.q, u.r])
			return
	lines.append("Trincerarsi: nessun esagono idoneo.")


## Mimetizzazione: nasconde le unità amiche efficienti (+1 morale da colpire).
static func _camouflage(state: GameState, faction: int, lines: Array[String]) -> void:
	var n := 0
	for u in state.units_of(faction):
		if u.is_man() and u.efficient and not u.concealed:
			u.concealed = true
			n += 1
	lines.append("Mimetizzazione: %d unità nascoste." % n)


## Granate fumogene: posa fumo (hindrance) sull'esagono indicato dalla carta.
static func _smoke(state: GameState, card: Card, lines: Array[String]) -> void:
	var qr := Domain.label_to_qr(card.random_hex_label)
	var hd: GameState.HexData = state.hex_at(qr.x, qr.y)
	if hd == null:
		lines.append("Granate fumogene: esagono non valido.")
		return
	hd.has_smoke = true
	lines.append("Granate fumogene: fumo posato in %s." % card.random_hex_label)


## Bombe a mano: attacco ravvicinato (distanza 1) sull'esagono bersaglio.
## Risoluzione pura: usa i dadi del Fato passati dal chiamante. Muta lo stato.
static func grenade_attack(
	state: GameState, attacker: Unit, tq: int, tr: int, dice: Vector2i
) -> Dictionary:
	var broken: Array[String] = []
	var eliminated: Array[String] = []
	var fp := attacker.fp + GRENADE_BONUS
	var hd: GameState.HexData = state.hex_at(tq, tr)
	var cover := 0
	if hd != null:
		cover = int(Domain.TERRAIN_COVER.get(hd.terrain, 0))
		if hd.has_foxhole:
			cover += 3
	var final_score := maxi(1, fp - cover) + dice.x + dice.y
	for t in state.men_at(tq, tr):
		if t.faction == attacker.faction:
			continue
		var threshold := t.morale
		if t.concealed:
			threshold += 1
			t.concealed = false
		if final_score >= threshold:
			if t.efficient:
				t.break_unit()
				broken.append(t.id)
			else:
				eliminated.append(t.id)
	for id in eliminated:
		state.eliminate_unit(id)
	return {
		"broken": broken,
		"eliminated": eliminated,
		"log": "Bombe a mano su (%d,%d): FP%d − cop.%d + dadi(%d+%d) = %d" % [
			tq, tr, fp, cover, dice.x, dice.y, final_score]
	}
