## Scena di gioco: HUD in sovrimpressione sulla mappa.
extends Control


# ─── Nodi ─────────────────────────────────────────────────────────────────────

@onready var hex_map: Node2D = $HexMap
@onready var log_panel: PanelContainer = $LogPanel
@onready var log_list: ItemList = $LogPanel/LogVBox/LogList
@onready var log_toggle_btn: Button = $LogPanel/LogVBox/LogHeader/LogToggleBtn
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
var _help: Panel = null
var _log_collapsed := false
var _log_reopen_btn: Button = null

# «Passa» (O15): pulsante nell'header + finestra per scegliere le carte da scartare.
var _pass_btn: Button = null
var _pass_dialog: Panel = null
var _pass_cards: HBoxContainer = null
var _pass_confirm: Button = null
var _pass_marked: Dictionary = {}  # indice carta → true se da scartare


func _ready() -> void:
	# Se si arriva qui senza passare dal menù, avvia una partita predefinita.
	if Game.state == null:
		Game.start_new_game(Domain.Faction.GERMAN)
	_connect_signals()
	_build_legend()
	_build_view3d_button()
	_build_los_button()
	_build_help_panel()
	_build_log_reopen()
	_build_pass_ui()
	log_toggle_btn.pressed.connect(_toggle_log)
	end_turn_btn.tooltip_text = "Concludi il turno e passa all'avversario (anche a ordini finiti)"
	_refresh_ui()
	# Riempi il registro con le righe già accumulate
	for line in Game.state.log:
		log_list.add_item(line)


var _v3d: SubViewportContainer = null
var _los_btn: Button = null
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
	_view3d_btn.text = "Vista 3D"
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
		_view3d_btn.text = "Vista 2D" if on else "Vista 3D"


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
		+ "#  Filo spinato    *  Mine\n" \
		+ "*  Esagono in fiamme (impassabile)\n" \
		+ "[color=#cfc]riempimento verde[/color]  buca/foxhole\n" \
		+ "[color=#ccd]nube grigia[/color]  fumo (hindrance)\n" \
		+ "[color=#f55]anello rosso[/color]  impatto d'artiglieria\n" \
		+ "gettone con numero  obiettivo (VP)\n" \
		+ "bordo arancio  esagono selezionabile"
	_legend.add_child(lbl)
	add_child(_legend)


## Pannello "Come si gioca": un pulsante nell'header della mano e il tasto «H» lo
## aprono/chiudono. Riassume selezione, carte, mossa, fuoco e tasti rapidi.
func _build_help_panel() -> void:
	var btn := Button.new()
	btn.text = "Comandi"
	btn.tooltip_text = "Come si gioca: selezione, carte, mossa, fuoco, tasti (anche col tasto «H»)"
	btn.custom_minimum_size = Vector2(96, 0)
	btn.pressed.connect(func() -> void:
		if _help != null:
			_help.visible = not _help.visible)
	# Insieme al Registro: nell'intestazione della colonna del registro.
	var header: HBoxContainer = $LogPanel/LogVBox/LogHeader
	header.add_child(btn)
	header.move_child(btn, 1)  # tra il titolo «Registro» e «Nascondi»

	_help = Panel.new()
	_help.visible = false
	_help.set_anchors_preset(Control.PRESET_CENTER)
	_help.offset_left = -300
	_help.offset_top = -260
	_help.offset_right = 300
	_help.offset_bottom = 260
	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.scroll_active = true
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.add_theme_constant_override("margin_left", 16)
	lbl.add_theme_constant_override("margin_top", 12)
	lbl.add_theme_constant_override("margin_right", 16)
	lbl.add_theme_constant_override("margin_bottom", 12)
	lbl.text = _help_text()
	_help.add_child(lbl)
	add_child(_help)


