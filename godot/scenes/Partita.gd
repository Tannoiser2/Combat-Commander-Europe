## Schermata di gioco.
##
## È un «lettore di decisioni»: a ogni momento mostra CHI deve fare COSA
## (riquadro Guida), evidenzia sulla mappa e nella mano solo ciò che è legale
## toccare, elenca le alternative come pulsanti e racconta in Cronaca tutto
## quello che accade, comprese le mosse dell'avversario una alla volta.
extends Control

const CARD_W := 112.0
const CARD_H := 155.0
const SIDE_W := 390.0

var board: Board2D
var board_holder: Control
var view3d: SubViewportContainer = null
var track: Control
var who_lbl: Label
var guide: RichTextLabel
var opts_box: VBoxContainer
var info: RichTextLabel
var log_box: RichTextLabel
var hand_box: HBoxContainer
var foe_lbl: Label
var title_lbl: Label
var skip_btn: Button
var preview: Control
var preview_card: CardView
var preview_lbl: Label
var dice_box: PanelContainer
var dice_a: TextureRect
var dice_b: TextureRect
var dice_lbl: Label
var played_box: PanelContainer
var played_card: CardView
var played_lbl: Label
var overlay: Control
var stack_pop: PopupPanel
var help_panel: PanelContainer
var btn_3d: Button
var btn_speed: Button
var btn_pause: Button

var _sel_card := -1
var _dice_until := 0
var _played_until := 0
var _log_lines := 0


func _ready() -> void:
	theme = Tema.get_theme()
	if Game.flow == null:
		Game.start_new_game(Flow.AX, 1, 1)
	_build()
	Game.decision_changed.connect(_refresh)
	Game.state_changed.connect(_refresh_status)
	Game.chronicle.connect(_on_event)
	Game.stack_offered.connect(_on_stack)
	Game.game_over.connect(_on_game_over)
	_refresh()
	_refresh_status()


# ═══ Costruzione ═════════════════════════════════════════════════════════════

