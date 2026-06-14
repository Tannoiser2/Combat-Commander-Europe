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


func _ready() -> void:
	_map_texture = load("res://assets/mappa1.png") as Texture2D
	_font = ThemeDB.fallback_font
	Game.state_changed.connect(queue_redraw)
	Game.unit_moved.connect(func(_id, _q, _r): queue_redraw())
	Game.unit_eliminated.connect(func(_id): queue_redraw())


# ─── Disegno principale ───────────────────────────────────────────────────────

func _draw() -> void:
	if Game.state == null:
		return
	var s := Game.state

	# Mappa sottostante
	if _map_texture:
		var tw := _map_texture.get_width()  * IMG_SCALE
		var th := _map_texture.get_height() * IMG_SCALE
		draw_texture_rect(_map_texture, Rect2(0, 0, tw, th), false)

	# Tinte terreno
	for key in s.hexes:
		var hd: GameState.HexData = s.hexes[key]
		var tint: Color = TERRAIN_TINT.get(hd.terrain, Color.TRANSPARENT)
		if tint.a > 0:
			var parts := key.split(",")
			_draw_hex_fill(int(parts[0]), int(parts[1]), tint)

	# Obiettivi
	for obj in s.objectives:
		_draw_hex_fill(obj.q, obj.r, COL_OBJECTIVE)

	# Esagoni evidenziati (movimento)
	for key in s.highlighted_hexes:
		var parts := key.split(",")
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
		var parts := key.split(",")
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


func _draw_counter(u: Unit, center: Vector2) -> void:
	var w := WCW if u.is_weapon() else CW
	var h := WCW if u.is_weapon() else CH
	var rect := Rect2(center.x - w * 0.5, center.y - h * 0.5, w, h)
	var bg := COL_GER if u.faction == Domain.Faction.GERMAN else COL_RUS

	# Sfondo
	draw_rect(rect, bg)
	draw_rect(rect, COL_DARK, false, 1.5)

	if u.is_weapon():
		_draw_weapon_counter(u, rect, center)
	elif u.is_leader():
		_draw_leader_counter(u, rect, center, h)
	else:
		_draw_squad_counter(u, rect, center, h)

	# Overlay soppressione
	if u.suppressed:
		draw_rect(rect, Color(1.0, 0.0, 0.0, 0.35))


func _draw_squad_counter(u: Unit, rect: Rect2, center: Vector2, h: float) -> void:
	# Striscia superiore
	var stripe := Rect2(rect.position.x, rect.position.y, rect.size.x, h * 0.28)
	draw_rect(stripe, COL_STRIPE)
	_draw_text("Rifle", Vector2(center.x, stripe.position.y + stripe.size.y * 0.5), 8.0, COL_TEXT, true)

	# Morale (in alto a destra)
	var mor_pos := Vector2(rect.position.x + rect.size.x - 9.0, rect.position.y + 9.0)
	_draw_text(str(u.morale), mor_pos, 10.0, COL_MORALE, true)

	# Statistiche in basso: FP | Range | Move
	_draw_bottom_stats(u, rect, center, h)


func _draw_leader_counter(u: Unit, rect: Rect2, center: Vector2, h: float) -> void:
	# Striscia col nome
	var stripe := Rect2(rect.position.x, rect.position.y, rect.size.x, h * 0.28)
	draw_rect(stripe, COL_STRIPE)
	var short_name := u.unit_name.split(" ")[0] if " " in u.unit_name else u.unit_name
	_draw_text(short_name, Vector2(center.x, stripe.position.y + stripe.size.y * 0.5), 7.0, COL_TEXT, true)

	# Morale in alto a destra
	var mor_pos := Vector2(rect.position.x + rect.size.x - 9.0, rect.position.y + 9.0)
	_draw_text(str(u.morale), mor_pos, 11.0, COL_MORALE, true)

	# Comando in cerchio al centro-destra
	var cmd_pos := Vector2(rect.position.x + rect.size.x - 10.0, center.y)
	draw_circle(cmd_pos, 9.0, COL_CMD)
	draw_arc(cmd_pos, 9.0, 0, TAU, 24, COL_DARK, 1.5)
	_draw_text(str(u.command), cmd_pos, 9.0, COL_DARK, true)

	# Stats in basso
	_draw_bottom_stats(u, rect, center, h)


func _draw_weapon_counter(u: Unit, rect: Rect2, center: Vector2) -> void:
	# Nome arma in striscia piccola
	var stripe := Rect2(rect.position.x, rect.position.y, rect.size.x, WCW * 0.30)
	draw_rect(stripe, COL_STRIPE)
	var label := u.unit_name.replace(" MG", "MG").replace("Light ", "Lt.").replace("Medium ", "Med.")
	_draw_text(label, Vector2(center.x, stripe.position.y + stripe.size.y * 0.5), 7.0, COL_TEXT, true)

	# Stats FP/Range/Move in basso
	var bot_y := rect.position.y + rect.size.y - 9.0
	var sections := 3
	var sw := rect.size.x / sections
	# FP
	var fp_pos := Vector2(rect.position.x + sw * 0.5, bot_y)
	_draw_stat(str(u.fp), fp_pos, 9.0, u.fp_boxed, rect)
	# Range
	var rng_pos := Vector2(rect.position.x + sw * 1.5, bot_y)
	_draw_stat(str(u.range), rng_pos, 9.0, u.range_boxed, rect)
	# Move penalty
	var mv_pos := Vector2(rect.position.x + sw * 2.5, bot_y)
	_draw_text(str(u.move_penalty), mv_pos, 9.0, COL_TEXT, true)


func _draw_bottom_stats(u: Unit, rect: Rect2, center: Vector2, h: float) -> void:
	var bot_y := rect.position.y + h - 9.0
	var sections := 3
	var sw := rect.size.x / sections
	# FP
	var fp_pos := Vector2(rect.position.x + sw * 0.5, bot_y)
	_draw_stat(str(u.fp), fp_pos, 9.0, u.fp_boxed, rect)
	# Range
	var rng_pos := Vector2(rect.position.x + sw * 1.5, bot_y)
	_draw_stat(str(u.range), rng_pos, 9.0, u.range_boxed, rect)
	# Move
	var mv_pos := Vector2(rect.position.x + sw * 2.5, bot_y)
	_draw_text(str(u.move), mv_pos, 9.0, COL_TEXT, true)


func _draw_stat(txt: String, pos: Vector2, size: float, boxed: bool, _rect: Rect2) -> void:
	if boxed:
		var tw := size * 0.65 * txt.length() + 4.0
		var box := Rect2(pos.x - tw * 0.5, pos.y - size * 0.7, tw, size + 2.0)
		draw_rect(box, COL_TEXT, false, 1.2)
	_draw_text(txt, pos, size, COL_TEXT, true)


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
