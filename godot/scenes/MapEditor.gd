## Editor di mappe: dipinge terreno e lati di esagono, salva in assets/maps/mapN.json.
## Strumento di sviluppo: il salvataggio funziona in locale (Godot/desktop), non sul web.
extends Node2D

# ─── Stato mappa ──────────────────────────────────────────────────────────────

var map_num: int = 1
const COLS := 15
const ROWS := 10

var terrain: Dictionary = {}   ## "A1" → stringa terreno (default "open" se assente)
var roads: Dictionary = {}     ## "A1" → true
var sides: Dictionary = {}     ## "A2|A3" → feature stringa
var objectives: Array = []     ## [{ "hex": "F2", "vp": 2 }]

# ─── Calibrazione (in pixel sorgente, poi scalata) ───────────────────────────
var cal_hex: float = 84.0
var cal_off_x: float = 182.0
var cal_off_y: float = 46.0
var cal_scale: float = 0.57

# ─── Strumento attivo ─────────────────────────────────────────────────────────
var tool: String = "woods"   ## terreno | "road" | "hedge" | "wall" | "objective" | "erase"

var _map_texture: Texture2D = null
var _font: Font = null
var _status: String = ""
var _painting: bool = false
var _show_labels: bool = false
var _undo_stack: Array = []

const TERRAIN_TOOLS := ["open", "woods", "field", "orchard", "building", "stream"]
const TINT := {
	"open": Color(0,0,0,0), "woods": Color(0.15,0.45,0.15,0.45),
	"field": Color(0.85,0.75,0.2,0.45), "orchard": Color(0.4,0.6,0.25,0.45),
	"building": Color(0.6,0.3,0.25,0.55), "stream": Color(0.2,0.45,0.75,0.5),
}


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_load_image()
	_load_existing()
	_build_ui()
	queue_redraw()


# ─── Caricamento ──────────────────────────────────────────────────────────────

func _map_image_path() -> String:
	# Carica dall'originale in ../MAPPE (alta risoluzione, solo locale)
	var proj := ProjectSettings.globalize_path("res://")
	return proj.path_join("../MAPPE/mappa%02d_ok.png" % map_num)


func _load_image() -> void:
	var path := _map_image_path()
	var img := Image.new()
	if img.load(path) == OK:
		_map_texture = ImageTexture.create_from_image(img)
		_status = "Mappa %d caricata" % map_num
	else:
		_map_texture = null
		_status = "Immagine non trovata: %s" % path


func _json_path() -> String:
	return "res://assets/maps/map%d.json" % map_num


func _load_existing() -> void:
	terrain.clear(); roads.clear(); sides.clear(); objectives.clear()
	var f := FileAccess.open(_json_path(), FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary):
		return
	for tname in data.get("terrainGroups", {}):
		for lbl in data["terrainGroups"][tname]:
			terrain[String(lbl)] = tname
	for lbl in data.get("featureGroups", {}).get("road", []):
		roads[String(lbl)] = true
	for sf in data.get("sideFeatures", []):
		sides[_side_key(String(sf.get("from","")), String(sf.get("to","")))] = sf.get("feature","hedge")
	for obj in data.get("objectives", []):
		objectives.append({ "hex": String(obj.get("hex","")), "vp": int(obj.get("vp",1)) })


# ─── Geometria ────────────────────────────────────────────────────────────────

func _label(q: int, r: int) -> String:
	return "%s%d" % [char(65 + q), r + 1]


func _center(q: int, r: int) -> Vector2:
	return Vector2(
		cal_off_x * cal_scale + cal_hex * cal_scale * 1.5 * q,
		cal_off_y * cal_scale + cal_hex * cal_scale * sqrt(3.0) * (r + 0.5 * (q & 1))
	)


func _hsize() -> float:
	return cal_hex * cal_scale


func _corners(q: int, r: int) -> Array[Vector2]:
	var c := _center(q, r)
	var pts: Array[Vector2] = []
	for i in range(6):
		var a := deg_to_rad(60.0 * i)
		pts.append(Vector2(c.x + _hsize() * cos(a), c.y + _hsize() * sin(a)))
	return pts


func _neighbors(q: int, r: int) -> Array[Vector2i]:
	var dirs := Domain.HEX_DIRS_ODD if (q & 1) else Domain.HEX_DIRS_EVEN
	var out: Array[Vector2i] = []
	for d in dirs:
		out.append(Vector2i(q + d.x, r + d.y))
	return out


func _side_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


# ─── Disegno ──────────────────────────────────────────────────────────────────

