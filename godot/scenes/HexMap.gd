## Nodo di disegno della mappa esagonale e delle pedine.
## Usa _draw() per SVG-like rendering direttamente su canvas.
extends Node2D

# ─── Costanti grafiche ────────────────────────────────────────────────────────

const HEX_SIZE   := 48.0   ## Raggio (centro→vertice) in pixel
const OFFSET_X   := 80.0
const OFFSET_Y   := 70.0
const IMG_SCALE  := 0.57

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

## Terreno → colore di tinta
const TERRAIN_TINT := {
	Domain.TerrainType.WOODS:    Color(0.18, 0.40, 0.18, 0.45),
	Domain.TerrainType.BUILDING: Color(0.55, 0.45, 0.35, 0.55),
	Domain.TerrainType.ROAD:     Color(0.70, 0.60, 0.40, 0.35),
	Domain.TerrainType.STREAM:   Color(0.20, 0.45, 0.70, 0.45),
}

# ─── Riferimenti ──────────────────────────────────────────────────────────────

var _map_texture: Texture2D = null
var _font: Font = null
var _counter_cache: Dictionary = {}  ## path → Texture2D (o null se mancante)


func _ready() -> void:
	_map_texture = load("res://assets/mappa1.png") as Texture2D
	_font = ThemeDB.fallback_font
	Game.state_changed.connect(queue_redraw)
	Game.unit_moved.connect(func(_id, _q, _r): queue_redraw())
	Game.unit_eliminated.connect(func(_id): queue_redraw())


# ─── Disegno principale ───────────────────────────────────────────────────────

func _draw() -> void:
	# Sfondo pieno: evita la "schermata grigia" se manca la texture o fuori mappa.
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.12, 0.13, 0.15, 1.0))

	if Game.state == null:
		return
	var s := Game.state

	# Mappa sottostante
	if _map_texture:
		var tw := _map_texture.get_width()  * IMG_SCALE
		var th := _map_texture.get_height() * IMG_SCALE
		draw_texture_rect(_map_texture, Rect2(0, 0, tw, th), false)
	elif _font:
		draw_string(_font, Vector2(100, 120),
			"[mappa non caricata: res://assets/mappa1.png]",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.6, 0.6))

	# Tinte terreno
	for key in s.hexes:
		var hd: GameState.HexData = s.hexes[key]
		var tint: Color = TERRAIN_TINT.get(hd.terrain, Color.TRANSPARENT)
		if tint.a > 0:
			var parts := String(key).split(",")
			_draw_hex_fill(int(parts[0]), int(parts[1]), tint)

	# Obiettivi
	for obj in s.objectives:
		_draw_hex_fill(obj.q, obj.r, COL_OBJECTIVE)

	# Esagoni evidenziati (movimento)
	for key in s.highlighted_hexes:
		var parts := String(key).split(",")
		_draw_hex_fill(int(parts[0]), int(parts[1]), COL_HIGHLIGHT)

	# Esagono selezionato
	if s.selected_unit_id != "":
		var u := s.unit_by_id(s.selected_unit_id)
		if u:
			_draw_hex_fill(u.q, u.r, COL_SELECT)

	# Griglia esagonale
	for q in s.map_cols:
		for r in s.map_rows:
			_draw_hex_outline(q, r, Color(0.0, 0.0, 0.0, 0.25), 1.0)

	# Pedine
	_draw_all_units(s)


func _draw_hex_fill(q: int, r: int, color: Color) -> void:
	var pts := _hex_corners(q, r)
	draw_colored_polygon(PackedVector2Array(pts), color)


func _draw_hex_outline(q: int, r: int, color: Color, width: float) -> void:
	var pts := _hex_corners(q, r)
	pts.append(pts[0])
	draw_polyline(PackedVector2Array(pts), color, width)


func _hex_center(q: int, r: int) -> Vector2:
	var x := OFFSET_X + HEX_SIZE * 1.5 * q
	var y := OFFSET_Y + HEX_SIZE * sqrt(3.0) * (r + 0.5 * (q & 1))
	return Vector2(x, y)


func _hex_corners(q: int, r: int) -> Array[Vector2]:
	var c := _hex_center(q, r)
	var corners: Array[Vector2] = []
	for i in range(6):
		var angle := deg_to_rad(60.0 * i)
		corners.append(Vector2(c.x + HEX_SIZE * cos(angle), c.y + HEX_SIZE * sin(angle)))
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
			var badge_pos := center + Vector2(-HEX_SIZE * 0.6, -HEX_SIZE * 0.6)
			draw_circle(badge_pos, 10.0, COL_DARK)
			_draw_text("×%d" % stack.size(), badge_pos, 9.0, COL_TEXT, true)


## Restituisce la texture del segnalino per l'unità (fronte o rovescio).
func _counter_texture(u: Unit) -> Texture2D:
	if u.art_name == "":
		return null
	var folder: String = Domain.FACTION_ART_DIR.get(u.faction, "")
	# Le armi non hanno rovescio; uomini inefficienti usano la cartella _Half
	if not u.efficient and not u.is_weapon():
		folder += "_Half"
	var path := "res://assets/counters/%s/%s.png" % [folder, u.art_name]
	if not _counter_cache.has(path):
		_counter_cache[path] = load(path)
	return _counter_cache[path]


func _draw_counter(u: Unit, center: Vector2) -> void:
	var sz := WCW if u.is_weapon() else CW
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
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		_on_click(mb.position)


func _on_click(mouse_pos: Vector2) -> void:
	if Game.state == null:
		return
	var s := Game.state
	# Trova l'esagono cliccato
	var clicked_q := -1
	var clicked_r := -1
	var best_dist := HEX_SIZE * 0.9
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

	var key := "%d,%d" % [clicked_q, clicked_r]
	var units_here := s.units_at(clicked_q, clicked_r)

	if s.phase == Domain.Phase.PLAYER_MOVING:
		# Clicco su esagono amico → cambia selezione; su evidenziato → muovi
		var own_here := units_here.filter(func(u): return u.faction == s.human_faction)
		if own_here.size() > 0 and s.highlighted_hexes.has(key) == false:
			Game.select_unit(own_here[0].id)
		elif s.highlighted_hexes.has(key):
			Game.click_hex_move(clicked_q, clicked_r)
	elif s.phase == Domain.Phase.PLAYER_TURN:
		# Seleziona unità amica
		var own := units_here.filter(func(u): return u.faction == s.human_faction and not u.activated)
		if own.size() > 0:
			Game.select_unit(own[0].id)
		else:
			Game.deselect()
