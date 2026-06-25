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

	# Costruisce e mescola i mazzi reali delle due nazioni (slot Asse/Alleati).
	state.german_deck = Cards.build_deck(state.axis_nation)
	state.russian_deck = Cards.build_deck(state.allied_nation)
	Cards.shuffle(state.german_deck)
	Cards.shuffle(state.russian_deck)
	Cards.deal_initial(state)

	_log("═══ SCENARIO %d: %s ═══" % [state.scenario_number, state.scenario_name])
	_log("Turno %d — iniziativa: %s" % [
		state.turn_number,
		Domain.FACTION_NAMES.get(state.initiative_holder, "?")
	])
	_change_phase(Domain.Phase.PLAYER_TURN)


## Salva la partita corrente sul file di salvataggio. true se riuscito.
func save_game(path: String = SaveGame.SAVE_PATH) -> bool:
	if state == null:
		return false
	var ok := SaveGame.save_state(state, path)
	if ok:
		_log("💾 Partita salvata.")
	return ok


## Ripristina la partita dal file di salvataggio. true se riuscito.
func load_game(path: String = SaveGame.SAVE_PATH) -> bool:
	var s := SaveGame.load_state(path)
	if s == null:
		return false
	state = s
	_log("📂 Partita caricata.")
	emit_signal("phase_changed", state.phase)
	emit_signal("state_changed")
	return true


func has_saved_game(path: String = SaveGame.SAVE_PATH) -> bool:
	return SaveGame.has_save(path)


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

	# ─── Mossa: gruppo di comando ────────────────────────────────────────────
	# Alla prima selezione si forma il gruppo attorno all'unità ordinata (un
	# leader trascina le unità nel suo raggio di Comando). Poi si può passare da
	# un membro all'altro, ma non aggiungere unità a un ordine già avviato.
	if state.phase == Domain.Phase.PLAYER_MOVING and state.current_order == Domain.OrderType.MOVE:
		if state.ordered_group.is_empty():
			if u.faction != state.human_faction or u.activated:
				return
			_form_move_group(u)
		elif not state.ordered_group.has(unit_id):
			return
		state.selected_unit_id = unit_id
		state.moving_unit_id = unit_id
		_highlight_reachable(u)
		emit_signal("state_changed")
		return

	# ─── Altri ordini ────────────────────────────────────────────────────────
	state.selected_unit_id = unit_id
	state.highlighted_hexes.clear()
	if state.phase == Domain.Phase.PLAYER_MOVING:
		match state.current_order:
			Domain.OrderType.FIRE:
				for h in _fire_targets(u):
					state.highlighted_hexes.append("%d,%d" % [h.x, h.y])
			Domain.OrderType.ADVANCE:
				for h in HexGrid.neighbors(u.q, u.r):
					if h.x >= 0 and h.x < state.map_cols and h.y >= 0 and h.y < state.map_rows:
						state.highlighted_hexes.append("%d,%d" % [h.x, h.y])
	emit_signal("state_changed")


## Forma il gruppo di comando per un ordine di Mossa (3.3): se l'unità ordinata
## è un leader con Comando > 0, attiva sé stesso e tutte le unità idonee (uomini
## efficienti e muovibili, non già attivate) entro il raggio di Comando.
func _form_move_group(u: Unit) -> void:
	state.ordered_group.clear()
	state.group_mp.clear()
	state.move_committed = false
	var ids: Array[String] = []
	if u.is_leader() and u.command > 0:
		for v in state.units_of(state.human_faction):
			if v.is_man() and v.efficient and v.move > 0 and not v.activated \
					and HexGrid.distance(u.q, u.r, v.q, v.r) <= u.command:
				ids.append(v.id)
		if not ids.has(u.id):
			ids.append(u.id)
	else:
		ids.append(u.id)
	for id in ids:
		state.ordered_group.append(id)
		state.group_mp[id] = Rules.move_with_command(state, state.unit_by_id(id))
	if ids.size() > 1:
		_log("Comando: %s attiva %d unità entro raggio %d." % [u.unit_name, ids.size(), u.command])


## Evidenzia gli esagoni raggiungibili dal mover coi suoi PM rimasti nel gruppo.
func _highlight_reachable(u: Unit) -> void:
	state.highlighted_hexes.clear()
	var budget := int(state.group_mp.get(u.id, u.move))
	for h in HexGrid.reachable(u, state, budget):
		state.highlighted_hexes.append("%d,%d" % [h.x, h.y])


## Esagoni nemici che l'unità può colpire (gittata + LOS + nemico presente).
func _fire_targets(u: Unit) -> Array[Vector2i]:
	var targets: Array[Vector2i] = []
	for h in HexGrid.hexes_in_range(u.q, u.r, Rules.range_with_command(state, u), state):
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
	state.last_impact_hexes.clear()  # un nuovo ordine rimuove il marker d'impatto
	var card: Card = hand[hand_index]

	# Limite di Ordini per turno (5.1): MOVE/FIRE/ADVANCE/RECOVER/ROUT contano come
	# Ordini. PASS e Artiglieria-negata no. Esauriti gli Ordini, si può solo passare
	# o giocare Azioni (tasto destro).
	var counts_as_order: bool = card.order in [
		Domain.OrderType.MOVE, Domain.OrderType.FIRE, Domain.OrderType.ADVANCE,
		Domain.OrderType.RECOVER, Domain.OrderType.ROUT, Domain.OrderType.ARTY]
	if counts_as_order and state.order_count >= state.max_orders:
		_log("Ordini esauriti per questo turno (%d/%d). Premi «Fine Turno» o gioca un'Azione." % [
			state.order_count, state.max_orders])
		return

	_log("Carta #%d giocata: %s" % [card.number, Domain.ORDER_LABELS.get(card.order, card.order_label)])

	match card.order:
		Domain.OrderType.MOVE, Domain.OrderType.FIRE, Domain.OrderType.ADVANCE:
			# Ordini con bersaglio: si entra in fase di selezione sulla mappa.
			state.order_count += 1
			state.current_order = card.order
			state.assault_fired = false  # Fuoco d'Assalto disponibile una volta per ordine
			state.selected_card_index = hand_index
			state.highlighted_hexes.clear()
			_change_phase(Domain.Phase.PLAYER_MOVING)
			# Se un'unità idonea è già selezionata la si mantiene, evidenziando subito
			# i bersagli (flusso naturale: unità → carta → bersaglio). Altrimenti si
			# attende che il giocatore clicchi un'unità sulla mappa.
			var pre := state.unit_by_id(state.selected_unit_id)
			if pre != null and pre.faction == state.human_faction and not pre.activated:
				select_unit(pre.id)
			else:
				state.selected_unit_id = ""
				emit_signal("state_changed")
		Domain.OrderType.RECOVER:
			_execute_recover(hand_index)
		Domain.OrderType.ROUT:
			_execute_rout(hand_index)
		Domain.OrderType.ARTY:
			_play_artillery(hand_index)
		Domain.OrderType.PASS:
			_discard_card(hand_index)
			_end_player_turn()
		_:
			# Artiglieria e altri ordini non ancora portati: scartati.
			_discard_card(hand_index)


