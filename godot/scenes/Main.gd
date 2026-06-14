## Scena radice: layout UI, pannello log, mano di carte, HUD fase.
extends Control


# ─── Nodi (collegati in _ready via $path) ────────────────────────────────────

@onready var hex_map: Node2D = $HexMap
@onready var log_list: ItemList = $UI/VBox/LogPanel/LogList
@onready var phase_label: Label = $UI/VBox/TopBar/PhaseLabel
@onready var turn_label: Label = $UI/VBox/TopBar/TurnLabel
@onready var hand_container: HBoxContainer = $UI/VBox/Hand/Cards
@onready var end_turn_btn: Button = $UI/VBox/Hand/EndTurnBtn
@onready var vp_label: Label = $UI/VBox/TopBar/VPLabel


func _ready() -> void:
	Game.start_new_game(Domain.Faction.GERMAN)
	_connect_signals()
	_refresh_ui()


func _connect_signals() -> void:
	Game.state_changed.connect(_refresh_ui)
	Game.log_added.connect(_on_log_added)
	Game.phase_changed.connect(_on_phase_changed)
	Game.game_over.connect(_on_game_over)
	end_turn_btn.pressed.connect(_on_end_turn)


# ─── Aggiornamento UI ─────────────────────────────────────────────────────────

func _refresh_ui() -> void:
	if Game.state == null:
		return
	var s := Game.state
	phase_label.text = Domain.PHASE_LABELS.get(s.phase, "—")
	turn_label.text = "Turno %d" % s.turn_number
	vp_label.text = "VP: %+d" % s.vp_tracker
	_refresh_hand()


func _refresh_hand() -> void:
	for child in hand_container.get_children():
		child.queue_free()
	if Game.state == null:
		return
	var hand := Game.state.hand_of(Game.state.human_faction)
	for i in hand.size():
		var card: Card = hand[i]
		var btn := Button.new()
		btn.text = "%s\n[%s]" % [card.card_name, Domain.ORDER_LABELS.get(card.order, "?")]
		btn.custom_minimum_size = Vector2(90, 64)
		btn.pressed.connect(_on_card_pressed.bind(i))
		hand_container.add_child(btn)


func _on_log_added(line: String) -> void:
	log_list.add_item(line)
	log_list.ensure_current_is_visible()
	# Mantieni al massimo 60 righe
	while log_list.item_count > 60:
		log_list.remove_item(0)


func _on_phase_changed(phase: int) -> void:
	phase_label.text = Domain.PHASE_LABELS.get(phase, "—")
	end_turn_btn.disabled = phase != Domain.Phase.PLAYER_TURN


func _on_end_turn() -> void:
	Game._end_player_turn()


func _on_card_pressed(index: int) -> void:
	Game.play_card(index)


func _on_game_over(winner: int) -> void:
	var name := Domain.FACTION_NAMES.get(winner, "PAREGGIO")
	var dlg := AcceptDialog.new()
	dlg.title = "Fine Partita"
	dlg.dialog_text = "Vincitore: %s" % name
	add_child(dlg)
	dlg.popup_centered()
