## Schermata iniziale: a sinistra l'elenco compatto dei 24 scenari; al centro
## l'ARTWORK pittorico a piena altezza; a destra, in una colonna ampia,
## l'anteprima della MAPPA (grande, in alto) e sotto l'Ordine di Battaglia su
## due colonne con le pedine reali (i due avversari — si sceglie con chi
## giocare). UI costruita via codice.
extends Control

var _scenarios: Array = []     ## scenari.json (numero, titolo, luogo, data)
var _catalog: Array = []       ## catalog.json (forze_axis/allies, fazioni…)
var _selected_num: int = 0

var _list: VBoxContainer
var _map_tex: TextureRect
var _art_tex: TextureRect
var _ob_axis: VBoxContainer
var _ob_allies: VBoxContainer
var _axis_btn: Button
var _allies_btn: Button
var _changelog: Panel
var _rules_panel: Panel
var _rules_label: RichTextLabel
var _difficulty: int = Domain.BotDifficulty.GREEN

## Nazione (stringa catalogo) → nome mostrato.
const NATION_LABEL := {
	"german": "Germania", "italian": "Italia", "romanian": "Romania",
	"russian": "Unione Sovietica", "american": "Stati Uniti",
	"british": "Gran Bretagna", "french": "Francia",
}


func _ready() -> void:
	_scenarios = _load_json("res://assets/scenari.json")
	_catalog = _load_json("res://assets/scenarios/catalog.json")
	_build_ui()
	if _scenarios.size() > 0:
		_select(int(_scenarios[0].get("numero", 1)))