func _btn(text: String, tip: String = "", min_w: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	if min_w > 0.0:
		b.custom_minimum_size.x = min_w
	return b


func _rich(min_h: float = 0.0) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = min_h <= 0.0
	r.scroll_active = min_h > 0.0
	r.custom_minimum_size = Vector2(SIDE_W - 40.0, min_h)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	return r


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Tema.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 6
	root.offset_top = 6
	root.offset_right = -6
	root.offset_bottom = -6
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	# ── Riga 1: titolo e comandi ────────────────────────────────────────────
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	root.add_child(bar)
	var menu := _btn("MENU", "Torna al menu degli scenari", 70)
	menu.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/Menu.tscn"))
	bar.add_child(menu)
	title_lbl = Tema.title("", 24)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.clip_text = true
	title_lbl.custom_minimum_size.x = 200
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(title_lbl)
	btn_3d = _btn("Vista 3D", "Passa dalla mappa 2D alla vista 3D e viceversa", 96)
	btn_3d.pressed.connect(_toggle_3d)
	bar.add_child(btn_3d)
	var recenter := _btn("Centra", "Reinquadra la mappa", 74)
	recenter.pressed.connect(func() -> void:
		board.reset_view()
		if view3d != null and view3d.visible:
			var m3 := view3d.get_child(0).get_child(0)
			if m3 != null and m3.has_method("_reset_camera"):
				m3._reset_camera()
				m3._update_camera())
	bar.add_child(recenter)
	btn_speed = _btn("", "Velocità con cui scorrono le azioni", 118)
	btn_speed.pressed.connect(_cycle_speed)
	bar.add_child(btn_speed)
	btn_pause = _btn("Pausa", "Ferma lo scorrere delle azioni dell'avversario", 78)
	btn_pause.pressed.connect(_toggle_pause)
	bar.add_child(btn_pause)
	var help := _btn("Come si gioca", "Sequenza di gioco e regole speciali dello scenario", 126)
	help.pressed.connect(func() -> void: help_panel.visible = not help_panel.visible)
	bar.add_child(help)

	# ── Riga 2: plancia (Tempo, PV, Iniziativa, perdite) ─────────────────────
	var tp := PanelContainer.new()
	tp.add_theme_stylebox_override("panel", Tema.box(Tema.PANEL, Tema.EDGE, 2, 4, 4))
	root.add_child(tp)
	track = Control.new()
	track.custom_minimum_size = Vector2(600, 46)
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.draw.connect(_draw_track)
	tp.add_child(track)

	# ── Centro: mappa + pannello laterale ───────────────────────────────────
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 6)
	root.add_child(mid)
	board_holder = Control.new()
	board_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_holder.custom_minimum_size = Vector2(320, 200)
	board_holder.clip_contents = true
	mid.add_child(board_holder)
	board = Board2D.new()
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	board_holder.add_child(board)
	board.hex_info.connect(_show_hex_info)
	_build_overlays()

	var side := PanelContainer.new()
	side.custom_minimum_size.x = SIDE_W
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(side)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 6)
	side.add_child(sv)
	var gp := PanelContainer.new()
	gp.add_theme_stylebox_override("panel", Tema.box(Tema.PANEL_HI, Tema.BRASS, 2, 4, 8))
	sv.add_child(gp)
	var gv := VBoxContainer.new()
	gv.add_theme_constant_override("separation", 6)
	gp.add_child(gv)
	who_lbl = Tema.title("", 20)
	who_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	who_lbl.custom_minimum_size.x = SIDE_W - 40.0
	gv.add_child(who_lbl)
	guide = _rich()
	guide.add_theme_font_size_override("normal_font_size", 19)
	guide.add_theme_font_size_override("bold_font_size", 19)
	gv.add_child(guide)
	skip_btn = _btn("Mostra subito (SPAZIO)", "Salta l'attesa e mostra subito l'esito")
	skip_btn.pressed.connect(func() -> void: Game.skip())
	gv.add_child(skip_btn)
	var osc := ScrollContainer.new()
	osc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	osc.custom_minimum_size.y = 40
	osc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	osc.size_flags_stretch_ratio = 1.1
	sv.add_child(osc)
	opts_box = VBoxContainer.new()
	opts_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opts_box.add_theme_constant_override("separation", 5)
	osc.add_child(opts_box)
	info = _rich()
	info.add_theme_font_size_override("normal_font_size", 16)
	info.add_theme_font_size_override("bold_font_size", 16)
	info.add_theme_color_override("default_color", Tema.DIM.lightened(0.2))
	sv.add_child(info)
	sv.add_child(Tema.title("CRONACA", 16))
	log_box = _rich(120)
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.scroll_following = true
	log_box.add_theme_font_size_override("normal_font_size", 16)
	log_box.add_theme_font_size_override("bold_font_size", 16)
	sv.add_child(log_box)

	# ── In basso: la mano ───────────────────────────────────────────────────
	var hp := PanelContainer.new()
	hp.custom_minimum_size.y = CARD_H + 20
	root.add_child(hp)
	var hh := HBoxContainer.new()
	hh.add_theme_constant_override("separation", 10)
	hp.add_child(hh)
	foe_lbl = Label.new()
	foe_lbl.custom_minimum_size.x = 190
	foe_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foe_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foe_lbl.add_theme_font_size_override("font_size", 16)
	foe_lbl.add_theme_color_override("font_color", Tema.DIM.lightened(0.15))
	hh.add_child(foe_lbl)
	var hsc := ScrollContainer.new()
	hsc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hsc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hh.add_child(hsc)
	hand_box = HBoxContainer.new()
	hand_box.add_theme_constant_override("separation", 8)
	hsc.add_child(hand_box)
	_set_speed_label()
	title_lbl.text = "%d · %s" % [Game.state.scenario_number, String(Game.state.scenario_name).to_upper()]