func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.1, 0.11, 0.13))
	if _map_texture:
		var tw := _map_texture.get_width() * cal_scale
		var th := _map_texture.get_height() * cal_scale
		draw_texture_rect(_map_texture, Rect2(0, 0, tw, th), false)

	# Tinte terreno dipinte
	for lbl in terrain:
		var t: String = terrain[lbl]
		var col: Color = TINT.get(t, Color(0,0,0,0))
		if col.a > 0:
			var qr := Domain.label_to_qr(lbl)
			draw_colored_polygon(PackedVector2Array(_corners(qr.x, qr.y)), col)

	# Strade
	for lbl in roads:
		var qr := Domain.label_to_qr(lbl)
		draw_circle(_center(qr.x, qr.y), _hsize() * 0.25, Color(0.8, 0.7, 0.4, 0.8))

	# Griglia
	for q in COLS:
		for r in ROWS:
			var pts := _corners(q, r)
			pts.append(pts[0])
			draw_polyline(PackedVector2Array(pts), Color(0, 0, 0, 0.3), 1.0)
			if _show_labels:
				_text(_label(q, r), _center(q, r) + Vector2(0, -2), 10, Color(1, 1, 0.2))

	# Lati (siepi/muri)
	for key in sides:
		var labs: PackedStringArray = key.split("|")
		var a := Domain.label_to_qr(labs[0])
		var b := Domain.label_to_qr(labs[1])
		var ca := _center(a.x, a.y); var cb := _center(b.x, b.y)
		var mid := (ca + cb) * 0.5
		var dir := (cb - ca).normalized()
		var perp := Vector2(-dir.y, dir.x)
		var feat: String = sides[key]
		var col := Color(0.15, 0.5, 0.12) if feat == "hedge" else Color(0.5, 0.47, 0.42)
		draw_line(mid + perp * _hsize() * 0.52, mid - perp * _hsize() * 0.52, col, 4.0)

	# Obiettivi
	for obj in objectives:
		var qr := Domain.label_to_qr(obj["hex"])
		var oc := _center(qr.x, qr.y)
		draw_circle(oc, 10.0, Color(0.1, 0.1, 0.1, 0.85))
		draw_arc(oc, 10.0, 0, TAU, 18, Color.WHITE, 1.5)
		_text("%d" % obj["vp"], oc, 11, Color(1, 0.95, 0.3))

	# HUD
	var hud := "Mappa %d | %s | trascina=dipingi  Ctrl+Z=annulla  L=etichette  S=salva | %s" % [
		map_num, tool.to_upper(), _status]
	draw_rect(Rect2(8, 8, 900, 20), Color(0, 0, 0, 0.7))
	_text(hud, Vector2(14, 22), 13, Color.WHITE, false)


