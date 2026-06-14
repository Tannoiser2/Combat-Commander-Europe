## Editor di mappe: dipinge terreno, altezze e lati di esagono sopra l'immagine
## della mappa (sempre visibile, opacità overlay regolabile). Salva in mapN.json.
extends Node2D

const COLS := 15
const ROWS := 10

# ─── Dati mappa ───────────────────────────────────────────────────────────────
var map_num: int = 1
var terrain: Dictionary = {}    ## "A1" → tipo terreno
var roads: Dictionary = {}      ## "A1" → true
var sides: Dictionary = {}      ## "A2|A3" → feature
var elevation: Dictionary = {}  ## "A1" → int (0 = base)
var objectives: Array = []      ## [{ hex, vp }]

# ─── Griglia (in pixel dell'immagine 1500px, ~uguale per tutte le mappe) ─────
var grid_hex: float = 55.0
var grid_ox: float = 138.0
var grid_oy: float = 46.0

# ─── Vista (pan/zoom) ─────────────────────────────────────────────────────────
var view_scale: float = 0.59
var view_origin: Vector2 = Vector2(16, 106)
var overlay_alpha: float = 0.5   ## opacità dell'overlay dipinto (slider)

# ─── Strumento ────────────────────────────────────────────────────────────────
var tool: String = "woods"

var _map_texture: Texture2D = null
var _font: Font = null
var _status: String = ""
var _painting: bool = false
var _show_labels: bool = false
var _undo_stack: Array = []
var _map_label: Label = null

const TERRAIN_TOOLS := ["open", "woods", "field", "orchard", "building", "stream", "brush"]
## Lati: (etichetta, chiave feature)
const SIDE_TOOLS := [
	["siepe", "hedge"], ["bocage", "bocage"], ["muro", "wall"],
	["steccato", "fence"], ["dirupo", "cliff"], ["corso d'acqua", "stream_side"],
]
const SIDE_COLORS := {
	"hedge": Color(0.1, 0.55, 0.1), "bocage": Color(0.05, 0.35, 0.05),
	"wall": Color(0.5, 0.47, 0.42), "fence": Color(0.65, 0.5, 0.3),
	"cliff": Color(0.35, 0.3, 0.28), "stream_side": Color(0.2, 0.5, 0.85),
}
const TINT := {
	"open": Color(0,0,0,0), "woods": Color(0.15,0.5,0.15), "field": Color(0.9,0.8,0.2),
	"orchard": Color(0.45,0.65,0.25), "building": Color(0.6,0.3,0.5), "stream": Color(0.2,0.5,0.85),
	"brush": Color(0.5,0.6,0.2),
}
const ELEV_TINT := [Color(0,0,0,0), Color(0.75,0.55,0.3), Color(0.6,0.4,0.2), Color(0.45,0.3,0.15)]


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_load_image()
	_load_existing()
	_build_ui()
	queue_redraw()


# ─── Caricamento ──────────────────────────────────────────────────────────────

func _load_image() -> void:
	# Immagine inclusa nel progetto (sempre disponibile, anche sul web)
	var path := "res://assets/maps_img/map%d.jpg" % map_num
	_map_texture = load(path) as Texture2D
	_status = "Mappa %d caricata" % map_num if _map_texture else "Immagine mancante: %s" % path


func _json_path() -> String:
	return "res://assets/maps/map%d.json" % map_num


func _load_existing() -> void:
	terrain.clear(); roads.clear(); sides.clear(); elevation.clear(); objectives.clear()
	# Preferisci il file del PROGETTO (committato); il browser solo come ripiego
	# per le mappe non ancora committate (3-24).
	var f := FileAccess.open(_json_path(), FileAccess.READ)
	if f == null:
		f = FileAccess.open("user://map%d.json" % map_num, FileAccess.READ)
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
	for grp in data.get("elevationGroups", []):
		for lbl in grp.get("hexes", []):
			elevation[String(lbl)] = int(grp.get("elevation", 1))
	for sf in data.get("sideFeatures", []):
		sides[_side_key(String(sf.get("from","")), String(sf.get("to","")))] = sf.get("feature","hedge")
	for obj in data.get("objectives", []):
		objectives.append({ "hex": String(obj.get("hex","")), "vp": int(obj.get("vp",1)) })
	# Taratura griglia salvata per questa mappa (se presente)
	if data.has("_calib"):
		var cal: Dictionary = data["_calib"]
		grid_hex = cal.get("hex", grid_hex)
		grid_ox = cal.get("ox", grid_ox)
		grid_oy = cal.get("oy", grid_oy)