## Richiesta d'Artiglieria (O18, versione auto-target): serve una Radio e un
## Leader (spotter) non rotti. Si fa un Targeting Roll spotter→bersaglio, la
## granata deriva (O18.2.2) e il punto d'impatto colpisce 7 esagoni (O18.2.3).
func _play_artillery(hand_index: int) -> void:
	var human := state.human_faction
	var radio: Unit = null
	var spotter: Unit = null
	for u in state.units_of(human):
		if not u.efficient:
			continue
		if radio == null and u.unit_name.contains("Radio"):
			radio = u
		if spotter == null and u.is_leader():
			spotter = u
	if radio == null or spotter == null:
		_log("Artiglieria: servono una Radio e un Leader non rotti in campo.")
		_discard_card(hand_index)
		return
	# Spotting (O18.2.1): si entra in fase di scelta del bersaglio. Il giocatore
	# clicca un esagono nella LOS dello spotter; lì cadrà la Spotting Round.
	state.order_count += 1
	state.current_order = Domain.OrderType.ARTY
	state.selected_unit_id = spotter.id
	state.selected_card_index = hand_index
	state.artillery_spotter_id = spotter.id
	state.artillery_radio_id = radio.id
	state.highlighted_hexes.clear()
	for key in state.hexes:
		var p := String(key).split(",")
		if HexGrid.has_los(spotter.q, spotter.r, int(p[0]), int(p[1]), state):
			state.highlighted_hexes.append(key)
	_change_phase(Domain.Phase.PLAYER_MOVING)
	_log("Artiglieria: scegli l'esagono bersaglio nella linea di vista di %s." % spotter.unit_name)
	emit_signal("state_changed")


## Vero se la fazione umana ha una Radio e un Leader (spotter) non rotti: può
## quindi giocare un ordine di Artiglieria (O18).
func has_artillery_available() -> bool:
	if state == null:
		return false
	var radio := false
	var spotter := false
	for u in state.units_of(state.human_faction):
		if not u.efficient:
			continue
		if u.unit_name.contains("Radio"):
			radio = true
		elif u.is_leader():
			spotter = true
	return radio and spotter


## Alterna barrage esplosivo/fumogeno durante la scelta del bersaglio (O18.2.1.1).
func toggle_artillery_smoke() -> void:
	if state == null or state.current_order != Domain.OrderType.ARTY:
		return
	state.artillery_smoke = not state.artillery_smoke
	_log("Artiglieria: barrage %s." % ("FUMOGENO" if state.artillery_smoke else "esplosivo"))
	emit_signal("state_changed")


## Il giocatore sceglie l'esagono bersaglio (Spotting Round): si risolve il
## bombardamento con deriva e impatto.
func click_hex_artillery(tq: int, tr: int) -> void:
	if state == null or state.phase != Domain.Phase.PLAYER_MOVING \
		or state.current_order != Domain.OrderType.ARTY:
		return
	var spotter := state.unit_by_id(state.artillery_spotter_id)
	var radio := state.unit_by_id(state.artillery_radio_id)
	var ci := state.selected_card_index
	var smoke := state.artillery_smoke
	_clear_order_selection()
	if spotter == null or radio == null:
		_change_phase(Domain.Phase.PLAYER_TURN)
		return
	_resolve_artillery_strike(spotter, radio, tq, tr, "", smoke)
	if ci >= 0:
		_discard_card(ci)
	_check_end_conditions()
	if state.phase != Domain.Phase.GAME_OVER:
		_change_phase(Domain.Phase.PLAYER_TURN)
	emit_signal("state_changed")


## Risoluzione comune della bombardamento (umano e IA): Targeting Roll
## spotter→bersaglio, deriva della granata (O18.2.2) e impatto a 7 esagoni
## (O18.2.3). Marca la radio come attivata.
func _resolve_artillery_strike(spotter: Unit, radio: Unit, tq: int, tr: int, prefix: String = "", smoke: bool = false) -> void:
	var dist := HexGrid.distance(spotter.q, spotter.r, tq, tr)
	var hind := HexGrid.los_hindrance(spotter.q, spotter.r, tq, tr, state)
	var tdice := Rules.roll_dice(_rng)
	var hit := tdice.x * tdice.y > dist + hind
	var dd := Rules.roll_dice(_rng)
	var sr := Rules.artillery_drift(state, tq, tr, hit, dd.x, dd.y)
	radio.activated = true
	if sr.x < 0:
		_log(prefix + "Artiglieria: la granata è uscita dalla mappa — nessun effetto.")
		return
	# Marker visivo: i 7 esagoni dell'area d'impatto (centro + adiacenti in mappa).
	state.last_impact_hexes = [Vector2i(sr.x, sr.y)]
	for nb in HexGrid.neighbors(sr.x, sr.y):
		if nb.x >= 0 and nb.x < state.map_cols and nb.y >= 0 and nb.y < state.map_rows:
			state.last_impact_hexes.append(nb)
	if smoke:
		# Barrage fumogeno (O18.2.3.1): posa fumo sui 7 esagoni, niente esplosivo.
		var ns := Combat.resolve_smoke_barrage(state, sr.x, sr.y)
		_log(prefix + "Artiglieria fumogena (%s) su (%d,%d): fumo su %d esagoni." % [
			"colpito" if hit else "mancato", sr.x, sr.y, ns])
		return
	var fp := _radio_fp(radio)
	var res := Combat.resolve_artillery(state, fp, sr.x, sr.y, _rng)
	var fort_txt := " %d fortif. distrutte." % int(res["forts"]) if int(res.get("forts", 0)) > 0 else ""
	_log(prefix + "Artiglieria (%s, FP%d) su (%d,%d): %d eliminate, %d rotte, %d soppresse.%s" % [
		"colpito" if hit else "mancato", fp, sr.x, sr.y,
		res["eliminated"].size(), res["broken"].size(), res["suppressed"].size(), fort_txt])
	for id in res["eliminated"]:
		emit_signal("unit_eliminated", id)