func _build_overlays() -> void:
	# Dadi dell'ultimo tiro.
	dice_box = PanelContainer.new()
	dice_box.add_theme_stylebox_override("panel", Tema.box(Color(0.05, 0.05, 0.04, 0.92), Tema.BRASS, 2, 6, 8))
	dice_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	dice_box.offset_top = 8
	dice_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dice_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dice_box.visible = false
	board_holder.add_child(dice_box)
	var dh := HBoxContainer.new()
	dh.add_theme_constant_override("separation", 8)
	dh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dice_box.add_child(dh)
	dice_a = TextureRect.new()
	dice_b = TextureRect.new()
	for d: TextureRect in [dice_a, dice_b]:
		d.custom_minimum_size = Vector2(54, 54)
		d.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		d.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dh.add_child(d)
	dice_lbl = Label.new()
	dice_lbl.custom_minimum_size.x = 250
	dice_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dice_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dice_lbl.add_theme_font_override("font", Tema.bold_font())
	dice_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dh.add_child(dice_lbl)

	# Carta appena giocata.
	played_box = PanelContainer.new()
	played_box.add_theme_stylebox_override("panel", Tema.box(Color(0.05, 0.05, 0.04, 0.92), Tema.BRASS, 2, 6, 6))
	played_box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	played_box.offset_left = 8
	played_box.offset_top = 8
	played_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	played_box.visible = false
	board_holder.add_child(played_box)
	var pv := VBoxContainer.new()
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	played_box.add_child(pv)
	played_lbl = Label.new()
	played_lbl.custom_minimum_size.x = 150
	played_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	played_lbl.add_theme_font_override("font", Tema.bold_font())
	played_lbl.add_theme_font_size_override("font_size", 15)
	played_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pv.add_child(played_lbl)
	played_card = CardView.new()
	played_card.custom_minimum_size = Vector2(150, 208)
	played_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	played_card.playable = true
	played_card.selected = true
	pv.add_child(played_card)

	# Anteprima grande della carta scelta in mano.
	preview = PanelContainer.new()
	(preview as PanelContainer).add_theme_stylebox_override("panel", Tema.box(Color(0.05, 0.05, 0.04, 0.95), Tema.BRASS, 2, 6, 8))
	preview.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	preview.offset_left = 8
	preview.offset_bottom = -8
	preview.grow_vertical = Control.GROW_DIRECTION_BEGIN
	preview.visible = false
	board_holder.add_child(preview)
	var pvv := VBoxContainer.new()
	preview.add_child(pvv)
	preview_card = CardView.new()
	preview_card.custom_minimum_size = Vector2(236, 327)
	preview_card.playable = true
	preview_card.selected = true
	preview_card.tapped.connect(func(_v: CardView) -> void: _select_card(-1))
	pvv.add_child(preview_card)
	preview_lbl = Label.new()
	preview_lbl.custom_minimum_size.x = 236
	preview_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_lbl.add_theme_font_size_override("font_size", 16)
	pvv.add_child(preview_lbl)

	# Scelta fra più pedine/opzioni nello stesso esagono.
	stack_pop = PopupPanel.new()
	add_child(stack_pop)

	# Aiuto.
	help_panel = PanelContainer.new()
	help_panel.add_theme_stylebox_override("panel", Tema.box(Color(0.07, 0.08, 0.06, 0.97), Tema.BRASS, 2, 6, 14))
	help_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	help_panel.offset_left = 20
	help_panel.offset_top = 20
	help_panel.offset_right = -20
	help_panel.offset_bottom = -20
	help_panel.visible = false
	board_holder.add_child(help_panel)
	var hv := VBoxContainer.new()
	help_panel.add_child(hv)
	var hr := RichTextLabel.new()
	hr.bbcode_enabled = true
	hr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hr.custom_minimum_size = Vector2(280, 120)
	hr.text = _help_text()
	hv.add_child(hr)
	var hc := _btn("Chiudi")
	hc.pressed.connect(func() -> void: help_panel.visible = false)
	hv.add_child(hc)

	# Fine partita.
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	add_child(overlay)


