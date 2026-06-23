## Controllore principale di Combat Commander: Europe.
## Autoload singleton — emette segnali verso la scena, non la tocca direttamente.
extends Node

# ─── Segnali ─────────────────────────────────────────────────────────────────

signal state_changed()               ## Aggiornamento generico — ridisegna tutto
signal log_added(line: String)       ## Nuova riga di log
signal fire_resolved(result: Object) ## Combat.FireResult
signal phase_changed(phase: int)     ## Nuova fase
signal unit_moved(unit_id: String, q: int, r: int)
signal unit_eliminated(unit_id: String)
signal game_over(winner: int)        ## Domain.Faction o -1 (patta)


# ─── Stato ────────────────────────────────────────────────────────────────────

var state: GameState = null
var _rng: RandomNumberGenerator = null


# ─── Init ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.randomize()


## Avvia una nuova partita. `scenario_num` 1..24 (default 1).
func start_new_game(human_faction: int = Domain.Faction.GERMAN, scenario_num: int = 1) -> void:
	state = GameState.new()
	state.human_faction = human_faction

	# Lo scenario 1 ha dati di piazzamento curati a mano; gli altri usano il
	# loader generico (catalogo + ordini di battaglia recuperati).
	if scenario_num <= 1:
		Scenario1.setup(state)
		state.scenario_number = 1
		state.scenario_name = Scenario1.SCENARIO_NAME
	elif not ScenarioLoader.setup(state, scenario_num):
		Scenario1.setup(state)
		state.scenario_number = 1
		state.scenario_name = Scenario1.SCENARIO_NAME

	# Costruisce e mescola i mazzi
	state.german_deck = Cards.build_german_deck()
	state.russian_deck = Cards.build_russian_deck()
	Cards.shuffle(state.german_deck)
	Cards.shuffle(state.russian_deck)
	Cards.deal_initial(state)

	_log("═══ SCENARIO %d: %s ═══" % [state.scenario_number, state.scenario_name])
	_log("Turno %d — iniziativa: %s" % [
		state.turn_number,
		Domain.FACTION_NAMES.get(state.initiative_holder, "?")
	])
	_change_phase(Domain.Phase.PLAYER_TURN)


# ─── Selezione unità ─────────────────────────────────────────────────────────

func select_unit(unit_id: String) -> void:
	if state == null:
		return
	var u := state.unit_by_id(unit_id)
	if u == null:
		state.selected_unit_id = ""
		state.highlighted_hexes.clear()
		emit_signal("state_changed")
		return
	state.selected_unit_id = unit_id
	state.highlighted_hexes.clear()
	# Evidenzia gli esagoni validi secondo l'ordine in corso.
	if state.phase == Domain.Phase.PLAYER_MOVING:
		match state.current_order:
			Domain.OrderType.MOVE:
				for h in HexGrid.reachable(u, state):
					state.highlighted_hexes.append("%d,%d" % [h.x, h.y])
			Domain.OrderType.FIRE:
				for h in _fire_targets(u):
					state.highlighted_hexes.append("%d,%d" % [h.x, h.y])
			Domain.OrderType.ADVANCE:
				for h in HexGrid.neighbors(u.q, u.r):
					if h.x >= 0 and h.x < state.map_cols and h.y >= 0 and h.y < state.map_rows:
						state.highlighted_hexes.append("%d,%d" % [h.x, h.y])
	emit_signal("state_changed")


## Esagoni nemici che l'unità può colpire (gittata + LOS + nemico presente).
func _fire_targets(u: Unit) -> Array[Vector2i]:
	var targets: Array[Vector2i] = []
	for h in HexGrid.hexes_in_range(u.q, u.r, u.range, state):
		if Combat.can_fire(u, h.x, h.y, state):
			targets.append(h)
	return targets


func deselect() -> void:
	if state == null:
		return
	state.selected_unit_id = ""
	state.highlighted_hexes.clear()
	emit_signal("state_changed")


# ─── Ordini ──────────────────────────────────────────────────────────────────

