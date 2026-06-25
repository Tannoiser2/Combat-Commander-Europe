## Schermata iniziale: a sinistra l'elenco compatto dei 24 scenari; a destra, in
## pila, l'anteprima della MAPPA (piccola, in alto), l'Ordine di Battaglia su due
## colonne (i due avversari — si sceglie con chi giocare) e infine l'ARTWORK
## pittorico, che prende tutta l'altezza rimanente. UI costruita via codice.
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

	# Colonna sinistra: elenco compatto dei 24 scenari (entra tutto).
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 16
	scroll.offset_top = 16
	scroll.offset_right = -724
	scroll.offset_bottom = -16
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)
	_build_list()

	# Colonna destra: pila Mappa (piccola) → Ordine di Battaglia → Artwork (grande).
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -708
	panel.offset_top = 16
	panel.offset_right = -16
	panel.offset_bottom = -16
	add_child(panel)
	var pad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(m, 12)
	panel.add_child(pad)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	pad.add_child(inner)

	# Mappa (piccola, in alto).
	_map_tex = TextureRect.new()
	_map_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_map_tex.custom_minimum_size = Vector2(0, 188)
	inner.add_child(_map_tex)

	# Ordine di Battaglia su due colonne: i due avversari. Cliccando una colonna
	# si avvia la partita con quella fazione.
	var ob := HBoxContainer.new()
	ob.add_theme_constant_override("separation", 10)
	inner.add_child(ob)
	var axis_box := _ob_column(true)
	var allies_box := _ob_column(false)
	ob.add_child(axis_box)
	ob.add_child(allies_box)

	# Artwork (grande): prende tutta l'altezza rimanente.
	_art_tex = TextureRect.new()
	_art_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art_tex.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_art_tex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(_art_tex)

	# Editor mappe (in alto a destra).
	var ed := Button.new()
	ed.text = "Editor mappe"
	ed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ed.offset_left = -150
	ed.offset_top = 12
	ed.offset_right = -16
	ed.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/MapEditor.tscn"))
	add_child(ed)


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
	btn.custom_minimum_size = Vector2(0, 42)
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
	_fill_ob(_axis_btn, _ob_axis, String(cat.get("fazione_axis", "german")), cat.get("forze_axis", []))
	_fill_ob(_allies_btn, _ob_allies, String(cat.get("fazione_allies", "russian")), cat.get("forze_allies", []))


## Riempie una colonna OB: il pulsante-fazione («Gioca con …») e l'elenco forze.
func _fill_ob(btn: Button, forces: VBoxContainer, nation: String, forze: Array) -> void:
	if btn == null:
		return
	btn.text = "Gioca: %s" % String(NATION_LABEL.get(nation, nation.capitalize()))
	for child in forces.get_children():
		child.queue_free()
	for u in forze:
		var n := int(u.get("n", 1))
		var tipo: String = u.get("tipo", "")
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.modulate = Color(0.84, 0.86, 0.9)
		lbl.text = "%d × %s" % [n, tipo]
		forces.add_child(lbl)


func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _start(faction: int) -> void:
	if _selected_num <= 0:
		return
	Game.start_new_game(faction, _selected_num)
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