## FP della bombardamento in base al calibro della Radio.
func _radio_fp(radio: Unit) -> int:
	var nm := radio.unit_name
	if nm.contains("105"):
		return 24
	if nm.contains("88"):
		return 20
	if nm.contains("81"):
		return 18
	return 16  # 75mm e default


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


## Dispatch unico di un clic su un esagono (q,r), indipendente dalla vista (2D o
## 3D): seleziona unità, esegue ordini, assembla il fuoco, gestisce la finestra di
## reazione. Sia la mappa 2D sia quella 3D chiamano questo metodo dopo aver
## tradotto il punto cliccato in coordinate esagono.
func click_hex(q: int, r: int) -> void:
	if state == null:
		return
	var s := state
	var key := "%d,%d" % [q, r]
	var units_here := s.units_at(q, r)
	if s.phase == Domain.Phase.PLAYER_MOVING:
		var sel := s.unit_by_id(s.selected_unit_id) if s.selected_unit_id != "" else null
		# Fuoco: assemblaggio del gruppo (bersaglio già scelto).
		if s.current_order == Domain.OrderType.FIRE and s.fire_target_q >= 0:
			if q == s.fire_target_q and r == s.fire_target_r:
				confirm_fire()
				return
			for eid in s.fire_eligible_ids:
				if eid == s.selected_unit_id:
					continue
				var ev := s.unit_by_id(eid)
				if ev != null and ev.q == q and ev.r == r:
					toggle_fire_piece(eid)
					return
			if sel != null and q == sel.q and r == sel.r:
				cancel_fire_target()
			return
		# Mossa di gruppo: cliccare un altro membro attivato cambia il mover attivo.
		if s.current_order == Domain.OrderType.MOVE:
			for gid in s.ordered_group:
				if gid == s.selected_unit_id:
					continue
				var gv := s.unit_by_id(gid)
				if gv != null and gv.q == q and gv.r == r:
					select_unit(gid)
					return
		# Click sull'esagono dell'unità attiva = concludi/annulla l'ordine.
		if sel != null and q == sel.q and r == sel.r:
			conclude_order()
			return
		# Click su esagono evidenziato = esegui l'ordine.
		if s.selected_unit_id != "" and s.highlighted_hexes.has(key):
			match s.current_order:
				Domain.OrderType.MOVE:
					click_hex_move(q, r)
				Domain.OrderType.FIRE:
					click_hex_fire(q, r)
				Domain.OrderType.ADVANCE:
					click_hex_advance(q, r)
				Domain.OrderType.ARTY:
					click_hex_artillery(q, r)
		else:
			_cycle_select(units_here, false)
	elif s.phase == Domain.Phase.REACTION_WINDOW:
		for sid in s.opfire_shooter_ids:
			var sv := s.unit_by_id(sid)
			if sv != null and sv.q == q and sv.r == r:
				opfire_choose(sid)
				return
		opfire_decline()
	elif s.phase == Domain.Phase.PLAYER_TURN:
		_cycle_select(units_here, true)


## Ciclo di selezione nell'impilamento: a clic ripetuti sullo stesso esagono
## scorre le pedine amiche non attivate (per scegliere quella voluta); dopo
## l'ultima, se `allow_deselect`, deseleziona, altrimenti riparte dalla prima.
func _cycle_select(units_here: Array, allow_deselect: bool) -> void:
	var sel_list: Array = units_here.filter(
		func(u: Unit) -> bool: return u.faction == state.human_faction and not u.activated)
	if sel_list.is_empty():
		if allow_deselect:
			deselect()
		return
	var idx := -1
	for i in sel_list.size():
		if sel_list[i].id == state.selected_unit_id:
			idx = i
			break
	if idx < 0:
		select_unit(sel_list[0].id)
	elif idx + 1 < sel_list.size():
		select_unit(sel_list[idx + 1].id)
	elif allow_deselect:
		deselect()
	else:
		select_unit(sel_list[0].id)


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


## Colonna del bordo AVVERSARIO da cui una fazione può uscire (7.2): i Tedeschi
## (schierati a Est) escono a Ovest (q=0), i Russi (a Ovest) a Est (q=cols-1).
func _exit_edge_col(faction: int) -> int:
	return 0 if faction == Domain.Faction.GERMAN else state.map_cols - 1


## Vero se l'unità è sul bordo avversario e può quindi uscire dalla mappa.
func _on_exit_edge(u: Unit) -> bool:
	return u.q == _exit_edge_col(u.faction)


## L'unità umana selezionata esce dal bordo avversario (7.2, costo 1 MP): il
## proprietario guadagna i VP del pezzo e la pedina lascia la mappa.
func can_exit_selected() -> bool:
	if state == null or state.phase != Domain.Phase.PLAYER_MOVING:
		return false
	if state.current_order != Domain.OrderType.MOVE:
		return false
	var u := state.unit_by_id(state.selected_unit_id)
	if u == null or u.faction != state.human_faction:
		return false
	return _on_exit_edge(u) and int(state.group_mp.get(u.id, 0)) >= 1


# ─── Fuoco d'Assalto (A26 Assault Fire) ───────────────────────────────────────

## Miglior bersaglio per il Fuoco d'Assalto di `u`: esagono nemico in gittata e
## LOS, col maggior numero di nemici (a parità, il più vicino). (-1,-1) se nessuno.
func _best_assault_target(u: Unit) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_n := 0
	var best_d := 999
	var rng := Rules.range_with_command(state, u)
	for other in state.units.values():
		if other.faction == u.faction or not other.is_man():
			continue
		var d := HexGrid.distance(u.q, u.r, other.q, other.r)
		if d == 0 or d > rng or not HexGrid.has_los(u.q, u.r, other.q, other.r, state):
			continue
		var n := 0
		for t in state.men_at(other.q, other.r):
			if t.faction != u.faction:
				n += 1
		if n > best_n or (n == best_n and d < best_d):
			best_n = n
			best_d = d
			best = Vector2i(other.q, other.r)
	return best


