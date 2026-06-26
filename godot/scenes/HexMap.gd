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
## Area di schermo riservata alla mappa (impostata dalla HUD: esclude barra,
## colonna e mano). Se vuota, si usa l'intero viewport.
var map_rect: Rect2 = Rect2()
var _map_image_id: String = ""   ## id immagine attualmente caricata
var _terrain_debug: bool = false  ## true = mostra le tinte del terreno (tasto T)
var _los_drag: int = -1            ## estremità LOS trascinata (0=A, 1=B, -1=nessuna)

# ─── Zoom & pan (vista 2D) ────────────────────────────────────────────────────
# Di default la mappa si auto-inquadra. Appena l'utente usa rotella o
# trascinamento, la vista diventa "personalizzata" e non viene più ri-adattata
# automaticamente (finché non cambia mappa o si preme «0» per reinquadrare).
var _fit_scale: float = 1.0        ## scala di auto-fit corrente (per i limiti di zoom)
var _view_custom: bool = false     ## true se l'utente ha zoomato/spostato
var _panning: bool = false         ## trascinamento in corso
var _press_pos: Vector2 = Vector2.ZERO  ## posizione del tasto sinistro premuto
var _press_moved: bool = false     ## il sinistro si è mosso oltre la soglia (→ pan, non clic)
const _DRAG_THRESHOLD := 6.0       ## px oltre cui un trascinamento non è un clic
const _ZOOM_STEP := 1.15           ## fattore di zoom per tacca di rotella

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
const COL_FIRE_READY := Color(0.2, 0.9, 1.0, 0.95)     ## unità che può sparare ora (anello ciano)
const COL_CMD_AURA := Color(1.0, 0.55, 0.0, 0.10)      ## alone tenue del raggio di comando
const COL_MP_TEXT := Color(0.06, 0.06, 0.06, 0.97)     ## numero costo PM (scuro, leggibile)

## Fortificazioni: lettera e colore del badge
const FORT_LETTERS := { 1: "T", 2: "C", 3: "B", 4: "#", 5: "*" }  # Trincea/Casamatta/Bunker/Filo/Mine
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
		_view_custom = false  # nuova mappa → riparti dall'auto-inquadratura
	_update_view()


## Area di schermo in cui inquadrare la mappa: `map_rect` se la HUD l'ha
## impostata (esclude barra/colonna/mano), altrimenti l'intero viewport.
func _map_area() -> Rect2:
	if map_rect.size.x > 1.0 and map_rect.size.y > 1.0:
		return map_rect
	return Rect2(Vector2.ZERO, get_viewport_rect().size)


## Calcola scala e origine per inquadrare l'immagine nell'area libera. Se l'utente
## ha zoomato/spostato (`_view_custom`) la vista resta com'è: si aggiorna solo il
## valore di auto-fit usato per i limiti di zoom.
func _update_view() -> void:
	if _map_texture == null:
		return
	var area := _map_area()
	var iw := float(_map_texture.get_width())
	var ih := float(_map_texture.get_height())
	_fit_scale = minf(area.size.x / iw, area.size.y / ih)
	if _view_custom:
		return
	view_scale = _fit_scale
	view_origin = area.position + Vector2(
		(area.size.x - iw * view_scale) * 0.5,
		(area.size.y - ih * view_scale) * 0.5)


## Zoom centrato su un punto-schermo (la rotella): l'esagono sotto il cursore
## resta fermo mentre la scala cambia, entro i limiti rispetto all'auto-fit.
func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	if _map_texture == null:
		return
	var img_pt := (screen_pos - view_origin) / view_scale  # punto immagine sotto il cursore
	var new_scale := clampf(view_scale * factor, _fit_scale * 0.5, _fit_scale * 6.0)
	if is_equal_approx(new_scale, view_scale):
		return
	view_scale = new_scale
	view_origin = screen_pos - img_pt * new_scale
	_view_custom = true
	queue_redraw()


