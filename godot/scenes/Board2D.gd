## Mappa 2D: immagine della mappa originale con le pedine sopra.
##
## Non conosce le regole: disegna lo stato e, per la decisione in corso
## (Game.pending()), evidenzia esagoni e pedine che si possono toccare.
## Spostamento: trascina con un dito o col mouse. Zoom: rotella, pizzico con
## due dita o gesto del trackpad. Doppio tocco: reinquadra.
class_name Board2D
extends Control

signal hex_info(q: int, r: int)   ## esagono indicato (per il pannello informazioni)

const COL_STEP := Color(0.35, 0.85, 0.35, 0.36)
const COL_TARGET := Color(0.95, 0.18, 0.12, 0.42)
const COL_PICK := Color(1.0, 0.82, 0.2, 0.36)
const COL_GOLD := Color(1.0, 0.80, 0.25)
const COL_ON := Color(0.35, 0.95, 0.45)
const COL_OFF := Color(0.75, 0.75, 0.75)
const COL_AX := Color(0.36, 0.42, 0.45)
const COL_AL := Color(0.55, 0.40, 0.22)

var cal_hex := 59.2
var cal_ox := 129.0
var cal_oy := 69.0
var view_scale := 1.0
var view_origin := Vector2.ZERO
var _fit_scale := 1.0
var _custom := false
var _tex: Texture2D = null
var _tex_id := ""
var _cache := {}
var _font: Font
var _font_bold: Font
var _press := Vector2.ZERO
var _dragged := false
var _touches := {}
var _pinch_d := 0.0
var _last_tap := 0
var _hover := Vector2i(-1, -1)
var _fx: Array = []          ## effetti temporanei: { kind, a, b, t0, dur }
var _t := 0.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = load("res://assets/fonts/BarlowCondensed-Medium.ttf")
	_font_bold = load("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
	Game.state_changed.connect(_on_state)
	Game.decision_changed.connect(queue_redraw)
	Game.chronicle.connect(_on_event)
	resized.connect(_fit)
	_on_state()


func _on_state() -> void:
	var s := Game.state
	if s == null:
		return
	cal_hex = s.cal_hex
	cal_ox = s.cal_ox
	cal_oy = s.cal_oy
	if s.map_image != _tex_id:
		_tex_id = s.map_image
		_tex = load("res://assets/maps_img/%s.jpg" % _tex_id) as Texture2D
		_custom = false
	_fit()
	queue_redraw()


func _fit() -> void:
	if _tex == null or size.x < 2.0 or Game.state == null:
		return
	# Inquadra la griglia di esagoni (non i bordi decorativi dell'immagine).
	var s := Game.state
	var x0 := cal_ox - cal_hex * 1.25
	var y0 := cal_oy - cal_hex * 1.15
	var x1 := cal_ox + cal_hex * 1.5 * (s.map_cols - 1) + cal_hex * 1.25
	var y1 := cal_oy + cal_hex * sqrt(3.0) * (s.map_rows - 0.5) + cal_hex * 1.15
	x0 = maxf(0.0, x0)
	y0 = maxf(0.0, y0)
	x1 = minf(float(_tex.get_width()), x1)
	y1 = minf(float(_tex.get_height()), y1)
	_fit_scale = minf(size.x / (x1 - x0), size.y / (y1 - y0))
	if _custom:
		return
	view_scale = _fit_scale
	view_origin = Vector2((size.x - (x1 - x0) * view_scale) * 0.5 - x0 * view_scale,
		(size.y - (y1 - y0) * view_scale) * 0.5 - y0 * view_scale)
	queue_redraw()


func reset_view() -> void:
	_custom = false
	_fit()


func _process(delta: float) -> void:
	_t += delta
	if not visible:
		return
	var now := Time.get_ticks_msec()
	_fx = _fx.filter(func(e: Dictionary) -> bool: return now - int(e["t0"]) < int(e["dur"]))
	if not _fx.is_empty() or not Game.pending().is_empty():
		queue_redraw()


func _on_event(ev: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	match String(ev.get("kind", "")):
		"fire":
			if ev.has("from") and ev.has("to"):
				_fx.append({ "kind": "line", "a": ev["from"], "b": ev["to"], "t0": now, "dur": 1500 })
		"move":
			if ev.has("to"):
				_fx.append({ "kind": "ring", "a": ev["to"], "t0": now, "dur": 600, "col": Color(1, 1, 1) })
	if ev.has("hex") and String(ev.get("kind", "")) != "fire":
		var col := Color(1.0, 0.5, 0.1)
		if String(ev.get("kind", "")) == "vp":
			col = Color(1.0, 0.85, 0.2)
		_fx.append({ "kind": "ring", "a": ev["hex"], "t0": now, "dur": 1100, "col": col })
	if String(ev.get("fx", "")) in ["break", "kill"] and ev.has("unit") and Game.state != null:
		var u: Unit = Game.state.unit_by_id(String(ev["unit"]))
		if u != null:
			_fx.append({ "kind": "ring", "a": u.pos(), "t0": now, "dur": 900, "col": Color(1.0, 0.2, 0.15) })


# ─── Geometria ───────────────────────────────────────────────────────────────

func _hs() -> float:
	return cal_hex * view_scale


func hex_center(q: int, r: int) -> Vector2:
	var ix := cal_ox + cal_hex * 1.5 * q
	var iy := cal_oy + cal_hex * sqrt(3.0) * (r + 0.5 * (q & 1))
	return view_origin + view_scale * Vector2(ix, iy)


func _corners(q: int, r: int, k: float = 1.0) -> PackedVector2Array:
	var c := hex_center(q, r)
	var rad := _hs() * k
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * i)
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	return pts


func hex_at(p: Vector2) -> Vector2i:
	var s := Game.state
	if s == null:
		return Vector2i(-1, -1)
	var best := Vector2i(-1, -1)
	var bd := _hs() * 0.95
	for q in s.map_cols:
		for r in s.map_rows:
			var d := p.distance_to(hex_center(q, r))
			if d < bd:
				bd = d
				best = Vector2i(q, r)
	return best


# ─── Disegno ─────────────────────────────────────────────────────────────────

func _txt(t: String, pos: Vector2, sz: float, col: Color, bold: bool = true, outline: bool = true) -> void:
	var f := _font_bold if bold else _font
	var isz := int(maxf(8.0, sz))
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, isz).x
	var p := Vector2(pos.x - w * 0.5, pos.y + isz * 0.35)
	if outline:
		draw_string_outline(f, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, isz, maxi(2, isz / 5), Color(0, 0, 0, 0.9))
	draw_string(f, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, isz, col)