## Fuoco d'Assalto (A26): durante una Mossa, un'unità attivata a muovere fa un
## attacco di fuoco (una volta per ordine). Bersaglio auto-scelto.
func assault_fire(hand_index: int) -> void:
	if state == null or state.phase != Domain.Phase.PLAYER_MOVING \
		or state.current_order != Domain.OrderType.MOVE:
		return
	var hand := state.hand_of(state.human_faction)
	if hand_index < 0 or hand_index >= hand.size():
		return
	var card: Card = hand[hand_index]
	if card.action_name != "FUOCO D'ASSALTO":
		_log("«%s» non è un Fuoco d'Assalto." % card.action_name)
		return
	if state.assault_fired:
		_log("Fuoco d'Assalto: già usato in questa Mossa.")
		return
	var u := state.unit_by_id(state.selected_unit_id)
	if u == null:
		u = state.unit_by_id(state.moving_unit_id)
	# A26: serve un pezzo in movimento con FP «in scatola» (qui: squadra/team non ordnance).
	if u == null or not u.is_man() or u.is_leader() or not u.efficient or u.fp <= 0 or u.ordnance:
		_log("Fuoco d'Assalto: serve una squadra/team in movimento con FP.")
		return
	var target := _best_assault_target(u)
	if target.x < 0:
		_log("Fuoco d'Assalto: nessun bersaglio in gittata/LOS.")
		return
	var group: Array[Unit] = [u]
	var atk_fate := _draw_fate(state.human_faction)
	var def_fate := _draw_fate(_ai_faction())
	var atk_dice := _dice_of(atk_fate)
	var result := Combat.resolve_fire(
		u, target.x, target.y, state, atk_dice, _dice_of(def_fate), group, 0)
	_log("Fuoco d'Assalto — " + result.log_line)
	for uid2 in result.eliminated:
		emit_signal("unit_eliminated", uid2)
	emit_signal("fire_resolved", result)
	_apply_fate(atk_fate, state.human_faction, { "kind": "fire", "weapons": [] })
	_apply_fate(def_fate, _ai_faction())
	state.assault_fired = true
	_discard_card(hand_index)
	_check_end_conditions()
	if state.phase != Domain.Phase.GAME_OVER:
		emit_signal("state_changed")


func exit_selected_unit() -> void:
	if not can_exit_selected():
		return
	var u := state.unit_by_id(state.selected_unit_id)
	var v := state.exit_unit_for_vp(u.id)
	_log("%s esce dal bordo avversario (7.2): +%d VP a %s." % [
		u.unit_name, v, Domain.FACTION_NAMES[u.faction]])
	emit_signal("unit_eliminated", u.id)  # rimuove la pedina dalla mappa
	state.group_mp.erase(u.id)
	_check_end_conditions()
	if state.phase == Domain.Phase.GAME_OVER:
		emit_signal("state_changed")
	else:
		_after_mover_done()


## Giocatore clicca un esagono nemico col FUOCO: entra nell'assemblaggio del
## gruppo di fuoco (O20.3.1). Se solo il pezzo base può colpire, spara subito.
func click_hex_fire(tq: int, tr: int) -> void:
	if state == null or state.current_order != Domain.OrderType.FIRE:
		return
	var u := state.unit_by_id(state.selected_unit_id)
	if u == null or u.faction != state.human_faction:
		return
	if not Combat.can_fire(u, tq, tr, state):
		_log("Fuoco illegale verso (%d,%d)" % [tq, tr])
		return
	# Pezzi idonei a colpire il bersaglio (base + co-locati/in-comando, LOS+gittata).
	var elig := Combat.fire_group(u, tq, tr, state)
	state.fire_target_q = tq
	state.fire_target_r = tr
	state.fire_eligible_ids.clear()
	state.fire_group_ids.clear()
	for g in elig:
		state.fire_eligible_ids.append(g.id)
		state.fire_group_ids.append(g.id)
	# Un solo pezzo idoneo → niente da assemblare: spara subito.
	if state.fire_eligible_ids.size() <= 1:
		confirm_fire()
		return
	state.highlighted_hexes = ["%d,%d" % [tq, tr]]
	emit_signal("state_changed")


## Include/esclude un pezzo idoneo dal gruppo di fuoco (il base resta sempre).
func toggle_fire_piece(id: String) -> void:
	if state == null or state.current_order != Domain.OrderType.FIRE or state.fire_target_q < 0:
		return
	if id == state.selected_unit_id or not state.fire_eligible_ids.has(id):
		return
	if state.fire_group_ids.has(id):
		state.fire_group_ids.erase(id)
	else:
		state.fire_group_ids.append(id)
	emit_signal("state_changed")


## Annulla la scelta del bersaglio e torna alla selezione del bersaglio.
func cancel_fire_target() -> void:
	if state == null:
		return
	state.fire_target_q = -1
	state.fire_target_r = -1
	state.fire_eligible_ids.clear()
	state.fire_group_ids.clear()
	state.spray_active = false
	var u := state.unit_by_id(state.selected_unit_id)
	if u != null:
		select_unit(u.id)  # ri-evidenzia i bersagli possibili
	else:
		emit_signal("state_changed")