## Reinquadra la mappa (auto-fit), annullando zoom/spostamenti dell'utente.
func reset_view() -> void:
	_view_custom = false
	_update_view()
	queue_redraw()


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
			_draw_text("*", _hex_center(int(bp[0]), int(bp[1])), 16.0, Color(1, 0.85, 0.2), true)

	# Fortificazioni: piccola etichetta in alto nell'esagono
	for key in s.hexes:
		var hd: GameState.HexData = s.hexes[key]
		if hd.fortification != Domain.Fort.NONE:
			var fp := String(key).split(",")
			var fc := _hex_center(int(fp[0]), int(fp[1])) - Vector2(0, _hsize() * 0.55)
			var col: Color = FORT_COLORS.get(hd.fortification, Color.WHITE)
			draw_circle(fc, 8.0, Color(0.08, 0.08, 0.08, 0.9))
			_draw_text(FORT_LETTERS.get(hd.fortification, "?"), fc, 11.0, col, true)

	# Schieramento manuale: evidenzia la zona di setup del giocatore (dove può
	# disporre le sue unità). Riempimento e contorno azzurri.
	if s.phase == Domain.Phase.PLAYER_SETUP:
		for h in s.setup_zone:
			_draw_hex_fill(int(h.x), int(h.y), Color(0.2, 0.55, 0.95, 0.20))
			_draw_hex_outline(int(h.x), int(h.y), Color(0.35, 0.72, 1.0, 0.75), 1.5)

	# Raggio di comando del leader del gruppo di Mossa: alone arancio tenue
	_draw_command_aura(s)

	# Esagoni evidenziati. Durante una Mossa il riempimento indica il COSTO in PM
	# per raggiungere l'esagono (verde=poco → rosso=tanto), col numero sopra.
	var cost_map := _move_cost_map(s)
	for key in s.highlighted_hexes:
		var parts := String(key).split(",")
		var hq := int(parts[0])
		var hr := int(parts[1])
		if cost_map.has(key):
			_draw_hex_fill(hq, hr, _cost_fill(int(cost_map[key])))
		else:
			_draw_hex_fill(hq, hr, COL_HIGHLIGHT)
	for ckey in cost_map:
		var cp := String(ckey).split(",")
		var cc := _hex_center(int(cp[0]), int(cp[1])) - Vector2(0, _hsize() * 0.5)
		_draw_text("%d" % int(cost_map[ckey]), cc, 14.0, COL_MP_TEXT, true)

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
		# Linee di mira: da ogni pezzo che spara verso il bersaglio (chi spara a chi).
		var tgt := _hex_center(s.fire_target_q, s.fire_target_r)
		for gid in s.fire_group_ids:
			var gu := s.unit_by_id(gid)
			if gu != null:
				_draw_aim_line(_hex_center(gu.q, gu.r), tgt)
		# Riquadro di anteprima sopra il bersaglio: FP attacco vs DIF stimata + esito.
		_draw_fire_readout(tgt)

	# FUOCO, prima di scegliere il bersaglio: evidenzia chi può sparare (anello
	# ciano) e, per l'unità selezionata, traccia le linee verso TUTTI i bersagli
	# validi — così si vede subito "chi spara a chi".
	if s.current_order == Domain.OrderType.FIRE and s.fire_target_q < 0:
		for fid in s.fire_ready_ids:
			if fid == s.selected_unit_id:
				continue
			var fv := s.unit_by_id(fid)
			if fv:
				_draw_hex_outline(fv.q, fv.r, COL_FIRE_READY, 2.5)
		var sel := s.unit_by_id(s.selected_unit_id) if s.selected_unit_id != "" else null
		if sel != null:
			var from := _hex_center(sel.q, sel.r)
			for key in s.highlighted_hexes:
				var p := String(key).split(",")
				_draw_aim_line(from, _hex_center(int(p[0]), int(p[1])))

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

	# Strumento Modalità LOS (sopra tutto)
	if s.los_mode:
		_draw_los_tool(s)


## Strumento di verifica della Linea di Vista: linea colorata tra le due estremità
## (verde=libera, gialla=ostacolata, rossa=bloccata) coi marcatori A/B e l'esito.
func _draw_los_tool(s: GameState) -> void:
	if s.los_a.x < 0 or s.los_b.x < 0:
		return
	var a := _hex_center(s.los_a.x, s.los_a.y)
	var b := _hex_center(s.los_b.x, s.los_b.y)
	var kind := HexGrid.los_kind(s.los_a.x, s.los_a.y, s.los_b.x, s.los_b.y, s)
	var col := _los_color(kind)
	draw_line(a, b, Color(0, 0, 0, 0.55), 6.0)  # contorno scuro per leggibilità
	draw_line(a, b, col, 3.5)
	for i in 2:
		var p: Vector2 = a if i == 0 else b
		draw_circle(p, 12.0, Color(0.05, 0.05, 0.08, 0.92))
		draw_arc(p, 12.0, 0, TAU, 24, col, 3.0)
		_draw_text("A" if i == 0 else "B", p, 13.0, Color.WHITE, true)
	var lbl := _los_label(s, kind)
	var mid := (a + b) * 0.5 - Vector2(0, 18)
	var w := _font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x if _font else 90.0
	draw_rect(Rect2(mid.x - w * 0.5 - 6, mid.y - 12, w + 12, 22), Color(0.05, 0.05, 0.08, 0.88))
	_draw_text(lbl, mid, 15.0, col, true)