func _help_text() -> String:
	return "[b]COME SI GIOCA[/b]   (pulsante «Comandi» o tasto «H» per chiudere)\n\n" \
		+ "[b]Selezione[/b]\n" \
		+ " - Clicca un'unità per selezionarla; ri-clicca l'esagono per scorrere le pedine impilate.\n" \
		+ " - In basso a sinistra compare la scheda dell'unità.\n\n" \
		+ "[b]Carte (in basso)[/b]\n" \
		+ " - Click [b]SINISTRO[/b] = gioca la metà [color=#7fb0ff]ORDINE[/color] (banda blu in alto: Muovere, Fuoco, Avanzata...).\n" \
		+ " - Click [b]DESTRO[/b] = gioca la metà [color=#ffae5a]AZIONE[/color] (banda arancio in basso: Granate, Cecchino, modificatori...).\n\n" \
		+ "[b]Mossa[/b]\n" \
		+ " - Un leader trascina le unità entro il suo Comando (alone arancione).\n" \
		+ " - Il numero sull'esagono = Punti Movimento per entrarci (verde = pochi, rosso = molti).\n" \
		+ " - Clicca di nuovo l'unità attiva per concludere la sua mossa.\n\n" \
		+ "[b]Fuoco[/b]\n" \
		+ " - Clicca un bersaglio evidenziato: la linea rossa mostra chi spara a chi.\n" \
		+ " - La targhetta sul bersaglio = FP d'attacco vs Difesa stimata, con l'esito.\n" \
		+ " - Click su un pezzo arancione = aggiungilo/toglilo dalla squadra di fuoco.\n\n" \
		+ "[b]Avanzata / Artiglieria[/b]\n" \
		+ " - Avanzata: clicca un esagono adiacente (può scatenare il corpo a corpo).\n" \
		+ " - Artiglieria: serve Radio + spotter; clicca il bersaglio nella LOS. «S» alterna fumo/esplosivo.\n\n" \
		+ "[b]Armi[/b]\n" \
		+ " - Ogni arma è «portata» da un'unità (vedi la scheda); spara insieme al portatore.\n" \
		+ " - Durante una Mossa, «G» passa l'arma a un compagno nello stesso esagono, o ne raccoglie una a terra (1 PM).\n" \
		+ " - Un'arma a terra (senza portatore) ha un anello giallo sulla mappa.\n\n" \
		+ "[b]Passare / finire il turno[/b]\n" \
		+ " - «Passa» (tasto «P»): non dai ordini — scegli quali carte scartare e ne ripeschi altrettante (O15).\n" \
		+ " - «Fine Turno»: concludi e passa all'avversario (anche a ordini finiti).\n\n" \
		+ "[b]Tasti rapidi[/b]\n" \
		+ " - L = legenda mappa    2 / 3 = vista 2D / 3D    C = carte    R = registro    V = LOS    P = passa\n" \
		+ " - X = esci dal bordo nemico (VP)    S = fumo/esplosivo    SPAZIO = non sparare\n" \
		+ " - F5 = salva    F9 = carica    M = muto    H = questo aiuto"


## Un badge della mano (Ordine o Azione) come bottone-immagine. `lit` = giocabile
## ora → colori pieni e cliccabile; altrimenti spento (grigio) e disabilitato.
## Se il badge grafico manca, ripiega su un bottone testuale.
func _make_badge(path: String, fallback_text: String, lit: bool, width: float) -> BaseButton:
	var tex: Texture2D = load(path) if path != "" and ResourceLoader.exists(path) else null
	if tex == null:
		var b := Button.new()
		b.text = fallback_text
		b.disabled = not lit
		b.focus_mode = Control.FOCUS_NONE
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(width, width * 0.33)
		return b
	var tb := TextureButton.new()
	tb.texture_normal = tex
	tb.ignore_texture_size = true
	tb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	tb.focus_mode = Control.FOCUS_NONE
	var ar := float(tex.get_height()) / float(tex.get_width())
	tb.custom_minimum_size = Vector2(width, width * ar)
	tb.disabled = not lit
	# Illuminato quando giocabile; spento (grigio scuro) quando non si può giocare.
	tb.modulate = Color(1, 1, 1, 1.0) if lit else Color(0.42, 0.42, 0.48, 0.92)
	return tb


## La metà AZIONE è giocabile ora? Nel proprio turno sempre; durante un Fuoco con
## bersaglio scelto solo i modificatori; durante una Mossa solo Fuoco d'Assalto.
func _action_playable(card: Card, s: GameState) -> bool:
	if s.phase == Domain.Phase.PLAYER_TURN:
		return true
	if s.phase == Domain.Phase.PLAYER_MOVING:
		if s.current_order == Domain.OrderType.FIRE and s.fire_target_q >= 0:
			return card.action_name in Game.FIRE_MOD_NAMES \
				or card.action_name.begins_with("SVENTAGLIATA")
		if s.current_order == Domain.OrderType.MOVE:
			return card.action_name == "FUOCO D'ASSALTO"
	return false