## Risolve il fuoco col gruppo attualmente scelto dal giocatore.
func confirm_fire() -> void:
	if state == null or state.current_order != Domain.OrderType.FIRE:
		return
	var u := state.unit_by_id(state.selected_unit_id)
	if u == null or state.fire_target_q < 0:
		return
	var tq := state.fire_target_q
	var tr := state.fire_target_r
	var group: Array[Unit] = []
	for id in state.fire_group_ids:
		var g := state.unit_by_id(id)
		if g != null:
			group.append(g)
	if group.is_empty():
		group.append(u)
	var weapon_ids: Array = []
	for g in group:
		g.activated = true
		if g.is_weapon():
			weapon_ids.append(g.id)
	# Carta ordine + carte modificatore: consumate per riferimento (l'ordine degli
	# indici non conta) dopo la risoluzione.
	var hand := state.hand_of(state.human_faction)
	var to_discard: Array = []
	if state.selected_card_index >= 0 and state.selected_card_index < hand.size():
		to_discard.append(hand[state.selected_card_index])
	for c in state.fire_modifier_cards:
		to_discard.append(c)
	var fp_bonus := 2 * state.fire_modifiers.size()
	var atk_fate := _draw_fate(state.human_faction)
	var def_fate := _draw_fate(_ai_faction())
	var atk_dice := _dice_of(atk_fate)
	var spray_q := -1
	var spray_r := -1
	if state.spray_active:
		var sp := _spray_target()
		spray_q = sp.x
		spray_r = sp.y
	var result := Combat.resolve_fire(
		u, tq, tr, state, atk_dice, _dice_of(def_fate), group, fp_bonus, spray_q, spray_r)
	_log(result.log_line)
	# Fuoco Sostenuto (A41): su un doppio, un'arma (MG/mortaio) che spara si inceppa.
	if atk_dice.x == atk_dice.y:
		var breaks := state.fire_modifiers.count("FUOCO SOSTENUTO")
		for g in group:
			if breaks <= 0:
				break
			if g.is_weapon() and g.efficient and (g.unit_class == Domain.UnitClass.MG or g.unit_class == Domain.UnitClass.MORTAR):
				g.break_unit()
				breaks -= 1
				_log("Fuoco Sostenuto: %s si inceppa (doppio)." % g.unit_name)
	for uid2 in result.eliminated:
		emit_signal("unit_eliminated", uid2)
	emit_signal("fire_resolved", result)
	_apply_fate(atk_fate, state.human_faction, { "kind": "fire", "weapons": weapon_ids })
	_apply_fate(def_fate, _ai_faction())
	for c in to_discard:
		var idx := hand.find(c)
		if idx >= 0:
			_discard_for(state.human_faction, idx)
	_clear_order_selection()
	_check_end_conditions()  # aggiorna obiettivi/VP e gestisce la fine partita
	if state.phase != Domain.Phase.GAME_OVER:
		_change_phase(Domain.Phase.PLAYER_TURN)


# ─── Modificatori di fuoco (A30/A37/A41) ──────────────────────────────────────

## Azioni che modificano un attacco di fuoco e si applicano durante
## l'assemblaggio (ognuna +2 FP, con prerequisiti propri).
const FIRE_MOD_NAMES := ["FUOCO MIRATO", "FUOCO SOSTENUTO", "FUOCO INCROCIATO"]


## Pezzi attualmente nel gruppo di fuoco (oggetti Unit).
func _current_fire_group() -> Array:
	var g: Array = []
	for id in state.fire_group_ids:
		var u := state.unit_by_id(id)
		if u != null:
			g.append(u)
	return g


## "" se il modificatore è applicabile, altrimenti il motivo (prerequisito CC:E).
func _fire_modifier_error(nm: String) -> String:
	var group := _current_fire_group()
	match nm:
		"FUOCO MIRATO":  # Marksmanship (A37): deve sparare una squadra/team.
			for g in group:
				if g.is_man() and not g.is_leader():
					return ""
			return "richiede una squadra/team nel gruppo di fuoco"
		"FUOCO SOSTENUTO":  # Sustained Fire (A41): deve sparare una MG/mortaio.
			for g in group:
				if g.is_weapon() and (g.unit_class == Domain.UnitClass.MG or g.unit_class == Domain.UnitClass.MORTAR):
					return ""
			return "richiede una MG o un mortaio nel gruppo"
		"FUOCO INCROCIATO":  # Crossfire (A30): solo contro un bersaglio in movimento.
			for t in state.men_at(state.fire_target_q, state.fire_target_r):
				if t.id == state.moving_unit_id:
					return ""
			return "solo contro un'unità in movimento"
	return ""


## Applica un modificatore di fuoco dalla mano durante l'assemblaggio (+2 FP).
func apply_fire_modifier(hand_index: int) -> void:
	if state == null or state.current_order != Domain.OrderType.FIRE or state.fire_target_q < 0:
		return
	var hand := state.hand_of(state.human_faction)
	if hand_index < 0 or hand_index >= hand.size():
		return
	var card: Card = hand[hand_index]
	var nm := card.action_name
	if nm == "SVENTAGLIATA":  # Spray Fire (A40): aggiunge un secondo esagono bersaglio
		_apply_spray(card)
		return
	if not FIRE_MOD_NAMES.has(nm):
		_log("«%s» non è un modificatore di fuoco (in questo contesto)." % (nm if nm != "" else "—"))
		return
	if state.fire_modifier_cards.has(card):
		return  # già applicata
	var err := _fire_modifier_error(nm)
	if err != "":
		_log("%s: %s." % [nm, err])
		return
	state.fire_modifiers.append(nm)
	state.fire_modifier_cards.append(card)
	_log("Modificatore di fuoco: %s (+2 FP)." % nm)
	emit_signal("state_changed")


## Secondo esagono bersaglio della Sventagliata (A40): adiacente al bersaglio
## primario, con un nemico, entro gittata e LOS di TUTTI i pezzi del gruppo.
## Sceglie quello con più nemici. (-1,-1) se nessuno è idoneo.
func _spray_target() -> Vector2i:
	var tq := state.fire_target_q
	var tr := state.fire_target_r
	if tq < 0:
		return Vector2i(-1, -1)
	var group := _current_fire_group()
	var best := Vector2i(-1, -1)
	var best_n := 0
	for n in HexGrid.neighbors(tq, tr):
		if n.x < 0 or n.x >= state.map_cols or n.y < 0 or n.y >= state.map_rows:
			continue
		var enemies := 0
		for t in state.men_at(n.x, n.y):
			if t.faction != state.human_faction:
				enemies += 1
		if enemies == 0:
			continue
		var reachable := true
		for g in group:
			if HexGrid.distance(g.q, g.r, n.x, n.y) > Rules.range_with_command(state, g) \
				or not HexGrid.has_los(g.q, g.r, n.x, n.y, state):
				reachable = false
				break
		if reachable and enemies > best_n:
			best_n = enemies
			best = n
	return best