## Gioca una carta dalla mano del giocatore umano.
func play_card(hand_index: int) -> void:
	if state == null or state.phase != Domain.Phase.PLAYER_TURN:
		return
	var hand := state.hand_of(state.human_faction)
	if hand_index < 0 or hand_index >= hand.size():
		return
	var card: Card = hand[hand_index]
	_log("Carta #%d giocata: %s" % [card.number, Domain.ORDER_LABELS.get(card.order, card.order_label)])

	match card.order:
		Domain.OrderType.MOVE, Domain.OrderType.FIRE, Domain.OrderType.ADVANCE:
			# Ordini con bersaglio: si entra in fase di selezione sulla mappa.
			state.order_count += 1
			state.current_order = card.order
			state.selected_card_index = hand_index
			state.selected_unit_id = ""
			state.highlighted_hexes.clear()
			_change_phase(Domain.Phase.PLAYER_MOVING)
		Domain.OrderType.RECOVER:
			_execute_recover(hand_index)
		Domain.OrderType.ROUT:
			_execute_rout(hand_index)
		Domain.OrderType.PASS:
			_discard_card(hand_index)
			_end_player_turn()
		_:
			# Artiglieria e altri ordini non ancora portati: scartati.
			_discard_card(hand_index)


## Gioca la CARTA come AZIONE (banda inferiore) invece che come ordine.
func play_action(hand_index: int) -> void:
	if state == null or state.phase != Domain.Phase.PLAYER_TURN:
		return
	var hand := state.hand_of(state.human_faction)
	if hand_index < 0 or hand_index >= hand.size():
		return
	var card: Card = hand[hand_index]
	_log("Azione giocata: %s" % card.action_name)
	if card.action_name == "BOMBE A MANO":
		_resolve_grenades(state.human_faction)
	else:
		for line in Actions.play(state, card, state.human_faction):
			_log(line)
	_discard_card(hand_index)
	_check_end_conditions()
	emit_signal("state_changed")


## Bombe a mano: la prima unità amica adiacente a un nemico lancia (auto-target).
func _resolve_grenades(faction: int) -> void:
	for u in state.units_of(faction):
		if not (u.is_man() and u.efficient):
			continue
		for nb in HexGrid.neighbors(u.q, u.r):
			if nb.x < 0 or nb.x >= state.map_cols or nb.y < 0 or nb.y >= state.map_rows:
				continue
			var enemies := state.men_at(nb.x, nb.y).filter(
				func(m: Unit) -> bool: return m.faction != faction)
			if enemies.is_empty():
				continue
			var fate := _draw_fate(faction)
			var res := Actions.grenade_attack(state, u, nb.x, nb.y, _dice_of(fate))
			_log(String(res["log"]))
			for id in res["eliminated"]:
				emit_signal("unit_eliminated", id)
			_apply_fate(fate, faction)
			return
	_log("Bombe a mano: nessun nemico adiacente.")


## Giocatore clicca su un esagono durante la fase di movimento.
func click_hex_move(tq: int, tr: int) -> void:
	if state == null or state.phase != Domain.Phase.PLAYER_MOVING:
		return
	var uid := state.selected_unit_id
	if uid == "":
		return
	var u := state.unit_by_id(uid)
	if u == null or u.faction != state.human_faction:
		return
	_execute_move_step(u, tq, tr)


## Giocatore clicca su un esagono nemico per sparare.
func click_hex_fire(tq: int, tr: int) -> void:
	if state == null:
		return
	var uid := state.selected_unit_id
	if uid == "":
		return
	var u := state.unit_by_id(uid)
	if u == null or u.faction != state.human_faction:
		return
	if state.current_order != Domain.OrderType.FIRE:
		return
	if not Combat.can_fire(u, tq, tr, state):
		_log("Fuoco illegale verso (%d,%d)" % [tq, tr])
		return
	# Tutto il gruppo di fuoco (unità co-locate in gittata) si attiva.
	var group := Combat.fire_group(u, tq, tr, state)
	var weapon_ids: Array = []
	for g in group:
		g.activated = true
		if g.is_weapon():
			weapon_ids.append(g.id)
	var atk_fate := _draw_fate(state.human_faction)
	var def_fate := _draw_fate(_ai_faction())
	var result := Combat.resolve_fire(u, tq, tr, state, _dice_of(atk_fate), _dice_of(def_fate))
	_log(result.log_line)
	for uid2 in result.eliminated:
		emit_signal("unit_eliminated", uid2)
	emit_signal("fire_resolved", result)
	_apply_fate(atk_fate, state.human_faction, { "kind": "fire", "weapons": weapon_ids })
	_apply_fate(def_fate, _ai_faction())
	_discard_card(state.selected_card_index)
	_clear_order_selection()
	_check_end_conditions()  # aggiorna obiettivi/VP e gestisce la fine partita
	if state.phase != Domain.Phase.GAME_OVER:
		_change_phase(Domain.Phase.PLAYER_TURN)