func _load_tex(path: String) -> Texture2D:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


func _counter_tex(u: Unit) -> Texture2D:
	if u.art_name == "":
		return null
	var folder: String = u.nation_art if u.nation_art != "" else String(Domain.FACTION_ART_DIR.get(u.faction, ""))
	if not u.efficient and not u.is_weapon():
		var half := _load_tex("res://assets/counters/%s_Half/%s.png" % [folder, u.art_name])
		if half != null:
			return half
	return _load_tex("res://assets/counters/%s/%s.png" % [folder, u.art_name])


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.08, 0.07))
	var s := Game.state
	if s == null or _tex == null:
		return
	draw_texture_rect(_tex, Rect2(view_origin, Vector2(_tex.get_width(), _tex.get_height()) * view_scale), false)
	var p := Game.pending()
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	_draw_ground(s)
	_draw_objectives(s)
	# Raggio di Comando del comandante scelto.
	if p.has("leader") and p.has("radius"):
		var L: Unit = s.unit_by_id(String(p["leader"]))
		if L != null:
			for q in s.map_cols:
				for r in s.map_rows:
					if HexGrid.distance(L.q, L.r, q, r) <= int(p["radius"]):
						draw_colored_polygon(_corners(q, r, 0.98), Color(1.0, 0.75, 0.2, 0.13))
						draw_polyline(_closed(_corners(q, r, 0.98)), Color(1.0, 0.75, 0.2, 0.35), 1.5)
	# Esagoni che si possono toccare.
	var hex_opts := {}
	var unit_opts := {}
	if not p.is_empty():
		for o: Dictionary in p["options"]:
			if o.has("hex"):
				hex_opts["%d,%d" % [o["hex"].x, o["hex"].y]] = o
			elif o.has("unit"):
				unit_opts[String(o["unit"])] = o
	var kind := String(p.get("kind", ""))
	for key in hex_opts:
		var o: Dictionary = hex_opts[key]
		var h: Vector2i = o["hex"]
		var col := COL_PICK
		if kind in ["fire_target", "fire_mods", "arty_target"] or (kind == "advance" and String(o.get("label", "")).contains("CORPO")):
			col = COL_TARGET
		elif kind == "move":
			col = COL_STEP
		if kind == "arty_target":
			col.a = 0.16
		col.a *= 0.75 + 0.25 * pulse
		draw_colored_polygon(_corners(h.x, h.y, 0.96), col)
		draw_polyline(_closed(_corners(h.x, h.y, 0.96)), Color(col.r, col.g, col.b, 0.95), 2.5)
		if o.has("cost"):
			_txt("%d PM" % int(o["cost"]), hex_center(h.x, h.y) + Vector2(0, _hs() * 0.55), _hs() * 0.30, Color(1, 1, 1))
	# Esagono di riferimento della decisione (bersaglio / esagono entrato).
	if p.has("hex"):
		var ph: Vector2i = p["hex"]
		draw_polyline(_closed(_corners(ph.x, ph.y, 1.0)), Color(1.0, 0.25, 0.2, 0.6 + 0.4 * pulse), 4.0)
	_draw_units(s, p, unit_opts, pulse)
	_draw_fx()
	if _hover.x >= 0:
		draw_polyline(_closed(_corners(_hover.x, _hover.y, 1.0)), Color(1, 1, 1, 0.35), 1.5)


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out


