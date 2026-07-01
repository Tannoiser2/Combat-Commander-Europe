## Controllore principale di Combat Commander: Europe.
## Autoload singleton — emette segnali verso la scena, non la tocca direttamente.
extends Node

# ─── Segnali ─────────────────────────────────────────────────────────────────

signal state_changed()               ## Aggiornamento generico — ridisegna tutto
signal stack_offered(unit_ids: Array)  ## Esagono con 2+ unità amiche: scegli quale (selettore di stack)
signal log_added(line: String, detail: String, kind: String)  ## Riga di log (+formula collassabile, +categoria)
signal fire_resolved(result: Object) ## Combat.FireResult
signal phase_changed(phase: int)     ## Nuova fase
signal unit_moved(unit_id: String, q: int, r: int)
signal unit_eliminated(unit_id: String)
signal game_over(winner: int)        ## Domain.Faction o -1 (patta)
signal grenade_thrown(fq: int, fr: int, tq: int, tr: int)  ## Bombe a mano: lancio da→a (per l'animazione)
signal artillery_impact(q: int, r: int)  ## Bombardamento caduto: esplosione sull'esagono centro


# ─── Stato ────────────────────────────────────────────────────────────────────

var state: GameState = null
var _rng: RandomNumberGenerator = null

# ─── Impostazioni persistenti (user://settings.cfg) ──────────────────────────
const SETTINGS_PATH := "user://settings.cfg"
## Modalità tutorial: quando attiva, la GUI apre una finestra di aiuto a ogni
## ordine/azione (regola + cosa fare). Si attiva dalla schermata iniziale.
var tutorial_enabled: bool = false


# ─── Init ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.randomize()
	_load_settings()


## Carica le impostazioni persistenti (modalità tutorial, ecc.).
func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		tutorial_enabled = bool(cfg.get_value("ui", "tutorial", false))


## Attiva/disattiva la modalità tutorial e la salva su disco.
func set_tutorial(on: bool) -> void:
	tutorial_enabled = on
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # ignora l'errore se il file non esiste ancora
	cfg.set_value("ui", "tutorial", on)
	cfg.save(SETTINGS_PATH)


## Avvia una nuova partita. `scenario_num` 1..24 (default 1).
func start_new_game(human_faction: int = Domain.Faction.GERMAN, scenario_num: int = 1,
		difficulty: int = Domain.BotDifficulty.GREEN) -> void:
	state = GameState.new()
	state.human_faction = human_faction
	state.bot_difficulty = difficulty

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

	# Portage (11.2): ogni arma è affidata a un uomo co-locato della sua fazione.
	_assign_initial_carriers(state)

	# Difficoltà del bot (FlipBot): bonus a ordini/mano/resa dell'IA. Prima di
	# distribuire le mani, così l'eventuale +carte vale già da subito.
	FlipBot.apply_difficulty(state)

	# Costruisce e mescola i mazzi reali delle due nazioni (slot Asse/Alleati).
	state.german_deck = Cards.build_deck(state.axis_nation)
	state.russian_deck = Cards.build_deck(state.allied_nation)
	Cards.shuffle(state.german_deck)
	Cards.shuffle(state.russian_deck)
	Cards.deal_initial(state)
	# SSR: carte garantite in mano a inizio partita (es. «inizia con G-65»).
	_apply_opening_cards(state)

	_log("SCENARIO %d: %s" % [state.scenario_number, state.scenario_name], "", "turn")
	_log("Turno %d — iniziativa: %s" % [
		state.turn_number,
		Domain.FACTION_NAMES.get(state.initiative_holder, "?")
	], "", "turn")
	# Schieramento manuale SOLO per gli scenari con una zona di schieramento vera
	# (dalle schede, via il loader generico). Lo scenario 1 — e ogni scenario con
	# piazzamento storico fisso curato a mano — NON ha una zona: parte direttamente
	# col suo piazzamento esatto, senza fase di setup (regola "ignora il setup
	# simultaneo" della scheda dello scenario 1).
	if not state.setup_zone.is_empty():
		_log("Schieramento: disponi le tue unità nella zona, o premi «Auto».")
		_change_phase(Domain.Phase.PLAYER_SETUP)
	else:
		_change_phase(Domain.Phase.PLAYER_TURN)


## «Schieramento pronto»: chiude la fase di setup e inizia il gioco vero.
func finish_setup() -> void:
	if state == null or state.phase != Domain.Phase.PLAYER_SETUP:
		return
	deselect()
	state.setup_zone = []
	_log("Schieramento confermato. Inizia la partita.")
	_change_phase(Domain.Phase.PLAYER_TURN)


## «Auto»: ripiazza le proprie unità con l'Auto intelligente (gruppi comandati
## da leader, distanziati, in copertura e su altura). Resta in fase di setup.
func auto_setup() -> void:
	if state == null or state.phase != Domain.Phase.PLAYER_SETUP:
		return
	ScenarioLoader.auto_deploy_human(state)
	deselect()
	_log("Schieramento Auto intelligente applicato.")
	emit_signal("state_changed")


## SSR: mette in mano le carte garantite a inizio partita (es. «G-65»). Il
## codice «X-NN» indica il mazzo/nazione (lettera) e il numero NN della carta;
## la si pesca dal mazzo del lato e la si aggiunge alla mano (se presente).
func _apply_opening_cards(s: GameState) -> void:
	_give_opening(s, ScenarioEffects.opening_cards(s.scenario_number, "axis"),
		s.german_deck, s.german_hand)
	_give_opening(s, ScenarioEffects.opening_cards(s.scenario_number, "allies"),
		s.russian_deck, s.russian_hand)


func _give_opening(s: GameState, codes: Array, deck: Array, hand: Array) -> void:
	for code in codes:
		var parts := String(code).split("-")
		if parts.size() < 2:
			continue
		var num := int(parts[parts.size() - 1])
		var found := false
		for i in deck.size():
			if int(deck[i].number) == num:
				hand.append(deck[i])
				deck.remove_at(i)
				found = true
				_log("Carta iniziale garantita (%s) in mano." % code)
				break
		if not found:
			_log("Carta iniziale %s non trovata nel mazzo (saltata)." % code)


## Assegna ogni arma a un uomo della stessa fazione (11.2): a inizio partita le
## armi sono sempre «possedute» da un'unità, mai a terra. Si cerca prima un
## portatore co-locato; se l'arma è stata schierata in un esagono senza uomini
## (capita coi dati di setup grezzi), la si sposta sull'uomo libero più vicino e
## gli viene affidata — così nessun'arma resta «a terra» (niente anelli gialli al
## via). Ogni uomo porta al più un'arma; si preferisce una squadra/team a un
## leader, così il leader resta libero.
func _assign_initial_carriers(s: GameState) -> void:
	for w in s.units.values():
		if not w.is_weapon() or w.carrier_id != "":
			continue
		# 1) portatore già nello stesso esagono
		var best := _best_carrier_at(s, w, w.q, w.r)
		# 2) altrimenti, sposta l'arma sull'uomo libero più vicino
		if best == null:
			best = _nearest_free_carrier(s, w)
			if best != null:
				w.q = best.q
				w.r = best.r
		if best != null:
			w.carrier_id = best.id


## Miglior uomo libero (senza arma) della fazione di `w` nell'esagono (q,r):
## preferisce una squadra/team a un leader. null se nessuno è idoneo.
func _best_carrier_at(s: GameState, w: Unit, q: int, r: int) -> Unit:
	var best: Unit = null
	for m in s.men_at(q, r):
		if m.faction != w.faction or s.weapon_carried_by(m.id) != null:
			continue
		if best == null or (best.is_leader() and not m.is_leader()):
			best = m
	return best


## Uomo libero della stessa fazione più vicino all'arma (per spostarvela sopra).
func _nearest_free_carrier(s: GameState, w: Unit) -> Unit:
	var best: Unit = null
	var best_d := 1 << 30
	for m in s.units.values():
		if not m.is_man() or m.faction != w.faction:
			continue
		if s.weapon_carried_by(m.id) != null:
			continue
		var d := HexGrid.distance(w.q, w.r, m.q, m.r)
		# A parità di distanza preferisci una squadra/team a un leader.
		if d < best_d or (d == best_d and best != null and best.is_leader() and not m.is_leader()):
			best_d = d
			best = m
	return best


## Salva la partita corrente sul file di salvataggio. true se riuscito.
func save_game(path: String = SaveGame.SAVE_PATH) -> bool:
	if state == null:
		return false
	var ok := SaveGame.save_state(state, path)
	if ok:
		_log("Partita salvata.")
	return ok


## Ripristina la partita dal file di salvataggio. true se riuscito.
func load_game(path: String = SaveGame.SAVE_PATH) -> bool:
	var s := SaveGame.load_state(path)
	if s == null:
		return false
	state = s
	_log("Partita caricata.")
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
		state.command_preview_ids.clear()
		emit_signal("state_changed")
		return

	# ─── Mossa: gruppo di comando ────────────────────────────────────────────
	# Alla prima selezione si forma il gruppo attorno all'unità ordinata (un
	# leader trascina le unità nel suo raggio di Comando). Poi si può passare da
	# un membro all'altro, ma non aggiungere unità a un ordine già avviato.
	if state.phase == Domain.Phase.PLAYER_MOVING and state.current_order == Domain.OrderType.MOVE:
		if state.ordered_group.is_empty():
			if u.faction != state.human_faction or not Rules.can_be_ordered(u):
				return
			_form_move_group(u)
		elif not state.ordered_group.has(unit_id):
			return
		state.selected_unit_id = unit_id
		state.moving_unit_id = unit_id
		state.command_preview_ids.clear()   # durante l'ordine vale ordered_group
		_highlight_reachable(u)
		emit_signal("state_changed")
		return

	# ─── Fuoco: assemblaggio gruppo-prima-del-bersaglio ──────────────────────
	# Selezionare un leader illumina i tiratori che comanda; selezionare un
	# tiratore assembla subito il gruppo e illumina i bersagli (con linee).
	if state.phase == Domain.Phase.PLAYER_MOVING and state.current_order == Domain.OrderType.FIRE:
		_select_fire_base(u)
		return

	# ─── Avanzata: gruppo di comando (O7, come la Mossa) ─────────────────────
	# Anche l'Avanzata può essere data «tramite» un leader: attiva il leader e le
	# unità idonee entro il suo raggio di Comando, ciascuna avanza di un esagono.
	if state.phase == Domain.Phase.PLAYER_MOVING and state.current_order == Domain.OrderType.ADVANCE:
		if state.ordered_group.is_empty():
			if u.faction != state.human_faction or not Rules.can_be_ordered(u):
				return
			_form_advance_group(u)
		elif not state.ordered_group.has(unit_id):
			return
		state.selected_unit_id = unit_id
		state.command_preview_ids.clear()
		_highlight_advance(u)
		emit_signal("state_changed")
		return

	# ─── Altri ordini ────────────────────────────────────────────────────────
	state.selected_unit_id = unit_id
	state.highlighted_hexes.clear()
	# Anteprima del gruppo di comando: selezionando un leader (o un'unità comandata)
	# fuori da un ordine, si illuminano le unità che potrebbe attivare nel turno.
	state.command_preview_ids.clear()
	if state.phase == Domain.Phase.PLAYER_TURN:
		var grp := _command_group_ids(u)
		if grp.size() > 1:
			state.command_preview_ids = grp
	emit_signal("state_changed")