## Colonna del Registro (a destra) collassabile. Da nascosta, un pulsante
## «Registro» in alto a destra la riapre (anche col tasto «R»).
func _build_log_reopen() -> void:
	_log_reopen_btn = Button.new()
	_log_reopen_btn.text = "Registro"
	_log_reopen_btn.tooltip_text = "Mostra il registro (R)"
	_log_reopen_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_log_reopen_btn.offset_left = -150
	_log_reopen_btn.offset_top = 84
	_log_reopen_btn.offset_right = -12
	_log_reopen_btn.visible = false
	_log_reopen_btn.pressed.connect(_toggle_log)
	add_child(_log_reopen_btn)


func _toggle_log() -> void:
	_log_collapsed = not _log_collapsed
	log_panel.visible = not _log_collapsed
	if _log_reopen_btn != null:
		_log_reopen_btn.visible = _log_collapsed


## Attiva/disattiva la "Modalità LOS": uno strumento per verificare la linea di
## vista tra due esagoni (estremità trascinabili, linea colorata). Inizializza le
## estremità così la linea è subito visibile; funziona sia in 2D sia in 3D.
## Pulsante «LOS» (in alto a destra, a fianco di «Vista 3D») per attivare la
## Modalità LOS senza dover ricordare il tasto «V».
func _build_los_button() -> void:
	_los_btn = Button.new()
	_los_btn.text = "LOS"
	_los_btn.tooltip_text = "Modalità LOS: verifica la linea di vista tra due esagoni (anche col tasto «V»)"
	_los_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_los_btn.offset_left = -296
	_los_btn.offset_top = 40
	_los_btn.offset_right = -158
	_los_btn.pressed.connect(_toggle_los_mode)
	add_child(_los_btn)


func _toggle_los_mode() -> void:
	var s := Game.state
	if s == null:
		return
	s.los_mode = not s.los_mode
	if s.los_mode and (s.los_a.x < 0 or s.los_b.x < 0):
		var u := s.unit_by_id(s.selected_unit_id)
		var a := Vector2i(u.q, u.r) if u != null else Vector2i(int(s.map_cols / 2), int(s.map_rows / 2))
		s.los_a = a
		s.los_b = Vector2i(clampi(a.x + 3, 0, s.map_cols - 1), a.y)
	if _los_btn != null:
		_los_btn.text = "LOS: ON" if s.los_mode else "LOS"
		_los_btn.modulate = Color(0.5, 1.0, 0.6) if s.los_mode else Color(1, 1, 1)
	Game.emit_signal("state_changed")
	_refresh_ui()


## «Passa» (O15): pulsante nell'header della mano (accanto a «Fine Turno») e
## finestra modale per scegliere quali carte scartare prima di passare. Passare
## non dà ordini: si scarta a piacere e si ripesca altrettante carte.
func _build_pass_ui() -> void:
	_pass_btn = Button.new()
	_pass_btn.text = "Passa"
	_pass_btn.custom_minimum_size = Vector2(110, 0)
	_pass_btn.tooltip_text = "Passa senza dare ordini: scegli quante carte scartare e ripescare (tasto «P»)"
	_pass_btn.pressed.connect(_open_pass_dialog)
	var header: HBoxContainer = $HandPanel/VBox/Header
	header.add_child(_pass_btn)
	header.move_child(_pass_btn, end_turn_btn.get_index())  # appena prima di «Fine Turno»

	_pass_dialog = Panel.new()
	_pass_dialog.visible = false
	_pass_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_pass_dialog.offset_left = -340
	_pass_dialog.offset_top = -190
	_pass_dialog.offset_right = 340
	_pass_dialog.offset_bottom = 190
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 10)
	vb.offset_left = 16
	vb.offset_top = 14
	vb.offset_right = -16
	vb.offset_bottom = -14
	var title := Label.new()
	title.text = "Passa il turno (O15)"
	title.add_theme_font_size_override("font_size", 20)
	vb.add_child(title)
	var desc := Label.new()
	desc.text = "Seleziona le carte da scartare: ne ripeschi altrettante. Passare non dà ordini."
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(desc)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_pass_cards = HBoxContainer.new()
	_pass_cards.add_theme_constant_override("separation", 10)
	scroll.add_child(_pass_cards)
	vb.add_child(scroll)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 10)
	_pass_confirm = Button.new()
	_pass_confirm.pressed.connect(_on_pass_confirm)
	var cancel := Button.new()
	cancel.text = "Annulla"
	cancel.pressed.connect(_close_pass_dialog)
	actions.add_child(cancel)
	actions.add_child(_pass_confirm)
	vb.add_child(actions)
	_pass_dialog.add_child(vb)
	add_child(_pass_dialog)