# ─── Geometria ────────────────────────────────────────────────────────────────

func _label(q: int, r: int) -> String:
	return "%s%d" % [char(65 + q), r + 1]


func _center(q: int, r: int) -> Vector2:
	var ix := grid_ox + 1.5 * grid_hex * q
	var iy := grid_oy + sqrt(3.0) * grid_hex * (r + 0.5 * (q & 1))
	return view_origin + view_scale * Vector2(ix, iy)


func _hsize() -> float:
	return grid_hex * view_scale


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
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0.1, 0.11, 0.13))
	# Mappa di base (sempre piena opacità)
	if _map_texture:
		var sz := Vector2(_map_texture.get_width(), _map_texture.get_height()) * view_scale
		draw_texture_rect(_map_texture, Rect2(view_origin, sz), false)

	# Overlay dipinto (opacità regolabile)
	var a := overlay_alpha
	for q in COLS:
		for r in ROWS:
			var lbl := _label(q, r)
			var poly := PackedVector2Array(_corners(q, r))
			# Altezza (sotto al terreno)
			var ev: int = elevation.get(lbl, 0)
			if ev > 0:
				var ec: Color = ELEV_TINT[min(ev, 3)]
				draw_colored_polygon(poly, Color(ec.r, ec.g, ec.b, a * 0.6))
			# Terreno
			if terrain.has(lbl):
				var col: Color = TINT.get(terrain[lbl], Color(0,0,0,0))
				if col.a > 0 or terrain[lbl] != "open":
					draw_colored_polygon(poly, Color(col.r, col.g, col.b, a))
			if roads.has(lbl):
				draw_circle(_center(q, r), _hsize() * 0.22, Color(0.85, 0.72, 0.4, min(1.0, a + 0.3)))
			if ev > 0:
				_text("%d" % ev, _center(q, r) + Vector2(_hsize()*0.5, -_hsize()*0.5), 12, Color(1,1,1))

	# Griglia
	for q in COLS:
		for r in ROWS:
			var pts := _corners(q, r); pts.append(pts[0])
			draw_polyline(PackedVector2Array(pts), Color(0, 0, 0, 0.35), 1.0)
			if _show_labels:
				_text(_label(q, r), _center(q, r) + Vector2(0, -2), 10, Color(1, 1, 0.3))

	# Lati (siepi/muri)
	for key in sides:
		var labs: PackedStringArray = key.split("|")
		var pa := Domain.label_to_qr(labs[0]); var pb := Domain.label_to_qr(labs[1])
		var ca := _center(pa.x, pa.y); var cb := _center(pb.x, pb.y)
		var mid := (ca + cb) * 0.5
		var perp := Vector2(-(cb - ca).normalized().y, (cb - ca).normalized().x)
		var col: Color = SIDE_COLORS.get(sides[key], Color(0.6, 0.2, 0.2))
		var wd := 6.0 if sides[key] == "bocage" else 5.0
		draw_line(mid + perp * _hsize() * 0.52, mid - perp * _hsize() * 0.52, col, wd)

	# Obiettivi
	for obj in objectives:
		var p := Domain.label_to_qr(obj["hex"])
		var oc := _center(p.x, p.y)
		draw_circle(oc, 10.0, Color(0.1, 0.1, 0.1, 0.85))
		draw_arc(oc, 10.0, 0, TAU, 18, Color.WHITE, 1.5)
		_text("%d" % obj["vp"], oc, 11, Color(1, 0.95, 0.3))

	# HUD
	var hud := "Mappa %d/24 | %s | trascina=dipingi  frecce=pan  Maiusc+frecce=griglia  [ ]=dimensione  +/-=zoom  Ctrl+Z  S=salva | %s" % [
		map_num, tool.to_upper(), _status]
	draw_rect(Rect2(8, 8, 1180, 18), Color(0, 0, 0, 0.7))
	_text(hud, Vector2(14, 21), 12, Color.WHITE, false)


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
		if (k.keycode == KEY_Z) and (k.ctrl_pressed or k.meta_pressed):
			_undo(); return
		# Maiusc+frecce = sposta la GRIGLIA rispetto alla mappa (calibrazione)
		if k.shift_pressed and k.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
			var gs := 1.0
			match k.keycode:
				KEY_LEFT: grid_ox -= gs
				KEY_RIGHT: grid_ox += gs
				KEY_UP: grid_oy -= gs
				KEY_DOWN: grid_oy += gs
			queue_redraw(); return
		var pan := 24.0
		match k.keycode:
			KEY_LEFT: view_origin.x += pan; queue_redraw()
			KEY_RIGHT: view_origin.x -= pan; queue_redraw()
			KEY_UP: view_origin.y += pan; queue_redraw()
			KEY_DOWN: view_origin.y -= pan; queue_redraw()
			KEY_EQUAL, KEY_KP_ADD: _zoom(1.08);
			KEY_MINUS, KEY_KP_SUBTRACT: _zoom(1.0/1.08)
			KEY_BRACKETLEFT: grid_hex -= 0.3; queue_redraw()    # calibrazione griglia (rara)
			KEY_BRACKETRIGHT: grid_hex += 0.3; queue_redraw()
			KEY_L: _show_labels = not _show_labels; queue_redraw()
			KEY_S: _save()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_snapshot(); _painting = true
			_paint((event as InputEventMouseButton).position, true)
		else:
			_painting = false
	elif event is InputEventMouseMotion and _painting:
		_paint((event as InputEventMouseMotion).position, false)