## Forma il gruppo di comando per un ordine di Mossa (3.3.1.2). L'ordine è dato
## "tramite" un leader: chiunque sia l'unità cliccata, se è comandata da un leader
## efficiente e disponibile, lo stesso ordine attiva il leader e TUTTE le unità
## idonee (uomini efficienti e muovibili, non già attivate) entro il suo raggio di
## Comando. Un'unità non comandata si muove da sola (un ordine per sé).
func _form_move_group(u: Unit) -> void:
	state.ordered_group.clear()
	state.group_mp.clear()
	state.move_committed = false
	var ids := _command_group_ids(u)
	for id in ids:
		state.ordered_group.append(id)
		state.group_mp[id] = Rules.move_allowance(state, state.unit_by_id(id))
	var leader := Rules.commanding_leader(state, u, true)
	if ids.size() > 1 and leader != null:
		_log("Comando: %s attiva %d unità entro raggio %d." % [leader.unit_name, ids.size(), leader.command])


## Forma il gruppo di comando per un'Avanzata (O7): come la Mossa, ma ogni membro
## ha UNA avanzata (un esagono) — qui `group_mp[id]` vale 1 finché non ha avanzato,
## poi 0. Un'unità non comandata avanza da sola.
func _form_advance_group(u: Unit) -> void:
	state.ordered_group.clear()
	state.group_mp.clear()
	state.move_committed = false
	var ids := _command_group_ids(u)
	for id in ids:
		state.ordered_group.append(id)
		state.group_mp[id] = 1  # una avanzata a testa
	var leader := Rules.commanding_leader(state, u, true)
	if ids.size() > 1 and leader != null:
		_log("Comando: %s fa avanzare %d unità entro raggio %d." % [leader.unit_name, ids.size(), leader.command])


## Evidenzia gli esagoni adiacenti dove l'unità può avanzare (se non l'ha già
## fatto): solo avanzate LEGALI, così non si resta bloccati cliccando un esagono
## dove non si può entrare (vedi _can_advance_into).
func _highlight_advance(u: Unit) -> void:
	state.highlighted_hexes.clear()
	if int(state.group_mp.get(u.id, 0)) <= 0:
		return  # ha già avanzato in questo ordine
	for h in HexGrid.neighbors(u.q, u.r):
		if h.x < 0 or h.x >= state.map_cols or h.y < 0 or h.y >= state.map_rows:
			continue
		if _can_advance_into(u, h.x, h.y):
			state.highlighted_hexes.append("%d,%d" % [h.x, h.y])


## L'unità può avanzare in (q,r)? Sì se vi è un nemico (si entra per il corpo a
## corpo: l'impilamento non vincola, O16) oppure se entrando in un esagono
## amico/vuoto non si supera il limite di impilamento (8.2). Evita di proporre (ed
## eseguire) avanzate impossibili, che bloccherebbero l'ordine.
func _can_advance_into(u: Unit, q: int, r: int) -> bool:
	for m in state.men_at(q, r):
		if m.faction != u.faction:
			return true  # nemico presente → corpo a corpo
	if u.is_man() and state.soldier_icons_at(q, r) + u.soldier_icons() > 7:
		return false
	return true


## Id delle unità che un ordine dato "tramite" `u` attiverebbe: il leader che la
## comanda e tutte le unità idonee (uomini efficienti e muovibili, non già
## attivate) entro il suo raggio di Comando; l'unità stessa è sempre inclusa.
func _command_group_ids(u: Unit) -> Array[String]:
	var ids: Array[String] = []
	var leader := Rules.commanding_leader(state, u, true)
	if leader != null:
		for v in state.units_of(state.human_faction):
			if v.is_man() and v.move > 0 and Rules.can_be_ordered(v) \
					and HexGrid.distance(leader.q, leader.r, v.q, v.r) <= leader.command:
				ids.append(v.id)
	if not ids.has(u.id):
		ids.append(u.id)
	return ids


## Evidenzia tutte le unità del giocatore che possono ricevere un ordine adesso
## (uomini idonei, non già attivati): dopo aver giocato Mossa/Avanzata mostra a
## colpo d'occhio chi si può cliccare (flusso carta-first).
func _compute_orderable_preview() -> void:
	state.command_preview_ids = actable_unit_ids()


## Id delle unità del giocatore che possono ancora ricevere un ordine ADESSO
## (uomini idonei e non già attivati). Serve a evidenziare "chi può ancora agire"
## a inizio turno e a capire quando il turno è di fatto finito (lista vuota →
## nessuna unità può più agire, conviene premere «Fine Turno»).
func actable_unit_ids() -> Array[String]:
	var ids: Array[String] = []
	if state == null:
		return ids
	for v in state.units_of(state.human_faction):
		if v.is_man() and Rules.can_be_ordered(v):
			ids.append(v.id)
	return ids


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


## Riempie `fire_ready_ids` con le unità del giocatore che possono sparare adesso
## (ordinabili, con potenza di fuoco e almeno un bersaglio valido). Serve a
## evidenziare sulla mappa "chi può sparare" appena si dà un ordine di Fuoco. Le
## armi sparano col loro portatore, quindi qui si considerano gli uomini (e
## l'ordnance, che spara da sola).
func _compute_fire_ready() -> void:
	state.fire_ready_ids.clear()
	for u in state.units_of(state.human_faction):
		if not Rules.can_be_ordered(u):
			continue
		if not (u.is_man() or u.ordnance):
			continue
		if Rules.range_with_command(state, u) <= 0 and not u.is_man():
			continue
		if not _fire_targets(u).is_empty():
			state.fire_ready_ids.append(u.id)
	# Leader-direttori: leader che, pur non sparando da soli, hanno ≥1 tiratore
	# pronto nel raggio di Comando → si possono cliccare per avviare un gruppo.
	state.fire_leader_ids.clear()
	for u in state.units_of(state.human_faction):
		if not u.is_leader() or state.fire_ready_ids.has(u.id) \
				or not Rules.can_be_ordered(u):
			continue
		if not _fire_command_preview(u).is_empty():
			state.fire_leader_ids.append(u.id)


## C'è almeno un'unità del giocatore che può sparare ora (≥1 bersaglio valido)?
func _any_fire_ready() -> bool:
	for u in state.units_of(state.human_faction):
		if not Rules.can_be_ordered(u):
			continue
		if not (u.is_man() or u.ordnance):
			continue
		if not _fire_targets(u).is_empty():
			return true
	return false


## Selezione del pezzo base del Fuoco (flusso gruppo-prima-del-bersaglio).
##  • un LEADER che non spara (nessun bersaglio proprio) illumina i tiratori che
##    comanda, così il giocatore ne sceglie uno (passo «seleziona leader»);
##  • un TIRATORE pronto assembla subito il gruppo potenziale (co-locati +
##    comandati), lo rende modificabile e illumina i bersagli con le linee.
func _select_fire_base(u: Unit) -> void:
	if u == null or u.faction != state.human_faction:
		return
	# Leader-direttore senza fuoco proprio: mostra i tiratori comandati.
	if u.is_leader() and _fire_targets(u).is_empty() and not state.fire_ready_ids.has(u.id):
		state.selected_unit_id = u.id
		state.fire_eligible_ids.clear()
		state.fire_group_ids.clear()
		state.fire_target_q = -1
		state.fire_target_r = -1
		state.highlighted_hexes.clear()
		state.command_preview_ids = _fire_command_preview(u)
		emit_signal("state_changed")
		return
	# Non è un tiratore valido adesso: ignora il click.
	if not state.fire_ready_ids.has(u.id):
		return
	state.selected_unit_id = u.id
	state.command_preview_ids.clear()
	state.fire_target_q = -1
	state.fire_target_r = -1
	state.fire_eligible_ids.clear()
	state.fire_group_ids.clear()
	for g in Combat.potential_fire_group(u, state):
		state.fire_eligible_ids.append(g.id)
		state.fire_group_ids.append(g.id)
	_recompute_fire_targets()
	emit_signal("state_changed")


## Tiratori pronti (≥1 bersaglio) entro il raggio di Comando di un leader: gli id
## che si illuminano quando si seleziona quel leader nell'ordine di Fuoco.
func _fire_command_preview(leader: Unit) -> Array[String]:
	var ids: Array[String] = []
	for v in state.units_of(state.human_faction):
		if v.id == leader.id:
			continue
		if not state.fire_ready_ids.has(v.id):
			continue
		if HexGrid.distance(leader.q, leader.r, v.q, v.r) <= leader.command:
			ids.append(v.id)
	return ids


## Ricalcola i bersagli candidati = unione degli esagoni che i pezzi attualmente
## nel gruppo di fuoco possono colpire (gittata + LOS + nemico). Usato a ogni
## modifica del gruppo finché non si sceglie un bersaglio.
func _recompute_fire_targets() -> void:
	var seen := {}
	state.highlighted_hexes.clear()
	for id in state.fire_group_ids:
		var g := state.unit_by_id(id)
		if g == null:
			continue
		for h in _fire_targets(g):
			var k := "%d,%d" % [h.x, h.y]
			if not seen.has(k):
				seen[k] = true
				state.highlighted_hexes.append(k)


## Annulla l'assemblaggio del fuoco e torna alla scelta del tiratore: i pezzi
## pronti restano accesi, niente gruppo/bersaglio selezionato.
func _cancel_fire_assembly() -> void:
	state.selected_unit_id = ""
	state.command_preview_ids.clear()
	state.fire_eligible_ids.clear()
	state.fire_group_ids.clear()
	state.fire_target_q = -1
	state.fire_target_r = -1
	state.spray_active = false
	state.highlighted_hexes.clear()
	_compute_fire_ready()
	emit_signal("state_changed")


## Un ordine di questo tipo è davvero eseguibile ora dal giocatore? Usato per
## illuminare i badge solo quando hanno effetto (3.x/5.1). Non controlla il limite
## di Ordini (lo fa il chiamante): qui conta solo se esiste un bersaglio/unità.
func order_feasible(order: int) -> bool:
	if state == null:
		return false
	var human := state.human_faction
	match order:
		Domain.OrderType.PASS:
			return true
		Domain.OrderType.ARTY:
			return has_artillery_available()
		Domain.OrderType.RECOVER:
			# Recupero utile se ci sono unità rotte o soppresse da ripristinare.
			if not state.broken_men_of(human).is_empty():
				return true
			for u in state.units_of(human):
				if u.suppressed:
					return true
			return false
		Domain.OrderType.ROUT:
			return not state.broken_men_of(human).is_empty()
		Domain.OrderType.FIRE:
			return _any_fire_ready()
		Domain.OrderType.MOVE:
			for u in state.units_of(human):
				if not (Rules.can_be_ordered(u) and u.is_man()):
					continue
				var mp := Rules.move_allowance(state, u)
				if mp > 0 and not HexGrid.reachable(u, state, mp).is_empty():
					return true
			return false
		Domain.OrderType.ADVANCE:
			for u in state.units_of(human):
				if not (Rules.can_be_ordered(u) and u.is_man()):
					continue
				for h in HexGrid.neighbors(u.q, u.r):
					if h.x >= 0 and h.x < state.map_cols and h.y >= 0 and h.y < state.map_rows:
						return true
			return false
		_:
			return true