func _los_color(kind: int) -> Color:
	match kind:
		HexGrid.LOS_CLEAR:    return Color(0.30, 1.0, 0.35, 0.95)
		HexGrid.LOS_HINDERED: return Color(1.0, 0.85, 0.2, 0.95)
		_:                    return Color(1.0, 0.25, 0.2, 0.95)


func _los_label(s: GameState, kind: int) -> String:
	match kind:
		HexGrid.LOS_CLEAR:
			return "LOS LIBERA"
		HexGrid.LOS_HINDERED:
			return "LOS OSTACOLATA (-%d)" % HexGrid.los_hindrance(s.los_a.x, s.los_a.y, s.los_b.x, s.los_b.y, s)
		_:
			return "LOS BLOCCATA"


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

	# Arma a terra (senza portatore, 11.3): anello giallo = raccoglibile con «G».
	if u.is_weapon() and u.carrier_id == "":
		draw_arc(center, sz * 0.62, 0, TAU, 22, Color(1.0, 0.85, 0.2, 0.95), 2.5)


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
	# Zoom con la rotella: attivo in qualunque modalità (anche LOS).
	if event is InputEventMouseButton:
		var w := event as InputEventMouseButton
		if w.pressed and w.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(w.position, _ZOOM_STEP)
			get_viewport().set_input_as_handled()
			return
		if w.pressed and w.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(w.position, 1.0 / _ZOOM_STEP)
			get_viewport().set_input_as_handled()
			return
	# Spostamento (pan) col tasto centrale o destro: sempre disponibile.
	if _handle_pan(event):
		return
	# In Modalità LOS i click/trascinamenti spostano le estremità, non le pedine.
	if Game.state != null and Game.state.los_mode:
		_los_input(event)
		return
	# Tasto sinistro: distingue clic (seleziona) da trascinamento (sposta la mappa).
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press_pos = mb.position
				_press_moved = false
			elif not _press_moved:
				_on_click(mb.position)  # rilascio senza trascinamento = clic
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			if not _press_moved and mm.position.distance_to(_press_pos) > _DRAG_THRESHOLD:
				_press_moved = true
			if _press_moved:
				view_origin += mm.relative
				_view_custom = true
				queue_redraw()