## Applica la Sventagliata: estende il fuoco al secondo esagono (no bonus FP).
func _apply_spray(card: Card) -> void:
	if state.fire_modifier_cards.has(card):
		return
	var has_man := false
	for g in _current_fire_group():
		if g.is_man():  # A40: i pezzi devono avere gittata «in scatola» (no ordnance)
			has_man = true
			break
	if not has_man:
		_log("Sventagliata: richiede squadre/team (non ordnance).")
		return
	var sp := _spray_target()
	if sp.x < 0:
		_log("Sventagliata: nessun esagono nemico adiacente al bersaglio e a tiro.")
		return
	state.spray_active = true
	state.fire_modifier_cards.append(card)
	_log("Sventagliata: colpirà anche (%d,%d)." % [sp.x, sp.y])
	emit_signal("state_changed")


## FP previsto del gruppo di fuoco attuale (per il banner; senza dadi).
func projected_fire_fp() -> int:
	if state == null or state.current_order != Domain.OrderType.FIRE or state.fire_target_q < 0:
		return 0
	var fp := 0
	for id in state.fire_group_ids:
		var g := state.unit_by_id(id)
		if g != null:
			fp = maxi(fp, Rules.fp_with_command(state, g))
	if state.fire_group_ids.size() > 1:
		fp += state.fire_group_ids.size() - 1
	fp += 2 * state.fire_modifiers.size()  # modificatori applicati (+2 ciascuno)
	var u := state.unit_by_id(state.selected_unit_id)
	if u != null and not u.ordnance:
		var hind := HexGrid.los_hindrance(u.q, u.r, state.fire_target_q, state.fire_target_r, state)
		var hd: GameState.HexData = state.hex_at(state.fire_target_q, state.fire_target_r)
		if hd != null and hd.has_smoke:
			hind += 1
		fp = maxi(1, fp - hind)
	return fp


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


## Conclude l'ordine di Mossa in corso: marca attivate TUTTE le unità del gruppo
## (anche quelle non mosse: l'ordine le ha usate), scarta la carta e torna al
## turno. Chiamata a PM esauriti dell'intero gruppo o per stop volontario.
func finish_move() -> void:
	if state == null or state.phase != Domain.Phase.PLAYER_MOVING:
		return
	if state.current_order != Domain.OrderType.MOVE:
		return
	var card_idx := state.selected_card_index if state.selected_card_index >= 0 else state.moving_card_index
	for id in state.ordered_group:
		var v := state.unit_by_id(id)
		if v != null:
			v.activated = true
	state.moving_unit_id = ""
	state.moving_remaining_mp = 0
	state.moving_card_index = -1
	if card_idx >= 0:
		_discard_card(card_idx)
	_clear_order_selection()
	_check_end_conditions()
	if state.phase != Domain.Phase.GAME_OVER:
		_change_phase(Domain.Phase.PLAYER_TURN)


## Annulla un ordine non ancora "impegnato" (nessun passo di movimento, carta
## NON consumata) e torna alla scelta. Se la Mossa ha già mosso qualcuno la si
## conclude invece (finish_move); FIRE/ADVANCE non eseguiti restituiscono la carta.
func cancel_order() -> void:
	if state == null or state.phase != Domain.Phase.PLAYER_MOVING:
		return
	if state.current_order == Domain.OrderType.MOVE and state.move_committed:
		finish_move()
		return
	if state.order_count > 0:
		state.order_count -= 1
	_clear_order_selection()
	_change_phase(Domain.Phase.PLAYER_TURN)


## Gesto unico «clic sull'unità attiva» dalla mappa: conclude o annulla l'ordine
## a seconda che sia già stato impegnato (un movimento eseguito / un fuoco no).
func conclude_order() -> void:
	if state == null or state.phase != Domain.Phase.PLAYER_MOVING:
		return
	if state.current_order == Domain.OrderType.MOVE and state.move_committed:
		finish_move()
	else:
		cancel_order()


## Dopo che un mover del gruppo ha esaurito i PM (o è stato rotto): se restano
## membri in grado di muovere, lascia scegliere il prossimo; altrimenti conclude.
func _after_mover_done() -> void:
	state.moving_unit_id = ""
	state.selected_unit_id = ""
	state.highlighted_hexes.clear()
	if state.ordered_group.size() > 1 and _any_group_mover_left():
		emit_signal("state_changed")  # il giocatore sceglie il prossimo membro
	else:
		finish_move()


## C'è ancora almeno un membro del gruppo con PM residui e un esagono dove andare?
func _any_group_mover_left() -> bool:
	for id in state.ordered_group:
		var v := state.unit_by_id(id)
		if v == null or not v.efficient:
			continue
		var mp := int(state.group_mp.get(id, 0))
		if mp > 0 and HexGrid.reachable(v, state, mp).size() > 0:
			return true
	return false


# ─── Implementazioni interne ──────────────────────────────────────────────────

func _execute_move_step(u: Unit, tq: int, tr: int) -> void:
	# PM rimasti del mover all'interno del gruppo di comando.
	var remaining := int(state.group_mp.get(u.id, u.move))
	var cost := HexGrid.move_cost(u, tq, tr, remaining, state)
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
	remaining -= cost
	state.group_mp[u.id] = remaining
	state.move_committed = true
	state.moving_unit_id = u.id
	state.moving_card_index = state.selected_card_index
	_log("%s si muove (%d,%d)→(%d,%d) [-%d PM, rimasti %d]" % [
		u.unit_name, old_q, old_r, tq, tr, cost, remaining
	])
	emit_signal("unit_moved", u.id, tq, tr)

	# Mine (F103): attacco entrando in un esagono minato; se colpita, la mossa finisce.
	if _mine_attack_on_move(u, old_q, old_r):
		state.group_mp[u.id] = 0
		_check_end_conditions()
		if state.phase == Domain.Phase.GAME_OVER:
			emit_signal("state_changed")
		else:
			_after_mover_done()
		return
	# Filo (F106): entrando/uscendo da un esagono con Filo la mossa si ferma qui.
	if _wire_on_move(u, old_q, old_r):
		remaining = 0
		state.group_mp[u.id] = 0

	# Fuoco di Opportunità del difensore (A33): può interrompere QUESTO mover.
	if _op_fire(u, _ai_faction()):
		state.group_mp[u.id] = 0
		_check_end_conditions()
		if state.phase == Domain.Phase.GAME_OVER:
			emit_signal("state_changed")
		else:
			_after_mover_done()  # passa al prossimo membro o conclude l'ordine
		return

	# Aggiorna gli esagoni raggiungibili coi PM RIMASTI del mover.
	var reach := HexGrid.reachable(u, state, remaining)
	state.highlighted_hexes.clear()
	for h in reach:
		state.highlighted_hexes.append("%d,%d" % [h.x, h.y])

	_check_end_conditions()  # un movimento può conquistare un obiettivo
	if state.phase == Domain.Phase.GAME_OVER:
		emit_signal("state_changed")
		return
	# PM del mover esauriti: passa al prossimo membro del gruppo o conclude.
	if reach.is_empty():
		_after_mover_done()
	else:
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
	# Soppressione: un ordine di Recupero la rimuove automaticamente (no tiro).
	var freed := Rules.clear_suppression(state, state.human_faction)
	if freed > 0:
		_log("Recupero: rimossa la soppressione da %d unità." % freed)
	if broken.is_empty() and freed == 0:
		_log("Recupero: nessuna unità da ripristinare.")
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
	state.ordered_group.clear()
	state.group_mp.clear()
	state.move_committed = false
	state.artillery_radio_id = ""
	state.artillery_spotter_id = ""
	state.artillery_smoke = false
	_clear_fire_assembly()