func _help_text() -> String:
	var t := "[b]COME SI GIOCA — in breve[/b]\n\n"
	t += "[b]Il turno.[/b] Nel tuo turno giochi carte dalla mano come ORDINI (il numero massimo è indicato nello scenario), uno alla volta, vedendo l'esito prima di decidere il successivo. In alternativa, se non dai ordini, puoi SCARTARE carte. A fine turno ripeschi fino a riempire la mano.\n\n"
	t += "[b]Attivare.[/b] Mossa, Fuoco e Avanzata attivano un'unità. Se attivi un COMANDANTE, lui attiva anche gli uomini entro il suo raggio di Comando (il numero nell'esagono sulla pedina): è il modo per far agire più unità con una carta sola. Ogni unità si attiva una sola volta per turno.\n\n"
	t += "[b]Mossa.[/b] Ogni unità attivata muove un esagono alla volta spendendo Punti Movimento. A ogni esagono l'avversario può reagire col FUOCO DI OPPORTUNITÀ.\n\n"
	t += "[b]Fuoco.[/b] Scegli il bersaglio, componi il gruppo di fuoco (il pezzo più forte dà il suo FP, ogni altro +1), aggiungi eventuali Azioni e tira: FP + dadi contro Morale + copertura + dadi di ogni difensore. Se l'attacco è più alto l'unità si rompe (se già rotta è eliminata); se è pari viene soppressa.\n\n"
	t += "[b]Avanzata.[/b] Un solo esagono, senza subire fuoco, anche dentro un esagono nemico: lì si risolve il CORPO A CORPO (FP + dadi, chi perde è eliminato).\n\n"
	t += "[b]Recupero e Ritirata.[/b] Il Recupero toglie le soppressioni e fa tirare le tue unità rotte per riprendersi. La Ritirata fa arretrare le unità rotte (di solito quelle nemiche) verso il loro bordo.\n\n"
	t += "[b]Dadi e inneschi.[/b] Ogni tiro è una carta pescata dal mazzo: può far scattare TEMPO!, CECCHINO!, EVENTO! o INCEPPAMENTO!. Chi ha la carta INIZIATIVA può far ripetere un tiro cedendola all'avversario.\n\n"
	t += "[b]Vittoria.[/b] Punti Vittoria da obiettivi, unità eliminate e unità uscite dal bordo nemico. Quando il Tempo raggiunge la Morte Subitanea, a ogni avanzamento si tira per chiudere la partita. Chi supera il proprio limite di perdite si arrende.\n"
	var sr := ScenarioRules.as_bbcode(Game.state.scenario_number)
	if sr != "":
		t += "\n[b]REGOLE SPECIALI DELLO SCENARIO[/b]\n" + sr
	return t


# ═══ Plancia in alto ═════════════════════════════════════════════════════════

