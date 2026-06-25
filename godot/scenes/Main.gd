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
@onready var hint_label: Label = $Hint
@onready var unit_info: Panel = $UnitInfo
@onready var info_label: RichTextLabel = $UnitInfo/Margin/InfoLabel
@onready var hand_container: HBoxContainer = $HandPanel/VBox/Cards
@onready var end_turn_btn: Button = $HandPanel/VBox/Header/EndTurnBtn
@onready var hand_toggle_btn: Button = $HandPanel/VBox/Header/ToggleBtn

var _hand_collapsed := false


var _legend: Panel = null


func _ready() -> void:
	# Se si arriva qui senza passare dal menù, avvia una partita predefinita.
	if Game.state == null:
		Game.start_new_game(Domain.Faction.GERMAN)
	_connect_signals()
	_build_legend()
	_build_view3d_button()
	_refresh_ui()
	# Riempi il registro con le righe già accumulate
	for line in Game.state.log:
		log_list.add_item(line)


var _v3d: SubViewportContainer = null
var _board3d: Node = null
var _view3d_btn: Button = null


## Vista 3D embeddata (SubViewport) + pulsante di toggle in alto a destra.
func _build_view3d_button() -> void:
	# Contenitore 3D a tutto schermo, dietro alla HUD.
	_v3d = SubViewportContainer.new()
	_v3d.set_anchors_preset(Control.PRESET_FULL_RECT)
	_v3d.stretch = true
	_v3d.visible = false
	add_child(_v3d)
	move_child(_v3d, hex_map.get_index() + 1)  # subito sopra la 2D, sotto la HUD
	var sub := SubViewport.new()
	sub.transparent_bg = false
	_v3d.add_child(sub)
	_board3d = load("res://scenes/Map3D.tscn").instantiate()
	_board3d.active = false
	sub.add_child(_board3d)

	_view3d_btn = Button.new()
	_view3d_btn.text = "⬚ Vista 3D"
	_view3d_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_view3d_btn.offset_left = -150
	_view3d_btn.offset_top = 40
	_view3d_btn.offset_right = -12
	_view3d_btn.pressed.connect(func() -> void: _set_3d(not _v3d.visible))
	add_child(_view3d_btn)


## Mostra/nasconde la mappa 3D (alternativa alla 2D). La HUD resta sopra entrambe.
func _set_3d(on: bool) -> void:
	if _v3d == null:
		return
	_v3d.visible = on
	hex_map.visible = not on
	if _board3d != null:
		_board3d.active = on
		if on:
			_board3d.refresh()
	if _view3d_btn != null:
		_view3d_btn.text = "▣ Vista 2D" if on else "⬚ Vista 3D"


## Legenda dei simboli della mappa (toggle col tasto «L»), creata via codice per
## non modificare la scena.
func _build_legend() -> void:
	_legend = Panel.new()
	_legend.visible = false
	_legend.position = Vector2(12, 90)
	_legend.size = Vector2(290, 196)
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content = true
	lbl.scroll_active = false
	lbl.add_theme_constant_override("margin_left", 10)
	lbl.add_theme_constant_override("margin_top", 8)
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.text = "[b]Legenda (L per chiudere)[/b]\n" \
		+ "T / C / B  Trincea / Casamatta / Bunker\n" \
		+ "≋  Filo spinato    ✸  Mine\n" \
		+ "✷  Esagono in fiamme (impassabile)\n" \
		+ "[color=#cfc]riempimento verde[/color]  buca/foxhole\n" \
		+ "[color=#ccd]nube grigia[/color]  fumo (hindrance)\n" \
		+ "[color=#f55]anello rosso[/color]  impatto d'artiglieria\n" \
		+ "gettone con numero  obiettivo (VP)\n" \
		+ "bordo arancio  esagono selezionabile"
	_legend.add_child(lbl)
	add_child(_legend)