func _zoom(f: float) -> void:
	view_scale = clampf(view_scale * f, 0.2, 2.0)
	queue_redraw()


# ─── Annulla ──────────────────────────────────────────────────────────────────

func _snapshot() -> void:
	_undo_stack.append({
		"terrain": terrain.duplicate(true), "roads": roads.duplicate(true),
		"sides": sides.duplicate(true), "elevation": elevation.duplicate(true),
		"objectives": objectives.duplicate(true),
	})
	if _undo_stack.size() > 50: _undo_stack.pop_front()


func _undo() -> void:
	if _undo_stack.is_empty(): return
	var s: Dictionary = _undo_stack.pop_back()
	terrain = s["terrain"]; roads = s["roads"]; sides = s["sides"]
	elevation = s["elevation"]; objectives = s["objectives"]
	_status = "Annullato"; queue_redraw()


# ─── Pittura ──────────────────────────────────────────────────────────────────

func _hex_under(pos: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1); var bd := _hsize() * 1.1
	for q in COLS:
		for r in ROWS:
			var d := pos.distance_to(_center(q, r))
			if d < bd: bd = d; best = Vector2i(q, r)
	return best


func _paint(pos: Vector2, is_click: bool) -> void:
	var h := _hex_under(pos)
	if h.x < 0: return
	var lbl := _label(h.x, h.y)
	if tool in ["hedge", "bocage", "wall", "fence", "cliff", "stream_side"]:
		_set_side(h, pos, tool, is_click)
		queue_redraw(); return
	match tool:
		"road":
			if is_click and roads.has(lbl): roads.erase(lbl)
			else: roads[lbl] = true
		"elev1": elevation[lbl] = 1
		"elev2": elevation[lbl] = 2
		"elev3": elevation[lbl] = 3
		"elev0": elevation.erase(lbl)
		"objective":
			if is_click: _toggle_objective(lbl)
		"erase":
			terrain.erase(lbl); roads.erase(lbl); elevation.erase(lbl)
		_: terrain[lbl] = tool
	queue_redraw()


func _set_side(h: Vector2i, pos: Vector2, feat: String, is_click: bool) -> void:
	var best_nb := Vector2i(-1, -1); var bd := 1e9
	for nb in _neighbors(h.x, h.y):
		if nb.x < 0 or nb.x >= COLS or nb.y < 0 or nb.y >= ROWS: continue
		var mid := (_center(h.x, h.y) + _center(nb.x, nb.y)) * 0.5
		var d := pos.distance_to(mid)
		if d < bd: bd = d; best_nb = nb
	if best_nb.x < 0: return
	var key := _side_key(_label(h.x, h.y), _label(best_nb.x, best_nb.y))
	if is_click and sides.has(key): sides.erase(key)
	else: sides[key] = feat


