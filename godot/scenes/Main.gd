## Scena di gioco: HUD in sovrimpressione sulla mappa.
extends Control


# ─── Nodi ─────────────────────────────────────────────────────────────────────

@onready var hex_map: Node2D = $HexMap
@onready var top_bar: PanelContainer = $TopBar
@onready var sidebar: PanelContainer = $Sidebar
@onready var log_list: ItemList = $Sidebar/SideVBox/LogList
@onready var log_toggle_btn: Button = $Sidebar/SideVBox/SideHeader/SideToggleBtn
@onready var view3d_btn: Button = $Sidebar/SideVBox/Tools/View3DBtn
@onready var los_btn: Button = $Sidebar/SideVBox/Tools/LosBtn
@onready var help_btn: Button = $Sidebar/SideVBox/Tools/HelpBtn
@onready var menu_btn: Button = $Sidebar/SideVBox/Tools2/MenuBtn
@onready var editor_btn: Button = $Sidebar/SideVBox/Tools2/EditorBtn
@onready var phase_label: Label = $TopBar/HBox/PhaseLabel
@onready var turn_label: Label = $TopBar/HBox/TurnLabel
@onready var orders_label: Label = $TopBar/HBox/OrdersLabel
@onready var init_label: Label = $TopBar/HBox/InitLabel
@onready var time_label: Label = $TopBar/HBox/TimeLabel
@onready var vp_label: Label = $TopBar/HBox/VPLabel
@onready var deck_label: Label = $TopBar/HBox/DeckLabel
@onready var info_label: RichTextLabel = $Sidebar/SideVBox/InfoPanel/InfoMargin/InfoLabel
@onready var hand_panel: PanelContainer = $HandPanel
@onready var hand_container: HBoxContainer = $HandPanel/VBox/Cards
@onready var end_turn_btn: Button = $HandPanel/VBox/Header/EndTurnBtn
@onready var hand_toggle_btn: Button = $HandPanel/VBox/Header/ToggleBtn

var _hand_collapsed := false


var _legend: Panel = null
var _help: Panel = null
var _rules_panel: Panel = null
var _rules_label: RichTextLabel = null
# Colonna laterale come "cassetto" che scorre in orizzontale (non un pulsante che
# apre una finestra). SIDE_W = larghezza; una maniglia sul bordo apre/chiude.
const SIDE_W := 340.0
var _sidebar_open := true
var _sidebar_handle: Button = null

# «Passa» (O15): pulsante nell'header + finestra per scegliere le carte da scartare.
var _pass_btn: Button = null
var _pass_dialog: Panel = null
var _pass_cards: HBoxContainer = null
var _pass_confirm: Button = null
var _pass_marked: Dictionary = {}  # indice carta → true se da scartare

# Schieramento manuale: barra con «Auto» e «Schieramento pronto».
var _setup_bar: Panel = null


func _ready() -> void:
	# Se si arriva qui senza passare dal menù, avvia una partita predefinita.
	if Game.state == null:
		Game.start_new_game(Domain.Faction.GERMAN)
	_connect_signals()
	# La colonna scorre sopra la barra delle carte (full-width): portarla in cima
	# allo z-order. Maniglia e finestre, aggiunte dopo, restano sopra di essa.
	move_child(sidebar, -1)
	_build_legend()
	_build_view3d_button()
	_build_los_button()
	_build_help_panel()
	_build_rules_ingame()
	_apply_solid_panels()
	_build_sidebar_handle()
	_build_pass_ui()
	_build_setup_ui()
	_build_reaction_banner()
	_build_tutorial_window()
	_build_log_view()
	log_toggle_btn.pressed.connect(_toggle_sidebar)
	end_turn_btn.tooltip_text = "Concludi il turno e passa all'avversario (anche a ordini finiti)"
	editor_btn.tooltip_text = "Apri l'editor delle mappe"
	editor_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/MapEditor.tscn"))
	# La mappa occupa solo l'area libera (sotto la barra, a sinistra della
	# colonna, sopra la mano): si ricalcola quando i pannelli cambiano dimensione.
	top_bar.resized.connect(_update_map_rect)
	sidebar.resized.connect(_update_map_rect)
	hand_panel.resized.connect(_update_map_rect)
	resized.connect(_update_map_rect)
	_refresh_ui()
	_update_map_rect.call_deferred()
	# Riempi il registro (dal più vecchio al più recente: state.log è newest-first).
	var _lg := Game.state.log
	var _dt := Game.state.log_details
	var _kd := Game.state.log_kinds
	for i in range(_lg.size() - 1, -1, -1):
		_add_log_entry(_lg[i],
			String(_dt[i]) if i < _dt.size() else "",
			String(_kd[i]) if i < _kd.size() else "")


