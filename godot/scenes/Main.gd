## Scena di gioco: HUD in sovrimpressione sulla mappa.
extends Control


# ─── Nodi ─────────────────────────────────────────────────────────────────────

@onready var hex_map: Node2D = $HexMap
@onready var log_list: ItemList = $LogPanel/LogList
@onready var phase_label: Label = $TopBar/HBox/PhaseLabel
@onready var turn_label: Label = $TopBar/HBox/TurnLabel
@onready var vp_label: Label = $TopBar/HBox/VPLabel
@onready var menu_btn: Button = $TopBar/HBox/MenuBtn
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


# ─── Aggiornamento UI ─────────────────────────────────────────────────────────

func _refresh_ui() -> void:
	if Game.state == null:
		return
	var s := Game.state
	phase_label.text = Domain.PHASE_LABELS.get(s.phase, "—")
	turn_label.text = "Turno %d" % s.turn_number
	vp_label.text = "VP: %+d" % s.vp_tracker
	end_turn_btn.disabled = s.phase != Domain.Phase.PLAYER_TURN
	_refresh_hand()


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
		tb.tooltip_text = "%s — %s" % [
			Domain.ORDER_LABELS.get(card.order, card.order_label), card.action_name
		]
		tb.pressed.connect(_on_card_pressed.bind(i))
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


func _on_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")


func _on_game_over(winner: int) -> void:
	var fname: String = Domain.FACTION_NAMES.get(winner, "PAREGGIO")
	var dlg := AcceptDialog.new()
	dlg.title = "Fine Partita"
	dlg.dialog_text = "Vincitore: %s" % fname
	add_child(dlg)
	dlg.popup_centered()