## Giocatore clicca un esagono adiacente durante un'Avanzata.
func click_hex_advance(tq: int, tr: int) -> void:
	if state == null or state.phase != Domain.Phase.PLAYER_MOVING:
		return
	if state.current_order != Domain.OrderType.ADVANCE:
		return
	var uid := state.selected_unit_id
	if uid == "":
		return
	var u := state.unit_by_id(uid)
	if u == null or u.faction != state.human_faction:
		return
	if HexGrid.distance(u.q, u.r, tq, tr) != 1:
		_log("Avanzata: scegli un esagono adiacente.")
		return
	_execute_advance(u, tq, tr)


# ─── Implementazioni interne ──────────────────────────────────────────────────

func _execute_move_step(u: Unit, tq: int, tr: int) -> void:
	# Prima attivazione: inizializza PM rimasti
	if state.moving_unit_id != u.id:
		state.moving_unit_id = u.id
		state.moving_remaining_mp = u.move
		state.moving_card_index = state.selected_card_index

	var cost := HexGrid.move_cost(u, tq, tr, state.moving_remaining_mp, state)
	if cost < 0:
		_log("Esagono (%d,%d) irraggiungibile (PM insufficienti)" % [tq, tr])
		return
	# Controllo impilamento: max 7 soldier icons per esagono (8.1)
	if u.is_man() and state.soldier_icons_at(tq, tr) + u.soldier_icons() > 7:
		_log("Impilamento: max 7 figure in (%d,%d)" % [tq, tr])
		return

	var old_q := u.q
	var old_r := u.r
	u.q = tq
	u.r = tr
	state.moving_remaining_mp -= cost
	_log("%s si muove (%d,%d)→(%d,%d) [-%d PM, rimasti %d]" % [
		u.unit_name, old_q, old_r, tq, tr, cost, state.moving_remaining_mp
	])
	emit_signal("unit_moved", u.id, tq, tr)

	# Fuoco di Opportunità del difensore (A33): può interrompere il movimento.
	if _op_fire(u, _ai_faction()):
		state.moving_unit_id = ""
		state.moving_remaining_mp = 0
		state.current_order = -1
		state.selected_unit_id = ""
		state.highlighted_hexes.clear()
		_check_end_conditions()
		emit_signal("state_changed")
		return

	# Aggiorna esagoni raggiungibili
	var reach := HexGrid.reachable(u, state)
	state.highlighted_hexes.clear()
	for h in reach:
		state.highlighted_hexes.append("%d,%d" % [h.x, h.y])

	_check_end_conditions()  # un movimento può conquistare un obiettivo
	emit_signal("state_changed")


## Avanzata (O21): l'unità entra nell'esagono adiacente. Se vi sono nemici si
## risolve un corpo a corpo tra tutte le unità presenti nei due schieramenti.
func _execute_advance(u: Unit, tq: int, tr: int) -> void:
	var enemies := state.men_at(tq, tr).filter(
		func(m: Unit) -> bool: return m.faction != u.faction
	)

	if enemies.is_empty():
		# Avanzata semplice in esagono vuoto/amico (rispetta l'impilamento).
		if u.is_man() and state.soldier_icons_at(tq, tr) + u.soldier_icons() > 7:
			_log("Impilamento: max 7 figure in (%d,%d)" % [tq, tr])
			return
		u.q = tq; u.r = tr
		u.activated = true
		_log("%s avanza in (%d,%d)" % [u.unit_name, tq, tr])
		emit_signal("unit_moved", u.id, tq, tr)
	else:
		# Corpo a corpo: attaccanti = unità amiche che entrano; difensori = nemici.
		u.q = tq; u.r = tr
		u.activated = true
		var attackers := state.men_at(tq, tr).filter(
			func(m: Unit) -> bool: return m.faction == u.faction
		)
		var defenders := state.men_at(tq, tr).filter(
			func(m: Unit) -> bool: return m.faction != u.faction
		)
		var def_faction: int = defenders[0].faction
		var af := _draw_fate(u.faction)
		var df := _draw_fate(def_faction)
		var mr := Rules.resolve_melee(
			state, attackers, defenders, _dice_of(af), _dice_of(df))
		_log(mr.log_line)
		for uid in mr.eliminated:
			emit_signal("unit_eliminated", uid)
		_apply_fate(af, u.faction)
		_apply_fate(df, def_faction)

	_discard_card(state.selected_card_index)
	_clear_order_selection()
	_check_end_conditions()  # aggiorna obiettivi/VP e gestisce la fine partita
	if state.phase != Domain.Phase.GAME_OVER:
		_change_phase(Domain.Phase.PLAYER_TURN)