## Comunica alla mappa l'area di disegno libera dai pannelli (top bar, colonna a
## destra se aperta, mano in basso). La mappa si re-inquadra al suo interno.
func _update_map_rect() -> void:
	if hex_map == null:
		return
	var vp := get_viewport_rect().size
	var top := top_bar.size.y if top_bar.size.y > 0 else 40.0
	var right := SIDE_W if _sidebar_open else 0.0
	var bottom := hand_panel.size.y if hand_panel.visible and hand_panel.size.y > 0 else 0.0
	var rect := Rect2(0, top, maxf(200.0, vp.x - right), maxf(120.0, vp.y - top - bottom))
	hex_map.set("map_rect", rect)
	hex_map.queue_redraw()


var _v3d: SubViewportContainer = null
var _board3d: Node = null


## Vista 3D embeddata (SubViewport); il pulsante di toggle vive nella sidebar.
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
	view3d_btn.tooltip_text = "Alterna mappa 2D / 3D (anche coi tasti «2» e «3»)"
	view3d_btn.pressed.connect(func() -> void: _set_3d(not _v3d.visible))


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
	view3d_btn.text = "Vista 2D" if on else "Vista 3D"


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
	# Il pulsante «Comandi» è nella barra strumenti della sidebar; apre/chiude
	# il pannello d'aiuto (anche col tasto «H»).
	help_btn.tooltip_text = "Come si gioca: selezione, carte, mossa, fuoco, tasti (anche col tasto «H»)"
	help_btn.pressed.connect(func() -> void:
		if _help != null:
			_help.visible = not _help.visible)

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
		+ " - Nella colonna a destra compare la scheda dell'unità/esagono.\n\n" \
		+ "[b]Mappa[/b]\n" \
		+ " - Rotella del mouse = zoom (sul punto sotto il cursore).\n" \
		+ " - Trascina (sinistro su area vuota, o tasto centrale/destro) = sposta la mappa.\n" \
		+ " - «0» = reinquadra (annulla zoom e spostamento).\n\n" \
		+ "[b]Carte (in basso)[/b]\n" \
		+ " - Ogni carta ha due badge: [color=#7fb0ff]ORDINE[/color] in alto, [color=#ffae5a]AZIONE[/color] in basso.\n" \
		+ " - Clicca il badge che vuoi giocare: è acceso quando è giocabile, spento quando no.\n\n" \
		+ "[b]Mossa[/b]\n" \
		+ " - Un leader trascina le unità entro il suo Comando (alone arancione).\n" \
		+ " - Il numero sull'esagono = Punti Movimento per entrarci (verde = pochi, rosso = molti).\n" \
		+ " - Clicca di nuovo l'unità attiva per concludere la sua mossa.\n\n" \
		+ "[b]Fuoco[/b]\n" \
		+ " - Dopo l'ordine, le unità che possono sparare hanno un [color=#4fd8ff]anello ciano[/color].\n" \
		+ " - Clicca un tiratore (o un leader per vederne i tiratori): il [color=#ffae5a]gruppo di fuoco[/color] si\n" \
		+ "   assembla subito (pezzi co-locati e quelli entro il Comando del leader). I pezzi sono cerchiati d'arancio.\n" \
		+ " - Clic su un pezzo arancione = aggiungilo/toglilo dal gruppo; le linee rosse mostrano i bersagli validi.\n" \
		+ " - Passa il mouse su un BERSAGLIO per le statistiche (FP vs Difesa + esito), poi clic per sparare.\n\n" \
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
		+ " - L = legenda mappa    2 / 3 = vista 2D / 3D    C = carte    R = pannello laterale    V = LOS    P = passa\n" \
		+ " - rotella = zoom    trascina = sposta    0 = reinquadra    X = esci dal bordo nemico (VP)    S = fumo/esplosivo    SPAZIO = non sparare\n" \
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