func _connect_signals() -> void:
	Game.state_changed.connect(_refresh_ui)
	Game.log_added.connect(_on_log_added)
	Game.phase_changed.connect(_on_phase_changed)
	Game.game_over.connect(_on_game_over)
	end_turn_btn.pressed.connect(_on_end_turn)
	hand_toggle_btn.pressed.connect(_toggle_hand)
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
		KEY_M:
			Game._log("Audio %s." % ("attivo" if Audio.toggle_mute() else "muto"))
			get_viewport().set_input_as_handled()
		KEY_C:
			_toggle_hand()
			get_viewport().set_input_as_handled()
		KEY_L:  # legenda dei simboli della mappa
			if _legend != null:
				_legend.visible = not _legend.visible
			get_viewport().set_input_as_handled()
		KEY_3:  # mostra la mappa 3D
			_set_3d(true)
			get_viewport().set_input_as_handled()
		KEY_2:  # torna alla mappa 2D
			_set_3d(false)
			get_viewport().set_input_as_handled()
		KEY_SPACE:
			if Game.state != null and Game.state.phase == Domain.Phase.REACTION_WINDOW:
				Game.opfire_decline()
				get_viewport().set_input_as_handled()
		KEY_X:  # uscita dal bordo avversario (7.2): VP al proprietario
			if Game.can_exit_selected():
				Game.exit_selected_unit()
				_refresh_ui()
				get_viewport().set_input_as_handled()
		KEY_S:  # durante l'artiglieria: alterna barrage esplosivo/fumogeno
			if Game.state != null and Game.state.current_order == Domain.OrderType.ARTY:
				Game.toggle_artillery_smoke()
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
	end_turn_btn.disabled = not _is_player_phase(s.phase)
	hint_label.text = _guidance_text(s)
	_refresh_hand()
	_refresh_unit_info()


## È un momento in cui il giocatore umano può agire/concludere il turno?
func _is_player_phase(phase: int) -> bool:
	return phase == Domain.Phase.PLAYER_TURN or phase == Domain.Phase.PLAYER_MOVING


## Istruzione contestuale mostrata nel banner guida (cosa fare adesso).
func _guidance_text(s: GameState) -> String:
	match s.phase:
		Domain.Phase.PLAYER_TURN:
			var ord := "  (ordini %d/%d)" % [s.order_count, s.max_orders]
			var arty := "  · 📻 Artiglieria pronta" if Game.has_artillery_available() else ""
			if s.order_count >= s.max_orders:
				return "Ordini esauriti%s — gioca un'Azione (dx) o premi «Fine Turno»" % ord
			if s.selected_unit_id != "":
				return "Unità scelta%s — gioca una carta:  Sx = ordine · Dx = azione%s" % [ord, arty]
			return "Il tuo turno%s — clicca un'unità, poi gioca una carta ordine%s" % [ord, arty]
		Domain.Phase.PLAYER_MOVING:
			var has_unit := s.selected_unit_id != ""
			if Game.can_exit_selected():
				return "MOSSA — sul bordo avversario: «X» per USCIRE (VP) · o un esagono giallo"
			match s.current_order:
				Domain.OrderType.MOVE:
					var n := s.ordered_group.size()
					if not has_unit:
						if n > 1:
							return "MOSSA DI GRUPPO — scegli il prossimo membro (arancio) o «Fine Turno»"
						return "MOSSA — clicca l'unità (o il leader) da muovere"
					var pm := int(s.group_mp.get(s.selected_unit_id, 0))
					if n > 1:
						return "MOSSA DI GRUPPO (%d) — PM %d · il numero sull'esagono = costo · membro arancio per cambiare · l'unità attiva per concludere" % [n, pm]
					if s.move_committed:
						return "MOSSA — PM %d · clicca un esagono (il numero = costo) · l'unità per concludere" % pm
					return "MOSSA — PM %d · clicca un esagono (il numero = costo) · l'unità per annullare" % pm
				Domain.OrderType.FIRE:
					if s.fire_target_q >= 0:
						var pv := Game.fire_preview()
						var msg := "FUOCO — squadra %d · FP %d" % [s.fire_group_ids.size(), int(pv.get("fp", 0))]
						if int(pv.get("defense", -1)) >= 0:
							msg += " vs DIF %d (cop %d) → %s" % [
								int(pv["defense"]), int(pv["cover"]), pv.get("verdict", "")]
						msg += " · pezzo arancio = aggiungi/togli · dx carta = modificatore · clicca il BERSAGLIO per sparare"
						if not s.fire_modifiers.is_empty():
							msg += "  [%s]" % ", ".join(s.fire_modifiers)
						if s.spray_active:
							msg += "  [SVENTAGLIATA]"
						return msg
					if not has_unit:
						return "FUOCO — clicca l'unità che spara"
					return "FUOCO — clicca un bersaglio nemico evidenziato (apparirà la linea di tiro) · l'unità per annullare"
				Domain.OrderType.ADVANCE:
					if not has_unit:
						return "AVANZATA — clicca l'unità che avanza"
					return "AVANZATA — clicca un esagono adiacente · l'unità per annullare"
				Domain.OrderType.ARTY:
					var mode := "FUMO" if s.artillery_smoke else "esplosivo"
					return "🎯 ARTIGLIERIA [%s] — clicca il bersaglio (giallo) nella LOS · «S» = fumo/esplosivo · lo spotter per annullare" % mode
				_:
					return "Clicca un'unità sulla mappa"
		Domain.Phase.REACTION_WINDOW:
			return "⚡ FUOCO DI OPPORTUNITÀ — clicca un tiratore (giallo) per sparare · altrove o SPAZIO = non sparare"
		_:
			return Domain.PHASE_LABELS.get(s.phase, "")


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
	# PM rimasti quando l'unità fa parte del gruppo che sta muovendo.
	if s.phase == Domain.Phase.PLAYER_MOVING and s.current_order == Domain.OrderType.MOVE \
			and s.group_mp.has(u.id):
		lines += "\n[color=#ffd24a]PM rimasti: %d / %d[/color]" % [
			int(s.group_mp[u.id]), Rules.move_with_command(s, u)]
	var stato: Array[String] = []
	if not u.efficient: stato.append("rotta")
	if u.suppressed: stato.append("soppressa")
	if u.activated: stato.append("attivata")
	if stato.size() > 0:
		lines += "\n[i]%s[/i]" % ", ".join(stato)
	# Info dell'esagono occupato: terreno + copertura + marker.
	var hd: GameState.HexData = s.hex_at(u.q, u.r)
	if hd != null:
		var terr: String = Domain.TERRAIN_NAMES.get(hd.terrain, "?")
		var cov := Rules.cover_at(s, u.q, u.r, false)
		var feats: Array[String] = []
		if hd.fortification != Domain.Fort.NONE:
			feats.append(Domain.FORT_NAMES.get(hd.fortification, "?"))
		if hd.has_foxhole: feats.append("buca")
		if hd.has_smoke: feats.append("fumo")
		if hd.has_blaze: feats.append("incendio")
		var ftxt := "  · " + ", ".join(feats) if feats.size() > 0 else ""
		lines += "\n[color=#9fd]%s (cop. %d)%s[/color]" % [terr, cov, ftxt]
	info_label.text = lines