## Recupero (O22): tiro di Morale per ogni unità rotta amica.
func _execute_recover(hand_index: int) -> void:
	state.order_count += 1
	var broken := state.broken_men_of(state.human_faction)
	if broken.is_empty():
		_log("Recupero: nessuna unità rotta da ripristinare.")
	for u in broken:
		var fate := _draw_fate(state.human_faction)
		var r := Rules.try_recover(state, u, _dice_of(fate))
		_log("Recupero %s: %d vs %d → %s" % [
			u.unit_name, r["roll"], r["target"], "OK" if r["success"] else "fallito"
		])
		_apply_fate(fate, state.human_faction)
		if state.phase == Domain.Phase.GAME_OVER:
			break
	_discard_card(hand_index)
	emit_signal("state_changed")


## Rotta (O23): ogni unità rotta amica si ritira verso il bordo amico.
func _execute_rout(hand_index: int) -> void:
	state.order_count += 1
	var broken := state.broken_men_of(state.human_faction)
	if broken.is_empty():
		_log("Rotta: nessuna unità rotta.")
	for u in broken:
		var fate := _draw_fate(state.human_faction)
		var r := Rules.rout_unit(state, u, _dice_of(fate))
		if r["eliminated"]:
			_log("Rotta %s: %d esagoni → ELIMINATA (nessuna via di fuga)" % [u.unit_name, r["steps"]])
			emit_signal("unit_eliminated", u.id)
		else:
			_log("Rotta %s: tiro %d, si ritira di %d esagoni" % [u.unit_name, r["roll"], r["moved"]])
			emit_signal("unit_moved", u.id, u.q, u.r)
		_apply_fate(fate, state.human_faction)
		if state.phase == Domain.Phase.GAME_OVER:
			break
	_discard_card(hand_index)
	_check_end_conditions()
	emit_signal("state_changed")


## Azzera la selezione e l'ordine corrente dopo aver risolto un ordine.
func _clear_order_selection() -> void:
	state.selected_card_index = -1
	state.selected_unit_id = ""
	state.current_order = -1
	state.highlighted_hexes.clear()


func _discard_card(hand_index: int) -> void:
	_discard_for(state.human_faction, hand_index)


## Scarta e ripesca per una fazione qualsiasi (umana o IA).
func _discard_for(faction: int, hand_index: int) -> void:
	var hand := state.hand_of(faction)
	var discard := state.german_discard if faction == Domain.Faction.GERMAN else state.russian_discard
	var deck := state.german_deck if faction == Domain.Faction.GERMAN else state.russian_deck
	if hand_index >= 0 and hand_index < hand.size():
		Cards.discard_from_hand(hand, discard, hand_index)
		Cards.draw(deck, discard, hand)


## La fazione controllata dall'IA (l'opposta dell'umano).
func _ai_faction() -> int:
	return Domain.Faction.RUSSIAN if state.human_faction == Domain.Faction.GERMAN else Domain.Faction.GERMAN


## La fazione avversaria di `f`.
func _opponent(f: int) -> int:
	return Domain.Faction.RUSSIAN if f == Domain.Faction.GERMAN else Domain.Faction.GERMAN


# ─── Mazzo del Fato ────────────────────────────────────────────────────────────

## Pesca una carta del Fato per la fazione (per ottenere i dadi del tiro).
func _draw_fate(faction: int) -> Card:
	return Fate.draw(state, faction)


## I dadi della carta pescata (fallback RNG se mazzo+scarti sono vuoti).
func _dice_of(card: Card) -> Vector2i:
	if card == null:
		return Rules.roll_dice(_rng)
	return Fate.dice(card)


# ─── Fuoco di Opportunità (A33) ───────────────────────────────────────────────