## La metà AZIONE è giocabile ora? Nella fase ordini si accendono SOLO le azioni
## autonome davvero implementate (Game.AUTONOMOUS_ACTIONS): le altre oggi si
## limiterebbero a scartare la carta, quindi restano spente per non ingannare.
## Le azioni "di contesto" (modificatori di fuoco e Sventagliata, Fuoco d'Assalto)
## si accendono solo nel loro contesto: durante un Fuoco col bersaglio scelto i
## modificatori/Sventagliata, durante una Mossa il Fuoco d'Assalto.
func _action_playable(card: Card, s: GameState) -> bool:
	var name := card.action_name
	if s.phase == Domain.Phase.PLAYER_TURN:
		return name in Game.AUTONOMOUS_ACTIONS
	if s.phase == Domain.Phase.PLAYER_MOVING:
		if s.current_order == Domain.OrderType.FIRE and s.fire_target_q >= 0:
			return name in Game.FIRE_MOD_NAMES or name.begins_with("SVENTAGLIATA")
		if s.current_order == Domain.OrderType.MOVE:
			return name == "FUOCO D'ASSALTO"
	return false


## Pulsante «Regole» nella colonna + pannello con setup e regole speciali dello
## scenario corrente (ScenarioRules). Aggiornato all'apertura.
func _build_rules_ingame() -> void:
	var btn := Button.new()
	btn.text = "Regole"
	btn.tooltip_text = "Setup e regole speciali dello scenario"
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tools2: HBoxContainer = $Sidebar/SideVBox/Tools2
	tools2.add_child(btn)

	_rules_panel = Panel.new()
	_rules_panel.visible = false
	_rules_panel.set_anchors_preset(Control.PRESET_CENTER)
	_rules_panel.offset_left = -380
	_rules_panel.offset_top = -300
	_rules_panel.offset_right = 380
	_rules_panel.offset_bottom = 300
	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(m, 16)
	_rules_panel.add_child(pad)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	pad.add_child(v)
	var head := HBoxContainer.new()
	var t := Label.new()
	t.text = "Regole dello scenario"
	t.add_theme_font_size_override("font_size", 18)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := Button.new()
	close.text = "Chiudi"
	close.pressed.connect(func() -> void: _rules_panel.visible = false)
	head.add_child(close)
	v.add_child(head)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	_rules_label = RichTextLabel.new()
	_rules_label.bbcode_enabled = true
	_rules_label.fit_content = true
	_rules_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_rules_label)
	add_child(_rules_panel)

	btn.pressed.connect(func() -> void:
		if _rules_panel.visible:
			_rules_panel.visible = false
		else:
			_rules_label.text = ScenarioRules.as_bbcode(Game.state.scenario_number)
			_rules_panel.visible = true)


## Sfondo SOLIDO (opaco) per le tre "finestre" della HUD — barra in alto, colonna
## a destra e mano in basso — così non sono più semi-trasparenti sopra la mappa.
func _apply_solid_panels() -> void:
	for p in [top_bar, sidebar, hand_panel]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.14, 0.17, 1.0)
		sb.border_color = Color(0.05, 0.06, 0.08, 1.0)
		for side in ["left", "top", "right", "bottom"]:
			sb.set("content_margin_" + side, 8.0)
		p.add_theme_stylebox_override("panel", sb)


## Maniglia sul bordo sinistro della colonna: cliccandola la colonna SCORRE in
## orizzontale (dentro/fuori), come un cassetto. Resta sempre visibile (anche a
## colonna chiusa, sul bordo destro dello schermo).
func _build_sidebar_handle() -> void:
	_sidebar_handle = Button.new()
	_sidebar_handle.text = "▶"
	_sidebar_handle.tooltip_text = "Apri/chiudi la colonna laterale (anche col tasto «R»)"
	_sidebar_handle.focus_mode = Control.FOCUS_NONE
	_sidebar_handle.anchor_left = 1.0
	_sidebar_handle.anchor_right = 1.0
	_sidebar_handle.anchor_top = 0.5
	_sidebar_handle.anchor_bottom = 0.5
	_sidebar_handle.offset_top = -54
	_sidebar_handle.offset_bottom = 54
	_sidebar_handle.pressed.connect(_toggle_sidebar)
	add_child(_sidebar_handle)
	_place_sidebar(true)  # stato iniziale: aperta


