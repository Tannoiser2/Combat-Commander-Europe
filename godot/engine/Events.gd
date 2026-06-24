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
		"MEDICO":                  _medic(state, faction, lines)
		"MALFUNZIONAMENTO":        _malfunction(state, card, lines)
		"BREZZA":                  _breeze(state, lines)
		"COMMISSARIO":             _commissar(state, card, lines)
		"EROE":                    _hero(state, faction, lines)
		"INTERDIZIONE":            _interdiction(state, lines)
		"TRINCERAMENTO":           _entrench_event(state, faction, lines)
		"PROMOZIONE SUL CAMPO":    _field_promotion(state, faction, lines)
		"COMANDO E CONTROLLO":     _command_control(state, faction, lines)
		"IMPETO":                  _elan(state, faction, lines)
		"PRIGIONIERI DI GUERRA":   _prisoners(state, faction, lines)
		"POLVERE":                 _dust(state, card, lines)
		"INCENDIO":                _blaze(state, card, lines)
		"OBIETTIVO DELLA MISSIONE": _draw_objective_chit(state, lines, "Obiettivo della missione")
		"OBIETTIVO STRATEGICO":    _draw_objective_chit(state, lines, "Obiettivo strategico")
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
		state.eliminate_unit(u.id)
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
		state.eliminate_unit(target.id)
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


## E64 Medico: ripristina (rally) un'unità rotta — di norma una amica di chi
## pesca; se non ce ne sono, una nemica (l'effetto è comunque obbligatorio).
static func _medic(state: GameState, faction: int, lines: Array[String]) -> void:
	var target := _find_broken(state, faction, false)  # prima un'amica
	if target == null:
		target = _find_broken(state, faction, true)    # altrimenti una nemica
	if target != null:
		target.recover()
		lines.append("Medico: %s ripristinata." % target.unit_name)
	else:
		lines.append("Medico: nessuna unità rotta da ripristinare.")


## E63 Malfunzionamento: l'arma efficiente più vicina all'esagono casuale della
## carta si inceppa (si rompe). Vale per entrambi gli schieramenti.
static func _malfunction(state: GameState, card: Card, lines: Array[String]) -> void:
	var qr := Domain.label_to_qr(card.random_hex_label)
	if qr.x < 0:
		lines.append("Malfunzionamento: esagono non valido.")
		return
	var best: Unit = null
	var best_d := 99999
	for u in state.units.values():
		if u.is_weapon() and u.efficient:
			var d := HexGrid.distance(qr.x, qr.y, u.q, u.r)
			if d < best_d:
				best_d = d
				best = u
	if best != null:
		best.break_unit()
		lines.append("Malfunzionamento: %s si inceppa." % best.unit_name)
	else:
		lines.append("Malfunzionamento: nessun'arma efficiente in campo.")


## E48 Brezza: rimuove tutti i marcatori di Fumo dalla mappa. (La posa di Incendi,
## non modellata, è loggata a parte.)
static func _breeze(state: GameState, lines: Array[String]) -> void:
	var removed := 0
	for key in state.hexes:
		var hd: GameState.HexData = state.hexes[key]
		if hd.has_smoke:
			hd.has_smoke = false
			removed += 1
	lines.append("Brezza: rimossi %d fumi (incendi non simulati)." % removed)


## E58 Eroe: se la fazione di chi pesca non ha già un Eroe in campo, ne compare
## uno in un esagono amico. L'Eroe è un leader a figura singola (Comando 1) che
## non conta mai sul Casualty Track (E58.1).
static func _hero(state: GameState, faction: int, lines: Array[String]) -> void:
	for u in state.units_of(faction):
		if u.hero:
			lines.append("Eroe: già in campo.")
			return
	var host: Unit = null
	for u in state.units_of(faction):
		if u.is_man():
			host = u
			break
	if host == null:
		lines.append("Eroe: nessun esagono amico dove apparire.")
		return
	var id := "HERO-%s" % Domain.FACTION_SHORT.get(faction, "U")
	var h := Unit.new(id, faction, Domain.UnitType.LEADER, Domain.UnitClass.ELITE, "Eroe")
	h.hero = true
	h.fp = 2
	h.range = 4
	h.move = 6
	h.morale = 10
	h.command = 1
	h.q = host.q
	h.r = host.r
	state.units[id] = h
	lines.append("Eroe: un Eroe appare in (%d,%d)!" % [h.q, h.r])