## Il difensore reagisce al movimento di `mover` con il miglior tiratore idoneo
## (fuoco automatico per ora; la scelta interattiva del tiratore è un'aggiunta
## futura). Restituisce true se il mover è stato rotto o eliminato (movimento da
## interrompere).
func _op_fire(mover: Unit, defender: int) -> bool:
	var shooter := OpFire.best_shooter(state, mover, defender)
	if shooter == null:
		return false
	var group := Combat.fire_group(shooter, mover.q, mover.r, state)
	var weapon_ids: Array = []
	for g in group:
		if g.is_weapon():
			weapon_ids.append(g.id)
	var atk_fate := _draw_fate(defender)
	var def_fate := _draw_fate(mover.faction)
	var res := Combat.resolve_fire(shooter, mover.q, mover.r, state, _dice_of(atk_fate), _dice_of(def_fate))
	_log("⚡ Opportunità — " + res.log_line)
	for id in res.eliminated:
		emit_signal("unit_eliminated", id)
	_apply_fate(atk_fate, defender, { "kind": "fire", "weapons": weapon_ids })
	_apply_fate(def_fate, mover.faction)
	return res.eliminated.has(mover.id) or res.broken.has(mover.id)


## Applica la conseguenza della carta del Fato (Tempo!/Cecchino/Inceppamento/
## Evento) e controlla l'eventuale Morte Subitanea.
func _apply_fate(card: Card, faction: int, context: Dictionary = {}) -> void:
	if card == null:
		return
	for line in Fate.apply_consequence(state, card, faction, context):
		_log("Fato — " + line)
	if state.time_marker >= state.sudden_death_space and state.phase != Domain.Phase.GAME_OVER:
		_check_sudden_death()


func _end_player_turn() -> void:
	# Azzera attivazioni e PM residui
	state.moving_unit_id = ""
	state.moving_remaining_mp = 0
	state.moving_card_index = -1
	state.current_order = -1
	state.selected_unit_id = ""
	state.highlighted_hexes.clear()
	for u in state.units.values():
		u.activated = false

	# Il tempo NON avanza a ogni turno: in CC:E si muove solo con un "Tempo!"
	# pescato dal Mazzo del Fato (vedi Fate._consequence_time).
	if state.time_marker >= state.sudden_death_space:
		_check_sudden_death()
		return

	state.turn_number += 1
	_log("--- Fine turno %d ---" % (state.turn_number - 1))
	# Turno dell'IA (la fazione opposta all'umano).
	_run_ai_turn()
	if state.phase == Domain.Phase.GAME_OVER:
		return  # l'IA ha chiuso la partita: non riportare il turno all'umano
	_change_phase(Domain.Phase.PLAYER_TURN)
	_log("Turno %d — il tuo ordine" % state.turn_number)


func _run_ai_turn() -> void:
	var faction := _ai_faction()
	var plays := 0
	while plays < state.ai_max_orders:
		var play := AI.choose_play(state, faction)
		if play.is_empty():
			break
		_ai_execute(faction, play)
		plays += 1
		_check_end_conditions()
		if state.phase == Domain.Phase.GAME_OVER:
			return
	if plays == 0:
		_log("IA: nessun ordine giocabile.")


## Esegue un ordine scelto dall'IA (vedi AI.choose_play) e scarta la carta.
func _ai_execute(faction: int, play: Dictionary) -> void:
	match int(play["order"]):
		Domain.OrderType.FIRE:
			var atk := state.unit_by_id(String(play["attacker_id"]))
			var fq := int(play["q"])
			var fr := int(play["r"])
			if atk != null and Combat.can_fire(atk, fq, fr, state):
				var group := Combat.fire_group(atk, fq, fr, state)
				var weapon_ids: Array = []
				for g in group:
					g.activated = true
					if g.is_weapon():
						weapon_ids.append(g.id)
				var ffate := _draw_fate(faction)
				var dfate := _draw_fate(_opponent(faction))
				var fres := Combat.resolve_fire(atk, fq, fr, state, _dice_of(ffate), _dice_of(dfate))
				_log("IA — " + fres.log_line)
				for fid in fres.eliminated:
					emit_signal("unit_eliminated", fid)
				_apply_fate(ffate, faction, { "kind": "fire", "weapons": weapon_ids })
				_apply_fate(dfate, _opponent(faction))
		Domain.OrderType.ADVANCE:
			var mover := state.unit_by_id(String(play["unit_id"]))
			if mover != null:
				_ai_advance(faction, mover, int(play["q"]), int(play["r"]))
		Domain.OrderType.RECOVER:
			for ru in state.broken_men_of(faction):
				var rfate := _draw_fate(faction)
				var rec := Rules.try_recover(state, ru, _dice_of(rfate))
				_log("IA recupero %s: %s" % [ru.unit_name, "OK" if rec["success"] else "fallito"])
				_apply_fate(rfate, faction)
				if state.phase == Domain.Phase.GAME_OVER:
					break
		Domain.OrderType.ROUT:
			for ou in state.broken_men_of(faction):
				var ofate := _draw_fate(faction)
				var rou := Rules.rout_unit(state, ou, _dice_of(ofate))
				if rou["eliminated"]:
					emit_signal("unit_eliminated", ou.id)
				else:
					emit_signal("unit_moved", ou.id, ou.q, ou.r)
				_apply_fate(ofate, faction)
				if state.phase == Domain.Phase.GAME_OVER:
					break
		Domain.OrderType.MOVE:
			_ai_move_order(faction)
	_discard_for(faction, int(play["card_index"]))
	emit_signal("state_changed")