## Posiziona colonna e maniglia per lo stato aperto/chiuso. Con `animate` la
## transizione scorre orizzontalmente con un Tween.
func _place_sidebar(open: bool, animate: bool = false) -> void:
	var s_left := -SIDE_W if open else 0.0           # bordo sinistro colonna (anchor dx)
	var s_right := 0.0 if open else SIDE_W            # bordo destro colonna
	var h_left := (-SIDE_W - 28.0) if open else -28.0 # maniglia: a sinistra del bordo colonna
	var h_right := (-SIDE_W - 2.0) if open else -2.0
	if animate:
		var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(sidebar, "offset_left", s_left, 0.22)
		tw.tween_property(sidebar, "offset_right", s_right, 0.22)
		tw.tween_property(_sidebar_handle, "offset_left", h_left, 0.22)
		tw.tween_property(_sidebar_handle, "offset_right", h_right, 0.22)
		tw.chain().tween_callback(_update_map_rect)
	else:
		sidebar.offset_left = s_left
		sidebar.offset_right = s_right
		_sidebar_handle.offset_left = h_left
		_sidebar_handle.offset_right = h_right
		_update_map_rect.call_deferred()
	_sidebar_handle.text = "▶" if open else "◀"


func _toggle_sidebar() -> void:
	_sidebar_open = not _sidebar_open
	_place_sidebar(_sidebar_open, true)


## Attiva/disattiva la "Modalità LOS": uno strumento per verificare la linea di
## vista tra due esagoni (estremità trascinabili, linea colorata). Inizializza le
## estremità così la linea è subito visibile; funziona sia in 2D sia in 3D.
## Il pulsante «LOS» vive nella barra strumenti della sidebar e attiva la
## Modalità LOS (equivalente al tasto «V»).
func _build_los_button() -> void:
	los_btn.tooltip_text = "Modalità LOS: verifica la linea di vista tra due esagoni (anche col tasto «V»)"
	los_btn.pressed.connect(_toggle_los_mode)


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
	los_btn.text = "LOS: ON" if s.los_mode else "LOS"
	los_btn.modulate = Color(0.5, 1.0, 0.6) if s.los_mode else Color(1, 1, 1)
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


## Barra dello Schieramento manuale (visibile solo in PLAYER_SETUP): pulsanti
## «Auto» (schieramento intelligente automatico) e «Schieramento pronto»
## (conferma e inizia la partita), con un suggerimento. Creata via codice,
## centrata sotto la barra in alto.
func _build_setup_ui() -> void:
	_setup_bar = Panel.new()
	_setup_bar.visible = false
	_setup_bar.anchor_left = 0.5
	_setup_bar.anchor_right = 0.5
	_setup_bar.anchor_top = 0.0
	_setup_bar.anchor_bottom = 0.0
	_setup_bar.offset_left = -300
	_setup_bar.offset_right = 300
	_setup_bar.offset_top = 50
	_setup_bar.offset_bottom = 96
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.14, 0.17, 0.96)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.35, 0.72, 1.0, 0.85)
	_setup_bar.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 12
	hb.offset_right = -12
	hb.add_theme_constant_override("separation", 12)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	_setup_bar.add_child(hb)
	var lbl := Label.new()
	lbl.text = "Schieramento: clicca un'unità, poi l'esagono (zona azzurra) dove spostarla"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(lbl)
	var auto_btn := Button.new()
	auto_btn.text = "Auto"
	auto_btn.tooltip_text = "Schieramento automatico intelligente: gruppi comandati dai leader, distanziati, in copertura e su altura"
	auto_btn.pressed.connect(func() -> void: Game.auto_setup())
	hb.add_child(auto_btn)
	var ready_btn := Button.new()
	ready_btn.text = "Schieramento pronto"
	ready_btn.tooltip_text = "Conferma le posizioni e inizia la partita"
	ready_btn.pressed.connect(func() -> void: Game.finish_setup())
	hb.add_child(ready_btn)
	add_child(_setup_bar)