func _toggle_objective(lbl: String) -> void:
	# Click ripetuti: 1 → 2 → 3 → rimuovi
	for i in objectives.size():
		if objectives[i]["hex"] == lbl:
			objectives[i]["vp"] += 1
			if objectives[i]["vp"] > 3:
				objectives.remove_at(i)
			return
	objectives.append({ "hex": lbl, "vp": 1 })


# ─── Salvataggio ──────────────────────────────────────────────────────────────

func _save() -> void:
	var tgroups := {}
	for lbl in terrain:
		var t: String = terrain[lbl]
		if t == "open": continue
		if not tgroups.has(t): tgroups[t] = []
		tgroups[t].append(lbl)
	var egroups := {}
	for lbl in elevation:
		var e: int = elevation[lbl]
		if e <= 0: continue
		if not egroups.has(e): egroups[e] = []
		egroups[e].append(lbl)
	var elev_arr := []
	for e in egroups: elev_arr.append({ "elevation": e, "hexes": egroups[e] })
	var sf := []
	for key in sides:
		var labs: PackedStringArray = key.split("|")
		sf.append({ "from": labs[0], "to": labs[1], "feature": sides[key] })
	var data := {
		"id": "map%d" % map_num, "cols": COLS, "rows": ROWS, "default": "open",
		"terrainGroups": tgroups, "featureGroups": { "road": roads.keys() },
		"elevationGroups": elev_arr, "sideFeatures": sf, "objectives": objectives,
		"_calib": { "hex": grid_hex, "ox": grid_ox, "oy": grid_oy },  # taratura griglia per mappa
	}
	var json_str := JSON.stringify(data, "\t")
	var counts := "(%d terreni, %d alt., %d lati)" % [terrain.size(), elevation.size(), sides.size()]

	# 1) Persistenza nel browser/utente (IndexedDB sul web) — sopravvive ai ricaricamenti
	var uf := FileAccess.open("user://map%d.json" % map_num, FileAccess.WRITE)
	if uf:
		uf.store_string(json_str); uf.close()

	if OS.has_feature("web"):
		# 2a) Sul web: scarica il file da committare
		_download_web("map%d.json" % map_num, json_str)
		_status = "SCARICATO map%d.json %s — mettilo in assets/maps/ e fai push" % [map_num, counts]
	else:
		# 2b) Su desktop: scrive direttamente il file del progetto
		var f := FileAccess.open(_json_path(), FileAccess.WRITE)
		if f:
			f.store_string(json_str); f.close()
			_status = "SALVATO map%d.json %s" % [map_num, counts]
		else:
			_status = "Salvato in user:// (impossibile scrivere nel progetto)"
	queue_redraw()


## Avvia il download del file nel browser (solo export web).
func _download_web(filename: String, content: String) -> void:
	var js := """
	(function(name, text){
		var blob = new Blob([text], {type: 'application/json'});
		var url = URL.createObjectURL(blob);
		var a = document.createElement('a');
		a.href = url; a.download = name;
		document.body.appendChild(a); a.click();
		setTimeout(function(){ document.body.removeChild(a); URL.revokeObjectURL(url); }, 200);
	})(%s, %s);
	""" % [JSON.stringify(filename), JSON.stringify(content)]
	JavaScriptBridge.eval(js, true)