func _draw_ground(s: GameState) -> void:
	var hs := _hs()
	for key in s.hexes:
		var hd: GameState.HexData = s.hexes[key]
		if not (hd.has_foxhole or hd.has_smoke or hd.has_blaze or hd.fortification != Domain.Fort.NONE):
			continue
		var parts := String(key).split(",")
		var c := hex_center(int(parts[0]), int(parts[1]))
		var names: Array = []
		if hd.has_foxhole:
			names.append("Foxholes")
		match hd.fortification:
			Domain.Fort.TRENCH: names.append("Trench")
			Domain.Fort.PILLBOX: names.append("Pillbox")
			Domain.Fort.BUNKER: names.append("Bunker")
			Domain.Fort.WIRE: names.append("Wire")
			Domain.Fort.MINES: names.append("Mines")
		if hd.has_blaze:
			names.append("Blaze")
		for i in names.size():
			var tex := _load_tex("res://assets/markers/%s.png" % names[i])
			var sz := hs * 0.72
			var pos := c + Vector2(-hs * 0.55 + i * hs * 0.3, hs * 0.12)
			if tex != null:
				draw_texture_rect(tex, Rect2(pos, Vector2(sz, sz)), false, Color(1, 1, 1, 0.95))
			else:
				draw_rect(Rect2(pos, Vector2(sz, sz * 0.6)), Color(0.5, 0.1, 0.1, 0.9))
				_txt("MINE", pos + Vector2(sz * 0.5, sz * 0.3), hs * 0.24, Color(1, 1, 1))
		if hd.has_smoke:
			for k in 5:
				var a := k * 1.26 + _t * 0.25
				draw_circle(c + Vector2(cos(a), sin(a)) * hs * 0.32, hs * 0.38, Color(0.92, 0.92, 0.92, 0.33))
			_txt("FUMO", c + Vector2(0, -hs * 0.62), hs * 0.24, Color(1, 1, 1))


func _draw_objectives(s: GameState) -> void:
	var hs := _hs()
	for o in s.objectives:
		var c := hex_center(o.q, o.r)
		var col := Color(0.85, 0.85, 0.85)
		if o.controller == Flow.AX:
			col = COL_AX.lightened(0.35)
		elif o.controller == Flow.AL:
			col = COL_AL.lightened(0.35)
		draw_polyline(_closed(_corners(o.q, o.r, 0.9)), Color(col.r, col.g, col.b, 0.95), 4.0)
		var tag := c + Vector2(0, -hs * 0.72)
		var owner := "nessuno"
		if o.controller >= 0 and Game.flow != null:
			owner = Game.flow.side_name(o.controller)
		var t := "Ob.%d  %s  %d PV" % [o.id, owner, o.vp]
		var w := _font_bold.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(maxf(9.0, hs * 0.24))).x
		draw_rect(Rect2(tag.x - w * 0.5 - 4, tag.y - hs * 0.15, w + 8, hs * 0.32), Color(0.08, 0.08, 0.08, 0.82))
		_txt(t, tag, hs * 0.24, col, true, false)


