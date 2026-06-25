## Nodo di disegno della mappa esagonale e delle pedine.
## Usa _draw() per SVG-like rendering direttamente su canvas.
extends Node2D

# ─── Vista mappa ──────────────────────────────────────────────────────────────
# La griglia usa la stessa geometria dell'editor: i centri esagono sono calcolati
# in pixel dell'immagine a piena risoluzione (cal_hex/cal_ox/cal_oy dal `_calib`
# del JSON) e poi trasformati a schermo con view_origin + view_scale.

var cal_hex: float = 59.2    ## Raggio esagono (centro→vertice) in pixel immagine
var cal_ox: float = 129.0    ## Centro dell'esagono (0,0) in pixel immagine
var cal_oy: float = 69.0
var view_scale: float = 1.0      ## Scala immagine→schermo (calcolata per adattarsi)
var view_origin: Vector2 = Vector2.ZERO
var _map_image_id: String = ""   ## id immagine attualmente caricata
var _terrain_debug: bool = false  ## true = mostra le tinte del terreno (tasto T)

## Pedine
const CW := 62.0   ## Larghezza pedina uomo
const CH := 58.0   ## Altezza pedina uomo
const WCW := 42.0  ## Pedina arma (quadrata)

## Colori fazione
const COL_GER    := Color(0.55, 0.50, 0.30, 1.0)   ## kaki tedesco
const COL_RUS    := Color(0.25, 0.45, 0.25, 1.0)   ## verde sovietico
const COL_STRIPE := Color(0.0,  0.0,  0.0,  0.45)  ## strisce nere semi-trasparenti
const COL_TEXT   := Color(1.0,  1.0,  1.0,  1.0)
const COL_DARK   := Color(0.0,  0.0,  0.0,  1.0)
const COL_MORALE := Color(1.0,  0.90, 0.0,  1.0)   ## giallo morale
const COL_CMD    := Color(1.0,  0.60, 0.0,  1.0)   ## arancio comando
const COL_HIGHLIGHT := Color(1.0, 1.0, 0.0, 0.35)
const COL_OBJECTIVE := Color(0.9, 0.2, 0.2, 0.55)
const COL_SELECT := Color(0.0,  0.8,  1.0,  0.55)
const COL_GROUP  := Color(1.0,  0.55, 0.0,  0.9)   ## contorno arancio del gruppo di comando
const COL_GROUP_OFF := Color(0.6, 0.6, 0.6, 0.7)   ## pezzo idoneo ma escluso dal gruppo di fuoco
const COL_FIRE_TARGET := Color(0.95, 0.15, 0.15, 0.5)  ## esagono bersaglio del fuoco

## Fortificazioni: lettera e colore del badge
const FORT_LETTERS := { 1: "T", 2: "C", 3: "B", 4: "≋", 5: "✸" }  # Trincea/Casamatta/Bunker/Filo/Mine
const FORT_COLORS := {
	1: Color(0.7, 0.9, 1.0),   # Trincea
	2: Color(0.8, 0.8, 0.85),  # Casamatta
	3: Color(0.85, 0.85, 0.9), # Bunker
	4: Color(1.0, 0.8, 0.3),   # Filo
	5: Color(1.0, 0.4, 0.3),   # Mine
}

## Terreno → colore di tinta
const TERRAIN_TINT := {
	Domain.TerrainType.WOODS:    Color(0.18, 0.40, 0.18, 0.45),
	Domain.TerrainType.BUILDING: Color(0.55, 0.45, 0.35, 0.55),
	Domain.TerrainType.ROAD:     Color(0.70, 0.60, 0.40, 0.35),
	Domain.TerrainType.STREAM:   Color(0.20, 0.45, 0.70, 0.45),
	Domain.TerrainType.FIELD:    Color(0.85, 0.75, 0.20, 0.40),
	Domain.TerrainType.ORCHARD:  Color(0.40, 0.60, 0.25, 0.40),
}

# ─── Riferimenti ──────────────────────────────────────────────────────────────

var _map_texture: Texture2D = null
var _font: Font = null
var _counter_cache: Dictionary = {}  ## path → Texture2D (o null se mancante)


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_refresh_map()
	Game.state_changed.connect(_on_state_changed)
	Game.unit_moved.connect(func(_id, _q, _r): queue_redraw())
	Game.unit_eliminated.connect(func(_id): queue_redraw())


func _on_state_changed() -> void:
	_refresh_map()
	queue_redraw()


# ─── Mappa / vista ────────────────────────────────────────────────────────────