## Un'AZIONE autonoma ha davvero un effetto adesso? Serve a illuminare i badge
## delle azioni solo quando producono qualcosa (altrimenti la carta si
## scarterebbe a vuoto). Le azioni non elencate sono considerate sempre fattibili.
func action_feasible(name: String) -> bool:
	if state == null:
		return false
	var fac := state.human_faction
	match name:
		"FERITE LEGGERE":  # serve un'unità rotta da curare
			for u in state.units_of(fac):
				if u.is_man() and not u.efficient:
					return true
			return false
		"MIMETIZZAZIONE":  # serve un'unità efficiente non già mimetizzata
			for u in state.units_of(fac):
				if u.is_man() and u.efficient and not u.concealed:
					return true
			return false
		"TRINCERARSI", "FILO SPINATO NASCOSTO", "MINE NASCOSTE", \
		"CASAMATTA NASCOSTA", "TRINCERAMENTI NASCOSTI":  # serve un esagono idoneo
			for u in state.units_of(fac):
				if u.is_man() and Actions._can_fortify(state.hex_at(u.q, u.r)):
					return true
			return false
		_:
			return true  # GRANATE FUMOGENE e altre: sempre giocabili


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
	# Un nuovo ordine rimuove gli indicatori dell'azione precedente (impatto
	# artiglieria, "chi ha sparato a chi", ultima granata).
	state.last_impact_hexes.clear()
	state.last_fire_from = Vector2i(-1, -1)
	state.last_fire_to = Vector2i(-1, -1)
	state.last_fire_text = ""
	state.last_grenade = Vector2i(-1, -1)
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

	_log("Carta #%d giocata: [b]%s[/b]" % [card.number, Domain.ORDER_LABELS.get(card.order, card.order_label)], "", "order")

	match card.order:
		Domain.OrderType.MOVE, Domain.OrderType.FIRE, Domain.OrderType.ADVANCE:
			# Ordini con bersaglio: si entra in fase di selezione sulla mappa.
			state.order_count += 1
			state.current_order = card.order
			state.assault_fired = false  # Fuoco d'Assalto disponibile una volta per ordine
			state.selected_card_index = hand_index
			state.highlighted_hexes.clear()
			state.command_preview_ids.clear()
			state.ordered_group.clear()   # nuovo ordine: niente gruppo residuo
			state.group_mp.clear()
			# Col Fuoco: evidenzia subito le unità che possono sparare (≥1 bersaglio).
			if card.order == Domain.OrderType.FIRE:
				_compute_fire_ready()
			_change_phase(Domain.Phase.PLAYER_MOVING)
			# Carta-first "puro": dopo aver giocato l'ordine si sceglie SEMPRE l'unità
			# (o il gruppo) sulla mappa; non si eredita una selezione fatta prima della
			# carta. Per Mossa/Avanzata si evidenziano le unità ordinabili (chi puoi
			# cliccare); per il Fuoco lo fa già fire_ready.
			state.selected_unit_id = ""
			if card.order == Domain.OrderType.MOVE or card.order == Domain.OrderType.ADVANCE:
				_compute_orderable_preview()
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
	emit_signal("artillery_impact", sr.x, sr.y)  # esplosione (animazione)
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
	# Un bombardamento può annientare/far arrendere una fazione: chiudi la partita
	# anche quando l'ordine arriva dall'IA (il percorso umano ricontrolla a parte).
	_check_end_conditions()


## FP della bombardamento in base al calibro della Radio.
func _radio_fp(radio: Unit) -> int:
	return Rules.radio_fp_for(radio.unit_name)


## Gioca la CARTA come AZIONE (banda inferiore) invece che come ordine.
func play_action(hand_index: int) -> void:
	if state == null or state.phase != Domain.Phase.PLAYER_TURN:
		return
	var hand := state.hand_of(state.human_faction)
	if hand_index < 0 or hand_index >= hand.size():
		return
	var card: Card = hand[hand_index]
	_log("Azione giocata: %s" % card.action_name)
	for line in Actions.play(state, card, state.human_faction):
		_log(line)
	_discard_card(hand_index)
	_check_end_conditions()
	emit_signal("state_changed")


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
	# Selettore di stack: se l'esagono ha 2+ unità amiche selezionabili, offre la
	# scelta esplicita (così si può prendere un leader "sotto" lo stack).
	_offer_stack(units_here)
	if s.phase == Domain.Phase.PLAYER_MOVING:
		# Fuoco: flusso dedicato gruppo-prima-del-bersaglio.
		if s.current_order == Domain.OrderType.FIRE:
			_click_fire(q, r, key, units_here)
			return
		var sel := s.unit_by_id(s.selected_unit_id) if s.selected_unit_id != "" else null
		# 1) Click su una DESTINAZIONE valida (esagono evidenziato) = esegui l'ordine,
		#    anche se l'esagono è occupato da un compagno (impilamento). Ha la priorità
		#    sulla selezione: durante un ordine cliccare non cambia l'unità attiva.
		if s.selected_unit_id != "" and s.highlighted_hexes.has(key):
			match s.current_order:
				Domain.OrderType.MOVE:
					click_hex_move(q, r)
				Domain.OrderType.ADVANCE:
					click_hex_advance(q, r)
				Domain.OrderType.ARTY:
					click_hex_artillery(q, r)
			return
		# 2) Click sull'esagono dell'unità attiva = concludi il SUO movimento. In un
		#    gruppo, se restano membri da muovere/avanzare passa al prossimo (NON
		#    chiude l'ordine); da sola (o ultimo membro) conclude/annulla l'ordine.
		if sel != null and q == sel.q and r == sel.r:
			if s.current_order == Domain.OrderType.MOVE and s.ordered_group.size() > 1:
				_conclude_mover(s.selected_unit_id)
			elif s.current_order == Domain.OrderType.ADVANCE and s.ordered_group.size() > 1:
				_conclude_advancer(s.selected_unit_id)
			else:
				conclude_order()
			return
		# 3) Click su un ALTRO membro del gruppo (esagono NON destinazione) = cambia
		#    l'unità attiva (per muovere/avanzare il prossimo membro).
		if s.current_order == Domain.OrderType.MOVE or s.current_order == Domain.OrderType.ADVANCE:
			for gid in s.ordered_group:
				if gid == s.selected_unit_id:
					continue
				var gv := s.unit_by_id(gid)
				if gv != null and gv.q == q and gv.r == r:
					select_unit(gid)
					return
		# 4) Altrimenti, ciclo di selezione (durante Mossa/Avanzata select_unit accetta
		#    solo i membri del gruppo, quindi non si selezionano unità estranee).
		_cycle_select(units_here, false)
	elif s.phase == Domain.Phase.REACTION_WINDOW:
		# Finestra di Mimetizzazione (difensore umano): clicca l'unità o rinuncia.
		if not s.conceal_offer_ids.is_empty():
			for cid in s.conceal_offer_ids:
				var cv := s.unit_by_id(cid)
				if cv != null and cv.q == q and cv.r == r:
					conceal_accept(cid)
					return
			conceal_decline()
			return
		# Finestra di Fuoco di Opportunità: clicca un tiratore o rinuncia.
		for sid in s.opfire_shooter_ids:
			var sv := s.unit_by_id(sid)
			if sv != null and sv.q == q and sv.r == r:
				opfire_choose(sid)
				return
		opfire_decline()
	elif s.phase == Domain.Phase.PLAYER_TURN:
		_cycle_select(units_here, true)
	elif s.phase == Domain.Phase.PLAYER_SETUP:
		_setup_click(q, r, units_here)


## Offre il selettore di stack: se l'esagono cliccato contiene 2+ unità amiche
## selezionabili (uomini, non armi), emette i loro id — coi LEADER per primi, così
## la GUI può mostrarli e far scegliere un leader "sotto" lo stack. Vuoto = nascondi.
func _offer_stack(units_here: Array) -> void:
	# Disponibile nella scelta dell'unità (turno/schieramento) e nel Fuoco (per il
	# tiratore base); NON durante Mossa/Avanzata, dove cliccare deve muovere, non
	# selezionare un'altra unità (così si può impilare su un esagono occupato).
	var ok := state.phase == Domain.Phase.PLAYER_TURN \
		or state.phase == Domain.Phase.PLAYER_SETUP \
		or (state.phase == Domain.Phase.PLAYER_MOVING and state.current_order == Domain.OrderType.FIRE)
	if not ok:
		emit_signal("stack_offered", [])
		return
	var ids: Array = []
	for u in units_here:
		if u.faction == state.human_faction and not u.is_weapon():
			ids.append(u.id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ua := state.unit_by_id(a)
		var ub := state.unit_by_id(b)
		return ua != null and ua.is_leader() and (ub == null or not ub.is_leader()))
	emit_signal("stack_offered", ids if ids.size() >= 2 else [])


## Schieramento manuale: con un'unità propria selezionata, un clic su un altro
## esagono della zona la sposta lì (rispettando zona e impilamento ≤7 figure);
## le armi seguono il portatore. Un clic sulla casella dell'unità selezionata
## (o su una pedina propria senza selezione) scorre l'impilamento o deseleziona.
func _setup_click(q: int, r: int, units_here: Array) -> void:
	var s := state
	var sel := s.unit_by_id(s.selected_unit_id) if s.selected_unit_id != "" else null
	if sel != null and not (q == sel.q and r == sel.r):
		if not _setup_in_zone(q, r):
			_log("Fuori dalla zona di schieramento.")
			return
		# L'unità lascia la sua casella: conta solo le figure già presenti qui.
		if s.soldier_icons_at(q, r) + sel.soldier_icons() > 7:
			_log("Impilamento pieno in %s (max 7 figure)." % Domain.qr_to_label(q, r))
			return
		s.set_unit_pos(sel, q, r)
		_log("%s schierata in %s." % [sel.unit_name, Domain.qr_to_label(q, r)])
		emit_signal("state_changed")
		return
	_cycle_setup_select(units_here)


## Vero se (q,r) appartiene alla zona di schieramento del giocatore.
func _setup_in_zone(q: int, r: int) -> bool:
	for h in state.setup_zone:
		if h.x == q and h.y == r:
			return true
	return false


## Selezione ciclica in fase di setup: scorre le pedine proprie nell'esagono
## (escluse le armi, che seguono il portatore); dopo l'ultima, deseleziona.
func _cycle_setup_select(units_here: Array) -> void:
	var sel_list: Array = units_here.filter(
		func(u: Unit) -> bool: return u.faction == state.human_faction and not u.is_weapon())
	if sel_list.is_empty():
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
	else:
		deselect()


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