func _draw_units(s: GameState, p: Dictionary, unit_opts: Dictionary, pulse: float) -> void:
	var hs := _hs()
	var by_hex := {}
	for u in s.units.values():
		if u.is_weapon():
			continue
		var k: String = u.hex_key()
		if not by_hex.has(k):
			by_hex[k] = []
		by_hex[k].append(u)
	var sel: Array = p.get("selected", [])
	var focus := String(p.get("unit", p.get("leader", "")))
	var kind := String(p.get("kind", ""))
	for k in by_hex:
		var stack: Array = by_hex[k]
		stack.sort_custom(func(a: Unit, b: Unit) -> bool: return a.id < b.id)
		var n := stack.size()
		var c := hex_center(stack[0].q, stack[0].r)
		var sz := hs * (1.18 if n == 1 else (1.0 if n == 2 else 0.86))
		var spread := 0.0 if n == 1 else minf(hs * 0.56, hs * 1.25 / float(n - 1))
		for i in n:
			var u: Unit = stack[i]
			var off := Vector2((i - (n - 1) * 0.5) * spread, (i - (n - 1) * 0.5) * hs * 0.10)
			var rect := Rect2(c + off - Vector2(sz, sz) * 0.5, Vector2(sz, sz))
			_draw_counter(s, u, rect, hs)
			var w := s.weapon_carried_by(u.id)
			var wopt: Dictionary = unit_opts.get(w.id, {}) if w != null else {}
			var opt: Dictionary = unit_opts.get(u.id, wopt)
			var is_on := sel.has(u.id) or (w != null and sel.has(w.id))
			if u.id == focus:
				draw_rect(rect.grow(4), Color(0.3, 0.8, 1.0, 0.95), false, 4.0)
			if not opt.is_empty():
				if opt.has("on"):
					var colx := COL_ON if is_on else COL_OFF
					draw_rect(rect.grow(3), colx, false, 4.0 if is_on else 2.5)
					_badge(rect.position + Vector2(sz * 0.5, -hs * 0.02), "DENTRO" if is_on else "FUORI", colx)
				else:
					var g := COL_GOLD
					g.a = 0.55 + 0.45 * pulse
					draw_rect(rect.grow(3 + 2 * pulse), g, false, 4.0)
					if kind == "activate" and u.is_leader() and u.command > 0:
						_badge(rect.position + Vector2(sz * 0.5, -hs * 0.02), "COMANDA %d" % u.command, COL_GOLD)


func _badge(center: Vector2, t: String, col: Color) -> void:
	var hs := _hs()
	var isz := int(maxf(9.0, hs * 0.22))
	var w := _font_bold.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, isz).x
	var r := Rect2(center.x - w * 0.5 - 4, center.y - isz * 0.75, w + 8, isz * 1.3)
	draw_rect(r, Color(0.05, 0.05, 0.05, 0.9))
	draw_rect(r, col, false, 1.5)
	_txt(t, center, isz, col, true, false)


func _draw_counter(s: GameState, u: Unit, rect: Rect2, hs: float) -> void:
	var tex := _counter_tex(u)
	draw_rect(Rect2(rect.position + Vector2(3, 3), rect.size), Color(0, 0, 0, 0.45))
	if tex != null:
		draw_texture_rect(tex, rect, false)
	else:
		draw_rect(rect, COL_AX if u.faction == Flow.AX else COL_AL)
		_txt(u.unit_name, rect.get_center(), hs * 0.2, Color(1, 1, 1))
	draw_rect(rect, COL_AX.darkened(0.5) if u.faction == Flow.AX else COL_AL.darkened(0.5), false, 2.0)
	if u.activated:
		draw_rect(rect, Color(0, 0, 0, 0.30))
	var tags: Array = []
	if not u.efficient:
		tags.append(["ROTTA", Color(0.85, 0.12, 0.1)])
	if u.suppressed:
		tags.append(["SOPPRESSA", Color(0.9, 0.65, 0.1)])
	if u.veteran:
		tags.append(["VETERANA", Color(0.2, 0.55, 0.9)])
	for i in tags.size():
		var isz := int(maxf(8.0, hs * 0.2))
		var y := rect.position.y + rect.size.y * 0.42 + i * isz * 1.25
		draw_rect(Rect2(rect.position.x, y - isz * 0.7, rect.size.x, isz * 1.2), Color(tags[i][1].r, tags[i][1].g, tags[i][1].b, 0.88))
		_txt(String(tags[i][0]), Vector2(rect.get_center().x, y - isz * 0.1), isz, Color(1, 1, 1), true, false)
	# Arma portata: pedina piccola nell'angolo.
	var w := s.weapon_carried_by(u.id)
	if w != null:
		var wsz := rect.size.x * 0.52
		var wr := Rect2(rect.position + rect.size - Vector2(wsz * 0.78, wsz * 0.78), Vector2(wsz, wsz))
		var wt := _counter_tex(w)
		if wt != null:
			draw_texture_rect(wt, wr, false, Color(1, 1, 1) if w.efficient else Color(0.6, 0.45, 0.45))
		else:
			draw_rect(wr, Color(0.85, 0.82, 0.7))
			_txt("RADIO" if w.unit_name.contains("Radio") else "ARMA", wr.get_center(), hs * 0.17, Color(0.1, 0.1, 0.1), true, false)
		draw_rect(wr, Color(0.1, 0.1, 0.1), false, 1.5)
		if not w.efficient:
			_txt("GUASTA", wr.get_center(), hs * 0.17, Color(1, 0.4, 0.3))