func _text(t: String, pos: Vector2, size: int, col: Color, centered: bool = true) -> void:
	if _font == null: return
	var x := pos.x
	if centered:
		x -= _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.5
	draw_string(_font, Vector2(x, pos.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


# ─── Input ────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var k := event as InputEventKey
		var step := 0.5 if k.shift_pressed else 2.0
		if k.keycode == KEY_Z and k.ctrl_pressed or k.keycode == KEY_Z and k.meta_pressed:
			_undo(); return
		match k.keycode:
			KEY_LEFT: cal_off_x -= step; queue_redraw()
			KEY_RIGHT: cal_off_x += step; queue_redraw()
			KEY_UP: cal_off_y -= step; queue_redraw()
			KEY_DOWN: cal_off_y += step; queue_redraw()
			KEY_MINUS: cal_hex -= 0.5; queue_redraw()
			KEY_EQUAL: cal_hex += 0.5; queue_redraw()
			KEY_L: _show_labels = not _show_labels; queue_redraw()
			KEY_S: _save()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_snapshot()
			_painting = true
			_paint((event as InputEventMouseButton).position, true)
		else:
			_painting = false
	elif event is InputEventMouseMotion and _painting:
		_paint((event as InputEventMouseMotion).position, false)


# ─── Annulla ──────────────────────────────────────────────────────────────────

func _snapshot() -> void:
	_undo_stack.append({
		"terrain": terrain.duplicate(true), "roads": roads.duplicate(true),
		"sides": sides.duplicate(true), "objectives": objectives.duplicate(true),
	})
	if _undo_stack.size() > 40:
		_undo_stack.pop_front()


func _undo() -> void:
	if _undo_stack.is_empty():
		return
	var s: Dictionary = _undo_stack.pop_back()
	terrain = s["terrain"]; roads = s["roads"]; sides = s["sides"]; objectives = s["objectives"]
	_status = "Annullato"
	queue_redraw()


func _hex_under(pos: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := _hsize() * 1.1
	for q in COLS:
		for r in ROWS:
			var d := pos.distance_to(_center(q, r))
			if d < bd:
				bd = d; best = Vector2i(q, r)
	return best


func _paint(pos: Vector2, is_click: bool) -> void:
	var h := _hex_under(pos)
	if h.x < 0:
		return
	var lbl := _label(h.x, h.y)
	match tool:
		"hedge", "wall":
			_set_side(h, pos, tool, is_click)
		"road":
			if is_click:
				if roads.has(lbl): roads.erase(lbl)
				else: roads[lbl] = true
			else:
				roads[lbl] = true
		"objective":
			if is_click: _toggle_objective(lbl)
		"erase":
			terrain.erase(lbl); roads.erase(lbl)
		_:
			terrain[lbl] = tool   # un tipo di terreno
	queue_redraw()


## Click singolo = alterna; trascinamento = aggiunge.
func _set_side(h: Vector2i, pos: Vector2, feat: String, is_click: bool) -> void:
	# Trova il vicino il cui bordo condiviso è più vicino al click
	var best_nb := Vector2i(-1, -1)
	var bd := 1e9
	for nb in _neighbors(h.x, h.y):
		if nb.x < 0 or nb.x >= COLS or nb.y < 0 or nb.y >= ROWS:
			continue
		var mid := (_center(h.x, h.y) + _center(nb.x, nb.y)) * 0.5
		var d := pos.distance_to(mid)
		if d < bd:
			bd = d; best_nb = nb
	if best_nb.x < 0:
		return
	var key := _side_key(_label(h.x, h.y), _label(best_nb.x, best_nb.y))
	if is_click and sides.has(key):
		sides.erase(key)
	else:
		sides[key] = feat


func _toggle_objective(lbl: String) -> void:
	for i in objectives.size():
		if objectives[i]["hex"] == lbl:
			objectives.remove_at(i)
			return
	objectives.append({ "hex": lbl, "vp": 2 })


# ─── Salvataggio ──────────────────────────────────────────────────────────────

func _save() -> void:
	var tgroups := {}
	for lbl in terrain:
		var t: String = terrain[lbl]
		if t == "open": continue
		if not tgroups.has(t): tgroups[t] = []
		tgroups[t].append(lbl)
	var sf := []
	for key in sides:
		var labs: PackedStringArray = key.split("|")
		sf.append({ "from": labs[0], "to": labs[1], "feature": sides[key] })
	var data := {
		"id": "map%d" % map_num, "cols": COLS, "rows": ROWS, "default": "open",
		"terrainGroups": tgroups,
		"featureGroups": { "road": roads.keys() },
		"sideFeatures": sf,
		"objectives": objectives,
	}
	var f := FileAccess.open(_json_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
		_status = "SALVATO in map%d.json (%d terreni, %d lati)" % [map_num, terrain.size(), sides.size()]
	else:
		_status = "ERRORE salvataggio (il web non può scrivere; usa Godot locale)"
	queue_redraw()


# ─── UI ───────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bar := HBoxContainer.new()
	bar.position = Vector2(8, 36)
	bar.add_theme_constant_override("separation", 4)
	layer.add_child(bar)
	for t in TERRAIN_TOOLS + ["road", "hedge", "wall", "objective", "erase"]:
		var b := Button.new()
		b.text = t
		b.toggle_mode = true
		b.pressed.connect(func(): tool = t; queue_redraw())
		bar.add_child(b)
	# Riga 2: selezione mappa + salva + menù
	var bar2 := HBoxContainer.new()
	bar2.position = Vector2(8, 66)
	bar2.add_theme_constant_override("separation", 4)
	layer.add_child(bar2)
	for delta in [-1, 1]:
		var nav := Button.new()
		nav.text = "◀ mappa" if delta < 0 else "mappa ▶"
		nav.pressed.connect(func(): _change_map(delta))
		bar2.add_child(nav)
	var save_b := Button.new()
	save_b.text = "💾 SALVA"
	save_b.pressed.connect(_save)
	bar2.add_child(save_b)
	var back := Button.new()
	back.text = "☰ Menù"
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Menu.tscn"))
	bar2.add_child(back)


func _change_map(delta: int) -> void:
	map_num = clampi(map_num + delta, 1, 24)
	_load_image()
	_load_existing()
	queue_redraw()