## Azzera lo stato di assemblaggio del gruppo di fuoco.
func _clear_fire_assembly() -> void:
	state.fire_target_q = -1
	state.fire_target_r = -1
	state.fire_eligible_ids.clear()
	state.fire_group_ids.clear()
	state.fire_modifiers.clear()
	state.fire_modifier_cards.clear()
	state.spray_active = false


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


# ─── Fortificazioni: effetti sul movimento (F103 Mine, F106 Filo) ─────────────

## Vero se l'unità è entrata in (o uscita da) un esagono con Filo: deve fermarsi.
func _wire_on_move(u: Unit, from_q: int, from_r: int) -> bool:
	var to_hd: GameState.HexData = state.hex_at(u.q, u.r)
	var from_hd: GameState.HexData = state.hex_at(from_q, from_r)
	return (to_hd != null and to_hd.fortification == Domain.Fort.WIRE) \
		or (from_hd != null and from_hd.fortification == Domain.Fort.WIRE)


## Attacco delle Mine (F103): se l'unità entra in (o esce da) un esagono minato,
## subisce un attacco da 6 FP (copertura 0). Restituisce true se rotta/eliminata.
func _mine_attack_on_move(u: Unit, from_q: int, from_r: int) -> bool:
	var to_hd: GameState.HexData = state.hex_at(u.q, u.r)
	var from_hd: GameState.HexData = state.hex_at(from_q, from_r)
	var mined := (to_hd != null and to_hd.fortification == Domain.Fort.MINES) \
		or (from_hd != null and from_hd.fortification == Domain.Fort.MINES)
	if not mined:
		return false
	var ad := Rules.roll_dice(_rng)
	var dd := Rules.roll_dice(_rng)
	var atk := 6 + ad.x + ad.y
	var defn := u.morale + dd.x + dd.y  # copertura sempre 0 contro le mine
	if atk > defn:
		if u.efficient:
			u.break_unit()
			_log("💥 Mine: %s colpita (att %d > dif %d) → rotta." % [u.unit_name, atk, defn])
		else:
			_log("💥 Mine: %s colpita (att %d > dif %d) → eliminata." % [u.unit_name, atk, defn])
			emit_signal("unit_eliminated", u.id)
			state.eliminate_unit(u.id)
		return true
	_log("Mine: %s passa (att %d ≤ dif %d)." % [u.unit_name, atk, defn])
	return false


# ─── Fuoco di Opportunità (A33) ───────────────────────────────────────────────

signal opfire_offered(mover_id: String)  ## Finestra di reazione aperta per l'umano
signal _opfire_decided()                 ## Interno: il giocatore ha scelto

var _opfire_choice: String = ""          ## Tiratore scelto ("" = non sparare)


## Risolve un Fuoco di Opportunità con uno SPECIFICO tiratore. Restituisce true se
## il mover è stato rotto o eliminato (movimento da interrompere).
func _resolve_op_fire(shooter: Unit, mover: Unit, defender: int) -> bool:
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


## Op Fire AUTOMATICO: il difensore reagisce col miglior tiratore idoneo. Usato
## quando il difensore è l'IA (durante il movimento del giocatore).
func _op_fire(mover: Unit, defender: int) -> bool:
	var shooter := OpFire.best_shooter(state, mover, defender)
	if shooter == null:
		return false
	return _resolve_op_fire(shooter, mover, defender)


## Op Fire come FINESTRA DI REAZIONE (A33). Se il difensore è l'umano, apre la
## scelta del tiratore (o «non sparare») e attende la decisione; se è l'IA, fuoco
## automatico. Coroutine: il chiamante deve usare `await`.
func _reactive_op_fire(mover: Unit, defender: int) -> bool:
	var shooters := OpFire.eligible_shooters(state, mover, defender)
	if shooters.is_empty():
		return false
	if defender != state.human_faction:
		return _op_fire(mover, defender)  # difensore IA: automatico

	# Difensore umano: apre la finestra di reazione e attende la scelta.
	state.opfire_mover_id = mover.id
	state.opfire_shooter_ids.clear()
	for s in shooters:
		state.opfire_shooter_ids.append(s.id)
	_opfire_choice = ""
	var prev_phase := state.phase
	_change_phase(Domain.Phase.REACTION_WINDOW)
	emit_signal("opfire_offered", mover.id)
	await _opfire_decided

	var broke := false
	var chosen := state.unit_by_id(_opfire_choice) if _opfire_choice != "" else null
	state.opfire_mover_id = ""
	state.opfire_shooter_ids.clear()
	if chosen != null:
		# Marca il mover «in movimento» così un pareggio in difesa lo rompe (A33).
		var prev_moving := state.moving_unit_id
		state.moving_unit_id = mover.id
		broke = _resolve_op_fire(chosen, mover, defender)
		state.moving_unit_id = prev_moving
	else:
		_log("Fuoco di Opportunità: non spari.")
	# Torna alla fase precedente (il turno IA prosegue) se la partita non è finita.
	if state.phase != Domain.Phase.GAME_OVER:
		_change_phase(prev_phase)
	return broke