func _open_pass_dialog() -> void:
	var s := Game.state
	if s == null or s.phase != Domain.Phase.PLAYER_TURN:
		return
	_pass_marked.clear()
	_refresh_pass_cards()
	_update_pass_confirm()
	_pass_dialog.visible = true


func _close_pass_dialog() -> void:
	if _pass_dialog != null:
		_pass_dialog.visible = false


## Riempie la finestra con le carte in mano: ogni carta è la coppia di badge
## (Ordine sopra, Azione sotto) con sotto una casella «scarta».
func _refresh_pass_cards() -> void:
	for child in _pass_cards.get_children():
		child.queue_free()
	var s := Game.state
	var hand := s.hand_of(s.human_faction)
	for i in hand.size():
		var card: Card = hand[i]
		var order_name: String = Domain.ORDER_LABELS.get(card.order, card.order_label)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		var ord_path := ""
		if Domain.ORDER_BADGE.has(card.order):
			ord_path = "res://assets/badges/orders/%s.png" % Domain.ORDER_BADGE[card.order]
		var act_path := ""
		if Domain.ACTION_BADGE.has(card.action_name):
			act_path = "res://assets/badges/actions/%s.png" % Domain.ACTION_BADGE[card.action_name]
		var ob := _make_badge(ord_path, order_name, true, 132.0)
		ob.disabled = true  # qui i badge sono solo anteprima, non si giocano
		ob.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ab := _make_badge(act_path, card.action_name, true, 132.0)
		ab.disabled = true
		ab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(ob)
		col.add_child(ab)
		var chk := CheckBox.new()
		chk.text = "scarta"
		chk.button_pressed = bool(_pass_marked.get(i, false))
		chk.toggled.connect(_on_pass_card_toggled.bind(i))
		col.add_child(chk)
		_pass_cards.add_child(col)


func _on_pass_card_toggled(pressed: bool, index: int) -> void:
	_pass_marked[index] = pressed
	_update_pass_confirm()


func _update_pass_confirm() -> void:
	var n := 0
	for v in _pass_marked.values():
		if v:
			n += 1
	_pass_confirm.text = "Scarta e passa (%d)" % n if n > 0 else "Passa senza scartare"


func _on_pass_confirm() -> void:
	var indices: Array = []
	for k in _pass_marked.keys():
		if _pass_marked[k]:
			indices.append(int(k))
	_close_pass_dialog()
	Game.pass_turn(indices)
	_refresh_ui()


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
		KEY_H:  # pannello d'aiuto: come si gioca / comandi
			if _help != null:
				_help.visible = not _help.visible
			get_viewport().set_input_as_handled()
		KEY_R:  # mostra/nascondi la colonna del Registro
			_toggle_log()
			get_viewport().set_input_as_handled()
		KEY_V:  # Modalità LOS: verifica la linea di vista tra due esagoni
			_toggle_los_mode()
			get_viewport().set_input_as_handled()
		KEY_P:  # Passa (O15): scegli quante carte scartare, poi cedi il turno
			if _pass_dialog != null and _pass_dialog.visible:
				_close_pass_dialog()
			else:
				_open_pass_dialog()
			get_viewport().set_input_as_handled()
		KEY_G:  # trasferisci/raccogli l'arma trasportata (11.3)
			if Game.state != null and Game.state.phase == Domain.Phase.PLAYER_MOVING \
					and Game.state.current_order == Domain.OrderType.MOVE:
				Game.transfer_weapon()
				_refresh_ui()
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
		"#".repeat(filled) + "-".repeat(max(0, sd - filled)), s.time_marker, sd
	]
	# Bilancia VP (positivo = Germania avanti)
	var leader := "GER" if s.vp_tracker > 0 else ("RUS" if s.vp_tracker < 0 else "—")
	vp_label.text = "VP %+d (%s)" % [s.vp_tracker, leader]
	deck_label.text = "Mazzi  GER:%d  RUS:%d" % [
		s.german_deck.size(), s.russian_deck.size()
	]
	end_turn_btn.disabled = not _is_player_phase(s.phase)
	# Passare si può solo nella fase ordini (non a metà di una mossa/fuoco).
	if _pass_btn != null:
		_pass_btn.disabled = s.phase != Domain.Phase.PLAYER_TURN
	hint_label.text = _guidance_text(s)
	_refresh_hand()
	_refresh_unit_info()


