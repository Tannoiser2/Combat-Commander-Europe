## Scena di gioco: HUD in sovrimpressione sulla mappa.
extends Control


# ─── Nodi ─────────────────────────────────────────────────────────────────────

@onready var hex_map: Node2D = $HexMap
@onready var log_list: ItemList = $LogPanel/LogList
@onready var phase_label: Label = $TopBar/HBox/PhaseLabel
@onready var turn_label: Label = $TopBar/HBox/TurnLabel
@onready var init_label: Label = $TopBar/HBox/InitLabel
@onready var time_label: Label = $TopBar/HBox/TimeLabel
@onready var vp_label: Label = $TopBar/HBox/VPLabel
@onready var deck_label: Label = $TopBar/HBox/DeckLabel
@onready var menu_btn: Button = $TopBar/HBox/MenuBtn
@onready var unit_info: Panel = $UnitInfo
@onready var info_label: RichTextLabel = $UnitInfo/Margin/InfoLabel
@onready var hand_container: HBoxContainer = $BottomBar/HBox/Cards
@onready var end_turn_btn: Button = $BottomBar/HBox/EndTurnBtn


func _ready() -> void:
	# Se si arriva qui senza passare dal menù, avvia una partita predefinita.
	if Game.state == null:
		Game.start_new_game(Domain.Faction.GERMAN)
	_connect_signals()
	_refresh_ui()
	# Riempi il registro con le righe già accumulate
	for line in Game.state.log:
		log_list.add_item(line)


func _connect_signals() -> void:
	Game.state_changed.connect(_refresh_ui)
	Game.log_added.connect(_on_log_added)
	Game.phase_changed.connect(_on_phase_changed)
	Game.game_over.connect(_on_game_over)
	end_turn_btn.pressed.connect(_on_end_turn)
	menu_btn.pressed.connect(_on_menu)


# ─── Salvataggio rapido (F5 salva, F9 carica) ─────────────────────────────────

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_F5:
			Game.save_game()
			get_viewport().set_input_as_handled()
		KEY_F9:
			if Game.load_game():
				_refresh_ui()
			get_viewport().set_input_as_handled()


# ─── Aggiornamento UI ─────────────────────────────────────────────────────────

func _refresh_ui() -> void:
	if Game.state == null:
		return
	var s := Game.state
	phase_label.text = Domain.PHASE_LABELS.get(s.phase, "—")
	turn_label.text = "Turno %d" % s.turn_number
	init_label.text = "Iniz: %s" % Domain.FACTION_SHORT.get(s.initiative_holder, "—")
	# Traccia del Tempo verso la Morte Subitanea (blocchi pieni/vuoti)
	var sd: int = s.sudden_death_space
	var filled: int = clampi(s.time_marker, 0, sd)
	time_label.text = "Tempo %s %d/%d" % [
		"▰".repeat(filled) + "▱".repeat(max(0, sd - filled)), s.time_marker, sd
	]
	# Bilancia VP (positivo = Germania avanti)
	var leader := "GER" if s.vp_tracker > 0 else ("RUS" if s.vp_tracker < 0 else "—")
	vp_label.text = "VP %+d (%s)" % [s.vp_tracker, leader]
	deck_label.text = "Mazzi  GER:%d  RUS:%d" % [
		s.german_deck.size(), s.russian_deck.size()
	]
	end_turn_btn.disabled = s.phase != Domain.Phase.PLAYER_TURN
	_refresh_hand()
	_refresh_unit_info()


func _refresh_unit_info() -> void:
	var s := Game.state
	var u := s.unit_by_id(s.selected_unit_id) if s.selected_unit_id != "" else null
	if u == null:
		unit_info.visible = false
		return
	unit_info.visible = true
	var fac: String = Domain.FACTION_SHORT.get(u.faction, "?")
	var cls: String = Domain.UNIT_CLASS_LABEL.get(u.unit_class, "")
	var lines := "[b]%s[/b]  (%s)\n" % [u.unit_name, fac]
	lines += "%s\n" % cls
	lines += "PdF %d   Gittata %d   Movimento %d\n" % [u.fp, u.range, u.move]
	lines += "Morale %d" % u.morale
	if u.is_leader():
		lines += "   Comando %d" % u.command
	if u.is_weapon():
		lines += "   (malus mov. %d)" % u.move_penalty
	var stato: Array[String] = []
	if not u.efficient: stato.append("rotta")
	if u.suppressed: stato.append("soppressa")
	if u.activated: stato.append("attivata")
	if stato.size() > 0:
		lines += "\n[i]%s[/i]" % ", ".join(stato)
	info_label.text = lines


func _refresh_hand() -> void:
	for child in hand_container.get_children():
		child.queue_free()
	if Game.state == null:
		return
	var hand := Game.state.hand_of(Game.state.human_faction)
	for i in hand.size():
		var card: Card = hand[i]
		var tb := TextureButton.new()
		tb.texture_normal = load(card.face_path())
		tb.ignore_texture_size = true
		tb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		tb.custom_minimum_size = Vector2(78, 108)
		tb.tooltip_text = "Sx: %s  ·  Dx: %s" % [
			Domain.ORDER_LABELS.get(card.order, card.order_label), card.action_name
		]
		tb.pressed.connect(_on_card_pressed.bind(i))
		tb.gui_input.connect(_on_card_input.bind(i))
		hand_container.add_child(tb)


func _on_log_added(line: String) -> void:
	log_list.add_item(line)
	log_list.ensure_current_is_visible()
	while log_list.item_count > 60:
		log_list.remove_item(0)


func _on_phase_changed(phase: int) -> void:
	phase_label.text = Domain.PHASE_LABELS.get(phase, "—")
	end_turn_btn.disabled = phase != Domain.Phase.PLAYER_TURN


func _on_end_turn() -> void:
	Game._end_player_turn()


func _on_card_pressed(index: int) -> void:
	Game.play_card(index)


## Click destro su una carta = gioca l'AZIONE (banda inferiore) invece dell'ordine.
func _on_card_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		Game.play_action(index)


func _on_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")


func _on_game_over(winner: int) -> void:
	var fname: String = Domain.FACTION_NAMES.get(winner, "PAREGGIO")
	var dlg := AcceptDialog.new()
	dlg.title = "Fine Partita"
	dlg.dialog_text = "Vincitore: %s" % fname
	add_child(dlg)
	dlg.popup_centered()