func _draw_fx() -> void:
	var now := Time.get_ticks_msec()
	var hs := _hs()
	for e: Dictionary in _fx:
		var k := clampf(float(now - int(e["t0"])) / float(e["dur"]), 0.0, 1.0)
		match String(e["kind"]):
			"line":
				var a := hex_center(e["a"].x, e["a"].y)
				var b := hex_center(e["b"].x, e["b"].y)
				var head := a.lerp(b, minf(1.0, k * 3.0))
				draw_line(a, head, Color(1.0, 0.85, 0.3, 1.0 - k * 0.6), 4.0)
				draw_circle(b, hs * (0.2 + 0.3 * k), Color(1.0, 0.4, 0.1, 0.7 * (1.0 - k)))
			"ring":
				var c := hex_center(e["a"].x, e["a"].y)
				var col: Color = e.get("col", Color(1, 1, 1))
				col.a = 1.0 - k
				draw_arc(c, hs * (0.4 + 0.8 * k), 0, TAU, 36, col, 5.0)


# ─── Input ───────────────────────────────────────────────────────────────────

func _zoom_at(pos: Vector2, factor: float) -> void:
	if _tex == null:
		return
	var img := (pos - view_origin) / view_scale
	var ns := clampf(view_scale * factor, _fit_scale * 0.6, _fit_scale * 5.0)
	view_scale = ns
	view_origin = pos - img * ns
	_custom = true
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = t.position
		else:
			_touches.erase(t.index)
		if _touches.size() == 2:
			var v: Array = _touches.values()
			_pinch_d = (v[0] as Vector2).distance_to(v[1])
			_dragged = true
		return
	if event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_touches[d.index] = d.position
		if _touches.size() >= 2:
			var v2: Array = _touches.values()
			var nd := (v2[0] as Vector2).distance_to(v2[1])
			var mid := ((v2[0] as Vector2) + (v2[1] as Vector2)) * 0.5 - global_position
			if _pinch_d > 1.0:
				_zoom_at(mid, nd / _pinch_d)
			_pinch_d = nd
			view_origin += d.relative * 0.5
			_dragged = true
			accept_event()
		return
	if event is InputEventMagnifyGesture:
		_zoom_at((event as InputEventMagnifyGesture).position, (event as InputEventMagnifyGesture).factor)
		return
	if event is InputEventPanGesture:
		view_origin -= (event as InputEventPanGesture).delta * 12.0
		_custom = true
		queue_redraw()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mb.position, 1.15)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mb.position, 1.0 / 1.15)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press = mb.position
				_dragged = _touches.size() >= 2
			elif not _dragged and _touches.size() < 2:
				var now := Time.get_ticks_msec()
				var h := hex_at(mb.position)
				if now - _last_tap < 320 and h.x < 0:
					reset_view()
				_last_tap = now
				if h.x >= 0:
					hex_info.emit(h.x, h.y)
					Game.click_hex(h.x, h.y)
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if (mm.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE)) != 0:
			if _touches.size() >= 2:
				return
			if not _dragged and mm.position.distance_to(_press) > 8.0:
				_dragged = true
			if _dragged:
				view_origin += mm.relative
				_custom = true
				queue_redraw()
		else:
			var h2 := hex_at(mm.position)
			if h2 != _hover:
				_hover = h2
				if h2.x >= 0:
					hex_info.emit(h2.x, h2.y)
				queue_redraw()