## Giocatore clicca su un esagono durante la fase di movimento. Il bersaglio può
## essere lontano: si percorre il tragitto a costo minimo UN ESAGONO ALLA VOLTA,
## così il costo del terreno si accumula davvero (niente "salti" a prezzo di un
## passo) e Mine/Filo/Fuoco di Opportunità scattano a ogni esagono attraversato.
func click_hex_move(tq: int, tr: int) -> void:
	if state == null or state.phase != Domain.Phase.PLAYER_MOVING:
		return
	var uid := state.selected_unit_id
	if uid == "":
		return
	var u := state.unit_by_id(uid)
	if u == null or u.faction != state.human_faction:
		return
	var budget := int(state.group_mp.get(uid, u.move))
	var path := HexGrid.path_to(u, state, tq, tr, budget)
	if path.is_empty():
		_log("(%d,%d) irraggiungibile coi PM rimasti." % [tq, tr])
		return
	# Movimento PASSO-PASSO: un clic = UN solo esagono (il primo passo verso il
	# bersaglio). Clic su un adiacente = ci entra; clic su uno lontano = avvicina
	# di un esagono. Così Mine, Filo e Fuoco di Opportunità scattano a OGNI
	# esagono e il giocatore decide passo per passo (niente "salti" multipli).
	_execute_move_step(u, path[0].x, path[0].y)


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
	# A26: il Fuoco d'Assalto richiede una FP «in scatola» (fp_boxed): solo le unità
	# con FP riquadrata possono sparare mentre sono attivate a muovere.
	if u == null or not u.is_man() or u.is_leader() or not u.efficient \
			or u.fp <= 0 or u.ordnance or not u.fp_boxed:
		_log("Fuoco d'Assalto: serve una squadra/team in movimento con FP «in scatola».")
		return
	var target := _best_assault_target(u)
	if target.x < 0:
		_log("Fuoco d'Assalto: nessun bersaglio in gittata/LOS.")
		return
	var group: Array[Unit] = [u]
	var atk_fate := _draw_fate(state.human_faction)
	var def_fate := _draw_fate(_ai_faction())
	var atk_dice := _dice_of(atk_fate)
	_maybe_react_concealment(target.x, target.y)
	var result := Combat.resolve_fire(
		u, target.x, target.y, state, atk_dice, _dice_of(def_fate), group, 0)
	_log("Fuoco d'Assalto — " + result.log_line, result.detail, "fire")
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


## Gestione del click durante il Fuoco (flusso gruppo-prima-del-bersaglio).
##  • con un gruppo assemblato: click su un membro idoneo = includi/escludi;
##    click su un bersaglio candidato = fuoco; click sul pezzo base = ANNULLA
##    l'ordine (torna alla scelta della carta); click su un altro tiratore = nuovo base;
##  • con un leader selezionato (anteprima): click su un tiratore comandato = nuovo
##    base; click sul leader = annulla l'ordine;
##  • senza selezione: scegli un tiratore pronto (o un leader per vederne i tiratori).
func _click_fire(q: int, r: int, key: String, units_here: Array) -> void:
	var s := state
	var sel := s.unit_by_id(s.selected_unit_id) if s.selected_unit_id != "" else null
	if sel != null and not s.fire_eligible_ids.is_empty():
		# 1) Click su un pezzo idoneo del gruppo (≠ base): includi/escludi.
		for eid in s.fire_eligible_ids:
			if eid == s.selected_unit_id:
				continue
			var ev := s.unit_by_id(eid)
			if ev != null and ev.q == q and ev.r == r:
				toggle_fire_piece(eid)
				return
		# 2) Click su un bersaglio candidato: apri il fuoco.
		if s.highlighted_hexes.has(key):
			click_hex_fire(q, r)
			return
		# 3) Click sul pezzo base: ANNULLA l'ordine di Fuoco (torna a PLAYER_TURN),
		#    come per gli altri ordini. Così non si resta mai bloccati nell'ordine.
		if q == sel.q and r == sel.r:
			conclude_order()
			return
		# 4) Click su un altro tiratore pronto: cambia pezzo base.
		for u2 in units_here:
			if u2.faction == s.human_faction and s.fire_ready_ids.has(u2.id):
				select_unit(u2.id)
				return
		return
	# Leader selezionato (anteprima dei tiratori comandati), nessun gruppo ancora.
	if sel != null:
		# Click sul leader = annulla l'ordine; su un tiratore comandato = nuovo base.
		if q == sel.q and r == sel.r:
			conclude_order()
			return
		for u2 in units_here:
			if u2.faction == s.human_faction and u2.id != s.selected_unit_id \
					and (s.fire_ready_ids.has(u2.id) or u2.is_leader()):
				select_unit(u2.id)
				return
		return
	# Nessuna selezione: scegli un tiratore pronto o un leader presente nell'esagono.
	for u2 in units_here:
		if u2.faction == s.human_faction and (s.fire_ready_ids.has(u2.id) or u2.is_leader()):
			select_unit(u2.id)
			return
	_cycle_select(units_here, false)


## Il giocatore sceglie un bersaglio candidato: il gruppo assemblato apre il fuoco
## (un solo click). Partecipano i membri del gruppo che colpiscono davvero il
## bersaglio (gittata + LOS); il resto della risoluzione è in confirm_fire().
func click_hex_fire(tq: int, tr: int) -> void:
	if state == null or state.current_order != Domain.OrderType.FIRE:
		return
	var firers: Array[String] = []
	for id in state.fire_group_ids:
		var g := state.unit_by_id(id)
		if g != null and Combat.can_fire(g, tq, tr, state):
			firers.append(g.id)
	if firers.is_empty():
		_log("Nessun pezzo del gruppo può colpire (%d,%d)." % [tq, tr])
		return
	state.fire_group_ids = firers
	state.fire_target_q = tq
	state.fire_target_r = tr
	confirm_fire()


## Include/esclude un pezzo idoneo dal gruppo di fuoco (il pezzo base resta sempre
## incluso). Funziona durante l'assemblaggio, prima di scegliere il bersaglio:
## dopo ogni modifica si ricalcolano i bersagli candidati.
func toggle_fire_piece(id: String) -> void:
	if state == null or state.current_order != Domain.OrderType.FIRE:
		return
	if id == state.selected_unit_id or not state.fire_eligible_ids.has(id):
		return
	if state.fire_group_ids.has(id):
		state.fire_group_ids.erase(id)
	else:
		state.fire_group_ids.append(id)
	if state.fire_target_q < 0:
		_recompute_fire_targets()  # gruppo-prima: i bersagli dipendono dal gruppo
	emit_signal("state_changed")


## Compat: annulla l'assemblaggio del fuoco (alias di _cancel_fire_assembly).
func cancel_fire_target() -> void:
	if state == null:
		return
	_cancel_fire_assembly()


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
	# Ancora di risoluzione: l'attaccante usato da Combat.resolve_fire deve poter
	# colpire il bersaglio (per LOS/ostacolo). Se il pezzo base non lo vede (gruppo
	# diretto da un leader), usa il membro col FP più alto che lo colpisce.
	if not Combat.can_fire(u, tq, tr, state):
		var anchor: Unit = null
		for g in group:
			if Combat.can_fire(g, tq, tr, state) \
					and (anchor == null or Rules.fp_with_command(state, g) > Rules.fp_with_command(state, anchor)):
				anchor = g
		if anchor != null:
			u = anchor
	var weapon_ids: Array = []
	for g in group:
		g.activated = true
		if g.is_weapon():
			weapon_ids.append(g.id)
	# Carta ordine + modificatori. Ogni modificatore accodato è VALIDATO ora contro
	# il bersaglio reale (Incrociato/Bombe/Sventagliata dipendono dal bersaglio): i
	# validi danno +2 FP e si consumano; quelli non applicabili NON si scartano
	# (la carta resta in mano).
	var hand := state.hand_of(state.human_faction)
	var to_discard: Array = []
	if state.selected_card_index >= 0 and state.selected_card_index < hand.size():
		to_discard.append(hand[state.selected_card_index])
	var fp_bonus := 0
	var applied_mods: Array[String] = []
	var spray_q := -1
	var spray_r := -1
	for c in state.fire_modifier_cards:
		var cnm: String = c.action_name
		if cnm.begins_with("SVENTAGLIATA"):
			var sp := _spray_target()
			if sp.x >= 0:
				spray_q = sp.x
				spray_r = sp.y
				to_discard.append(c)
			else:
				_log("Sventagliata: nessun 2° esagono valido qui, carta conservata.")
		elif _fire_modifier_error(cnm) == "":
			fp_bonus += 2
			applied_mods.append(cnm)
			to_discard.append(c)
		else:
			_log("%s non applicabile a questo bersaglio: carta conservata." % cnm)
	var atk_fate := _draw_fate(state.human_faction)
	var def_fate := _draw_fate(_ai_faction())
	var atk_dice := _dice_of(atk_fate)
	_maybe_react_concealment(tq, tr)
	_record_fire(u, tq, tr)  # indicatore "chi spara a chi" sulla mappa
	var result := Combat.resolve_fire(
		u, tq, tr, state, atk_dice, _dice_of(def_fate), group, fp_bonus, spray_q, spray_r)
	_log(result.log_line, result.detail, "fire")
	# Fuoco Sostenuto (A41): su un doppio, un'arma (MG/mortaio) che spara si inceppa.
	if atk_dice.x == atk_dice.y:
		var breaks := applied_mods.count("FUOCO SOSTENUTO")
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
	# Bombe a mano (A34): se applicate, l'animazione lancia una granata sul bersaglio
	# (parte dal pezzo del gruppo adiacente al bersaglio, se c'è).
	if applied_mods.has("BOMBE A MANO"):
		var thrower := u
		for g in group:
			if HexGrid.distance(g.q, g.r, tq, tr) == 1:
				thrower = g
				break
		state.last_grenade = Vector2i(tq, tr)  # marker "qui è caduta la granata"
		emit_signal("grenade_thrown", thrower.q, thrower.r, tq, tr)
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
## l'assemblaggio (ognuna +2 FP, con prerequisiti propri). BOMBE A MANO (A34) è
## anch'essa un modificatore: +2 se almeno un pezzo spara a un esagono adiacente.
const FIRE_MOD_NAMES := ["FUOCO MIRATO", "FUOCO SOSTENUTO", "FUOCO INCROCIATO", "BOMBE A MANO"]

## Azioni "autonome" effettivamente implementate (hanno un effetto reale quando
## giocate nella fase ordini). Serve a NON accendere i badge delle azioni che oggi
## non fanno nulla (verrebbero solo scartate). I modificatori di fuoco, la
## Sventagliata e il Fuoco d'Assalto restano "di contesto" (vedi _action_playable).
const AUTONOMOUS_ACTIONS := [
	"MIMETIZZAZIONE", "TRINCERARSI", "FERITE LEGGERE", "GRANATE FUMOGENE",
	"TRINCERAMENTI NASCOSTI", "MINE NASCOSTE", "CASAMATTA NASCOSTA", "FILO SPINATO NASCOSTO",
]


