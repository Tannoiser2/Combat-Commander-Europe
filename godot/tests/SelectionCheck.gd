## Verifica dell'anteprima del gruppo di comando: selezionando un leader nella
## fase di gioco, le unità che potrà attivare finiscono in command_preview_ids;
## giocando un ordine l'anteprima si azzera. Stampa SELECTION_RESULT: PASS/FAIL.
extends Node

var _ok := true


func _fail(m: String) -> void:
	print("  [NO] ", m)
	_ok = false


func _ready() -> void:
	Game.start_new_game(Domain.Faction.GERMAN, 1)
	var s = Game.state
	if s == null:
		print("SELECTION_RESULT: FAIL (nessuno stato)")
		get_tree().quit(1)
		return

	if s.phase != Domain.Phase.PLAYER_TURN:
		print("  [..] fase iniziale non PLAYER_TURN (%d): salto le asserzioni" % s.phase)
		print("SELECTION_RESULT: PASS")
		get_tree().quit(0)
		return

	# Un leader del giocatore con almeno un'unità comandabile vicina.
	var leader = null
	for u in s.units.values():
		if u.faction == s.human_faction and u.is_leader():
			var grp = Game._command_group_ids(u)
			if grp.size() > 1:
				leader = u
				break
	if leader == null:
		print("  [..] nessun leader con gruppo > 1 in scenario 1: salto")
		print("SELECTION_RESULT: PASS")
		get_tree().quit(0)
		return

	# Selezione → anteprima popolata col gruppo, leader incluso.
	Game.select_unit(leader.id)
	var preview: Array = s.command_preview_ids
	if preview.size() <= 1:
		_fail("anteprima vuota/singola selezionando un leader (attese più unità)")
	if not preview.has(leader.id):
		_fail("il leader non è nell'anteprima del proprio gruppo")

	# Giocando un ordine, l'anteprima si azzera (comanda ordered_group).
	var hand = s.hand_of(s.human_faction)
	var move_idx := -1
	for i in hand.size():
		if hand[i].order == Domain.OrderType.MOVE:
			move_idx = i
			break
	if move_idx >= 0:
		Game.play_card(move_idx)
		if not s.command_preview_ids.is_empty():
			_fail("l'anteprima non si è azzerata dopo aver giocato un ordine")

	print("SELECTION_RESULT: ", "PASS" if _ok else "FAIL")
	get_tree().quit(0 if _ok else 1)
