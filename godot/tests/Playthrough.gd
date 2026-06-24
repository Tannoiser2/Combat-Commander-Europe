## Harness manuale (NON in CI): guida il loop di gioco come fa la UI, per
## verificare che la partita sia giocabile end-to-end (selezione → carta →
## bersaglio → conclusione). Si esegue come scena:
##   godot --headless --path . res://tests/Playthrough.gd  (via .tscn)
extends Node

var _fail := 0


func _ready() -> void:
	_test_move_loop()
	_test_fire_transition_and_cancel()
	_test_leader_group_move()
	_test_fire_group_assembly()
	if _fail == 0:
		print("\nPLAYTHROUGH: PASS")
	else:
		print("\nPLAYTHROUGH: FAIL (%d)" % _fail)
	get_tree().quit(_fail)


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  [ok] " + msg)
	else:
		_fail += 1
		print("  [NO] " + msg)


## Carta sintetica con un dato ordine (per garantire la mano del test).
func _make_card(order: int, faction: int) -> Card:
	var c := Card.new()
	c.faction = faction
	c.number = 1
	c.order = order
	c.order_label = Domain.ORDER_LABELS.get(order, "?")
	c.dice_white = 3
	c.dice_red = 4
	return c


func _movable_unit(faction: int) -> Unit:
	for u in Game.state.units_of(faction):
		if u.is_man() and u.efficient and u.move > 0 and not u.activated:
			return u
	return null


# ─── Loop di MOSSA completo ───────────────────────────────────────────────────

func _test_move_loop() -> void:
	print("· Loop MOSSA: unità → carta → esagono → conclusione")
	Game.start_new_game(Domain.Faction.GERMAN, 2)
	var s := Game.state
	var hand := s.hand_of(s.human_faction)
	hand[0] = _make_card(Domain.OrderType.MOVE, s.human_faction)
	var hand_before := hand.size()

	var u := _movable_unit(s.human_faction)
	_check(u != null, "trovata un'unità muovibile")
	if u == null:
		return

	# Flusso naturale: prima seleziono l'unità, poi gioco la carta MOSSA.
	Game.select_unit(u.id)
	Game.play_card(0)
	_check(s.phase == Domain.Phase.PLAYER_MOVING, "carta MOSSA → fase PLAYER_MOVING")
	_check(s.current_order == Domain.OrderType.MOVE, "ordine corrente = MOSSA")
	_check(s.selected_unit_id == u.id, "selezione mantenuta dopo la carta")
	_check(s.highlighted_hexes.size() > 0, "esagoni di movimento evidenziati (%d)" % s.highlighted_hexes.size())
	if s.highlighted_hexes.is_empty():
		return

	# Clicco un esagono evidenziato (come HexMap._on_click).
	var parts := String(s.highlighted_hexes[0]).split(",")
	var tq := int(parts[0])
	var tr := int(parts[1])
	var oq := u.q
	var orr := u.r
	Game.click_hex_move(tq, tr)
	_check(u.q == tq and u.r == tr, "unità mossa (%d,%d)→(%d,%d)" % [oq, orr, tq, tr])

	# Concludo la mossa (se non si è già conclusa da sola coi PM esauriti).
	if s.phase == Domain.Phase.PLAYER_MOVING:
		Game.finish_move()
	_check(s.phase == Domain.Phase.PLAYER_TURN, "dopo la mossa → ritorno a PLAYER_TURN")
	_check(s.hand_of(s.human_faction).size() == hand_before, "mano ricostituita (carta MOSSA scartata e ripescata)")
	_check(s.selected_unit_id == "" and s.current_order == -1, "selezione/ordine azzerati")


# ─── Transizione FUOCO + annullamento ─────────────────────────────────────────

func _test_fire_transition_and_cancel() -> void:
	print("· FUOCO: transizione e annullamento (carta non consumata)")
	Game.start_new_game(Domain.Faction.GERMAN, 2)
	var s := Game.state
	var hand := s.hand_of(s.human_faction)
	hand[0] = _make_card(Domain.OrderType.FIRE, s.human_faction)
	var hand_before := hand.size()

	var u := _movable_unit(s.human_faction)
	if u == null:
		_check(false, "trovata un'unità per il fuoco")
		return
	Game.select_unit(u.id)
	Game.play_card(0)
	_check(s.phase == Domain.Phase.PLAYER_MOVING, "carta FUOCO → fase PLAYER_MOVING")
	_check(s.current_order == Domain.OrderType.FIRE, "ordine corrente = FUOCO")

	# Annullo (come il click sulla propria unità senza movimento avviato).
	Game.cancel_order()
	_check(s.phase == Domain.Phase.PLAYER_TURN, "annullamento → ritorno a PLAYER_TURN")
	_check(s.hand_of(s.human_faction).size() == hand_before, "mano invariata")
	_check(s.hand_of(s.human_faction)[0].order == Domain.OrderType.FIRE, "carta FUOCO ancora in mano (non consumata)")


# ─── Mossa di gruppo attivata dal leader (Comando 3.3) ────────────────────────