## Allinea immagine e taratura allo scenario corrente (come l'editor di mappe).
func _refresh_map() -> void:
	if Game.state == null:
		return
	cal_hex = Game.state.cal_hex
	cal_ox = Game.state.cal_ox
	cal_oy = Game.state.cal_oy
	if Game.state.map_image != _map_image_id:
		_map_image_id = Game.state.map_image
		var path := "res://assets/maps_img/%s.jpg" % _map_image_id
		_map_texture = load(path) as Texture2D
	_update_view()


## Calcola scala e origine per far entrare l'immagine sotto la barra superiore.
func _update_view() -> void:
	if _map_texture == null:
		return
	var vp := get_viewport_rect().size
	var top := 46.0
	var bottom := 44.0
	var avail := Vector2(maxi(1, int(vp.x)), maxf(100.0, vp.y - top - bottom))
	var iw := float(_map_texture.get_width())
	var ih := float(_map_texture.get_height())
	view_scale = minf(avail.x / iw, avail.y / ih)
	view_origin = Vector2((vp.x - iw * view_scale) * 0.5, top)


## Raggio esagono a schermo.
func _hsize() -> float:
	return cal_hex * view_scale


# ─── Disegno principale ───────────────────────────────────────────────────────

func _draw() -> void:
	# Sfondo pieno: evita la "schermata grigia" se manca la texture o fuori mappa.
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.12, 0.13, 0.15, 1.0))

	if Game.state == null:
		return
	var s := Game.state
	_update_view()

	# Mappa sottostante (immagine dello scenario, adattata alla vista)
	if _map_texture:
		var sz := Vector2(_map_texture.get_width(), _map_texture.get_height()) * view_scale
		draw_texture_rect(_map_texture, Rect2(view_origin, sz), false)
	elif _font:
		draw_string(_font, Vector2(100, 120),
			"[immagine mappa non caricata: %s]" % _map_image_id,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.6, 0.6))

	# Tinte terreno — solo in debug (tasto T); di norma la mappa le mostra già
	if _terrain_debug:
		for key in s.hexes:
			var hd: GameState.HexData = s.hexes[key]
			var tint: Color = TERRAIN_TINT.get(hd.terrain, Color.TRANSPARENT)
			if tint.a > 0:
				var parts := String(key).split(",")
				_draw_hex_fill(int(parts[0]), int(parts[1]), tint)
			if hd.has_road:
				var p2 := String(key).split(",")
				_draw_hex_fill(int(p2[0]), int(p2[1]), Color(0.7, 0.6, 0.4, 0.4))

	# Obiettivi (gettone con valore VP e controllore)
	for obj in s.objectives:
		_draw_hex_fill(obj.q, obj.r, COL_OBJECTIVE)
		var oc := _hex_center(obj.q, obj.r)
		draw_circle(oc, 11.0, Color(0.1, 0.1, 0.1, 0.85))
		draw_arc(oc, 11.0, 0, TAU, 20, Color.WHITE, 1.5)
		_draw_text("%d" % obj.vp, oc, 12.0, Color(1, 0.95, 0.3), true)

	# Fumo (Granate/Polvere/Fosforo/barrage): nube grigia translucida (hindrance)
	for key in s.hexes:
		var shd: GameState.HexData = s.hexes[key]
		if shd.has_smoke:
			var sp := String(key).split(",")
			_draw_hex_fill(int(sp[0]), int(sp[1]), Color(0.82, 0.82, 0.86, 0.62))

	# Ultimo impatto d'artiglieria: anello rosso sui 7 esagoni colpiti (O18)
	for ih in s.last_impact_hexes:
		var ic := _hex_center(int(ih.x), int(ih.y))
		draw_arc(ic, _hsize() * 0.62, 0, TAU, 24, Color(0.95, 0.15, 0.1, 0.9), 2.5)

	# Incendio (E46): esagono in fiamme (riempimento arancio + simbolo)
	for key in s.hexes:
		var bhd: GameState.HexData = s.hexes[key]
		if bhd.has_blaze:
			var bp := String(key).split(",")
			_draw_hex_fill(int(bp[0]), int(bp[1]), Color(0.95, 0.45, 0.1, 0.45))
			_draw_text("✷", _hex_center(int(bp[0]), int(bp[1])), 14.0, Color(1, 0.85, 0.2), true)

	# Fortificazioni: piccola etichetta in alto nell'esagono
	for key in s.hexes:
		var hd: GameState.HexData = s.hexes[key]
		if hd.fortification != Domain.Fort.NONE:
			var fp := String(key).split(",")
			var fc := _hex_center(int(fp[0]), int(fp[1])) - Vector2(0, _hsize() * 0.55)
			var col: Color = FORT_COLORS.get(hd.fortification, Color.WHITE)
			draw_circle(fc, 8.0, Color(0.08, 0.08, 0.08, 0.9))
			_draw_text(FORT_LETTERS.get(hd.fortification, "?"), fc, 11.0, col, true)

	# Esagoni evidenziati (movimento)
	for key in s.highlighted_hexes:
		var parts := String(key).split(",")
		_draw_hex_fill(int(parts[0]), int(parts[1]), COL_HIGHLIGHT)

	# Unità attivate dall'ordine del leader (gruppo di comando)
	for gid in s.ordered_group:
		if gid == s.selected_unit_id:
			continue
		var gv := s.unit_by_id(gid)
		if gv:
			_draw_hex_outline(gv.q, gv.r, COL_GROUP, 3.0)

	# Assemblaggio gruppo di fuoco: bersaglio + pezzi inclusi/esclusi
	if s.fire_target_q >= 0:
		_draw_hex_fill(s.fire_target_q, s.fire_target_r, COL_FIRE_TARGET)
		for eid in s.fire_eligible_ids:
			if eid == s.selected_unit_id:
				continue
			var ev := s.unit_by_id(eid)
			if ev == null:
				continue
			var inc: bool = s.fire_group_ids.has(eid)
			_draw_hex_outline(ev.q, ev.r, COL_GROUP if inc else COL_GROUP_OFF, 3.0 if inc else 2.0)

	# Finestra di reazione (Fuoco di Opportunità): mover in rosso, tiratori in giallo
	if s.phase == Domain.Phase.REACTION_WINDOW:
		var mv := s.unit_by_id(s.opfire_mover_id)
		if mv:
			_draw_hex_fill(mv.q, mv.r, COL_FIRE_TARGET)
		for sid in s.opfire_shooter_ids:
			var sv := s.unit_by_id(sid)
			if sv:
				_draw_hex_outline(sv.q, sv.r, COL_GROUP, 3.0)

	# Esagono selezionato
	if s.selected_unit_id != "":
		var u := s.unit_by_id(s.selected_unit_id)
		if u:
			_draw_hex_fill(u.q, u.r, COL_SELECT)

	# Griglia esagonale leggera, allineata all'immagine
	for q in s.map_cols:
		for r in s.map_rows:
			_draw_hex_outline(q, r, Color(0.0, 0.0, 0.0, 0.25), 1.0)

	# Lati di esagono (siepi/muri) come elementi di gioco
	_draw_side_features(s)

	# Pedine
	_draw_all_units(s)