## È un momento in cui il giocatore umano può agire/concludere il turno?
func _is_player_phase(phase: int) -> bool:
	return phase == Domain.Phase.PLAYER_TURN or phase == Domain.Phase.PLAYER_MOVING


## Istruzione contestuale mostrata nel banner guida (cosa fare adesso).
func _guidance_text(s: GameState) -> String:
	if s.los_mode:
		return "MODALITÀ LOS — trascina le estremità (o clicca un esagono) · verde = libera · gialla = ostacolata · rossa = bloccata · «V» per uscire"
	match s.phase:
		Domain.Phase.PLAYER_TURN:
			var ord := "  (ordini %d/%d)" % [s.order_count, s.max_orders]
			var arty := "  · Artiglieria pronta" if Game.has_artillery_available() else ""
			if s.order_count >= s.max_orders:
				return "Ordini esauriti%s — gioca un'Azione (dx), «Passa» o «Fine Turno»" % ord
			if s.selected_unit_id != "":
				return "Unità scelta%s — gioca una carta:  Sx = ordine · Dx = azione%s" % [ord, arty]
			return "Il tuo turno%s — clicca un'unità e gioca un ordine, oppure «Passa» (P)%s" % [ord, arty]
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
					var wtip := "  ·  «G» = passa arma" if s.weapon_carried_by(s.selected_unit_id) != null else ""
					if n > 1:
						return "MOSSA DI GRUPPO (%d) — PM %d · il numero sull'esagono = costo · membro arancio per cambiare · l'unità attiva per concludere%s" % [n, pm, wtip]
					if s.move_committed:
						return "MOSSA — PM %d · clicca un esagono (il numero = costo) · l'unità per concludere%s" % [pm, wtip]
					return "MOSSA — PM %d · clicca un esagono (il numero = costo) · l'unità per annullare%s" % [pm, wtip]
				Domain.OrderType.FIRE:
					if s.fire_target_q >= 0:
						var pv := Game.fire_preview()
						var msg := "FUOCO — squadra %d · FP %d" % [s.fire_group_ids.size(), int(pv.get("fp", 0))]
						if int(pv.get("defense", -1)) >= 0:
							msg += " vs DIF %d (cop %d) -> %s" % [
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
					return "ARTIGLIERIA [%s] — clicca il bersaglio (giallo) nella LOS · «S» = fumo/esplosivo · lo spotter per annullare" % mode
				_:
					return "Clicca un'unità sulla mappa"
		Domain.Phase.REACTION_WINDOW:
			return "FUOCO DI OPPORTUNITÀ — clicca un tiratore (giallo) per sparare · altrove o SPAZIO = non sparare"
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
		# Portage (11.2): chi tiene quest'arma, o se è a terra.
		var carrier := s.unit_by_id(u.carrier_id) if u.carrier_id != "" else null
		if carrier != null:
			lines += "\n[color=#bfe0b0]Portata da: %s[/color]" % carrier.unit_name
		else:
			lines += "\n[color=#ffc080]Arma a terra — «G» per raccoglierla[/color]"
	elif u.is_man():
		# Arma eventualmente trasportata da quest'unità.
		var wpn := s.weapon_carried_by(u.id)
		if wpn != null:
			lines += "\n[color=#bfe0b0]Arma: %s (malus PM %d)[/color]" % [wpn.unit_name, wpn.move_penalty]
	# PM rimasti quando l'unità fa parte del gruppo che sta muovendo.
	if s.phase == Domain.Phase.PLAYER_MOVING and s.current_order == Domain.OrderType.MOVE \
			and s.group_mp.has(u.id):
		lines += "\n[color=#ffd24a]PM rimasti: %d / %d[/color]" % [
			int(s.group_mp[u.id]), Rules.move_allowance(s, u)]
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
	var n_cards := Game.state.hand_of(Game.state.human_faction).size()
	hand_toggle_btn.text = "Mostra carte (%d)" % n_cards if _hand_collapsed else "Nascondi carte (%d)" % n_cards
	hand_container.visible = not _hand_collapsed
	if _hand_collapsed:
		return
	var s := Game.state
	# Giocabilità: gli ordini e le azioni si giocano solo nel proprio turno; un
	# ordine "vero" (Mossa/Fuoco/Avanzata/Recupero/Rotta/Artiglieria) richiede
	# ordini ancora disponibili. Le carte non giocabili sono attenuate.
	var is_turn := s.phase == Domain.Phase.PLAYER_TURN
	var orders_left := s.order_count < s.max_orders
	var hand := s.hand_of(s.human_faction)
	for i in hand.size():
		var card: Card = hand[i]
		var order_name: String = Domain.ORDER_LABELS.get(card.order, card.order_label)
		var counts: bool = card.order in [
			Domain.OrderType.MOVE, Domain.OrderType.FIRE, Domain.OrderType.ADVANCE,
			Domain.OrderType.RECOVER, Domain.OrderType.ROUT, Domain.OrderType.ARTY]
		var order_ok := is_turn and (orders_left or not counts)
		var action_ok := _action_playable(card, s)
		# Carta = due badge impilati: Ordine sopra, Azione sotto. Ogni badge è
		# illuminato quando giocabile, spento (grigio) quando no.
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		var ord_path := ""
		if Domain.ORDER_BADGE.has(card.order):
			ord_path = "res://assets/badges/orders/%s.png" % Domain.ORDER_BADGE[card.order]
		var act_path := ""
		if Domain.ACTION_BADGE.has(card.action_name):
			act_path = "res://assets/badges/actions/%s.png" % Domain.ACTION_BADGE[card.action_name]
		var ob := _make_badge(ord_path, order_name, order_ok, 154.0)
		ob.tooltip_text = "ORDINE: %s%s" % [order_name, "" if order_ok else "  —  non giocabile ora"]
		ob.pressed.connect(_on_card_pressed.bind(i))
		var ab := _make_badge(act_path, card.action_name, action_ok, 154.0)
		ab.tooltip_text = "AZIONE: %s%s" % [card.action_name, "" if action_ok else "  —  non giocabile ora"]
		ab.pressed.connect(_on_action_pressed.bind(i))
		col.add_child(ob)
		col.add_child(ab)
		hand_container.add_child(col)


func _on_log_added(line: String) -> void:
	log_list.add_item(line)
	log_list.ensure_current_is_visible()
	while log_list.item_count > 60:
		log_list.remove_item(0)


func _on_phase_changed(phase: int) -> void:
	phase_label.text = Domain.PHASE_LABELS.get(phase, "—")
	end_turn_btn.disabled = not _is_player_phase(phase)
	if _pass_btn != null:
		_pass_btn.disabled = phase != Domain.Phase.PLAYER_TURN
	if phase != Domain.Phase.PLAYER_TURN:
		_close_pass_dialog()
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


## Badge AZIONE premuto: gioca l'Azione. Durante l'assemblaggio del fuoco applica
## il modificatore (Mirato/Sostenuto/Incrociato/Sventagliata); durante una Mossa,
## FUOCO D'ASSALTO spara col pezzo in movimento (A26).
func _on_action_pressed(index: int) -> void:
	var s := Game.state
	if s == null:
		return
	var hand := s.hand_of(s.human_faction)
	var nm := hand[index].action_name if index >= 0 and index < hand.size() else ""
	if s.current_order == Domain.OrderType.FIRE and s.fire_target_q >= 0:
		Game.apply_fire_modifier(index)
	elif s.phase == Domain.Phase.PLAYER_MOVING and s.current_order == Domain.OrderType.MOVE \
			and nm == "FUOCO D'ASSALTO":
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