func _test_leader_group_move() -> void:
	print("· Mossa di gruppo: il leader attiva e muove le unità nel suo raggio")
	Game.start_new_game(Domain.Faction.GERMAN, 2)
	var s := Game.state
	# Leader umano con Comando>0 che ha almeno un altro uomo muovibile nel raggio.
	var leader: Unit = null
	for u in s.units_of(s.human_faction):
		if u.is_leader() and u.command > 0 and u.efficient and u.move > 0:
			for v in s.units_of(s.human_faction):
				if v.id != u.id and v.is_man() and v.efficient and v.move > 0 \
						and HexGrid.distance(u.q, u.r, v.q, v.r) <= u.command:
					leader = u
					break
		if leader != null:
			break
	_check(leader != null, "trovato un leader con Comando e unità nel raggio")
	if leader == null:
		return

	s.hand_of(s.human_faction)[0] = _make_card(Domain.OrderType.MOVE, s.human_faction)
	Game.select_unit(leader.id)
	Game.play_card(0)
	_check(s.current_order == Domain.OrderType.MOVE, "ordine MOSSA in corso")
	_check(s.ordered_group.size() > 1, "gruppo attivato con %d unità" % s.ordered_group.size())
	_check(s.ordered_group.has(leader.id), "il leader fa parte del gruppo")
	_check(s.selected_unit_id == leader.id, "il leader è il mover attivo")
	_check(s.highlighted_hexes.size() > 0, "esagoni di movimento del leader evidenziati")

	# Muovo il leader di un passo.
	if s.highlighted_hexes.size() > 0:
		var p := String(s.highlighted_hexes[0]).split(",")
		Game.click_hex_move(int(p[0]), int(p[1]))
		_check(s.move_committed, "movimento impegnato dopo il primo passo")

	# Passo a un altro membro del gruppo (cambio mover attivo).
	var other_id := ""
	for id in s.ordered_group:
		if id != leader.id:
			other_id = id
			break
	if other_id != "" and s.phase == Domain.Phase.PLAYER_MOVING:
		Game.select_unit(other_id)
		_check(s.selected_unit_id == other_id, "passaggio a un altro membro del gruppo")

	# Concludo l'ordine: tutte le unità del gruppo risultano attivate.
	if s.phase == Domain.Phase.PLAYER_MOVING:
		Game.finish_move()
	_check(s.phase == Domain.Phase.PLAYER_TURN, "ordine di gruppo concluso → PLAYER_TURN")
	var ldr := s.unit_by_id(leader.id)
	_check(ldr != null and ldr.activated, "leader marcato attivato (consumato dall'ordine)")
	_check(s.ordered_group.is_empty(), "gruppo azzerato dopo la conclusione")


# ─── Gruppo di fuoco interattivo (O20.3.1) ────────────────────────────────────

func _mk_unit(id: String, faction: int, type: int, q: int, r: int, fp: int, mor: int) -> Unit:
	var u := Unit.new(id, faction, type, Domain.UnitClass.RIFLE, id)
	u.fp = fp
	u.range = 6
	u.move = 4
	u.morale = mor
	u.q = q
	u.r = r
	return u


func _test_fire_group_assembly() -> void:
	print("· Gruppo di fuoco interattivo: scegli bersaglio, includi/escludi, spara")
	# Stato pulito (mappa aperta) per controllare gittata e LOS.
	var s := GameState.new()
	s.map_cols = 6
	s.map_rows = 3
	for q in 6:
		for r in 3:
			s.hexes["%d,%d" % [q, r]] = GameState.HexData.new(Domain.TerrainType.OPEN)
	s.human_faction = Domain.Faction.GERMAN
	var base := _mk_unit("b", Domain.Faction.GERMAN, Domain.UnitType.SQUAD, 0, 0, 6, 5)
	var ld := _mk_unit("l", Domain.Faction.GERMAN, Domain.UnitType.LEADER, 0, 0, 4, 5)
	ld.command = 2
	var sq2 := _mk_unit("s2", Domain.Faction.GERMAN, Domain.UnitType.SQUAD, 1, 0, 6, 5)
	var tgt := _mk_unit("t", Domain.Faction.RUSSIAN, Domain.UnitType.SQUAD, 2, 0, 5, 5)
	for u in [base, ld, sq2, tgt]:
		s.units[u.id] = u
	Game.state = s
	s.phase = Domain.Phase.PLAYER_MOVING
	s.current_order = Domain.OrderType.FIRE
	s.selected_unit_id = "b"
	s.selected_card_index = -1

	Game.click_hex_fire(2, 0)
	_check(s.fire_target_q == 2 and s.fire_target_r == 0, "bersaglio del fuoco impostato")
	_check(s.fire_group_ids.size() >= 2, "gruppo iniziale con più pezzi idonei (%d)" % s.fire_group_ids.size())
	var before := s.fire_group_ids.size()

	Game.toggle_fire_piece("s2")
	_check(s.fire_group_ids.size() == before - 1, "pezzo escluso dal gruppo")
	_check(not s.fire_group_ids.has("s2"), "s2 fuori dal gruppo")
	Game.toggle_fire_piece("s2")
	_check(s.fire_group_ids.size() == before, "pezzo re-incluso")
	Game.toggle_fire_piece("b")
	_check(s.fire_group_ids.has("b"), "il pezzo base non si può escludere")

	Game.confirm_fire()
	_check(s.phase == Domain.Phase.PLAYER_TURN, "dopo il fuoco → PLAYER_TURN")
	_check(s.fire_target_q == -1 and s.fire_group_ids.is_empty(), "assemblaggio azzerato dopo il fuoco")