## Mostra/nasconde la barra di schieramento e adatta la HUD: durante il setup la
## mano (non serve) resta nascosta, così la mappa si riprende lo spazio.
func _update_setup_bar(phase: int) -> void:
	var on := phase == Domain.Phase.PLAYER_SETUP
	if _setup_bar != null:
		_setup_bar.visible = on
	if hand_panel.visible == on:
		hand_panel.visible = not on
		_update_map_rect()


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
		KEY_R:  # mostra/nascondi la colonna laterale (registro, info, strumenti)
			_toggle_sidebar()
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
				if not Game.state.conceal_offer_ids.is_empty():
					Game.conceal_decline()
				else:
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
	# Conteggio Ordini nella barra in alto (5.1): evidenziato quando esauriti.
	orders_label.text = "Ordini %d/%d" % [s.order_count, s.max_orders]
	orders_label.modulate = Color(1, 0.6, 0.5) if s.order_count >= s.max_orders else Color(1, 1, 1)
	end_turn_btn.disabled = not _is_player_phase(s.phase)
	# Passare si può solo nella fase ordini (non a metà di una mossa/fuoco).
	if _pass_btn != null:
		_pass_btn.disabled = s.phase != Domain.Phase.PLAYER_TURN
	_update_setup_bar(s.phase)
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
						msg += " · pezzo arancio nel gruppo (clic = aggiungi/togli) · dx carta = modificatore · clicca il BERSAGLIO per sparare"
						if not s.fire_modifiers.is_empty():
							msg += "  [%s]" % ", ".join(s.fire_modifiers)
						if s.spray_active:
							msg += "  [SVENTAGLIATA]"
						return msg
					if not has_unit:
						var n := s.fire_ready_ids.size()
						if n == 0:
							return "FUOCO — nessuna unità ha un bersaglio valido · «Fine Turno» o gioca un'Azione"
						return "FUOCO — clicca un tiratore (anello ciano) o un leader per vederne i tiratori (%d possono sparare)" % n
					if s.fire_eligible_ids.is_empty() and not s.command_preview_ids.is_empty():
						return "FUOCO — leader: clicca uno dei tiratori comandati (arancio) per assemblare il gruppo"
					return "FUOCO — gruppo assemblato: clic su un pezzo = aggiungi/togli · mouse su un BERSAGLIO per le statistiche · clic per sparare · il tiratore per annullare"
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
			if not s.conceal_offer_ids.is_empty():
				return "MIMETIZZAZIONE — clicca l'unità (ciano) per mimetizzarti · altrove o SPAZIO = rinuncia"
			return "FUOCO DI OPPORTUNITÀ — clicca un tiratore (giallo) per sparare · altrove o SPAZIO = non sparare"
		_:
			return Domain.PHASE_LABELS.get(s.phase, "")


func _refresh_unit_info() -> void:
	var s := Game.state
	# Guida contestuale, discreta in cima alla colonna (non più sovrapposta alla
	# mappa): cosa fare adesso.
	var guide := "[color=#cfe3ff]%s[/color]\n\n" % _guidance_text(s)
	var u := s.unit_by_id(s.selected_unit_id) if s.selected_unit_id != "" else null
	if u == null:
		info_label.text = guide + "[color=#9aa]Nessuna unità selezionata.\nClicca una pedina sulla mappa.[/color]"
		return
	var fac: String = Domain.FACTION_SHORT.get(u.faction, "?")
	var cls: String = Domain.UNIT_CLASS_LABEL.get(u.unit_class, "")
	var lines := guide + "[b]%s[/b]  (%s)\n" % [u.unit_name, fac]
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
	# ordini ancora disponibili E che esista davvero un bersaglio/unità su cui
	# applicarlo. Le carte non giocabili sono attenuate (badge spento).
	var is_turn := s.phase == Domain.Phase.PLAYER_TURN
	var orders_left := s.order_count < s.max_orders
	var hand := s.hand_of(s.human_faction)
	for i in hand.size():
		var card: Card = hand[i]
		var order_name: String = Domain.ORDER_LABELS.get(card.order, card.order_label)
		var counts: bool = card.order in [
			Domain.OrderType.MOVE, Domain.OrderType.FIRE, Domain.OrderType.ADVANCE,
			Domain.OrderType.RECOVER, Domain.OrderType.ROUT, Domain.OrderType.ARTY]
		var order_ok := is_turn and (orders_left or not counts) and Game.order_feasible(card.order)
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


