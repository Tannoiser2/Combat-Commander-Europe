## Schermata iniziale: elenco scenari a sinistra; a destra anteprima della MAPPA
## (tabellone) e dell'ARTWORK pittorico dello scenario selezionato, più la scelta
## della fazione. UI costruita via codice.
extends Control

var _scenarios: Array = []
var _selected_num: int = 0

var _list: VBoxContainer
var _title: Label
var _subtitle: Label
var _map_tex: TextureRect
var _art_tex: TextureRect
var _play_ger: Button
var _play_rus: Button


func _ready() -> void:
	_scenarios = _load_scenarios()
	_build_ui()
	if _scenarios.size() > 0:
		_select(int(_scenarios[0].get("numero", 1)))


func _load_scenarios() -> Array:
	var f := FileAccess.open("res://assets/scenari.json", FileAccess.READ)
	if f == null:
		return []
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return data if data is Array else []


# ─── Costruzione UI ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.11, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "COMBAT COMMANDER: EUROPE"
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 14
	title.offset_bottom = 60
	add_child(title)

	# Colonna sinistra: lista scenari (scroll).
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 24
	scroll.offset_top = 74
	scroll.offset_right = -748
	scroll.offset_bottom = -24
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 5)
	scroll.add_child(_list)
	_build_list()

	# Colonna destra: dettaglio (titolo, Mappa + Artwork, fazioni).
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -708
	panel.offset_top = 74
	panel.offset_right = -24
	panel.offset_bottom = -24
	add_child(panel)
	var pad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(m, 16)
	panel.add_child(pad)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	pad.add_child(inner)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	inner.add_child(_title)
	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 14)
	_subtitle.modulate = Color(0.8, 0.82, 0.86)
	inner.add_child(_subtitle)

	# Mappa + Artwork affiancati (occupano lo spazio centrale).
	var imgs := HBoxContainer.new()
	imgs.add_theme_constant_override("separation", 14)
	imgs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(imgs)
	_map_tex = _make_preview(imgs, "MAPPA")
	_art_tex = _make_preview(imgs, "ARTWORK")

	# Fazioni + avvio.
	var hint := Label.new()
	hint.text = "Con quale fazione vuoi giocare?"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(hint)
	var fac := HBoxContainer.new()
	fac.alignment = BoxContainer.ALIGNMENT_CENTER
	fac.add_theme_constant_override("separation", 20)
	inner.add_child(fac)
	_play_ger = Button.new()
	_play_ger.text = "Germania"
	_play_ger.custom_minimum_size = Vector2(190, 52)
	_play_ger.pressed.connect(_start.bind(Domain.Faction.GERMAN))
	fac.add_child(_play_ger)
	_play_rus = Button.new()
	_play_rus.text = "Unione Sovietica"
	_play_rus.custom_minimum_size = Vector2(190, 52)
	_play_rus.pressed.connect(_start.bind(Domain.Faction.RUSSIAN))
	fac.add_child(_play_rus)

	# Editor mappe (in alto a destra).
	var ed := Button.new()
	ed.text = "Editor mappe"
	ed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ed.offset_left = -170
	ed.offset_top = 12
	ed.offset_right = -16
	ed.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/MapEditor.tscn"))
	add_child(ed)


## Riquadro etichetta + immagine (mantiene le proporzioni). Restituisce il TextureRect.
func _make_preview(parent: Control, caption: String) -> TextureRect:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	parent.add_child(box)
	var cap := Label.new()
	cap.text = caption
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 13)
	box.add_child(cap)
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tr)
	return tr


func _build_list() -> void:
	for child in _list.get_children():
		child.queue_free()
	for sc in _scenarios:
		var num := int(sc.get("numero", 0))
		var titolo: String = sc.get("titolo", "—")
		var luogo: String = sc.get("luogo", "")
		var data: String = sc.get("data", "")
		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 46)
		btn.text = "%2d.  %s\n      %s — %s" % [num, titolo, luogo, data]
		btn.pressed.connect(_select.bind(num))
		_list.add_child(btn)


# ─── Selezione / avvio ────────────────────────────────────────────────────────

func _select(num: int) -> void:
	_selected_num = num
	var sc := {}
	for s in _scenarios:
		if int(s.get("numero", 0)) == num:
			sc = s
			break
	_title.text = "Scenario %d — %s" % [num, sc.get("titolo", "")]
	_subtitle.text = "%s · %s" % [sc.get("luogo", ""), sc.get("data", "")]
	_map_tex.texture = _load_tex("res://assets/maps_img/map%d.jpg" % num)
	_art_tex.texture = _load_tex("res://assets/artwork/scenario_%02d.jpg" % num)


func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _start(faction: int) -> void:
	if _selected_num <= 0:
		return
	Game.start_new_game(faction, _selected_num)
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