func _draw_track() -> void:
	var s := Game.state
	var fl := Game.flow
	if s == null:
		return
	var f := Tema.bold_font()
	var w := track.size.x
	var h := track.size.y
	# Traccia del Tempo: caselle 0..12.
	var n := 13
	var bw := minf(34.0, (w * 0.40) / n)
	var x0 := 62.0
	track.draw_string(f, Vector2(4, h * 0.5 + 6), "TEMPO", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Tema.BRASS)
	for i in n:
		var r := Rect2(x0 + i * bw, 6, bw - 3, h - 12)
		var col := Tema.PANEL_HI
		if i >= s.sudden_death_space:
			col = Color(0.36, 0.14, 0.11)
		if i == s.time_marker:
			col = Tema.BRASS
		track.draw_rect(r, col)
		track.draw_rect(r, Tema.EDGE, false, 1.0)
		var tc := Color(0.1, 0.1, 0.08) if i == s.time_marker else Tema.INK
		var ts := f.get_string_size(str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		track.draw_string(f, Vector2(r.position.x + (r.size.x - ts) * 0.5, h * 0.5 + 6), str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, tc)
	var x := x0 + n * bw + 14
	var seg: Array = []
	seg.append(["rosso = Morte Subitanea", Color(0.85, 0.45, 0.4)])
	var vp := s.vp_tracker
	if vp == 0:
		seg.append(["PV 0 (parità)", Tema.INK])
	else:
		var lead := Flow.AX if vp > 0 else Flow.AL
		seg.append(["PV %d %s" % [absi(vp), fl.side_name(lead)], Tema.side_color(lead)])
	seg.append(["Iniziativa: %s" % fl.side_name(s.initiative_holder), Tema.side_color(s.initiative_holder)])
	for side: int in [Flow.AX, Flow.AL]:
		var thr := int(s.surrender_threshold.get(side, 0))
		seg.append(["Perdite %s %d/%s" % [fl.side_name(side), int(s.casualties.get(side, 0)), str(thr) if thr > 0 else "-"], Tema.side_color(side)])
	var total := 0.0
	for sg in seg:
		total += f.get_string_size(String(sg[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 22
	var fs := 17
	if total > w - x:
		fs = maxi(12, int(17.0 * (w - x) / total))
	for sg in seg:
		track.draw_string(f, Vector2(x, h * 0.5 + 6), String(sg[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, sg[1])
		x += f.get_string_size(String(sg[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 22.0 * fs / 17.0


func _refresh_status() -> void:
	if track != null:
		track.queue_redraw()


# ═══ Decisione corrente ══════════════════════════════════════════════════════

func _refresh() -> void:
	var fl := Game.flow
	if fl == null:
		return
	var p := Game.pending()
	for c in opts_box.get_children():
		c.queue_free()
	skip_btn.visible = Game.busy and not fl.over
	if fl.over:
		who_lbl.text = "PARTITA FINITA"
		guide.text = "Vincono i [b]%s[/b].\n%s" % [fl.side_name(fl.winner), fl.end_reason]
	elif p.is_empty():
		var who := int(fl.pending.get("who", fl.s.active_faction))
		who_lbl.text = "%s IN AZIONE" % fl.side_name(who).to_upper()
		who_lbl.add_theme_color_override("font_color", Tema.side_color(who))
		guide.text = "Segui in Cronaca e sulla mappa che cosa succede."
		if Game.is_human(who):
			guide.text = "Risoluzione in corso..."
	else:
		var who2 := int(p["who"])
		who_lbl.text = "TOCCA A TE — %s" % fl.side_name(who2).to_upper()
		if fl.s.active_faction != who2 and not String(p["kind"]).begins_with("setup"):
			who_lbl.text = "REAGISCI — %s" % fl.side_name(who2).to_upper()
		who_lbl.add_theme_color_override("font_color", Tema.side_color(who2))
		guide.text = String(p["title"])
		_build_options(p)
	_refresh_hand(p)
	_refresh_status()
	board.queue_redraw()


func _build_options(p: Dictionary) -> void:
	var opts: Array = p["options"]
	var kind := String(p["kind"])
	var hex_n := 0
	var unit_n := 0
	for o: Dictionary in opts:
		if o.has("hex"):
			hex_n += 1
		elif o.has("unit"):
			unit_n += 1
	if hex_n > 0:
		opts_box.add_child(_hint("Tocca sulla mappa uno degli esagoni evidenziati (%d)." % hex_n))
	if unit_n > 0 and kind in ["activate", "pick_mover", "sniper", "ambush_victim", "spotter", "deploy", "setup"]:
		opts_box.add_child(_hint("Tocca sulla mappa una delle pedine col bordo dorato, oppure scegli dall'elenco."))
	for i in opts.size():
		var o: Dictionary = opts[i]
		# Gli esagoni si scelgono sulla mappa; le carte dalla mano (tranne le
		# Azioni proposte in una finestra, che compaiono anche qui).
		if o.has("hex") and not o.has("card"):
			continue
		if o.has("card") and kind in ["turn", "discard"]:
			continue
		if kind == "setup" and o.has("unit"):
			continue
		var b := _btn(String(o.get("label", o.get("id", "?"))))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(SIDE_W - 44.0, 38)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var id := String(o.get("id", ""))
		if id in ["confirm", "go", "end", "pass", "stop", "no", "stay", "keep"]:
			b.add_theme_stylebox_override("normal", Tema.box(Tema.BRASS.darkened(0.55), Tema.BRASS, 2, 4, 8))
		if o.has("on") and bool(o["on"]):
			b.add_theme_color_override("font_color", Color(0.5, 1.0, 0.55))
		b.pressed.connect(func() -> void: Game.choose(i))
		opts_box.add_child(b)
	if kind == "turn":
		var blocked: Dictionary = p.get("blocked", {})
		opts_box.add_child(_hint("Tocca una carta in mano per vederla in grande e giocarla. Le carte col bordo dorato sono giocabili ora; di quelle scurite ti dico il perché."))
		if not blocked.is_empty() and blocked.size() == Game.flow.hand(int(p["who"])).size():
			opts_box.add_child(_hint("Nessuna carta è giocabile come Ordine in questo momento: scarta per pescarne di nuove."))
	elif kind == "discard":
		opts_box.add_child(_hint("Tocca le carte in mano per segnarle da scartare."))


func _hint(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = SIDE_W - 44.0
	l.add_theme_color_override("font_color", Tema.DIM.lightened(0.25))
	l.add_theme_font_size_override("font_size", 16)
	return l


# ═══ Mano ════════════════════════════════════════════════════════════════════

func _refresh_hand(p: Dictionary) -> void:
	var fl := Game.flow
	var me := Game.viewer()
	var foe := fl.opp(me)
	for c in hand_box.get_children():
		c.queue_free()
	var h := fl.hand(me)
	var playable := {}
	var marked: Array = p.get("selected_cards", [])
	if not p.is_empty() and int(p["who"]) == me:
		for o: Dictionary in p["options"]:
			if o.has("card"):
				playable[int(o["card"])] = true
	if _sel_card >= h.size():
		_sel_card = -1
	for i in h.size():
		var cv := CardView.new()
		cv.custom_minimum_size = Vector2(CARD_W, CARD_H)
		cv.setup(h[i], i)
		cv.playable = playable.has(i)
		cv.selected = i == _sel_card
		cv.marked = marked.has(i)
		cv.face_down = Game.mode == Game.Mode.DEMO
		cv.tapped.connect(_on_card_tapped)
		hand_box.add_child(cv)
	foe_lbl.text = "%s\nin mano %d carte · mazzo %d\n\n%s (tu)\nmazzo %d · scarti %d\nOrdini: %d di %d" % [
		fl.side_name(foe).to_upper(), fl.hand(foe).size(), fl.deck(foe).size(),
		fl.side_name(me).to_upper(), fl.deck(me).size(), fl.pile(me).size(),
		fl.orders_done if fl.s.active_faction == me else 0, int(fl.orders_max[me])]
	_refresh_preview(p)


func _on_card_tapped(v: CardView) -> void:
	var p := Game.pending()
	if not p.is_empty() and String(p["kind"]) == "discard":
		var opts: Array = p["options"]
		for i in opts.size():
			if String(opts[i].get("id", "")) == "toggle" and int(opts[i].get("card", -1)) == v.index:
				Game.choose(i)
				return
		return
	# Secondo tocco sulla stessa carta: se c'è un solo modo di giocarla, giocala.
	if v.index == _sel_card:
		var mine := _card_options(p, v.index)
		if mine.size() == 1:
			_sel_card = -1
			Game.choose(mine[0])
			return
	_select_card(v.index)


func _card_options(p: Dictionary, card_index: int) -> Array:
	var out: Array = []
	if p.is_empty():
		return out
	var opts: Array = p["options"]
	for i in opts.size():
		if opts[i].has("card") and int(opts[i]["card"]) == card_index:
			out.append(i)
	return out


func _select_card(i: int) -> void:
	_sel_card = -1 if i == _sel_card else i
	_refresh_hand(Game.pending())


func _refresh_preview(p: Dictionary) -> void:
	var h := Game.flow.hand(Game.viewer())
	if _sel_card < 0 or _sel_card >= h.size() or Game.mode == Game.Mode.DEMO:
		preview.visible = false
		return
	preview.visible = true
	preview_card.setup(h[_sel_card], _sel_card)
	for c in preview.get_child(0).get_children():
		if c is Button:
			c.queue_free()
	var mine := _card_options(p, _sel_card)
	if mine.is_empty():
		var why := String((p.get("blocked", {}) as Dictionary).get(_sel_card, ""))
		if why == "":
			why = "Ora non c'è modo di giocare questa carta. Le Azioni si giocano quando il gioco te le propone (durante un fuoco, una mossa, una difesa...)."
		preview_lbl.text = why
	else:
		preview_lbl.text = "Tocca di nuovo la carta o il pulsante per giocarla."
		for oi: int in mine:
			var b := _btn("GIOCA — %s" % String(p["options"][oi].get("label", "")))
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.custom_minimum_size = Vector2(236, 40)
			b.add_theme_stylebox_override("normal", Tema.box(Tema.BRASS.darkened(0.55), Tema.BRASS, 2, 4, 8))
			b.pressed.connect(func() -> void:
				_sel_card = -1
				Game.choose(oi))
			preview.get_child(0).add_child(b)


# ═══ Cronaca, dadi, carta giocata ════════════════════════════════════════════

const KIND_COL := {
	"turn": "#e0c060", "order": "#f0e8c8", "fire": "#f0a070", "roll": "#b8c8d8",
	"bad": "#f08070", "kill": "#ff6050", "good": "#90d890", "vp": "#f0d040",
	"time": "#e0b040", "fate": "#90c0f0", "melee": "#f09050", "end": "#ffffff",
	"miss": "#a8a8a0", "move": "#c8c8b8", "init": "#d0a0f0",
}


func _on_event(ev: Dictionary) -> void:
	var kind := String(ev.get("kind", ""))
	var col := String(KIND_COL.get(kind, "#c8c8b8"))
	if kind == "turn":
		log_box.append_text("\n")
	log_box.append_text("[color=%s]%s[/color]\n" % [col, String(ev.get("text", ""))])
	_log_lines += 1
	if kind == "roll" and ev.has("dice"):
		var d: Array = ev["dice"]
		dice_a.texture = load("res://assets/dice/w%d.png" % clampi(int(d[0]), 1, 6))
		dice_b.texture = load("res://assets/dice/r%d.png" % clampi(int(d[1]), 1, 6))
		dice_lbl.text = _plain(String(ev.get("text", "")))
		dice_box.visible = true
		_dice_until = Time.get_ticks_msec() + 2200
	if ev.has("card") and ev["card"] is Card:
		played_card.setup(ev["card"], -1)
		played_card.queue_redraw()
		var who := int(ev.get("who", -1))
		played_lbl.text = "%s: carta giocata" % (Game.flow.side_name(who) if who >= 0 else "")
		played_box.visible = true
		_played_until = Time.get_ticks_msec() + 2600


func _plain(bb: String) -> String:
	var re := RegEx.new()
	re.compile("\\[[^\\]]*\\]")
	return re.sub(bb, "", true)


func _process(_d: float) -> void:
	var now := Time.get_ticks_msec()
	if dice_box.visible and now > _dice_until:
		dice_box.visible = false
	if played_box.visible and now > _played_until:
		played_box.visible = false
	if skip_btn.visible != (Game.busy and not Game.flow.over):
		skip_btn.visible = Game.busy and not Game.flow.over


# ═══ Informazioni su esagono e pedine ════════════════════════════════════════

func _show_hex_info(q: int, r: int) -> void:
	var s := Game.state
	var hd: GameState.HexData = s.hex_at(q, r)
	if hd == null:
		return
	var t := "[b]%s[/b] · %s · copertura %+d" % [Domain.qr_to_label(q, r),
		String(Domain.TERRAIN_NAMES.get(hd.terrain, "?")), Rules.cover_at(s, q, r, false)]
	if hd.has_road:
		t += " · strada"
	if hd.elevation > 0:
		t += " · quota %d" % hd.elevation
	if hd.has_foxhole:
		t += " · buche"
	if hd.fortification != Domain.Fort.NONE:
		t += " · " + String(Domain.FORT_NAMES.get(hd.fortification, ""))
	if hd.has_smoke:
		t += " · fumo"
	for u in s.units_at(q, r):
		if u.is_weapon():
			continue
		t += "\n[b]%s[/b] — FP %d · gittata %d · mov. %d · morale %d" % [u.unit_name, u.fp, u.range, u.move, u.morale]
		if u.is_leader():
			t += " · comando %d" % u.command
		var st: Array = []
		if not u.efficient:
			st.append("rotta")
		if u.suppressed:
			st.append("soppressa")
		if u.activated:
			st.append("già attivata")
		if not st.is_empty():
			t += " (" + ", ".join(st) + ")"
		var w := s.weapon_carried_by(u.id)
		if w != null:
			t += "\n     con %s — FP %d · gittata %d%s" % [w.unit_name, w.fp, w.range, "" if w.efficient else " (guasta)"]
	info.text = t


# ═══ Comandi vari ════════════════════════════════════════════════════════════

func _on_stack(indices: Array) -> void:
	var p := Game.pending()
	if p.is_empty():
		return
	for c in stack_pop.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	stack_pop.add_child(v)
	var l := Label.new()
	l.text = "Più scelte in questo esagono:"
	v.add_child(l)
	for i: int in indices:
		var b := _btn(String(p["options"][i].get("label", "?")))
		b.custom_minimum_size = Vector2(300, 40)
		b.pressed.connect(func() -> void:
			stack_pop.hide()
			Game.choose(i))
		v.add_child(b)
	stack_pop.popup_centered()


func _toggle_3d() -> void:
	if view3d == null:
		view3d = SubViewportContainer.new()
		view3d.stretch = true
		view3d.set_anchors_preset(Control.PRESET_FULL_RECT)
		var vp := SubViewport.new()
		vp.handle_input_locally = false
		vp.physics_object_picking = false
		view3d.add_child(vp)
		var scene: PackedScene = load("res://scenes/Map3D.tscn")
		vp.add_child(scene.instantiate())
		board_holder.add_child(view3d)
		board_holder.move_child(view3d, 1)
		view3d.visible = false
	view3d.visible = not view3d.visible
	board.visible = not view3d.visible
	btn_3d.text = "Vista 2D" if view3d.visible else "Vista 3D"


func _set_speed_label() -> void:
	var name := "normale"
	if Game.speed < 0.8:
		name = "lento"
	elif Game.speed > 1.5:
		name = "veloce"
	btn_speed.text = "Ritmo: %s" % name


func _cycle_speed() -> void:
	if Game.speed < 0.8:
		Game.speed = 1.0
	elif Game.speed > 1.5:
		Game.speed = 0.55
	else:
		Game.speed = 2.2
	Game.save_settings()
	_set_speed_label()


func _toggle_pause() -> void:
	Game.set_paused(not Game.paused)
	btn_pause.text = "Riprendi" if Game.paused else "Pausa"


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_SPACE:
		if Game.busy:
			Game.skip()
		else:
			for id in ["confirm", "go", "pass", "no", "keep"]:
				if Game.choose_id(id):
					break
	elif k.keycode == KEY_ESCAPE:
		if _sel_card >= 0:
			_select_card(-1)


func _on_game_over(w: int) -> void:
	overlay.visible = true
	for c in overlay.get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(cc)
	var pn := PanelContainer.new()
	pn.add_theme_stylebox_override("panel", Tema.box(Tema.PANEL, Tema.BRASS, 3, 8, 24))
	cc.add_child(pn)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	pn.add_child(v)
	var fl := Game.flow
	var mine := Game.mode == Game.Mode.VS_AI
	var head := "VITTORIA!" if (mine and w == Game.human) else ("SCONFITTA" if mine else "FINE PARTITA")
	var t := Tema.title(head, 44, Tema.BRASS if (not mine or w == Game.human) else Tema.RED)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var l := Label.new()
	l.text = "Vincono i %s.\n%s" % [fl.side_name(w), fl.end_reason]
	l.custom_minimum_size.x = 460
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 12)
	v.add_child(hb)
	var again := _btn("Rigioca lo scenario", "", 190)
	again.pressed.connect(func() -> void:
		Game.start_new_game(Game.human, fl.s.scenario_number, Game.difficulty, Game.mode)
		get_tree().reload_current_scene())
	hb.add_child(again)
	var look := _btn("Guarda la mappa", "", 160)
	look.pressed.connect(func() -> void: overlay.visible = false)
	hb.add_child(look)
	var back := _btn("Menu", "", 110)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/Menu.tscn"))
	hb.add_child(back)