## E60 Interdizione: ogni giocatore perde una carta dalla propria mano, che va
## nello scarto (semplificazione del «scelta a caso dalla mano avversaria»: si
## scarta l'ultima carta della mano).
static func _interdiction(state: GameState, lines: Array[String]) -> void:
	var n := 0
	for fac in [Domain.Faction.GERMAN, Domain.Faction.RUSSIAN]:
		var hand := state.hand_of(fac)
		if hand.is_empty():
			continue
		var discard := state.german_discard if fac == Domain.Faction.GERMAN else state.russian_discard
		Cards.discard_from_hand(hand, discard, hand.size() - 1)
		n += 1
	lines.append("Interdizione: ogni giocatore scarta una carta (%d in tutto)." % n)


## E55 Trinceramento: il giocatore posa una buca su un esagono occupato da una
## sua unità, privo di buca e di fortificazioni.
static func _entrench_event(state: GameState, faction: int, lines: Array[String]) -> void:
	for u in state.units_of(faction):
		if not u.is_man():
			continue
		var hd: GameState.HexData = state.hex_at(u.q, u.r)
		if hd != null and not hd.has_foxhole and hd.fortification == Domain.Fort.NONE:
			hd.has_foxhole = true
			lines.append("Trinceramento: buca creata in (%d,%d)." % [u.q, u.r])
			return
	lines.append("Trinceramento: nessun esagono idoneo.")


## E56 Promozione sul campo (semplificata): se non già in campo, compare il
## «Soldato» della nazione (Comando 2, Morale 6) su un'unità amica rotta.
static func _field_promotion(state: GameState, faction: int, lines: Array[String]) -> void:
	var id := "PRIVATE-%s" % Domain.FACTION_SHORT.get(faction, "U")
	if state.units.has(id):
		lines.append("Promozione sul campo: il Soldato è già in campo.")
		return
	var broken := state.broken_men_of(faction)
	if broken.is_empty():
		lines.append("Promozione sul campo: nessuna unità rotta su cui promuovere.")
		return
	var host: Unit = broken[0]
	var p := Unit.new(id, faction, Domain.UnitType.LEADER, Domain.UnitClass.ELITE, "Soldato")
	p.fp = 0
	p.range = 6
	p.move = 5
	p.morale = 6
	p.command = 2
	p.q = host.q
	p.r = host.r
	state.units[id] = p
	lines.append("Promozione sul campo: un Soldato (Comando 2) appare in (%d,%d)." % [p.q, p.r])


## E49 Comando e Controllo: il giocatore guadagna 1 VP per ogni obiettivo che
## controlla in questo momento.
static func _command_control(state: GameState, faction: int, lines: Array[String]) -> void:
	var n := 0
	for o in state.objectives:
		if o.controller == faction:
			n += 1
	if n > 0:
		if faction == Domain.Faction.GERMAN:
			state.bonus_vp += n
		else:
			state.bonus_vp -= n
	lines.append("Comando e Controllo: %d obiettivi controllati → +%d VP." % [n, n])


## E54 Impeto: il giocatore sposta il suo segnalino Resa di una casella più in
## alto sul Casualty Track, cioè può subire una perdita in più prima di arrendersi.
static func _elan(state: GameState, faction: int, lines: Array[String]) -> void:
	var cur := int(state.surrender_threshold.get(faction, 0))
	if cur <= 0:
		lines.append("Impeto: nessuna soglia di resa da spostare.")
		return
	state.surrender_threshold[faction] = cur + 1
	lines.append("Impeto: soglia di resa di %s ora %d." % [
		Domain.FACTION_NAMES.get(faction, "?"), cur + 1])


## E66 Prigionieri di guerra: il giocatore deve eliminare una propria unità rotta
## adiacente a (o nello stesso esagono di) un nemico. L'avversario incassa i VP.
static func _prisoners(state: GameState, faction: int, lines: Array[String]) -> void:
	for u in state.broken_men_of(faction):
		if _enemy_near(state, u, faction):
			lines.append("Prigionieri di guerra: %s catturata ed eliminata." % u.unit_name)
			state.eliminate_unit(u.id)
			return
	lines.append("Prigionieri di guerra: nessuna unità rotta a contatto col nemico.")


## Vero se c'è un'unità nemica nello stesso esagono o adiacente a `u`.
static func _enemy_near(state: GameState, u: Unit, faction: int) -> bool:
	for m in state.men_at(u.q, u.r):
		if m.faction != faction:
			return true
	for nb in HexGrid.neighbors(u.q, u.r):
		for m in state.men_at(nb.x, nb.y):
			if m.faction != faction:
				return true
	return false