func _refresh_hand() -> void:
	for child in hand_container.get_children():
		child.queue_free()
	if Game.state == null:
		return
	hand_toggle_btn.text = "▲ Carte (%d)" % Game.state.hand_of(Game.state.human_faction).size() if _hand_collapsed \
		else "▼ Carte (%d)" % Game.state.hand_of(Game.state.human_faction).size()
	hand_container.visible = not _hand_collapsed
	if _hand_collapsed:
		return
	var hand := Game.state.hand_of(Game.state.human_faction)
	for i in hand.size():
		var card: Card = hand[i]
		var tb := TextureButton.new()
		tb.texture_normal = load(card.face_path())
		tb.ignore_texture_size = true
		tb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		tb.custom_minimum_size = Vector2(124, 174)
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
	end_turn_btn.disabled = not _is_player_phase(phase)
	if Game.state:
		hint_label.text = _guidance_text(Game.state)


func _on_end_turn() -> void:
	var s := Game.state
	# Se è in corso un ordine non risolto, concludilo/annullalo prima di passare.
	if s != null and s.phase == Domain.Phase.PLAYER_MOVING:
		if s.current_order == Domain.OrderType.MOVE and s.moving_unit_id != "":
			Game.finish_move()
		else:
			Game.cancel_order()
	Game._end_player_turn()


func _on_card_pressed(index: int) -> void:
	Game.play_card(index)


## Click destro su una carta = gioca l'AZIONE; durante l'assemblaggio del fuoco
## applica invece il modificatore di fuoco (Mirato/Sostenuto/Incrociato/Sventagliata);
## durante una Mossa, una carta FUOCO D'ASSALTO spara col pezzo in movimento (A26).
func _on_card_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		var s := Game.state
		if s == null:
			return
		var hand := s.hand_of(s.human_faction)
		var name := hand[index].action_name if index >= 0 and index < hand.size() else ""
		if s.current_order == Domain.OrderType.FIRE and s.fire_target_q >= 0:
			Game.apply_fire_modifier(index)
		elif s.phase == Domain.Phase.PLAYER_MOVING and s.current_order == Domain.OrderType.MOVE \
				and name == "FUOCO D'ASSALTO":
			Game.assault_fire(index)
			_refresh_ui()
		else:
			Game.play_action(index)


## Mostra/nasconde la fila carte (il pannello si riduce all'header) per liberare
## la mappa. Le carte restano giocabili appena riaperto.
func _toggle_hand() -> void:
	_hand_collapsed = not _hand_collapsed
	_refresh_hand()


func _on_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")


func _on_game_over(winner: int) -> void:
	var fname: String = Domain.FACTION_NAMES.get(winner, "PAREGGIO")
	var dlg := AcceptDialog.new()
	dlg.title = "Fine Partita"
	dlg.dialog_text = "Vincitore: %s" % fname
	add_child(dlg)
	dlg.popup_centered()