func _on_log_added(line: String, detail: String = "", kind: String = "") -> void:
	_add_log_entry(line, detail, kind)


# ─── Registro ricco (banda di turno, colori, neretto, formula collassabile) ───

var _log_scroll: ScrollContainer = null
var _log_box: VBoxContainer = null


## Sostituisce l'ItemList con un registro scorrevole a voci formattate.
func _build_log_view() -> void:
	if log_list == null:
		return
	log_list.visible = false
	_log_scroll = ScrollContainer.new()
	_log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_log_box = VBoxContainer.new()
	_log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_box.add_theme_constant_override("separation", 3)
	_log_scroll.add_child(_log_box)
	var parent := log_list.get_parent()
	parent.add_child(_log_scroll)
	parent.move_child(_log_scroll, log_list.get_index() + 1)


## Aggiunge una voce al registro: banda per i turni, riga colorata per il resto,
## con eventuale dettaglio del calcolo (formula) collassabile.
func _add_log_entry(line: String, detail: String, kind: String) -> void:
	if _log_box == null:
		return
	var k := kind
	if k == "":  # categoria inferita dal testo (righe IA) per la colorazione
		if line.begins_with("IA ") or line.begins_with("Opportunità") or line.begins_with("FlipBot"):
			k = "ai"
	if k == "turn":
		_log_box.add_child(_make_turn_band(line))
	else:
		_log_box.add_child(_make_log_line(line, detail, k))
	while _log_box.get_child_count() > 80:
		_log_box.get_child(0).queue_free()
	_scroll_log_bottom()


## Banda colorata per l'inizio/fine di un turno.
func _make_turn_band(line: String) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.17, 0.27, 0.20)
	sb.border_color = Color(0.35, 0.55, 0.38)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	var l := _log_label(12)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = "[b][color=#d8f0c8]— %s —[/color][/b]" % line
	p.add_child(l)
	return p


## Riga di registro colorata per categoria; collassabile se ha una formula.
func _make_log_line(line: String, detail: String, kind: String) -> Control:
	var l := _log_label(12)
	var col := _log_color(kind)
	var body := _bold_keywords(line)
	if detail == "":
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.text = "[color=%s]%s[/color]" % [col, body]
	else:
		l.set_meta("summary", body)
		l.set_meta("detail", detail)
		l.set_meta("color", col)
		l.set_meta("open", false)
		l.meta_clicked.connect(func(_m: Variant) -> void:
			l.set_meta("open", not bool(l.get_meta("open")))
			_render_collapsible(l))
		_render_collapsible(l)
	return l


func _render_collapsible(l: RichTextLabel) -> void:
	var summary := String(l.get_meta("summary"))
	var detail := String(l.get_meta("detail"))
	var col := String(l.get_meta("color"))
	if bool(l.get_meta("open")):
		l.text = "[color=%s]%s[/color]  [url=t][color=#8fd0ff]▼ formula[/color][/url]\n[color=#a8b6c4]    %s[/color]" % [
			col, summary, detail.replace("\n", "\n    ")]
	else:
		l.text = "[color=%s]%s[/color]  [url=t][color=#8fd0ff]▶ formula[/color][/url]" % [col, summary]


func _log_label(font_size: int) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.add_theme_font_size_override("normal_font_size", font_size)
	l.add_theme_font_size_override("bold_font_size", font_size)
	return l


## Colore della riga per categoria (rosso = ordine giocato, ecc.).
func _log_color(kind: String) -> String:
	match kind:
		"order":   return "#ff7a66"
		"fire":    return "#ffb060"
		"melee":   return "#ff9a5a"
		"ai":      return "#86b6e0"
		"recover": return "#7fd08a"
		_:         return "#c8c8c8"


## Mette in neretto alcune parole chiave, se la riga non è già formattata a monte.
func _bold_keywords(line: String) -> String:
	if line.contains("[b]"):
		return line
	var s := line
	for kw in ["ELIMINATE", "ELIMINATA", "ROTTE", "ROTTA", "SOPPRESSE", "SOPPRESSA",
			"ANNULLATO", "MANCATO", "Recupero", "Fuga", "Imboscata"]:
		s = s.replace(kw, "[b]%s[/b]" % kw)
	return s