## Disegna i lati di esagono (siepi = verde, muri = grigio) sul bordo condiviso.
func _draw_side_features(s: GameState) -> void:
	for sf in s.side_features:
		var a: Vector2i = sf["a"]
		var b: Vector2i = sf["b"]
		var ca := _hex_center(a.x, a.y)
		var cb := _hex_center(b.x, b.y)
		var mid := (ca + cb) * 0.5
		# Direzione del bordo = perpendicolare alla congiungente dei centri
		var dir := (cb - ca).normalized()
		var perp := Vector2(-dir.y, dir.x)
		var half := _hsize() * 0.52
		var p1 := mid + perp * half
		var p2 := mid - perp * half
		var feat: int = sf["feature"]
		var col := Color(0.15, 0.45, 0.12, 0.95)  # siepe verde
		var w := 4.0
		if feat == Domain.HexsideFeature.WALL:
			col = Color(0.45, 0.42, 0.38, 0.95); w = 5.0
		elif feat == Domain.HexsideFeature.STREAM_SIDE:
			col = Color(0.2, 0.45, 0.75, 0.9)
		draw_line(p1, p2, col, w)


func _draw_hex_fill(q: int, r: int, color: Color) -> void:
	var pts := _hex_corners(q, r)
	draw_colored_polygon(PackedVector2Array(pts), color)


func _draw_hex_outline(q: int, r: int, color: Color, width: float) -> void:
	var pts := _hex_corners(q, r)
	pts.append(pts[0])
	draw_polyline(PackedVector2Array(pts), color, width)


func _hex_center(q: int, r: int) -> Vector2:
	var ix := cal_ox + cal_hex * 1.5 * q
	var iy := cal_oy + cal_hex * sqrt(3.0) * (r + 0.5 * (q & 1))
	return view_origin + view_scale * Vector2(ix, iy)


func _hex_corners(q: int, r: int) -> Array[Vector2]:
	var c := _hex_center(q, r)
	var rad := _hsize()
	var corners: Array[Vector2] = []
	for i in range(6):
		var angle := deg_to_rad(60.0 * i)
		corners.append(Vector2(c.x + rad * cos(angle), c.y + rad * sin(angle)))
	return corners