## Avanzata dell'IA in (tq,tr); se vi sono nemici risolve il corpo a corpo (O21).
func _ai_advance(faction: int, u: Unit, tq: int, tr: int) -> void:
	u.q = tq
	u.r = tr
	u.activated = true
	emit_signal("unit_moved", u.id, tq, tr)
	var defenders := state.men_at(tq, tr).filter(
		func(m: Unit) -> bool: return m.faction != faction)
	if defenders.is_empty():
		_log("IA — %s avanza in (%d,%d)" % [u.unit_name, tq, tr])
		return
	var def_faction: int = defenders[0].faction
	var attackers := state.men_at(tq, tr).filter(
		func(m: Unit) -> bool: return m.faction == faction)
	var af := _draw_fate(faction)
	var df := _draw_fate(def_faction)
	var mr := Rules.resolve_melee(
		state, attackers, defenders, _dice_of(af), _dice_of(df))
	_log("IA — " + mr.log_line)
	for mid in mr.eliminated:
		emit_signal("unit_eliminated", mid)
	_apply_fate(af, faction)
	_apply_fate(df, def_faction)


## Ordine di Mossa dell'IA: avvicina gli uomini all'obiettivo più vicino.
func _ai_move_order(faction: int) -> void:
	for u in state.units_of(faction):
		if u.activated or u.is_weapon() or not u.efficient:
			continue
		var obj := _nearest_objective(faction, u)
		if obj != null:
			_ai_move_toward(u, obj.q, obj.r, faction)
		u.activated = true


## Obiettivo più vicino non controllato dall'IA (o il primo disponibile).
func _nearest_objective(faction: int, u: Unit) -> Objective:
	var best: Objective = null
	var best_d := 99999
	for o in state.objectives:
		if o.controller == faction:
			continue
		var d := HexGrid.distance(u.q, u.r, o.q, o.r)
		if d < best_d:
			best_d = d
			best = o
	if best == null and state.objectives.size() > 0:
		best = state.objectives[0]
	return best


func _ai_move_toward(u: Unit, tq: int, tr: int, faction: int) -> void:
	if u.move <= 0:
		return
	var best: Vector2i = Vector2i(u.q, u.r)
	var best_dist := HexGrid.distance(u.q, u.r, tq, tr)
	for n in HexGrid.neighbors(u.q, u.r):
		if n.x < 0 or n.x >= state.map_cols or n.y < 0 or n.y >= state.map_rows:
			continue
		var d := HexGrid.distance(n.x, n.y, tq, tr)
		if d >= best_dist:
			continue
		var men := state.men_at(n.x, n.y)
		var enemy := false
		for m in men:
			if m.faction != faction:
				enemy = true
				break
		if not enemy and state.soldier_icons_at(n.x, n.y) + u.soldier_icons() <= 7:
			best_dist = d
			best = n
	if best != Vector2i(u.q, u.r):
		u.q = best.x
		u.r = best.y
		emit_signal("unit_moved", u.id, best.x, best.y)
		# Il difensore (avversario di chi muove) reagisce col Fuoco di Opportunità.
		# Marca l'unità come "in movimento" così un pareggio difesa la rompe (A33).
		var prev_moving := state.moving_unit_id
		state.moving_unit_id = u.id
		_op_fire(u, _opponent(u.faction))
		state.moving_unit_id = prev_moving


# ─── Fine partita ─────────────────────────────────────────────────────────────