func _load_json(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return data if data is Array else []


func _catalog_entry(num: int) -> Dictionary:
	for s in _catalog:
		if int(s.get("numero", 0)) == num:
			return s
	return {}


# ─── Costruzione UI ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.11, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Colonna sinistra STRETTA: elenco dei 24 scenari (lascia spazio ad artwork+mappa).
	var scroll := ScrollContainer.new()
	scroll.anchor_left = 0.0
	scroll.anchor_right = 0.0
	scroll.anchor_top = 0.0
	scroll.anchor_bottom = 1.0
	scroll.offset_left = 12
	scroll.offset_right = 214
	scroll.offset_top = 16
	scroll.offset_bottom = -44  # spazio per versione + Changelog in basso
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)
	_build_list()

	# ARTWORK al centro, a PIENA ALTEZZA: l'elemento dominante (cambia con lo scenario).
	_art_tex = TextureRect.new()
	_art_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art_tex.anchor_left = 0.0
	_art_tex.anchor_right = 1.0
	_art_tex.anchor_top = 0.0
	_art_tex.anchor_bottom = 1.0
	_art_tex.offset_left = 224
	_art_tex.offset_right = -492
	_art_tex.offset_top = 16
	_art_tex.offset_bottom = -16
	add_child(_art_tex)

	# Colonna destra: MAPPA in alto (affiancata all'artwork) e, SOTTO, l'ORDINE DI
	# BATTAGLIA su due colonne. Anch'essi cambiano con lo scenario selezionato.
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -480
	panel.offset_right = -12
	panel.offset_top = 16
	panel.offset_bottom = -16
	add_child(panel)
	var pad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(m, 10)
	panel.add_child(pad)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	pad.add_child(inner)

	# Mappa (in alto).
	_map_tex = TextureRect.new()
	_map_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_map_tex.custom_minimum_size = Vector2(0, 300)
	inner.add_child(_map_tex)

	# Ordine di Battaglia (sotto la mappa): una colonna per avversario; cliccando
	# una colonna si avvia la partita con quella fazione.
	var ob := HBoxContainer.new()
	ob.add_theme_constant_override("separation", 8)
	ob.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(ob)
	ob.add_child(_ob_column(true))
	ob.add_child(_ob_column(false))

	# Versione + Changelog (sempre presenti, in basso a sinistra).
	var ver := Label.new()
	ver.text = "v%s" % Domain.VERSION
	ver.add_theme_font_size_override("font_size", 13)
	ver.modulate = Color(0.72, 0.74, 0.78)
	ver.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ver.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ver.offset_left = 18
	ver.offset_top = -40
	ver.offset_right = 78
	ver.offset_bottom = -12
	add_child(ver)
	var clog_btn := Button.new()
	clog_btn.text = "Changelog"
	clog_btn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	clog_btn.offset_left = 84
	clog_btn.offset_top = -42
	clog_btn.offset_right = 204
	clog_btn.offset_bottom = -12
	clog_btn.pressed.connect(func() -> void:
		if _changelog != null:
			_changelog.visible = not _changelog.visible)
	add_child(clog_btn)
	_build_changelog_panel()

	# Pulsante «Regole scenario»: mostra setup e regole speciali del selezionato.
	var rules_btn := Button.new()
	rules_btn.text = "Regole scenario"
	rules_btn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	rules_btn.offset_left = 210
	rules_btn.offset_top = -42
	rules_btn.offset_right = 360
	rules_btn.offset_bottom = -12
	rules_btn.pressed.connect(func() -> void:
		if _rules_panel != null:
			_rules_panel.visible = not _rules_panel.visible)
	add_child(rules_btn)
	_build_rules_panel()

	# Difficoltà del bot (FlipBot): Recluta / Di linea / Veterano.
	var diff_lbl := Label.new()
	diff_lbl.text = "Difficoltà IA:"
	diff_lbl.add_theme_font_size_override("font_size", 13)
	diff_lbl.modulate = Color(0.72, 0.74, 0.78)
	diff_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	diff_lbl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	diff_lbl.offset_left = 372
	diff_lbl.offset_top = -42
	diff_lbl.offset_right = 470
	diff_lbl.offset_bottom = -12
	add_child(diff_lbl)
	var diff_opt := OptionButton.new()
	for lvl in [Domain.BotDifficulty.GREEN, Domain.BotDifficulty.LINE, Domain.BotDifficulty.VETERAN]:
		diff_opt.add_item(String(Domain.BOT_DIFFICULTY_LABELS.get(lvl, "?")), lvl)
	diff_opt.selected = 0
	diff_opt.tooltip_text = "Più alto = l'IA ha più carte, più ordini e si arrende più tardi (FlipBot)"
	diff_opt.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	diff_opt.offset_left = 474
	diff_opt.offset_top = -44
	diff_opt.offset_right = 604
	diff_opt.offset_bottom = -10
	diff_opt.item_selected.connect(func(idx: int) -> void:
		_difficulty = diff_opt.get_item_id(idx))
	add_child(diff_opt)

	# Modalità tutorial: aiuto guidato a ogni ordine/azione (persistente).
	var tut := CheckButton.new()
	tut.text = "Modalità tutorial (aiuto guidato)"
	tut.button_pressed = Game.tutorial_enabled
	tut.tooltip_text = "Se attiva, a ogni ordine o azione compare una finestra con la regola e cosa fare nel programma"
	tut.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	tut.offset_left = 620
	tut.offset_top = -46
	tut.offset_right = 1000
	tut.offset_bottom = -8
	tut.toggled.connect(func(on: bool) -> void: Game.set_tutorial(on))
	add_child(tut)
	# Nota: l'«Editor mappe» è stato spostato nella colonna laterale in partita.


## Una colonna dell'Ordine di Battaglia: pulsante-fazione in cima + elenco forze.
## `axis` = colonna dell'Asse (gioca come Germania/axis) o degli Alleati.
func _ob_column(axis: bool) -> Control:
	var box := PanelContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 8)
	margin.add_child(col)
	box.add_child(margin)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 48)
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.add_theme_font_size_override("font_size", 16)
	btn.tooltip_text = "Clicca per giocare con questa fazione"
	btn.pressed.connect(_start.bind(Domain.Faction.GERMAN if axis else Domain.Faction.RUSSIAN))
	col.add_child(btn)
	var forces := VBoxContainer.new()
	forces.add_theme_constant_override("separation", 1)
	col.add_child(forces)
	if axis:
		_axis_btn = btn
		_ob_axis = forces
	else:
		_allies_btn = btn
		_ob_allies = forces
	return box


func _build_list() -> void:
	for child in _list.get_children():
		child.queue_free()
	for sc in _scenarios:
		var num := int(sc.get("numero", 0))
		var titolo: String = sc.get("titolo", "—")
		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 28)
		btn.add_theme_font_size_override("font_size", 12)
		btn.clip_text = true
		btn.text = "%2d.  %s" % [num, titolo]
		btn.tooltip_text = "%s — %s" % [sc.get("luogo", ""), sc.get("data", "")]
		btn.pressed.connect(_select.bind(num))
		_list.add_child(btn)