## Pan col tasto centrale o destro (premuto e trascinato). Restituisce true se
## ha consumato l'evento. Tenuto separato dal sinistro per non interferire con
## la selezione delle pedine.
func _handle_pan(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			_panning = mb.pressed
			return true
	elif event is InputEventMouseMotion and _panning:
		view_origin += (event as InputEventMouseMotion).relative
		_view_custom = true
		queue_redraw()
		return true
	return false


## Input della Modalità LOS: premendo si afferra l'estremità più vicina e la si
## porta sull'esagono cliccato; trascinando, la linea si aggiorna in tempo reale.
func _los_input(event: InputEvent) -> void:
	var s := Game.state
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			var h := _hex_at(mb.position)
			if h.x < 0:
				return
			var da := HexGrid.distance(h.x, h.y, s.los_a.x, s.los_a.y)
			var db := HexGrid.distance(h.x, h.y, s.los_b.x, s.los_b.y)
			_los_drag = 0 if da <= db else 1
			_set_los_endpoint(_los_drag, h)
		else:
			_los_drag = -1
	elif event is InputEventMouseMotion and _los_drag >= 0:
		var h := _hex_at((event as InputEventMouseMotion).position)
		if h.x >= 0:
			_set_los_endpoint(_los_drag, h)


func _set_los_endpoint(idx: int, h: Vector2i) -> void:
	if idx == 0:
		Game.state.los_a = h
	else:
		Game.state.los_b = h
	queue_redraw()


func _handle_key(k: InputEventKey) -> void:
	# T = mostra/nascondi le tinte di terreno (debug)
	if k.keycode == KEY_T:
		_terrain_debug = not _terrain_debug
		queue_redraw()
	# 0 = reinquadra la mappa (annulla zoom/spostamento)
	elif k.keycode == KEY_0:
		reset_view()


## Linea di mira dal tiratore al bersaglio, con punta di freccia sull'esagono
## bersaglio (rende esplicito "chi spara a chi").
func _draw_aim_line(from: Vector2, to: Vector2) -> void:
	var col := Color(0.95, 0.2, 0.15, 0.85)
	var dir := (to - from)
	if dir.length() < 1.0:
		return
	dir = dir.normalized()
	var tip := to - dir * (_hsize() * 0.45)   # ferma la punta sul bordo del bersaglio
	draw_line(from, tip, col, 3.0)
	var perp := Vector2(-dir.y, dir.x)
	var base := tip - dir * 13.0
	draw_colored_polygon(PackedVector2Array([tip, base + perp * 7.0, base - perp * 7.0]), col)


## Riquadro di anteprima del fuoco, ancorato sopra l'esagono bersaglio:
## FP d'attacco · DIF stimata (copertura) · esito atteso (colore = verdetto).
func _draw_fire_readout(target_center: Vector2) -> void:
	var pv := Game.fire_preview()
	if pv.is_empty():
		return
	var txt := "FP %d" % int(pv.get("fp", 0))
	var col := Color(0.95, 0.95, 0.5)
	if int(pv.get("defense", -1)) >= 0:
		txt += "  vs DIF %d  ->  %s" % [int(pv["defense"]), pv.get("verdict", "")]
		match String(pv.get("verdict", "")):
			"favorevole":  col = Color(0.4, 1.0, 0.4)
			"sfavorevole": col = Color(1.0, 0.45, 0.4)
			_:             col = Color(1.0, 0.9, 0.4)
	var pos := target_center - Vector2(0, _hsize() * 1.05)
	var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x if _font else 80.0
	draw_rect(Rect2(pos.x - w * 0.5 - 6, pos.y - 13, w + 12, 22), Color(0.05, 0.05, 0.08, 0.85))
	_draw_text(txt, pos, 15.0, col, true)


## Mappa "q,r" → costo in PM per raggiungere l'esagono, valida solo durante una
## Mossa con un mover selezionato (altrimenti vuota: gli altri ordini non mostrano
## il costo). Ricalcolata a ogni redraw dallo stato corrente (niente cache).
func _move_cost_map(s: GameState) -> Dictionary:
	if s.phase != Domain.Phase.PLAYER_MOVING or s.current_order != Domain.OrderType.MOVE:
		return {}
	if s.selected_unit_id == "":
		return {}
	var u := s.unit_by_id(s.selected_unit_id)
	if u == null:
		return {}
	var budget := int(s.group_mp.get(u.id, u.move))
	return HexGrid.reachable_costs(u, s, budget)


## Colore di riempimento in base al costo in PM: verde (1) → rosso (4+).
func _cost_fill(cost: int) -> Color:
	match cost:
		1:  return Color(0.30, 0.85, 0.30, 0.45)
		2:  return Color(0.85, 0.85, 0.25, 0.45)
		3:  return Color(0.95, 0.60, 0.15, 0.50)
		_:  return Color(0.95, 0.25, 0.20, 0.52)


## Alone tenue che mostra il raggio di Comando del leader del gruppo di Mossa.
func _draw_command_aura(s: GameState) -> void:
	if s.phase != Domain.Phase.PLAYER_MOVING or s.current_order != Domain.OrderType.MOVE:
		return
	if s.ordered_group.size() <= 1:
		return
	var leader: Unit = null
	for gid in s.ordered_group:
		var g := s.unit_by_id(gid)
		if g != null and g.is_leader() and g.command > 0:
			leader = g
			break
	if leader == null:
		return
	for q in s.map_cols:
		for r in s.map_rows:
			if HexGrid.distance(leader.q, leader.r, q, r) <= leader.command:
				_draw_hex_fill(q, r, COL_CMD_AURA)


## Esagono (q,r) sotto una posizione del mouse, o (-1,-1) se nessuno è abbastanza
## vicino. Condiviso da selezione pedine e Modalità LOS.
func _hex_at(mouse_pos: Vector2) -> Vector2i:
	if Game.state == null:
		return Vector2i(-1, -1)
	var s := Game.state
	var best_q := -1
	var best_r := -1
	var best_dist := _hsize() * 0.9
	for q in s.map_cols:
		for r in s.map_rows:
			var d := mouse_pos.distance_to(_hex_center(q, r))
			if d < best_dist:
				best_dist = d
				best_q = q
				best_r = r
	return Vector2i(best_q, best_r)


func _on_click(mouse_pos: Vector2) -> void:
	var h := _hex_at(mouse_pos)
	if h.x < 0:
		return
	Game.click_hex(h.x, h.y)