## Registra l'ultimo attacco di fuoco per l'indicatore "chi spara a chi" sulla
## mappa (linea tiratore→bersaglio + etichetta), utile soprattutto per capire il
## fuoco dell'IA. Va chiamato PRIMA della risoluzione, così i nomi dei bersagli
## si leggono ancora. L'indicatore resta finché non parte l'ordine successivo.
func _record_fire(attacker: Unit, tq: int, tr: int) -> void:
	if attacker == null:
		return
	state.last_fire_from = Vector2i(attacker.q, attacker.r)
	state.last_fire_to = Vector2i(tq, tr)
	var tgt_ids: Array = []
	for m in state.men_at(tq, tr):
		if m.faction != attacker.faction:
			tgt_ids.append(m.id)
	var tgt := Combat._names(state, tgt_ids) if not tgt_ids.is_empty() else Domain.qr_to_label(tq, tr)
	state.last_fire_text = "%s → %s" % [attacker.unit_name, tgt]


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
		"BOMBE A MANO":  # Hand Grenades (A34): un pezzo deve sparare a un esagono adiacente.
			for g in group:
				if HexGrid.distance(g.q, g.r, state.fire_target_q, state.fire_target_r) == 1:
					return ""
			return "richiede un pezzo che spari a un esagono adiacente"
	return ""


## Accoda/rimuove un modificatore di fuoco (+2 FP) durante l'assemblaggio del
## gruppo (flusso gruppo-prima): basta che ci sia un gruppo, non serve il
## bersaglio. I prerequisiti che dipendono dal bersaglio (Incrociato, Bombe a
## Mano) si verificano allo sparo, in confirm_fire; se non valgono, la carta NON
## viene consumata. Cliccare di nuovo lo stesso modificatore lo toglie (toggle).
func apply_fire_modifier(hand_index: int) -> void:
	if state == null or state.current_order != Domain.OrderType.FIRE \
			or state.fire_eligible_ids.is_empty():
		return  # serve un gruppo di fuoco assemblato
	var hand := state.hand_of(state.human_faction)
	if hand_index < 0 or hand_index >= hand.size():
		return
	var card: Card = hand[hand_index]
	var nm := card.action_name
	if nm.begins_with("SVENTAGLIATA"):  # Spray Fire (A40): 2° esagono bersaglio
		_apply_spray(card)
		return
	if not FIRE_MOD_NAMES.has(nm):
		_log("«%s» non è un modificatore di fuoco (in questo contesto)." % (nm if nm != "" else "—"))
		return
	if state.fire_modifier_cards.has(card):  # toggle: già accodato → rimuovi
		state.fire_modifier_cards.erase(card)
		state.fire_modifiers.erase(nm)
		_log("Modificatore «%s» rimosso." % nm)
		emit_signal("state_changed")
		return
	# Prerequisiti verificabili senza bersaglio (Mirato/Sostenuto: tipo di pezzo nel
	# gruppo). Quelli legati al bersaglio (Incrociato/Bombe) si validano allo sparo.
	if nm == "FUOCO MIRATO" or nm == "FUOCO SOSTENUTO" or state.fire_target_q >= 0:
		var err := _fire_modifier_error(nm)
		if err != "":
			_log("%s: %s." % [nm, err])
			return
	state.fire_modifiers.append(nm)
	state.fire_modifier_cards.append(card)
	_log("Modificatore di fuoco pronto: %s (+2 FP)." % nm)
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


## Accoda/rimuove la Sventagliata (A40): estende il fuoco a un 2° esagono. Il
## secondo bersaglio dipende da quello principale, quindi durante l'assemblaggio
## si accoda soltanto; l'esagono effettivo è calcolato allo sparo (confirm_fire).
func _apply_spray(card: Card) -> void:
	if state.fire_modifier_cards.has(card):  # toggle: già accodata → annulla
		state.fire_modifier_cards.erase(card)
		state.spray_active = false
		_log("Sventagliata annullata.")
		emit_signal("state_changed")
		return
	var has_man := false
	for g in _current_fire_group():
		if g.is_man():  # A40: i pezzi devono avere gittata «in scatola» (no ordnance)
			has_man = true
			break
	if not has_man:
		_log("Sventagliata: richiede squadre/team (non ordnance).")
		return
	# Se il bersaglio è già scelto, conferma subito che esiste un 2° esagono valido.
	if state.fire_target_q >= 0 and _spray_target().x < 0:
		_log("Sventagliata: nessun esagono nemico adiacente al bersaglio e a tiro.")
		return
	state.spray_active = true
	state.fire_modifier_cards.append(card)
	_log("Sventagliata pronta: colpirà un 2° esagono adiacente al bersaglio.")
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
		# Hindrance non cumulativo; fumo già incluso in los_hindrance (10.3.3/.4).
		# 0 = l'attacco sarebbe annullato (10.3.2.1), così l'HUD lo segnala.
		var hind := HexGrid.los_hindrance(u.q, u.r, state.fire_target_q, state.fire_target_r, state)
		fp = maxi(0, fp - hind)
	return fp


## Anteprima del fuoco in assemblaggio (per l'HUD). Restituisce il FP d'attacco
## proiettato e la difesa STATICA (senza dadi) del difensore più ostico
## nell'esagono bersaglio, calcolata con la stessa formula di Combat
## (morale + copertura + Comando − Filo). Il margine ≈ FP − difesa indica quanto
## il tiro è favorevole: i dadi (2d6 per parte) in media si annullano.
## {} se non c'è un bersaglio scelto.
func fire_preview() -> Dictionary:
	if state == null or state.current_order != Domain.OrderType.FIRE or state.fire_target_q < 0:
		return {}
	var tq := state.fire_target_q
	var tr := state.fire_target_r
	var u := state.unit_by_id(state.selected_unit_id)
	var ordnance := u != null and u.ordnance
	var cover := Rules.cover_at(state, tq, tr, ordnance)
	var best_def := -1
	var n := 0
	for t in state.men_at(tq, tr):
		if u != null and t.faction == u.faction:
			continue
		n += 1
		var d: int = t.morale + cover + Rules.unit_command_bonus(state, t) - Rules.wire_penalty(state, t)
		best_def = maxi(best_def, d)
	var fp := projected_fire_fp()
	var margin: int = (fp - best_def) if best_def >= 0 else 0
	var verdict := "—"
	if best_def >= 0:
		if margin >= 3:
			verdict = "favorevole"
		elif margin <= -3:
			verdict = "sfavorevole"
		else:
			verdict = "incerto"
	return {
		"fp": fp, "cover": cover, "defenders": n,
		"defense": best_def, "margin": margin, "verdict": verdict,
	}


## FP proiettato di un insieme di pezzi (per id) su un bersaglio qualsiasi (per il
## flyover): miglior FP col Comando + 1 per pezzo extra + modificatori, meno
## l'ostacolo lungo la LOS del pezzo "ancora" (quello col FP più alto).
func _group_fp_at(ids: Array, tq: int, tr: int) -> int:
	var fp := 0
	var count := 0
	var anchor: Unit = null
	for id in ids:
		var g := state.unit_by_id(id)
		if g == null:
			continue
		count += 1
		var gfp := Rules.fp_with_command(state, g)
		fp = maxi(fp, gfp)
		if not g.ordnance and (anchor == null or gfp > Rules.fp_with_command(state, anchor)):
			anchor = g
	if count > 1:
		fp += count - 1
	fp += 2 * state.fire_modifiers.size()
	if anchor != null:
		var hind := HexGrid.los_hindrance(anchor.q, anchor.r, tq, tr, state) + maxi(0, state.global_hindrance)
		fp = maxi(0, fp - hind)
	return fp


## Anteprima del fuoco su un bersaglio CANDIDATO qualsiasi (per il flyover in
## hover): considera i membri del gruppo che colpiscono (tq,tr). Stessa formula di
## fire_preview(). {} se nessun pezzo del gruppo colpisce il bersaglio.
func fire_preview_at(tq: int, tr: int) -> Dictionary:
	if state == null or state.current_order != Domain.OrderType.FIRE:
		return {}
	var firers: Array = []
	for id in state.fire_group_ids:
		var g := state.unit_by_id(id)
		if g != null and Combat.can_fire(g, tq, tr, state):
			firers.append(g.id)
	if firers.is_empty():
		return {}
	var anchor := state.unit_by_id(String(firers[0]))
	var ordnance := anchor != null and anchor.ordnance
	var cover := Rules.cover_at(state, tq, tr, ordnance)
	var best_def := -1
	var n := 0
	for t in state.men_at(tq, tr):
		if anchor != null and t.faction == anchor.faction:
			continue
		n += 1
		var d: int = t.morale + cover + Rules.unit_command_bonus(state, t) - Rules.wire_penalty(state, t)
		best_def = maxi(best_def, d)
	var fp := _group_fp_at(firers, tq, tr)
	var margin: int = (fp - best_def) if best_def >= 0 else 0
	var verdict := "—"
	if best_def >= 0:
		verdict = "favorevole" if margin >= 3 else ("sfavorevole" if margin <= -3 else "incerto")
	return {
		"fp": fp, "cover": cover, "defenders": n, "defense": best_def,
		"margin": margin, "verdict": verdict, "shooters": firers.size(),
	}


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
	if not Rules.can_be_ordered(u):
		_log("Avanzata: l'unità è immobilizzata (rotta o soppressa).")
		return
	if int(state.group_mp.get(u.id, 1)) <= 0:
		_log("Avanzata: questa unità ha già avanzato.")
		return
	if HexGrid.distance(u.q, u.r, tq, tr) != 1:
		_log("Avanzata: scegli un esagono adiacente.")
		return
	_execute_advance(u, tq, tr)


## Trasferimento/raccolta arma (11.3): durante una Mossa, spendendo 1 PM, il
## mover passa l'arma che porta a un compagno co-locato; se non porta nulla,
## raccoglie un'arma a terra (senza portatore) nell'esagono. Tasto «G».
## (Semplificazione: il malus PM dell'arma resta quello calcolato a inizio mossa.)
func transfer_weapon() -> void:
	if state == null or state.phase != Domain.Phase.PLAYER_MOVING \
			or state.current_order != Domain.OrderType.MOVE:
		return
	var u := state.unit_by_id(state.selected_unit_id)
	if u == null or not u.is_man():
		return
	if int(state.group_mp.get(u.id, 0)) < 1:
		_log("Trasferimento arma: serve almeno 1 PM.")
		return
	var carried := state.weapon_carried_by(u.id)
	if carried != null:
		# Dà l'arma a un compagno co-locato senza arma (preferendo un non-leader).
		var target: Unit = null
		for m in state.men_at(u.q, u.r):
			if m.id == u.id or m.faction != u.faction or state.weapon_carried_by(m.id) != null:
				continue
			if target == null or (target.is_leader() and not m.is_leader()):
				target = m
		if target == null:
			_log("Nessun compagno libero a cui passare %s." % carried.unit_name)
			return
		carried.carrier_id = target.id
		state.group_mp[u.id] = int(state.group_mp[u.id]) - 1
		_log("%s passa %s a %s (-1 PM)." % [u.unit_name, carried.unit_name, target.unit_name])
	else:
		# Raccoglie un'arma a terra (senza portatore) nello stesso esagono.
		var pick: Unit = null
		for w in state.units_at(u.q, u.r):
			if w.is_weapon() and w.carrier_id == "" and w.faction == u.faction:
				pick = w
				break
		if pick == null:
			_log("Nessun'arma a terra da raccogliere qui.")
			return
		pick.carrier_id = u.id
		state.group_mp[u.id] = int(state.group_mp[u.id]) - 1
		_log("%s raccoglie %s (-1 PM)." % [u.unit_name, pick.unit_name])
	_highlight_reachable(u)  # i PM sono cambiati: aggiorna l'anteprima
	emit_signal("state_changed")


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
	# Avanzata di gruppo già impegnata: la si conclude (le unità attivate restano tali).
	if state.current_order == Domain.OrderType.ADVANCE and state.move_committed:
		_finish_advance()
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
	elif state.current_order == Domain.OrderType.ADVANCE and state.move_committed:
		_finish_advance()
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