# ─── Selezione / avvio ────────────────────────────────────────────────────────

func _select(num: int) -> void:
	_selected_num = num
	_map_tex.texture = _load_tex("res://assets/maps_img/map%d.jpg" % num)
	_art_tex.texture = _load_tex("res://assets/artwork/scenario_%02d.jpg" % num)
	var cat := _catalog_entry(num)
	_fill_ob(_axis_btn, _ob_axis, String(cat.get("fazione_axis", "german")), cat.get("forze_axis", []), Domain.Faction.GERMAN)
	_fill_ob(_allies_btn, _ob_allies, String(cat.get("fazione_allies", "russian")), cat.get("forze_allies", []), Domain.Faction.RUSSIAN)
	if _rules_label != null:
		_rules_label.text = ScenarioRules.as_bbcode(num)


## Riempie una colonna OB: il pulsante-fazione e l'elenco forze, ognuna con la
## PEDINA reale (segnalino) accanto al conteggio.
func _fill_ob(btn: Button, forces: VBoxContainer, nation: String, forze: Array, faction: int) -> void:
	if btn == null:
		return
	btn.text = String(NATION_LABEL.get(nation, nation.capitalize()))
	for child in forces.get_children():
		child.queue_free()
	var nat := UnitChart.nation_code(nation)
	for u in forze:
		var n := int(u.get("n", 1))
		var tipo: String = u.get("tipo", "")
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		var tex := _counter_for(faction, tipo, nat)
		if tex != null:
			var ic := TextureRect.new()
			ic.texture = tex
			ic.custom_minimum_size = Vector2(42, 42)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(ic)
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.modulate = Color(0.84, 0.86, 0.9)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.text = "%d × %s" % [n, tipo]
		row.add_child(lbl)
		forces.add_child(row)


## Texture del segnalino per un'unità dell'OB (stessa logica della mappa).
func _counter_for(faction: int, tipo: String, nat: String) -> Texture2D:
	var c := UnitChart.category(tipo)
	if c == UnitChart.Cat.SKIP or c == UnitChart.Cat.FOXHOLE:
		return null
	var u := UnitChart.build_unit("ob", faction, tipo, 0, 0, nat)
	if u == null or u.art_name == "":
		return null
	var folder: String = u.nation_art if u.nation_art != "" else String(Domain.FACTION_ART_DIR.get(u.faction, ""))
	var path := "res://assets/counters/%s/%s.png" % [folder, u.art_name]
	return load(path) if ResourceLoader.exists(path) else null


## Pannello del changelog (centrato), aperto dal pulsante «Changelog». Legge
## res://assets/changelog.md.
## Pannello (overlay) con setup e regole speciali dello scenario selezionato.
func _build_rules_panel() -> void:
	_rules_panel = Panel.new()
	_rules_panel.visible = false
	_rules_panel.set_anchors_preset(Control.PRESET_CENTER)
	_rules_panel.offset_left = -420
	_rules_panel.offset_top = -320
	_rules_panel.offset_right = 420
	_rules_panel.offset_bottom = 320
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


func _build_changelog_panel() -> void:
	_changelog = Panel.new()
	_changelog.visible = false
	_changelog.set_anchors_preset(Control.PRESET_CENTER)
	_changelog.offset_left = -380
	_changelog.offset_top = -300
	_changelog.offset_right = 380
	_changelog.offset_bottom = 300
	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(m, 16)
	_changelog.add_child(pad)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	pad.add_child(v)
	var head := HBoxContainer.new()
	var t := Label.new()
	t.text = "Novità — Changelog"
	t.add_theme_font_size_override("font_size", 18)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := Button.new()
	close.text = "Chiudi"
	close.pressed.connect(func() -> void: _changelog.visible = false)
	head.add_child(close)
	v.add_child(head)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.text = _load_text("res://assets/changelog.md")
	sc.add_child(rt)
	add_child(_changelog)


func _load_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "(changelog non disponibile)"
	var t := f.get_as_text()
	f.close()
	return t


func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _start(faction: int) -> void:
	if _selected_num <= 0:
		return
	Game.start_new_game(faction, _selected_num, _difficulty)
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