## E46 Incendio: l'esagono casuale della carta prende fuoco (diventa impassabile),
## perde fumo e fortificazioni, e le unità presenti sono spostate in un esagono
## adiacente passabile (eliminate se non ce n'è).
static func _blaze(state: GameState, card: Card, lines: Array[String]) -> void:
	var qr := Domain.label_to_qr(card.random_hex_label)
	var hd: GameState.HexData = state.hex_at(qr.x, qr.y)
	if hd == null:
		lines.append("Incendio: esagono non valido.")
		return
	if hd.has_blaze:
		lines.append("Incendio: %s è già in fiamme." % card.random_hex_label)
		return
	hd.has_blaze = true
	hd.has_smoke = false
	hd.fortification = Domain.Fort.NONE
	var occupants: Array = []
	for u in state.units.values():
		if u.q == qr.x and u.r == qr.y:
			occupants.append(u)
	var moved := 0
	var killed := 0
	for u in occupants:
		var dest := _blaze_escape(state, qr.x, qr.y, u)
		if dest.x >= 0:
			u.q = dest.x
			u.r = dest.y
			moved += 1
		else:
			state.eliminate_unit(u.id)
			killed += 1
	lines.append("Incendio: %s in fiamme; %d unità spostate, %d eliminate." % [
		card.random_hex_label, moved, killed])


## Primo esagono adiacente passabile (non in fiamme, non impassabile, impilamento
## rispettato) dove far fuggire un'unità dall'incendio. (-1,-1) se nessuno.
static func _blaze_escape(state: GameState, q: int, r: int, u: Unit) -> Vector2i:
	for nb in HexGrid.neighbors(q, r):
		if nb.x < 0 or nb.x >= state.map_cols or nb.y < 0 or nb.y >= state.map_rows:
			continue
		var thd: GameState.HexData = state.hex_at(nb.x, nb.y)
		if thd == null or thd.has_blaze:
			continue
		if int(Domain.TERRAIN_MOVE_COST.get(thd.terrain, 1)) >= 99:
			continue
		if u.is_man() and state.soldier_icons_at(nb.x, nb.y) + u.soldier_icons() > 7:
			continue
		return nb
	return Vector2i(-1, -1)


## E53 Polvere: posa un marker di fumo (polvere) sull'esagono casuale della carta.
static func _dust(state: GameState, card: Card, lines: Array[String]) -> void:
	var qr := Domain.label_to_qr(card.random_hex_label)
	var hd: GameState.HexData = state.hex_at(qr.x, qr.y)
	if hd == null:
		lines.append("Polvere: esagono non valido.")
		return
	hd.has_smoke = true
	lines.append("Polvere: nube di polvere (fumo) in %s." % card.random_hex_label)


## E65 Obiettivo della missione / E74 Obiettivo strategico: si estrae un chit
## aggiuntivo e lo si somma (cumulativo, 7.3.2) ad un obiettivo casuale; i VP
## fluiscono al controllore corrente tramite il normale calcolo.
static func _draw_objective_chit(state: GameState, lines: Array[String], label: String) -> void:
	if state.objectives.is_empty():
		lines.append("%s: nessun obiettivo sulla mappa." % label)
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pool: Array = ObjectiveChits.CHIT_POOL
	var v := int(pool[rng.randi_range(0, pool.size() - 1)])
	var o: Objective = state.objectives[rng.randi_range(0, state.objectives.size() - 1)]
	o.vp += v
	lines.append("%s: Obiettivo #%d +%d VP." % [label, o.id, v])


## E50 Commissario: il giocatore russo sceglie una sua unità rotta e tira (dadi
## della carta del Fato): se il risultato è > Morale l'unità è eliminata,
## altrimenti viene ripristinata (rally).
static func _commissar(state: GameState, card: Card, lines: Array[String]) -> void:
	# Stand-in: il giocatore "russo" è lo slot Alleati (Domain.Faction.RUSSIAN).
	var broken := state.broken_men_of(Domain.Faction.RUSSIAN)
	if broken.is_empty():
		lines.append("Commissario: nessuna unità russa rotta.")
		return
	var target: Unit = broken[0]
	var roll := card.dice_white + card.dice_red
	if roll > target.morale:
		state.eliminate_unit(target.id)
		lines.append("Commissario: %s — tiro %d > morale %d → ELIMINATA." % [
			target.unit_name, roll, target.morale])
	else:
		target.recover()
		lines.append("Commissario: %s — tiro %d ≤ morale %d → ripristinata." % [
			target.unit_name, roll, target.morale])