## Il giocatore sceglie un tiratore per il Fuoco di Opportunità (dalla finestra).
func opfire_choose(shooter_id: String) -> void:
	if state == null or state.phase != Domain.Phase.REACTION_WINDOW:
		return
	if not state.opfire_shooter_ids.has(shooter_id):
		return
	_opfire_choice = shooter_id
	emit_signal("_opfire_decided")


## Il giocatore rinuncia al Fuoco di Opportunità.
func opfire_decline() -> void:
	if state == null or state.phase != Domain.Phase.REACTION_WINDOW:
		return
	_opfire_choice = ""
	emit_signal("_opfire_decided")


## Applica la conseguenza della carta del Fato (Tempo!/Cecchino/Inceppamento/
## Evento) e, se un Tempo! ha appena fatto avanzare la traccia dentro o oltre la
## casella della Morte Subitanea, esegue il tiro di Morte Subitanea (6.2.2).
func _apply_fate(card: Card, faction: int, context: Dictionary = {}) -> void:
	if card == null:
		return
	var prev_time := state.time_marker
	for line in Fate.apply_consequence(state, card, faction, context):
		_log("Fato — " + line)
	if state.time_marker > prev_time \
			and state.time_marker >= state.sudden_death_space \
			and state.phase != Domain.Phase.GAME_OVER:
		_check_sudden_death(faction)


func _end_player_turn() -> void:
	# Azzera attivazioni, PM residui e il conteggio Ordini del turno (5.1).
	state.order_count = 0
	state.moving_unit_id = ""
	state.moving_remaining_mp = 0
	state.moving_card_index = -1
	state.current_order = -1
	state.selected_unit_id = ""
	state.highlighted_hexes.clear()
	state.ordered_group.clear()
	state.group_mp.clear()
	state.move_committed = false
	_clear_fire_assembly()
	for u in state.units.values():
		u.activated = false

	# Il tempo NON avanza a ogni turno: in CC:E si muove solo con un "Tempo!"
	# pescato dal Mazzo del Fato (vedi Fate._consequence_time). La Morte Subitanea
	# è quindi risolta nel momento dell'avanzamento (vedi _apply_fate), non qui.
	if state.phase == Domain.Phase.GAME_OVER:
		return

	state.turn_number += 1
	_log("--- Fine turno %d ---" % (state.turn_number - 1))
	# Turno dell'IA: coroutine «fire-and-forget» — può sospendersi sulla finestra
	# di reazione (Op Fire) del giocatore e riprendere alla sua decisione. Il
	# ritorno al turno del giocatore avviene alla fine di _run_ai_turn.
	_run_ai_turn()


func _run_ai_turn() -> void:
	_change_phase(Domain.Phase.AI_TURN)
	var faction := _ai_faction()
	var plays := 0
	while plays < state.ai_max_orders:
		var play := AI.choose_play(state, faction)
		if play.is_empty():
			break
		await _ai_execute(faction, play)
		plays += 1
		_check_end_conditions()
		if state.phase == Domain.Phase.GAME_OVER:
			return
	if plays == 0:
		_log("IA: nessun ordine giocabile.")
	# Fine del turno IA → al giocatore (qui, non in _end_player_turn, perché questa
	# coroutine può essersi sospesa sulla finestra di reazione).
	if state.phase != Domain.Phase.GAME_OVER:
		_change_phase(Domain.Phase.PLAYER_TURN)
		_log("Turno %d — il tuo ordine" % state.turn_number)


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
			Rules.clear_suppression(state, faction)
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
			await _ai_move_order(faction)
		Domain.OrderType.ARTY:
			_ai_artillery(faction, play)
	_discard_for(faction, int(play["card_index"]))
	emit_signal("state_changed")


## L'IA richiede l'artiglieria (O18) sul bersaglio scelto da AI.best_artillery.
func _ai_artillery(faction: int, play: Dictionary) -> void:
	var spotter := state.unit_by_id(String(play.get("spotter_id", "")))
	var radio := state.unit_by_id(String(play.get("radio_id", "")))
	if spotter == null or radio == null:
		return
	_resolve_artillery_strike(spotter, radio, int(play["q"]), int(play["r"]), "IA — ")


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
			await _ai_move_toward(u, obj.q, obj.r, faction)
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
	# (coroutine: può attendere la finestra di reazione del giocatore)
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
		var oq := u.q
		var orr := u.r
		u.q = best.x
		u.r = best.y
		emit_signal("unit_moved", u.id, best.x, best.y)
		# Mine (F103) sull'IA che si muove: se colpita, il movimento si ferma.
		if _mine_attack_on_move(u, oq, orr):
			_check_end_conditions()
			return
		# Il difensore reagisce col Fuoco di Opportunità (finestra interattiva se il
		# difensore è l'umano). Marca l'unità «in movimento» per il pareggio (A33).
		var prev_moving := state.moving_unit_id
		state.moving_unit_id = u.id
		await _reactive_op_fire(u, _opponent(u.faction))
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


## Tiro di Morte Subitanea (6.2.2): il giocatore che ha innescato l'avanzamento
## del Tempo pesca una carta del Fato (= 2d6, dopo il rimescolo già fatto da
## TEMPO!). Se il risultato è MINORE del numero della casella ora occupata dal
## segnalino Tempo, la partita finisce subito e il vincitore è deciso ai VP
## (6.3.2); altrimenti si prosegue. La carta tirata serve solo per i dadi: la sua
## conseguenza non si applica, per evitare inneschi a catena.
func _check_sudden_death(triggering_faction: int) -> void:
	var dice := _dice_of(_draw_fate(triggering_faction))
	var total := dice.x + dice.y
	var space := state.time_marker
	if total < space:
		_log("⏰ MORTE SUBITANEA: tiro %d < %d (casella Tempo) — fine partita." % [total, space])
		_end_game(_count_objectives())
	else:
		_log("Morte Subitanea evitata: tiro %d ≥ %d (casella Tempo)." % [total, space])


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
	# Bilancia = VP obiettivi + VP non-obiettivo (iniziali, Tempo!, eliminazioni 7.1).
	state.vp_tracker = ger_vp - rus_vp + state.bonus_vp
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