# ─── Pedine ──────────────────────────────────────────────────────────────────

func _draw_all_units(s: GameState) -> void:
	# Raggruppa per esagono
	var by_hex: Dictionary = {}
	for u in s.units.values():
		var key := "%d,%d" % [u.q, u.r]
		if not by_hex.has(key):
			by_hex[key] = []
		by_hex[key].append(u)

	for key in by_hex:
		var stack: Array = by_hex[key]
		# Armi prima (sotto), uomini sopra
		stack.sort_custom(func(a, b): return a.is_weapon() and not b.is_weapon())
		var parts := String(key).split(",")
		var hq := int(parts[0])
		var hr := int(parts[1])
		var center := _hex_center(hq, hr)
		var depth := 0
		for u in stack:
			var offset := Vector2(depth * 4.0, depth * -4.0)
			_draw_counter(u, center + offset)
			depth += 1
		# Badge ×N se più di 1 pedina
		if stack.size() > 1:
			var badge_pos := center + Vector2(-_hsize() * 0.6, -_hsize() * 0.6)
			draw_circle(badge_pos, 10.0, COL_DARK)
			_draw_text("×%d" % stack.size(), badge_pos, 9.0, COL_TEXT, true)


## Restituisce la texture del segnalino per l'unità (fronte o rovescio).
func _counter_texture(u: Unit) -> Texture2D:
	if u.art_name == "":
		return null
	# Nazione reale dell'unità se disponibile, altrimenti lo stand-in per fazione.
	var folder: String = u.nation_art if u.nation_art != "" else String(Domain.FACTION_ART_DIR.get(u.faction, ""))
	# Le armi non hanno rovescio; uomini inefficienti usano la cartella _Half.
	if not u.efficient and not u.is_weapon():
		folder += "_Half"
	var path := "res://assets/counters/%s/%s.png" % [folder, u.art_name]
	if not _counter_cache.has(path):
		_counter_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _counter_cache[path]


func _draw_counter(u: Unit, center: Vector2) -> void:
	# Dimensione proporzionale all'esagono a schermo (così resta allineata su
	# qualunque mappa/zoom). Tarata per stare DENTRO l'esagono lasciando margine.
	var sz := _hsize() * (0.92 if u.is_weapon() else 1.28)
	var rect := Rect2(center.x - sz * 0.5, center.y - sz * 0.5, sz, sz)
	var tex := _counter_texture(u)

	if tex:
		# Ombra sottile per stacco dal fondo
		draw_rect(Rect2(rect.position + Vector2(2, 2), rect.size), Color(0, 0, 0, 0.35))
		draw_texture_rect(tex, rect, false)
	else:
		# Ripiego: rettangolo colorato col nome, se l'arte manca
		var bg := COL_GER if u.faction == Domain.Faction.GERMAN else COL_RUS
		draw_rect(rect, bg)
		_draw_text(u.unit_name, center, 8.0, COL_TEXT, true)

	# Bordo
	draw_rect(rect, COL_DARK, false, 1.5)

	# Overlay soppressione
	if u.suppressed:
		draw_rect(rect, Color(1.0, 0.0, 0.0, 0.35))


func _draw_text(txt: String, pos: Vector2, size: float, color: Color, centered: bool) -> void:
	if _font == null:
		return
	if centered:
		var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		draw_string(_font, Vector2(pos.x - tw * 0.5, pos.y + size * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size), color)
	else:
		draw_string(_font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size), color)


# ─── Input ───────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not visible:  # la 3D è attiva: non gestire i click della 2D
		return
	if event is InputEventKey and event.pressed:
		_handle_key(event as InputEventKey)
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		_on_click(mb.position)


func _handle_key(k: InputEventKey) -> void:
	# T = mostra/nascondi le tinte di terreno (debug)
	if k.keycode == KEY_T:
		_terrain_debug = not _terrain_debug
		queue_redraw()


func _on_click(mouse_pos: Vector2) -> void:
	if Game.state == null:
		return
	var s := Game.state
	# Trova l'esagono cliccato
	var clicked_q := -1
	var clicked_r := -1
	var best_dist := _hsize() * 0.9
	for q in s.map_cols:
		for r in s.map_rows:
			var c := _hex_center(q, r)
			var d := mouse_pos.distance_to(c)
			if d < best_dist:
				best_dist = d
				clicked_q = q
				clicked_r = r
	if clicked_q < 0:
		return

	Game.click_hex(clicked_q, clicked_r)
