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


## Avvia una nuova partita con lo scenario 1.
func start_new_game(human_faction: int = Domain.Faction.GERMAN) -> void:
	state = GameState.new()
	state.human_faction = human_faction

	Scenario1.setup(state)

	# Costruisce e mescola i mazzi
	state.german_deck = Cards.build_german_deck()
	state.russian_deck = Cards.build_russian_deck()
	Cards.shuffle(state.german_deck)
	Cards.shuffle(state.russian_deck)
	Cards.deal_initial(state)

	_log("═══ SCENARIO: %s ═══" % Scenario1.SCENARIO_NAME)
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
	# Evidenzia esagoni raggiungibili
	if state.phase == Domain.Phase.PLAYER_MOVING:
		var reach := HexGrid.reachable(u, state)
		state.highlighted_hexes.clear()
		for h in reach:
			state.highlighted_hexes.append("%d,%d" % [h.x, h.y])
	else:
		state.highlighted_hexes.clear()
	emit_signal("state_changed")


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
		Domain.OrderType.MOVE:
			state.order_count += 1
			_change_phase(Domain.Phase.PLAYER_MOVING)
			state.selected_card_index = hand_index
		Domain.OrderType.FIRE:
			state.order_count += 1
			_change_phase(Domain.Phase.PLAYER_MOVING)  # riusa fase per selezione bersaglio
			state.selected_card_index = hand_index
		Domain.OrderType.RECOVER:
			_execute_recover(hand_index)
		Domain.OrderType.PASS:
			_discard_card(hand_index)
			_end_player_turn()
		_:
			_discard_card(hand_index)


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
	if not Combat.can_fire(u, tq, tr, state):
		_log("Fuoco illegale verso (%d,%d)" % [tq, tr])
		return
	var result := Combat.resolve_fire(u, tq, tr, state, _rng)
	u.activated = true
	_log(result.log_line)
	for uid2 in result.broken:
		emit_signal("unit_eliminated", uid2)
	emit_signal("fire_resolved", result)
	# Scarta la carta usata e pesca una nuova
	var hand := state.hand_of(state.human_faction)
	var discard := state.german_discard if state.human_faction == Domain.Faction.GERMAN else state.russian_discard
	var deck := state.german_deck if state.human_faction == Domain.Faction.GERMAN else state.russian_deck
	var ci := state.selected_card_index
	if ci >= 0 and ci < hand.size():
		Cards.discard_from_hand(hand, discard, ci)
		Cards.draw(deck, discard, hand)
	state.selected_card_index = -1
	state.selected_unit_id = ""
	state.highlighted_hexes.clear()
	_change_phase(Domain.Phase.PLAYER_TURN)
	_check_end_conditions()


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
	# Controllo stacking
	if u.is_man() and state.men_at(tq, tr).size() >= 8:
		_log("Stacking: max 8 uomini in (%d,%d)" % [tq, tr])
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

	# Aggiorna esagoni raggiungibili
	var reach := HexGrid.reachable(u, state)
	state.highlighted_hexes.clear()
	for h in reach:
		state.highlighted_hexes.append("%d,%d" % [h.x, h.y])

	emit_signal("state_changed")


func _execute_recover(hand_index: int) -> void:
	# Rimuove soppressione da tutte le unità amiche
	var count := 0
	for u in state.units_of(state.human_faction):
		if u.suppressed:
			u.suppressed = false
			count += 1
	_discard_card(hand_index)
	_log("Recupero: %d unità ripristinate" % count)
	emit_signal("state_changed")


func _discard_card(hand_index: int) -> void:
	var hand := state.hand_of(state.human_faction)
	var discard := state.german_discard if state.human_faction == Domain.Faction.GERMAN else state.russian_discard
	var deck := state.german_deck if state.human_faction == Domain.Faction.GERMAN else state.russian_deck
	if hand_index >= 0 and hand_index < hand.size():
		Cards.discard_from_hand(hand, discard, hand_index)
		Cards.draw(deck, discard, hand)


func _end_player_turn() -> void:
	# Azzera attivazioni e PM residui
	state.moving_unit_id = ""
	state.moving_remaining_mp = 0
	state.moving_card_index = -1
	state.selected_unit_id = ""
	state.highlighted_hexes.clear()
	for u in state.units.values():
		u.activated = false

	# Avanza il segnatore del tempo
	state.time_marker += 1
	if state.time_marker >= state.sudden_death_space:
		_check_sudden_death()
		return

	state.turn_number += 1
	_log("--- Fine turno %d ---" % (state.turn_number - 1))
	# In questo prototipo il giocatore è sempre GERMAN; l'IA gestisce i russi brevemente
	_run_ai_turn()
	_change_phase(Domain.Phase.PLAYER_TURN)
	_log("Turno %d — il tuo ordine" % state.turn_number)


func _run_ai_turn() -> void:
	# IA minimale: muove ogni unità russa verso l'obiettivo centrale
	var obj: Objective = null
	if state.objectives.size() > 0:
		obj = state.objectives[0]
	for u in state.units_of(Domain.Faction.RUSSIAN):
		if u.is_weapon():
			continue
		if obj:
			_ai_move_toward(u, obj.q, obj.r)


func _ai_move_toward(u: Unit, tq: int, tr: int) -> void:
	if u.move <= 0:
		return
	var nb := HexGrid.neighbors(u.q, u.r)
	var best: Vector2i = Vector2i(u.q, u.r)
	var best_dist := HexGrid.distance(u.q, u.r, tq, tr)
	for n in nb:
		if n.x < 0 or n.x >= state.map_cols or n.y < 0 or n.y >= state.map_rows:
			continue
		var d := HexGrid.distance(n.x, n.y, tq, tr)
		if d < best_dist:
			# Controlla stacking e nemici
			var men := state.men_at(n.x, n.y)
			var enemy := false
			for m in men:
				if m.faction == Domain.Faction.GERMAN:
					enemy = true
					break
			if not enemy and men.size() < 8:
				best_dist = d
				best = n
	if best != Vector2i(u.q, u.r):
		u.q = best.x
		u.r = best.y
		emit_signal("unit_moved", u.id, best.x, best.y)


# ─── Fine partita ─────────────────────────────────────────────────────────────

func _check_end_conditions() -> void:
	var ger_units := state.units_of(Domain.Faction.GERMAN).size()
	var rus_units := state.units_of(Domain.Faction.RUSSIAN).size()
	if ger_units == 0:
		_end_game(Domain.Faction.RUSSIAN)
	elif rus_units == 0:
		_end_game(Domain.Faction.GERMAN)


func _check_sudden_death() -> void:
	_log("⏰ MORTE SUBITANEA — fine partita!")
	var winner := _count_objectives()
	_end_game(winner)


func _count_objectives() -> int:
	var ger_vp := 0
	var rus_vp := 0
	for obj in state.objectives:
		# Controller = fazione con più uomini nell'esagono
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
		elif rus > ger:
			obj.controller = Domain.Faction.RUSSIAN
			rus_vp += obj.vp
		else:
			obj.controller = -1
	state.vp_tracker = ger_vp - rus_vp
	_log("VP finali — GER: %d, RUS: %d" % [ger_vp, rus_vp])
	if ger_vp > rus_vp:
		return Domain.Faction.GERMAN
	elif rus_vp > ger_vp:
		return Domain.Faction.RUSSIAN
	return -1


func _end_game(winner: int) -> void:
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
