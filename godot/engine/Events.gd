## Eventi del Mazzo del Fato di Combat Commander: Europe.
## Quando si pesca una carta con conseguenza "event", si applica l'effetto
## dell'evento stampato (card.event_name). Sono implementati gli eventi
## realizzabili con i sistemi già presenti nel motore; gli altri (che
## richiedono marker, Casualty Track, chit obiettivo, ecc.) vengono loggati
## come non ancora simulati.
##
## Riferimento: ROADMAP.md (cross-check col rulebook, eventi E43-E77).
class_name Events
extends RefCounted


## Applica l'evento della carta per la fazione che pesca. Muta lo stato e
## restituisce le righe di log.
static func fire(state: GameState, card: Card, faction: int) -> Array[String]:
	var lines: Array[String] = []
	match card.event_name:
		"SUPPORTO AEREO":          _air_support(state, card, lines)
		"MACERIE":                 _rubble(state, card, lines)
		"SHOCK DA COMBATTIMENTO":  _shell_shock(state, card, lines)
		"UCCISO IN AZIONE":        _kia(state, faction, lines)
		"INFILTRAZIONI":           _infiltration(state, faction, lines)
		"FUOCO DI SOPPRESSIONE":   _suppressing_fire(state, faction, lines)
		"ACQUATTARSI":             _cower(state, faction, lines)
		"TEMPRATI DALLA GUERRA":   _battle_harden(state, faction, lines)
		"ZAPPATORI":
			lines.append("Zappatori: nessuna mina o filo spinato da rimuovere.")
		"SCONTRO SENZA PERDITE":
			lines.append("Scontro senza perdite: nessun effetto.")
		_:
			lines.append("Evento «%s»: effetto non ancora simulato." % card.event_name)
	return lines


# ─── Helper ──────────────────────────────────────────────────────────────────

## Colpisce un'unità: efficiente → rotta; già rotta → eliminata.
static func _hit(state: GameState, u: Unit, lines: Array[String], label: String) -> void:
	if u.efficient:
		u.break_unit()
		lines.append("%s: %s rotta" % [label, u.unit_name])
	else:
		state.units.erase(u.id)
		lines.append("%s: %s eliminata" % [label, u.unit_name])


# ─── Eventi ──────────────────────────────────────────────────────────────────

## E43 Supporto aereo: colpisce tutte le unità nell'esagono indicato dalla carta.
static func _air_support(state: GameState, card: Card, lines: Array[String]) -> void:
	var qr := Domain.label_to_qr(card.random_hex_label)
	var men := state.men_at(qr.x, qr.y)
	if men.is_empty():
		lines.append("Supporto aereo su %s: nessuna unità colpita." % card.random_hex_label)
		return
	for u in men:
		_hit(state, u, lines, "Supporto aereo")


## E69 Macerie: l'esagono indicato diventa terreno Macerie (Rubble).
static func _rubble(state: GameState, card: Card, lines: Array[String]) -> void:
	var qr := Domain.label_to_qr(card.random_hex_label)
	var hd: GameState.HexData = state.hex_at(qr.x, qr.y)
	if hd == null:
		lines.append("Macerie: esagono non valido.")
		return
	hd.terrain = Domain.TerrainType.RUBBLE
	lines.append("Macerie: %s ridotto in macerie." % card.random_hex_label)


## E72 Shock da combattimento: rompe l'unità più vicina all'esagono indicato.
static func _shell_shock(state: GameState, card: Card, lines: Array[String]) -> void:
	var qr := Domain.label_to_qr(card.random_hex_label)
	if qr.x < 0:
		lines.append("Shock da combattimento: esagono non valido.")
		return
	var best: Unit = null
	var best_d := 99999
	for u in state.units.values():
		if not u.is_man():
			continue
		var d := HexGrid.distance(qr.x, qr.y, u.q, u.r)
		if d < best_d:
			best_d = d
			best = u
	if best != null:
		_hit(state, best, lines, "Shock da combattimento")
	else:
		lines.append("Shock da combattimento: nessuna unità in campo.")


## E62 Ucciso in azione: elimina un'unità rotta (prima un nemico di chi pesca).
static func _kia(state: GameState, faction: int, lines: Array[String]) -> void:
	var target := _find_broken(state, faction, true)
	if target == null:
		target = _find_broken(state, faction, false)
	if target != null:
		state.units.erase(target.id)
		lines.append("Ucciso in azione: %s eliminata." % target.unit_name)
	else:
		lines.append("Ucciso in azione: nessuna unità rotta in campo.")


static func _find_broken(state: GameState, faction: int, enemy: bool) -> Unit:
	for u in state.units.values():
		if u.is_man() and not u.efficient and ((u.faction != faction) == enemy):
			return u
	return null


## E59 Infiltrazione: rompe le unità nemiche allo scoperto (copertura < 1).
static func _infiltration(state: GameState, faction: int, lines: Array[String]) -> void:
	var hit := 0
	for u in state.units.values():
		if u.is_man() and u.faction != faction and u.efficient:
			var hd: GameState.HexData = state.hex_at(u.q, u.r)
			var cover: int = Domain.TERRAIN_COVER.get(hd.terrain, 0) if hd else 0
			if cover < 1:
				u.suppress()
				hit += 1
	lines.append("Infiltrazione: %d unità nemiche allo scoperto soppresse." % hit)


## E75 Fuoco di soppressione: rompe i nemici in gittata e LOS di una MG amica.
static func _suppressing_fire(state: GameState, faction: int, lines: Array[String]) -> void:
	var mgs: Array[Unit] = []
	for u in state.units_of(faction):
		if u.efficient and u.is_weapon() and u.unit_class == Domain.UnitClass.MG:
			mgs.append(u)
	var hit := 0
	for e in state.units.values():
		if not (e.is_man() and e.faction != faction and e.efficient):
			continue
		for mg in mgs:
			if HexGrid.distance(mg.q, mg.r, e.q, e.r) <= mg.range \
					and HexGrid.has_los(mg.q, mg.r, e.q, e.r, state):
				e.suppress()
				hit += 1
				break
	lines.append("Fuoco di soppressione: %d unità nemiche soppresse." % hit)


## E51 Acquattarsi: le squadre di chi pesca fuori dal raggio di Comando si rompono.
static func _cower(state: GameState, faction: int, lines: Array[String]) -> void:
	var hit := 0
	for u in state.units_of(faction):
		if u.type == Domain.UnitType.SQUAD and u.efficient:
			if not Rules.has_command_at(state, u.q, u.r, faction):
				u.suppress()
				hit += 1
	lines.append("Acquattarsi: %d squadre fuori comando soppresse." % hit)


## E44 Temprati dalla guerra: una unità di chi pesca diventa veterana (+1 morale).
static func _battle_harden(state: GameState, faction: int, lines: Array[String]) -> void:
	for u in state.units_of(faction):
		if u.is_man() and not u.veteran:
			u.veteran = true
			u.morale += 1
			lines.append("Temprati dalla guerra: %s veterana (morale %d)." % [u.unit_name, u.morale])
			return
	lines.append("Temprati dalla guerra: nessuna unità idonea.")