func _scroll_log_bottom() -> void:
	if _log_scroll == null:
		return
	await get_tree().process_frame
	var bar := _log_scroll.get_v_scroll_bar()
	if bar != null:
		_log_scroll.scroll_vertical = int(bar.max_value)


func _on_phase_changed(phase: int) -> void:
	phase_label.text = Domain.PHASE_LABELS.get(phase, "—")
	end_turn_btn.disabled = not _is_player_phase(phase)
	if _pass_btn != null:
		_pass_btn.disabled = phase != Domain.Phase.PLAYER_TURN
	if phase != Domain.Phase.PLAYER_TURN:
		_close_pass_dialog()
	_update_setup_bar(phase)
	_update_reaction_banner(phase)
	if Game.state:
		_refresh_unit_info()


# ─── Banner della finestra di reazione (Op Fire / Mimetizzazione) ─────────────
# Durante il turno dell'IA il gioco può chiederti una reazione (sparare a un'unità
# che si muove, o mimetizzarti). È una fase «non tua»: ordini e «Fine Turno» sono
# spenti. Per non lasciarti senza indicazioni, un banner centrale spiega cosa fare
# e offre un pulsante per proseguire senza reagire.

var _reaction_banner: PanelContainer = null
var _reaction_label: RichTextLabel = null
var _reaction_btn: Button = null


func _build_reaction_banner() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60  # sopra la HUD e la vista 3D
	add_child(layer)
	_reaction_banner = PanelContainer.new()
	_reaction_banner.visible = false
	# Centrato in alto, larghezza fissa; l'altezza cresce col contenuto.
	_reaction_banner.anchor_left = 0.5
	_reaction_banner.anchor_right = 0.5
	_reaction_banner.anchor_top = 0.0
	_reaction_banner.anchor_bottom = 0.0
	_reaction_banner.offset_left = -320
	_reaction_banner.offset_right = 320
	_reaction_banner.offset_top = 54
	_reaction_banner.grow_vertical = Control.GROW_DIRECTION_END
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.07, 0.05, 0.97)
	sb.border_color = Color(1.0, 0.62, 0.2)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	_reaction_banner.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_reaction_banner.add_child(vb)
	_reaction_label = RichTextLabel.new()
	_reaction_label.bbcode_enabled = true
	_reaction_label.fit_content = true
	_reaction_label.custom_minimum_size = Vector2(604, 0)
	_reaction_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_reaction_label)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	_reaction_btn = Button.new()
	_reaction_btn.custom_minimum_size = Vector2(240, 36)
	_reaction_btn.pressed.connect(_on_reaction_decline)
	hb.add_child(_reaction_btn)
	vb.add_child(hb)
	layer.add_child(_reaction_banner)


## Mostra/aggiorna il banner secondo la fase e il tipo di reazione in corso.
func _update_reaction_banner(phase: int) -> void:
	if _reaction_banner == null:
		return
	var s := Game.state
	if s == null or phase != Domain.Phase.REACTION_WINDOW:
		_reaction_banner.visible = false
		return
	if not s.conceal_offer_ids.is_empty():
		_reaction_label.text = "[b][color=#7fe0ff]MIMETIZZAZIONE[/color][/b]  —  reazione\n" \
			+ "L'IA sta per spararti. Clicca un'unità [color=#7fe0ff]ciano[/color] sulla mappa per " \
			+ "mimetizzarti (la Copertura ridurrà il colpo), oppure prosegui."
		_reaction_btn.text = "Non mimetizzarmi  (SPAZIO)"
	else:
		_reaction_label.text = "[b][color=#ffcf66]FUOCO DI OPPORTUNITÀ[/color][/b]  —  reazione\n" \
			+ "Un'unità nemica si muove allo scoperto. Clicca un tuo tiratore [color=#ffd24a]giallo[/color] " \
			+ "sulla mappa per sparargli, oppure prosegui senza sparare."
		_reaction_btn.text = "Non sparare  (SPAZIO)"
	_reaction_banner.visible = true