# ─── UI ───────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var layer := CanvasLayer.new(); add_child(layer)
	var v := VBoxContainer.new(); v.position = Vector2(8, 26)
	v.add_theme_constant_override("separation", 0)
	v.theme = _compact_theme()
	layer.add_child(v)

	# Riga TERRENO
	var row1 := HBoxContainer.new(); row1.add_theme_constant_override("separation", 3); v.add_child(row1)
	_row_label(row1, "TERRENO:")
	for t in TERRAIN_TOOLS:
		_tool_btn(row1, t, t)

	# Riga LATI (siepi, muri, bocage…)
	var rowS := HBoxContainer.new(); rowS.add_theme_constant_override("separation", 3); v.add_child(rowS)
	_row_label(rowS, "LATI:")
	for pair in SIDE_TOOLS:
		_tool_btn(rowS, pair[0], pair[1])

	# Riga ALTRO (altezze, strada, obiettivo, cancella)
	var row2 := HBoxContainer.new(); row2.add_theme_constant_override("separation", 3); v.add_child(row2)
	_row_label(row2, "ALTRO:")
	_tool_btn(row2, "alt.1", "elev1"); _tool_btn(row2, "alt.2", "elev2")
	_tool_btn(row2, "alt.3", "elev3"); _tool_btn(row2, "alt.0", "elev0")
	_tool_btn(row2, "strada", "road")
	_tool_btn(row2, "obiettivo", "objective")
	_tool_btn(row2, "cancella", "erase")

	var row3 := HBoxContainer.new(); row3.add_theme_constant_override("separation", 5); v.add_child(row3)
	var opl := Label.new(); opl.text = "Opacità:"; opl.add_theme_font_size_override("font_size", 10)
	opl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; row3.add_child(opl)
	var sld := HSlider.new(); sld.min_value = 0.0; sld.max_value = 1.0; sld.step = 0.05
	sld.value = overlay_alpha; sld.custom_minimum_size = Vector2(110, 0)
	sld.value_changed.connect(func(val): overlay_alpha = val; queue_redraw())
	row3.add_child(sld)
	# Navigazione mappe con testo chiaro
	var prev := Button.new(); prev.text = "< MAPPA PREC"; prev.add_theme_font_size_override("font_size", 10)
	prev.pressed.connect(func(): _change_map(-1)); row3.add_child(prev)
	_map_label = Label.new(); _map_label.add_theme_font_size_override("font_size", 11)
	_map_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; row3.add_child(_map_label)
	var nextb := Button.new(); nextb.text = "MAPPA SUCC >"; nextb.add_theme_font_size_override("font_size", 10)
	nextb.pressed.connect(func(): _change_map(1)); row3.add_child(nextb)
	var sb := Button.new(); sb.text = "SALVA"; sb.add_theme_font_size_override("font_size", 10)
	sb.pressed.connect(_save); row3.add_child(sb)
	var bk := Button.new(); bk.text = "MENU"; bk.add_theme_font_size_override("font_size", 10)
	bk.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Menu.tscn")); row3.add_child(bk)
	_update_map_label()


## Tema con pulsanti bassi (poco margine verticale) per condensare le righe.
func _compact_theme() -> Theme:
	var th := Theme.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.22, 0.23, 0.26) if state != "pressed" else Color(0.35, 0.5, 0.7)
		sb.content_margin_top = 1; sb.content_margin_bottom = 1
		sb.content_margin_left = 5; sb.content_margin_right = 5
		sb.corner_radius_top_left = 3; sb.corner_radius_top_right = 3
		sb.corner_radius_bottom_left = 3; sb.corner_radius_bottom_right = 3
		th.set_stylebox(state, "Button", sb)
	return th


func _row_label(parent: Node, txt: String) -> void:
	var l := Label.new(); l.text = txt
	l.add_theme_font_size_override("font_size", 10)
	l.custom_minimum_size = Vector2(54, 0); l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(l)


func _tool_btn(parent: Node, lbl: String, t: String) -> void:
	var b := Button.new(); b.text = lbl; b.toggle_mode = true
	b.add_theme_font_size_override("font_size", 10)
	b.add_theme_constant_override("h_separation", 2)
	parent.add_child(b)
	b.pressed.connect(func(): tool = t; queue_redraw())


func _change_map(delta: int) -> void:
	map_num = clampi(map_num + delta, 1, 24)
	# Reimposta la griglia ai default; _load_existing la sovrascrive se la mappa ha _calib
	grid_hex = 55.0; grid_ox = 138.0; grid_oy = 46.0
	_load_image(); _load_existing(); _undo_stack.clear()
	_update_map_label(); queue_redraw()


func _update_map_label() -> void:
	if _map_label:
		_map_label.text = "  Mappa %d / 24  " % map_num