## Da chiamare dopo ogni azione: aggiorna obiettivi/VP, controlla la resa
## (Casualty Track), la vittoria automatica (tutti gli obiettivi) e
## l'eliminazione totale di una fazione.
func _check_end_conditions() -> void:
	# Resa (6.3.1): le perdite di una fazione hanno raggiunto la sua soglia →
	# sconfitta immediata, a prescindere dai VP. Ha la precedenza su obiettivi/VP.
	var ger_surr := state.has_surrendered(Domain.Faction.GERMAN)
	var rus_surr := state.has_surrendered(Domain.Faction.RUSSIAN)
	if ger_surr or rus_surr:
		_resolve_loss(ger_surr, rus_surr, "resa")
		return

	var sweep := _update_objectives()
	if sweep != -1:
		_log("%s controlla tutti gli obiettivi — vittoria automatica!" % Domain.FACTION_NAMES.get(sweep, "?"))
		_end_game(sweep)
		return

	# Ultima unità sulla mappa eliminata (6.3, situazione 2).
	var ger_units := state.units_of(Domain.Faction.GERMAN).size()
	var rus_units := state.units_of(Domain.Faction.RUSSIAN).size()
	if ger_units == 0 or rus_units == 0:
		_resolve_loss(ger_units == 0, rus_units == 0, "annientamento")


## Conclude la partita quando una o entrambe le fazioni hanno perso (6.3.1):
## in caso di doppia sconfitta simultanea vince chi detiene l'iniziativa.
func _resolve_loss(ger_lost: bool, rus_lost: bool, reason: String) -> void:
	var winner: int
	if ger_lost and rus_lost:
		winner = state.initiative_holder
		_log("Doppia sconfitta (%s) — l'iniziativa decide il vincitore." % reason)
	elif ger_lost:
		winner = Domain.Faction.RUSSIAN
		_log("%s si arrende (%s)." % [Domain.FACTION_NAMES.get(Domain.Faction.GERMAN, "?"), reason])
	else:
		winner = Domain.Faction.GERMAN
		_log("%s si arrende (%s)." % [Domain.FACTION_NAMES.get(Domain.Faction.RUSSIAN, "?"), reason])
	_end_game(winner)


func _check_sudden_death() -> void:
	_log("⏰ MORTE SUBITANEA — fine partita!")
	var winner := _count_objectives()
	_end_game(winner)


## Ricalcola il controllo degli obiettivi e la bilancia VP (in-place).
## Restituisce la fazione che controlla TUTTI gli obiettivi, o -1.
func _update_objectives() -> int:
	var ger_vp := 0
	var rus_vp := 0
	var all_ger := state.objectives.size() > 0
	var all_rus := state.objectives.size() > 0
	for obj in state.objectives:
		var ger := 0
		var rus := 0
		for u in state.men_at(obj.q, obj.r):
			if u.faction == Domain.Faction.GERMAN:
				ger += 1
			else:
				rus += 1
		if ger > rus:
			obj.controller = Domain.Faction.GERMAN
			ger_vp += obj.vp
			all_rus = false
		elif rus > ger:
			obj.controller = Domain.Faction.RUSSIAN
			rus_vp += obj.vp
			all_ger = false
		else:
			obj.controller = -1
			all_ger = false
			all_rus = false
	state.vp_tracker = ger_vp - rus_vp
	if all_ger:
		return Domain.Faction.GERMAN
	if all_rus:
		return Domain.Faction.RUSSIAN
	return -1


func _count_objectives() -> int:
	_update_objectives()
	_log("VP finali — bilancia %+d (positivo = Germania)" % state.vp_tracker)
	if state.vp_tracker > 0:
		return Domain.Faction.GERMAN
	elif state.vp_tracker < 0:
		return Domain.Faction.RUSSIAN
	return -1


func _end_game(winner: int) -> void:
	if state.phase == Domain.Phase.GAME_OVER:
		return  # partita già conclusa: evita doppio segnale
	_change_phase(Domain.Phase.GAME_OVER)
	var fname: String = Domain.FACTION_NAMES.get(winner, "PAREGGIO")
	_log("═══ FINE PARTITA — Vincitore: %s ═══" % fname)
	emit_signal("game_over", winner)


# ─── Utilità ──────────────────────────────────────────────────────────────────

func _log(msg: String) -> void:
	if state:
		state.add_log(msg)
	emit_signal("log_added", msg)


func _change_phase(new_phase: int) -> void:
	if state:
		state.phase = new_phase
	emit_signal("phase_changed", new_phase)
	emit_signal("state_changed")