## Pulsante del banner: rinuncia alla reazione (equivale a SPAZIO / clic altrove).
func _on_reaction_decline() -> void:
	var s := Game.state
	if s == null or s.phase != Domain.Phase.REACTION_WINDOW:
		return
	if not s.conceal_offer_ids.is_empty():
		Game.conceal_decline()
	else:
		Game.opfire_decline()


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
	var s := Game.state
	var order := -1
	if s != null:
		var hand := s.hand_of(s.human_faction)
		if index >= 0 and index < hand.size():
			order = hand[index].order
	Game.play_card(index)
	# Modalità tutorial: spiega l'ordine appena giocato (regola + cosa fare).
	if Game.tutorial_enabled and order >= 0:
		_show_tutorial(TutorialHelp.for_order(order))


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
	# Modalità tutorial: spiega l'azione (regola + cosa fare).
	if Game.tutorial_enabled and nm != "":
		_show_tutorial(TutorialHelp.for_action(nm))


# ─── Finestra di aiuto «Modalità tutorial» ────────────────────────────────────
# Quando la modalità è attiva (dal menù iniziale), a ogni ordine/azione compare
# una finestra fluttuante con due sezioni in neretto: «Regola» (sunto del
# regolamento) e «Cosa fare» (come funziona il programma).

var _tut_win: PanelContainer = null
var _tut_title: RichTextLabel = null
var _tut_rule: RichTextLabel = null
var _tut_todo: RichTextLabel = null


func _build_tutorial_window() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 55
	add_child(layer)
	_tut_win = PanelContainer.new()
	_tut_win.visible = false
	_tut_win.anchor_left = 0.0
	_tut_win.anchor_top = 0.0
	_tut_win.offset_left = 12
	_tut_win.offset_top = 62
	_tut_win.offset_right = 12 + 404
	_tut_win.grow_vertical = Control.GROW_DIRECTION_END
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.12, 0.16, 0.98)
	sb.border_color = Color(0.45, 0.70, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	_tut_win.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_tut_win.add_child(vb)
	# Intestazione: titolo + chiusura.
	var hdr := HBoxContainer.new()
	_tut_title = _tut_body(18)
	_tut_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(_tut_title)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: _tut_win.visible = false)
	hdr.add_child(close)
	vb.add_child(hdr)
	# Sezioni «Regola» e «Cosa fare» (intestazioni in neretto nei testi).
	_tut_rule = _tut_body(15)
	vb.add_child(_tut_rule)
	_tut_todo = _tut_body(15)
	vb.add_child(_tut_todo)
	# Piè di pagina: disattiva la modalità senza tornare al menù.
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	var off := Button.new()
	off.text = "Disattiva tutorial"
	off.focus_mode = Control.FOCUS_NONE
	off.pressed.connect(func() -> void:
		Game.set_tutorial(false)
		_tut_win.visible = false)
	foot.add_child(off)
	vb.add_child(foot)
	layer.add_child(_tut_win)


func _tut_body(font_size: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.custom_minimum_size = Vector2(376, 0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_size_override("normal_font_size", font_size)
	r.add_theme_font_size_override("bold_font_size", font_size)
	return r


## Mostra/aggiorna la finestra tutorial col contenuto dato. No-op se la modalità
## non è attiva o il contenuto è vuoto.
func _show_tutorial(data: Dictionary) -> void:
	if _tut_win == null or data.is_empty() or not Game.tutorial_enabled:
		return
	_tut_title.text = "[b][color=#b3d4ff]%s[/color][/b]" % String(data.get("title", "Aiuto"))
	_tut_rule.text = "[b][color=#ffd766]Regola[/color][/b]\n%s" % String(data.get("rule", ""))
	_tut_todo.text = "[b][color=#8bff9a]Cosa fare[/color][/b]\n%s" % String(data.get("todo", ""))
	_tut_win.visible = true


## Mostra/nasconde la fila carte (il pannello si riduce all'header) per liberare
## la mappa. Le carte restano giocabili appena riaperto.
func _toggle_hand() -> void:
	_hand_collapsed = not _hand_collapsed
	_refresh_hand()
	_update_map_rect.call_deferred()  # la mappa riprende lo spazio della mano


func _on_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")


func _on_game_over(winner: int) -> void:
	var fname: String = Domain.FACTION_NAMES.get(winner, "PAREGGIO")
	var dlg := AcceptDialog.new()
	dlg.title = "Fine Partita"
	dlg.dialog_text = "Vincitore: %s" % fname
	add_child(dlg)
	dlg.popup_centered()