## Conclude il movimento del SOLO mover indicato (anche con PM residui): lo segna
## attivato e senza PM, poi passa al prossimo membro del gruppo (o conclude
## l'ordine se non resta nessuno). Per i gruppi: cliccare il mover non chiude tutto.
func _conclude_mover(mover_id: String) -> void:
	var mv := state.unit_by_id(mover_id)
	if mv != null:
		mv.activated = true
		state.group_mp[mover_id] = 0
	_after_mover_done()


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
	state.set_unit_pos(u, tq, tr)  # porta con sé l'eventuale arma (11.1)
	remaining -= cost
	state.group_mp[u.id] = remaining
	state.move_committed = true
	state.moving_unit_id = u.id
	state.moving_card_index = state.selected_card_index
	_log("%s si muove (%d,%d)->(%d,%d) [-%d PM, rimasti %d]" % [
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
		state.set_unit_pos(u, tq, tr)  # porta con sé l'eventuale arma (11.1)
		u.activated = true
		_log("%s avanza in (%d,%d)" % [u.unit_name, tq, tr])
		emit_signal("unit_moved", u.id, tq, tr)
	else:
		# Corpo a corpo: attaccanti = unità amiche che entrano; difensori = nemici.
		state.set_unit_pos(u, tq, tr)  # porta con sé l'eventuale arma (11.1)
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
		_resolve_melee_ambushes(attackers, defenders)  # A25: Imboscata prima dei dadi
		var mr := Rules.resolve_melee(
			state, attackers, defenders, _dice_of(af), _dice_of(df))
		_log(mr.log_line, mr.detail, "melee")
		for uid in mr.eliminated:
			emit_signal("unit_eliminated", uid)
		_apply_fate(af, u.faction)
		_apply_fate(df, def_faction)

	# Questo membro ha avanzato. Se il gruppo (leader + comandate) ne ha altri che
	# possono ancora avanzare, si sceglie il prossimo; altrimenti l'ordine conclude.
	state.group_mp[u.id] = 0
	state.move_committed = true
	_check_end_conditions()  # aggiorna obiettivi/VP e gestisce la fine partita
	if state.phase == Domain.Phase.GAME_OVER:
		return
	_after_advance_done()


## Dopo che un membro ha avanzato: se restano membri del gruppo che possono ancora
## avanzare, lascia scegliere il prossimo; altrimenti conclude l'ordine di Avanzata.
func _after_advance_done() -> void:
	state.selected_unit_id = ""
	state.highlighted_hexes.clear()
	if state.ordered_group.size() > 1 and _any_group_advancer_left():
		emit_signal("state_changed")  # il giocatore sceglie il prossimo membro
	else:
		_finish_advance()


## Conclude l'avanzata del SOLO membro indicato (lo segna fatto) e passa al
## prossimo; conclude l'ordine solo se non resta nessun membro da far avanzare.
func _conclude_advancer(member_id: String) -> void:
	var av := state.unit_by_id(member_id)
	if av != null:
		av.activated = true
		state.group_mp[member_id] = 0
	_after_advance_done()


## C'è ancora un membro del gruppo che non ha avanzato e ha un esagono adiacente?
func _any_group_advancer_left() -> bool:
	for id in state.ordered_group:
		var v := state.unit_by_id(id)
		if v == null or not v.efficient:
			continue
		if int(state.group_mp.get(id, 0)) <= 0:
			continue  # ha già avanzato
		for h in HexGrid.neighbors(v.q, v.r):
			if h.x >= 0 and h.x < state.map_cols and h.y >= 0 and h.y < state.map_rows \
					and _can_advance_into(v, h.x, h.y):
				return true
	return false


## Conclude l'Avanzata di gruppo: marca attivate TUTTE le unità del gruppo (anche
## quelle non avanzate: l'ordine le ha usate), scarta la carta e torna al turno.
func _finish_advance() -> void:
	var card_idx := state.selected_card_index
	for id in state.ordered_group:
		var v := state.unit_by_id(id)
		if v != null:
			v.activated = true
	if card_idx >= 0:
		_discard_card(card_idx)
	_clear_order_selection()
	_check_end_conditions()
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
		_log("Recupero %s: %d vs %d -> %s" % [
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
			_log("Rotta %s: %d esagoni -> ELIMINATA (nessuna via di fuga)" % [u.unit_name, r["steps"]])
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
	state.fire_ready_ids.clear()
	state.fire_leader_ids.clear()
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


## Reazione di Mimetizzazione (A29) del DIFENSORE all'istante del tiro di Difesa.
## Per ora SOLO per l'IA: l'umano la gioca in anticipo nel proprio turno (la
## finestra di reazione lato umano è una slice successiva). Se l'IA che difende
## l'esagono bersaglio ha una carta Mimetizzazione e un'unità idonea in copertura,
## la gioca: scarta la carta e mimetizza l'unità, così la Copertura riduce una
## volta l'attacco subìto (consumata in Combat).
func _maybe_react_concealment(tq: int, tr: int) -> void:
	if state == null:
		return
	var defenders := state.men_at(tq, tr)
	if defenders.is_empty():
		return
	var fac: int = defenders[0].faction
	if fac == state.human_faction:
		return  # l'umano la gioca in anticipo (per ora)
	if Rules.cover_at(state, tq, tr, false) <= 0:
		return  # senza copertura non darebbe alcun effetto: non sprecare la carta
	var hand := state.hand_of(fac)
	var ci := -1
	for i in hand.size():
		if hand[i].action_name == "MIMETIZZAZIONE":
			ci = i
			break
	if ci < 0:
		return
	var who: Unit = null
	for d in defenders:
		if d.is_man() and d.efficient and not d.concealed:
			who = d
			break
	if who == null:
		return
	who.concealed = true
	_discard_for(fac, ci)
	_log("%s reagisce con Mimetizzazione (A29)." % Domain.FACTION_NAMES.get(fac, "IA"))


## Reazione di Mimetizzazione (A29) del DIFENSORE UMANO: quando l'IA spara a un
## esagono con un'unità umana in copertura e il giocatore ha la carta, apre una
## finestra e attende che clicchi l'unità (o rinunci). Coroutine: il chiamante
## deve usare `await`. Senza condizioni valide ritorna subito senza aprire nulla.
func _reactive_concealment_human(tq: int, tr: int) -> void:
	if state == null:
		return
	var defenders := state.men_at(tq, tr)
	if defenders.is_empty() or defenders[0].faction != state.human_faction:
		return
	if Rules.cover_at(state, tq, tr, false) <= 0:
		return
	if _human_concealment_index() < 0:
		return
	var eligible: Array[String] = []
	for d in defenders:
		if d.is_man() and d.efficient and not d.concealed:
			eligible.append(d.id)
	if eligible.is_empty():
		return

	state.conceal_offer_ids = eligible
	_conceal_choice = ""
	var prev_phase := state.phase
	_change_phase(Domain.Phase.REACTION_WINDOW)
	emit_signal("conceal_offered", tq, tr)
	emit_signal("state_changed")
	await _conceal_decided

	state.conceal_offer_ids = []
	if _conceal_choice != "":
		var who := state.unit_by_id(_conceal_choice)
		var ci := _human_concealment_index()
		if who != null and ci >= 0:
			who.concealed = true
			_discard_for(state.human_faction, ci)
			_log("Mimetizzazione (A29): %s si mimetizza." % who.unit_name)
	else:
		_log("Mimetizzazione: rinunci.")
	if state.phase != Domain.Phase.GAME_OVER:
		_change_phase(prev_phase)
	emit_signal("state_changed")


## Indice della prima carta Mimetizzazione nella mano dell'umano (−1 se assente).
func _human_concealment_index() -> int:
	var hand := state.hand_of(state.human_faction)
	for i in hand.size():
		if hand[i].action_name == "MIMETIZZAZIONE":
			return i
	return -1


## Il giocatore sceglie l'unità da mimetizzare (dalla finestra di reazione).
func conceal_accept(unit_id: String) -> void:
	if state == null or state.phase != Domain.Phase.REACTION_WINDOW:
		return
	if not state.conceal_offer_ids.has(unit_id):
		return
	_conceal_choice = unit_id
	emit_signal("_conceal_decided")


## Il giocatore rinuncia alla Mimetizzazione.
func conceal_decline() -> void:
	if state == null or state.phase != Domain.Phase.REACTION_WINDOW:
		return
	_conceal_choice = ""
	emit_signal("_conceal_decided")


## Imboscata (A25) in Mischia: prima del tiro, l'IA può giocarla per ROMPERE
## un'unità avversaria partecipante (così ne dimezza la PdF prima del calcolo).
## Ordine A25: prima il difensore (inattivo), poi l'attaccante (attivo). Per ora
## solo l'IA gioca l'Imboscata; il lato umano è una slice successiva.
func _resolve_melee_ambushes(attackers: Array, defenders: Array) -> void:
	if attackers.is_empty() or defenders.is_empty():
		return
	_ai_ambush(defenders[0].faction, defenders, attackers)  # difensore IA rompe un attaccante
	_ai_ambush(attackers[0].faction, attackers, defenders)  # attaccante IA rompe un difensore


## L'IA `faction` (se partecipa con `own`) gioca un'Imboscata, se ha la carta,
## rompendo l'unità avversaria più DEBOLE ancora intatta tra `opp` (è ciò che il
## difensore razionale sceglierebbe: rompere la propria più debole).
func _ai_ambush(faction: int, own: Array, opp: Array) -> void:
	if faction == state.human_faction or own.is_empty():
		return  # l'Imboscata umana è una slice successiva
	var hand := state.hand_of(faction)
	var ci := -1
	for i in hand.size():
		if hand[i].action_name == "IMBOSCATA":
			ci = i
			break
	if ci < 0:
		return
	var victim: Unit = null
	for o in opp:
		if o.efficient and (victim == null or o.effective_fp() < victim.effective_fp()):
			victim = o
	if victim == null:
		return  # nessun bersaglio intatto: non sprecare la carta
	victim.break_unit()
	_discard_for(faction, ci)
	_log("%s gioca Imboscata (A25): %s è rotta." % [
		Domain.FACTION_NAMES.get(faction, "IA"), victim.unit_name])


## «Passa» (O15): invece di dare un ordine il giocatore può passare. Scarta le
## carte scelte (per indice nella propria mano), ne ripesca altrettante e cede il
## turno all'avversario. Passando senza scartare nulla si conserva la mano.
func pass_turn(discard_indices: Array = []) -> void:
	if state == null or state.phase != Domain.Phase.PLAYER_TURN:
		return
	var faction := state.human_faction
	var hand := state.hand_of(faction)
	# Raccogliamo i riferimenti alle carte: scartando in sequenza gli indici
	# cambierebbero, mentre l'identità della carta resta stabile.
	var to_discard: Array[Card] = []
	for idx in discard_indices:
		var i := int(idx)
		if i >= 0 and i < hand.size():
			to_discard.append(hand[i])
	for c in to_discard:
		var i := hand.find(c)
		if i >= 0:
			_discard_for(faction, i)  # scarta 1 e ripesca 1: la mano resta piena
	if to_discard.is_empty():
		_log("Passi: nessun ordine, mano invariata.")
	else:
		_log("Passi: scarti %d carta/e e ripeschi." % to_discard.size())
	_end_player_turn()


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
			_log("Mine: %s colpita (att %d > dif %d) -> rotta." % [u.unit_name, atk, defn])
		else:
			_log("Mine: %s colpita (att %d > dif %d) -> eliminata." % [u.unit_name, atk, defn])
			emit_signal("unit_eliminated", u.id)
			state.eliminate_unit(u.id)
		return true
	_log("Mine: %s passa (att %d <= dif %d)." % [u.unit_name, atk, defn])
	return false


# ─── Fuoco di Opportunità (A33) ───────────────────────────────────────────────

signal opfire_offered(mover_id: String)  ## Finestra di reazione aperta per l'umano
signal _opfire_decided()                 ## Interno: il giocatore ha scelto

var _opfire_choice: String = ""          ## Tiratore scelto ("" = non sparare)

signal conceal_offered(tq: int, tr: int)  ## Finestra di Mimetizzazione per l'umano
signal _conceal_decided()                 ## Interno: il giocatore ha scelto
var _conceal_choice: String = ""          ## Unità da mimetizzare ("" = rinuncia)


## Indice in mano di una carta con ordine FUOCO (da giocare come Azione di Op
## Fire, A24.1), oppure -1 se la fazione non ne ha.
func _fire_card_index(faction: int) -> int:
	var hand := state.hand_of(faction)
	for i in hand.size():
		if hand[i].order == Domain.OrderType.FIRE:
			return i
	return -1


## Risolve un Fuoco di Opportunità con uno SPECIFICO tiratore. Restituisce true se
## il mover è stato rotto o eliminato (movimento da interrompere).
## A24.1: è un'Azione → si gioca SCARTANDO una carta Fuoco dalla mano del
## difensore (col rifornimento standard). A24.3: l'Op Fire ATTIVA il tiratore,
## che quindi non può reagire una seconda volta nello stesso turno.
func _resolve_op_fire(shooter: Unit, mover: Unit, defender: int) -> bool:
	var fci := _fire_card_index(defender)
	if fci < 0:
		return false  # nessuna carta Fuoco in mano: nessuna reazione possibile
	var group := Combat.fire_group(shooter, mover.q, mover.r, state)
	var weapon_ids: Array = []
	for g in group:
		if g.is_weapon():
			weapon_ids.append(g.id)
	shooter.activated = true             # A24.3
	_discard_for(defender, fci)          # A24.1: la carta Fuoco giocata come Azione
	var atk_fate := _draw_fate(defender)
	var def_fate := _draw_fate(mover.faction)
	_maybe_react_concealment(mover.q, mover.r)  # il mover (se IA) può mimetizzarsi
	_record_fire(shooter, mover.q, mover.r)  # indicatore "chi spara a chi"
	var res := Combat.resolve_fire(shooter, mover.q, mover.r, state, _dice_of(atk_fate), _dice_of(def_fate))
	_log("Opportunità — " + res.log_line, res.detail, "fire")
	for id in res.eliminated:
		emit_signal("unit_eliminated", id)
	_apply_fate(atk_fate, defender, { "kind": "fire", "weapons": weapon_ids })
	_apply_fate(def_fate, mover.faction)
	return res.eliminated.has(mover.id) or res.broken.has(mover.id)


## Op Fire AUTOMATICO (A33): il difensore IA reagisce col tiratore il cui gruppo
## di fuoco ha la massima FP contro il mover (FlipBot), purché abbia una carta
## Fuoco e il tiro soddisfi la FP minima. Niente carte sprecate su tiri deboli.
func _op_fire(mover: Unit, defender: int) -> bool:
	if _fire_card_index(defender) < 0:
		return false
	var shooter := FlipBot.best_op_fire(state, mover, defender)
	if shooter == null:
		return false
	return _resolve_op_fire(shooter, mover, defender)


## Op Fire come FINESTRA DI REAZIONE (A33). Se il difensore è l'umano, apre la
## scelta del tiratore (o «non sparare») e attende la decisione; se è l'IA, fuoco
## automatico. Coroutine: il chiamante deve usare `await`.
func _reactive_op_fire(mover: Unit, defender: int) -> bool:
	# A24.1: senza una carta Fuoco in mano il difensore non può reagire.
	if _fire_card_index(defender) < 0:
		return false
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
	if state.time_marker > prev_time:
		# Rinforzi (Tabella del Tempo): entrano quando il Tempo raggiunge il loro spazio.
		_check_reinforcements()
		# FlipBot: la Disposizione si rivaluta a ogni avanzamento del Tempo.
		state.disposition = FlipBot.compute_disposition(state, _ai_faction())
		if state.time_marker >= state.sudden_death_space \
				and state.phase != Domain.Phase.GAME_OVER:
			_check_sudden_death(faction)


## Fa entrare i rinforzi il cui spazio della Tabella del Tempo è stato raggiunto
## dal segnalino: crea le unità sul bordo amico (esagoni liberi) e le rimuove dal
## pool. Finora NON erano in `state.units`, quindi nessuna logica le considerava.
func _check_reinforcements() -> void:
	if state.reinforcements.is_empty():
		return
	var still_waiting: Array = []
	for grp in state.reinforcements:
		if int(grp.get("space", 99)) <= state.time_marker:
			_enter_reinforcement(grp)
		else:
			still_waiting.append(grp)
	state.reinforcements = still_waiting


func _enter_reinforcement(grp: Dictionary) -> void:
	var faction := int(grp.get("faction", Domain.Faction.GERMAN))
	# Bordo amico: Axis entra dalle colonne di destra, Allied da sinistra.
	var edge_q := state.map_cols - 1 if faction == Domain.Faction.GERMAN else 0
	var rows: Array = []
	for r in state.map_rows:
		rows.append(r)
	var seq := state.units.size() + 1000  # id univoci, lontani da quelli di setup
	var entered := 0
	for f in grp.get("forces", []):
		var tipo := String(f.get("tipo", ""))
		var nat := String(f.get("nat", ""))
		for k in int(f.get("n", 1)):
			var pos := _free_edge_hex(edge_q, rows)
			var id := "R-%s-%d" % [Domain.FACTION_SHORT.get(faction, "U"), seq]
			seq += 1
			state.units[id] = UnitChart.build_unit(id, faction, tipo, pos.x, pos.y, nat)
			entered += 1
	if entered > 0:
		_log("Rinforzi (spazio %d): entrano %d unità dal bordo." % [int(grp.get("space", 0)), entered])
		_assign_initial_carriers(state)  # le armi dei rinforzi vanno a una squadra
		emit_signal("state_changed")


## Un esagono libero (senza uomini) sulla colonna di bordo `q`; se sono tutte
## occupate, ripiega su una riga qualsiasi della colonna.
func _free_edge_hex(q: int, rows: Array) -> Vector2i:
	for r in rows:
		if state.men_at(q, r).is_empty():
			return Vector2i(q, r)
	return Vector2i(q, int(rows[0]) if not rows.is_empty() else 0)


## Risoluzione del sovraccarico a fine turno (8.2): in ogni esagono con più di 7
## figure amiche il proprietario elimina unità finché rientra nel limite. Le armi
## (0 figure) non contano. Si sceglie di volta in volta la vittima che copre lo
## sforamento sprecando meno figure (a parità, prima le rotte), così si conserva
## la forza efficiente. È il vero punto in cui valgono le regole di impilamento:
## durante il turno si può sovrastare, a fine turno si rientra (o si perde gente).
func _resolve_overstacking(faction: int) -> void:
	var by_hex: Dictionary = {}
	for u in state.units.values():
		if u.faction != faction or not u.is_man():
			continue
		var k := "%d,%d" % [u.q, u.r]
		if not by_hex.has(k):
			by_hex[k] = []
		by_hex[k].append(u)
	var eliminated_any := false
	for k in by_hex:
		var stack: Array = by_hex[k]
		var total := 0
		for u in stack:
			total += u.soldier_icons()
		if total <= 7:
			continue
		var victims: Array = []
		while total > 7 and not stack.is_empty():
			var v := _overstack_victim(stack, total - 7)
			if v == null:
				break
			stack.erase(v)
			total -= v.soldier_icons()
			victims.append(v)
		if victims.is_empty():
			continue
		var ids: Array = victims.map(func(x: Unit) -> String: return x.id)
		var names := Combat._names(state, ids)
		var kind := "ai" if faction == _ai_faction() else ""
		_log("[b]Sovraccarico[/b] in (%s): eliminate %d unità in eccesso — %s (8.2)." % [
			k, victims.size(), names],
			"Limite 7 figure/esagono: durante il turno si può sovrastare, a fine turno l'eccesso va eliminato.",
			kind)
		for u in victims:
			state.eliminate_unit(u.id)
			emit_signal("unit_eliminated", u.id)
		eliminated_any = true
	# Solo se si è davvero eliminato qualcosa: aggiorna VP/obiettivi/resa (così un
	# turno senza sovraccarico non tocca lo stato di fine partita).
	if eliminated_any:
		_check_end_conditions()


## Sceglie quale unità eliminare da uno stack sovraccarico dato lo sforamento
## `deficit` (figure di troppo): la più piccola unità che da sola lo copre (meno
## spreco); a parità di figure, prima le rotte; se nessuna lo copre, la più grande
## (per fare progresso). Restituisce null se lo stack è vuoto.
func _overstack_victim(stack: Array, deficit: int) -> Unit:
	var cover: Unit = null
	var biggest: Unit = null
	for u: Unit in stack:
		var f: int = u.soldier_icons()
		if f >= deficit:
			if cover == null or f < cover.soldier_icons() \
					or (f == cover.soldier_icons() and not u.efficient and cover.efficient):
				cover = u
		if biggest == null or f > biggest.soldier_icons() \
				or (f == biggest.soldier_icons() and not u.efficient and biggest.efficient):
			biggest = u
	return cover if cover != null else biggest


func _end_player_turn() -> void:
	# Fine turno (8.2): risolvi il sovraccarico delle TUE unità prima di passare.
	_resolve_overstacking(state.human_faction)
	if state.phase == Domain.Phase.GAME_OVER:
		return
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
	_log("Fine turno %d" % (state.turn_number - 1), "", "turn")
	# Turno dell'IA: coroutine «fire-and-forget» — può sospendersi sulla finestra
	# di reazione (Op Fire) del giocatore e riprendere alla sua decisione. Il
	# ritorno al turno del giocatore avviene alla fine di _run_ai_turn.
	_run_ai_turn()


func _run_ai_turn() -> void:
	_change_phase(Domain.Phase.AI_TURN)
	var faction := _ai_faction()
	# FlipBot: ricalcola la Disposizione (Offensiva/Difensiva) a inizio turno.
	state.disposition = FlipBot.compute_disposition(state, faction)
	_log("FlipBot: disposizione %s." % Domain.DISPOSITION_LABELS.get(state.disposition, "?"))
	# FlipBot: se più di metà della mano è fatta di carte "dud", passa e scarta.
	if FlipBot.should_pass_and_discard(state, faction):
		_ai_pass_discard(faction)
		_resolve_overstacking(faction)  # fine turno IA (8.2)
		if state.phase != Domain.Phase.GAME_OVER:
			_change_phase(Domain.Phase.PLAYER_TURN)
			_log("Turno %d — il tuo ordine" % state.turn_number, "", "turn")
		return
	# FlipBot: Recupero per primo, poi il primo ordine giocabile da sinistra.
	var plays := 0
	while plays < state.ai_max_orders:
		var play := FlipBot.choose_turn_order(state, faction)
		if play.is_empty():
			break
		await _ai_execute(faction, play)
		plays += 1
		_check_end_conditions()
		if state.phase == Domain.Phase.GAME_OVER:
			return
	if plays == 0:
		# Nessun ordine giocabile: passa e scarta le dud (o cicla una carta).
		_log("IA: nessun ordine giocabile.")
		_ai_pass_discard(faction)
	# Fine del turno IA (8.2): risolvi il sovraccarico delle unità del bot, poi →
	# al giocatore (qui, non in _end_player_turn, perché questa coroutine può
	# essersi sospesa sulla finestra di reazione).
	_resolve_overstacking(faction)
	if state.phase != Domain.Phase.GAME_OVER:
		_change_phase(Domain.Phase.PLAYER_TURN)
		_log("Turno %d — il tuo ordine" % state.turn_number, "", "turn")


## FlipBot passa e scarta: scarta le carte "dud" (Confusione d'Ordini,
## Artiglieria inutile) e ne ripesca altrettante. Se non ci sono dud, cicla la
## carta più a sinistra per non restare con la mano bloccata.
func _ai_pass_discard(faction: int) -> void:
	var hand := state.hand_of(faction)
	var dud_cards: Array = []
	for i in FlipBot.dud_indices(state, faction):
		dud_cards.append(hand[int(i)])
	if dud_cards.is_empty() and not hand.is_empty():
		dud_cards.append(hand[0])  # cicla una carta per sbloccare la mano
	# Scarta per identità (gli indici cambiano via via); ripesca a ogni scarto.
	for c in dud_cards:
		var idx := hand.find(c)
		if idx >= 0:
			_discard_for(faction, idx)
	if not dud_cards.is_empty():
		_log("IA passa e scarta %d carta/e." % dud_cards.size())


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
				await _reactive_concealment_human(fq, fr)  # il difensore umano può mimetizzarsi
				_record_fire(atk, fq, fr)  # indicatore "l'IA spara a chi" sulla mappa
				var fres := Combat.resolve_fire(atk, fq, fr, state, _dice_of(ffate), _dice_of(dfate))
				_log("IA — " + fres.log_line, fres.detail, "ai")
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
	state.set_unit_pos(u, tq, tr)  # porta con sé l'eventuale arma (11.1)
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
	_resolve_melee_ambushes(attackers, defenders)  # A25: Imboscata prima dei dadi
	var mr := Rules.resolve_melee(
		state, attackers, defenders, _dice_of(af), _dice_of(df))
	_log("IA — " + mr.log_line, mr.detail, "ai")
	for mid in mr.eliminated:
		emit_signal("unit_eliminated", mid)
	_apply_fate(af, faction)
	_apply_fate(df, def_faction)


## Ordine di Mossa dell'IA (FlipBot): muove prima le unità rotte (in ritirata),
## poi le altre; ciascuna verso la sua destinazione strategica (priorità FlipBot
## + Disposizione), un esagono alla volta fino ai suoi PM.
func _ai_move_order(faction: int) -> void:
	var movers: Array = state.units_of(faction).filter(
		func(u: Unit) -> bool: return Rules.can_be_ordered(u) and not u.is_weapon())
	# Rotti per primi (si ritirano), poi le unità efficienti.
	movers.sort_custom(func(a: Unit, b: Unit) -> bool:
		return (not a.efficient) and b.efficient)
	for u in movers:
		if not state.units.has(u.id) or not Rules.can_be_ordered(u):
			continue
		# Non abbandonare un obiettivo presidiato dall'unica unità amica.
		if FlipBot.should_hold_objective(state, faction, u):
			u.activated = true
			continue
		var dest := FlipBot.move_destination(state, faction, u)
		# Budget di Punti Movimento (come il giocatore): Movimento + Comando − arma.
		# Ogni passo costa secondo il terreno, così l'IA non si muove più del dovuto.
		var budget := Rules.move_allowance(state, u)
		while budget > 0:
			if u.q == dest.x and u.r == dest.y:
				break
			var spent: int = await _ai_move_toward(u, dest.x, dest.y, faction, budget)
			if spent <= 0 or state.phase == Domain.Phase.GAME_OVER:
				break
			budget -= spent
		u.activated = true


## Sposta l'unità di UN esagono verso (tq,tr), scegliendo fra gli esagoni che si
## avvicinano quello migliore per (copertura, vicinanza al bordo nemico). Rispetta
## i Punti Movimento residui (`budget`): scarta i passi che costano più dei PM
## rimasti. Evita nemici e sovraccarico. Restituisce i PM SPESI (0 se non si muove;
## coroutine: può attendere la finestra di reazione del difensore umano).
func _ai_move_toward(u: Unit, tq: int, tr: int, faction: int, budget: int) -> int:
	if u.move <= 0 or budget <= 0:
		return 0
	var here := Vector2i(u.q, u.r)
	var cur_dist := HexGrid.distance(u.q, u.r, tq, tr)
	if cur_dist == 0:
		return 0
	var enemy_col := FlipBot.enemy_edge_col(state, faction)
	var best := here
	var best_key := [cur_dist, 0, 9999]  # [distanza, -copertura, dist. bordo nemico]
	var best_cost := 0
	for n in HexGrid.neighbors(u.q, u.r):
		if n.x < 0 or n.x >= state.map_cols or n.y < 0 or n.y >= state.map_rows:
			continue
		var d := HexGrid.distance(n.x, n.y, tq, tr)
		if d >= cur_dist:
			continue  # il passo deve avvicinare alla destinazione
		# Costo del terreno (e dei lati): salta gli esagoni impraticabili o troppo
		# cari per i PM rimasti — così l'IA paga davvero il terreno.
		var cost := HexGrid.step_cost(state, u.q, u.r, n.x, n.y)
		if cost < 0 or cost > budget:
			continue
		var enemy := false
		for m in state.men_at(n.x, n.y):
			if m.faction != faction:
				enemy = true
				break
		if enemy:
			continue
		if state.soldier_icons_at(n.x, n.y) + u.soldier_icons() > 7:
			continue
		var key := [d, -Rules.cover_at(state, n.x, n.y, false), absi(n.x - enemy_col)]
		if _key_less(key, best_key):
			best_key = key
			best = n
			best_cost = cost
	if best == here:
		return 0
	var oq := u.q
	var orr := u.r
	state.set_unit_pos(u, best.x, best.y)  # porta con sé l'eventuale arma (11.1)
	emit_signal("unit_moved", u.id, best.x, best.y)
	# Mine (F103) sull'IA che si muove: se colpita, il movimento si ferma.
	if _mine_attack_on_move(u, oq, orr):
		_check_end_conditions()
		return 0
	# Il difensore reagisce col Fuoco di Opportunità (finestra interattiva se il
	# difensore è l'umano). Marca l'unità «in movimento» per il pareggio (A33).
	var prev_moving := state.moving_unit_id
	state.moving_unit_id = u.id
	await _reactive_op_fire(u, _opponent(u.faction))
	state.moving_unit_id = prev_moving
	return best_cost


## Confronto lessicografico fra due chiavi (array di interi): a < b?
func _key_less(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] != b[i]:
			return a[i] < b[i]
	return false


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
	var space := state.time_marker
	var total := _sd_roll(triggering_faction)
	if total >= space:
		_log("Morte Subitanea evitata: tiro %d >= %d (casella Tempo)." % [total, space])
		return
	# La Morte Subitanea scatterebbe. Vincitore = leader nei VP; in pareggio,
	# il detentore dell'Iniziativa (9.2).
	_update_objectives()
	var winner := Rules.sd_winner(state.vp_tracker, state.initiative_holder)
	# 9.1 Re-Roll: chi sta perdendo può annullare e rifare il tiro, MA cedendo la
	# carta Iniziativa all'avversario. (Lo fa solo se gli conviene, cioè se perde.)
	if Rules.sd_initiative_rerolls(state.vp_tracker, state.initiative_holder):
		var loser := state.initiative_holder
		state.initiative_holder = winner  # la carta Iniziativa passa all'avversario
		var t2 := _sd_roll(loser)
		_log("Re-Roll dell'Iniziativa: %s annulla la Morte Subitanea e cede l'Iniziativa a %s — nuovo tiro %d vs %d." % [
			Domain.FACTION_NAMES.get(loser, "?"), Domain.FACTION_NAMES.get(winner, "?"), t2, space])
		if t2 >= space:
			_log("Morte Subitanea evitata col Re-Roll: %d >= %d — la partita continua." % [t2, space])
			return
		_log("Morte Subitanea confermata anche dopo il Re-Roll: %d < %d." % [t2, space])
	_log("VP finali — bilancia %+d (positivo = Germania)" % state.vp_tracker)
	_log("MORTE SUBITANEA — fine partita.")
	_end_game(winner)


## Un singolo tiro di Morte Subitanea (somma dei dadi di una carta del Fato).
func _sd_roll(faction: int) -> int:
	var dice := _dice_of(_draw_fate(faction))
	return dice.x + dice.y


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
	_log("=== FINE PARTITA — Vincitore: %s ===" % fname)
	emit_signal("game_over", winner)


# ─── Utilità ──────────────────────────────────────────────────────────────────

func _log(msg: String, detail: String = "", kind: String = "") -> void:
	if state:
		state.add_log(msg, detail, kind)
	emit_signal("log_added", msg, detail, kind)


func _change_phase(new_phase: int) -> void:
	if state:
		state.phase = new_phase
	emit_signal("phase_changed", new_phase)
	emit_signal("state_changed")
