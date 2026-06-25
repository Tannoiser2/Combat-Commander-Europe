## Mappa 3D INTERATTIVA (vista alternativa, embeddabile in un SubViewport).
## Il tabellone reale è la SKIN su esagoni flat-top estrusi per elevazione. Il
## terreno (skin, fianchi, alberi/edifici/muri) è statico; un layer DINAMICO
## (pedine, obiettivi, evidenziazioni) viene rigenerato a ogni cambiamento di
## stato. Un clic su un esagono è tradotto in (q,r) e instradato a Game.click_hex,
## quindi carte/LOS/movimento/fuoco funzionano come nella 2D. Camera orbitabile.
extends Node3D

const ELEV_STEP := 0.55
const BASE_H := 0.25

var _world := 1.0 / 59.2
var _ox := 129.0
var _oy := 69.0
var _hx := 59.2

var _cam_yaw := 0.6
var _cam_pitch := 0.85
var _cam_dist := 30.0
var _center := Vector3.ZERO

var _dynamic: Node3D
var _press_pos := Vector2.ZERO
var _dragged := false
var active := true   ## Main lo mette a false quando la 3D è nascosta (no refresh)

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	_add_lighting()
	var s := Game.state
	if s == null:
		Game.start_new_game(Domain.Faction.GERMAN, 1)
		s = Game.state
	_build_static(s)
	_dynamic = Node3D.new()
	add_child(_dynamic)
	_refresh_dynamic(s)
	_camera.current = true
	_update_camera()
	if not Game.state_changed.is_connected(_on_state_changed):
		Game.state_changed.connect(_on_state_changed)


func _on_state_changed() -> void:
	if Game.state != null and active:
		_refresh_dynamic(Game.state)


## Rigenera il layer dinamico (pedine, obiettivi, evidenziazioni).
func refresh() -> void:
	if Game.state != null:
		_refresh_dynamic(Game.state)


func _refresh_dynamic(s: GameState) -> void:
	for c in _dynamic.get_children():
		c.queue_free()
	_add_highlights(s)
	_add_pieces(s)
	_add_objectives(s)


func _add_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58.0, -35.0, 0.0)
	sun.light_energy = 1.05
	add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.66, 0.82)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.92, 0.92, 0.95)
	env.ambient_light_energy = 0.85
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


## Centro dell'esagono (q,r) in PIXEL dell'immagine del tabellone.
func _hex_img(q: int, r: int) -> Vector2:
	return Vector2(_ox + _hx * 1.5 * q, _oy + _hx * sqrt(3.0) * (r + 0.5 * (q & 1)))


func _top_y(s: GameState, q: int, r: int) -> float:
	var hd: GameState.HexData = s.hex_at(q, r)
	return BASE_H + (hd.elevation if hd != null else 0) * ELEV_STEP


# ─── Terreno statico (skin + fianchi + volumi) ────────────────────────────────

func _build_static(s: GameState) -> void:
	var tex := load("res://assets/maps_img/%s.jpg" % s.map_image) as Texture2D
	var iw := float(tex.get_width()) if tex != null else 1024.0
	var ih := float(tex.get_height()) if tex != null else 1024.0
	_ox = s.cal_ox
	_oy = s.cal_oy
	_hx = s.cal_hex
	_world = 1.0 / _hx

	var top_st := SurfaceTool.new()
	top_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var side_st := SurfaceTool.new()
	side_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var minx := INF
	var minz := INF
	var maxx := -INF
	var maxz := -INF
	for key in s.hexes:
		var p := String(key).split(",")
		var q := int(p[0])
		var r := int(p[1])
		var hd: GameState.HexData = s.hexes[key]
		var top_y := BASE_H + hd.elevation * ELEV_STEP
		var cimg := _hex_img(q, r)
		var corners_w: Array[Vector3] = []
		var corners_uv: Array[Vector2] = []
		for i in range(6):
			var a := deg_to_rad(60.0 * i)
			var ci := cimg + _hx * Vector2(cos(a), sin(a))
			corners_w.append(Vector3(ci.x * _world, top_y, ci.y * _world))
			corners_uv.append(Vector2(ci.x / iw, ci.y / ih))
		var center_w := Vector3(cimg.x * _world, top_y, cimg.y * _world)
		var center_uv := Vector2(cimg.x / iw, cimg.y / ih)
		for i in range(6):
			var j := (i + 1) % 6
			top_st.set_normal(Vector3.UP)
			top_st.set_uv(center_uv); top_st.add_vertex(center_w)
			top_st.set_uv(corners_uv[i]); top_st.add_vertex(corners_w[i])
			top_st.set_uv(corners_uv[j]); top_st.add_vertex(corners_w[j])
		for i in range(6):
			var j := (i + 1) % 6
			var tA := corners_w[i]
			var tB := corners_w[j]
			var bA := Vector3(tA.x, 0.0, tA.z)
			var bB := Vector3(tB.x, 0.0, tB.z)
			side_st.add_vertex(tA); side_st.add_vertex(bA); side_st.add_vertex(tB)
			side_st.add_vertex(tB); side_st.add_vertex(bA); side_st.add_vertex(bB)
		_decorate(hd, q, r, center_w)
		minx = minf(minx, center_w.x); maxx = maxf(maxx, center_w.x)
		minz = minf(minz, center_w.z); maxz = maxf(maxz, center_w.z)

	top_st.generate_normals()
	var top_mat := StandardMaterial3D.new()
	if tex != null:
		top_mat.albedo_texture = tex
	top_mat.roughness = 1.0
	var top_mi := MeshInstance3D.new()
	top_mi.mesh = top_st.commit()
	top_mi.material_override = top_mat
	add_child(top_mi)

	side_st.generate_normals()
	var side_mi := MeshInstance3D.new()
	side_mi.mesh = side_st.commit()
	side_mi.material_override = _mat(Color(0.32, 0.26, 0.18))
	add_child(side_mi)

	_add_side_features(s)
	_center = Vector3((minx + maxx) * 0.5, 0.0, (minz + maxz) * 0.5)
	_cam_dist = maxf(maxx - minx, maxz - minz) * 0.7 + 8.0


# ─── Layer dinamico ───────────────────────────────────────────────────────────

## Evidenzia gli esagoni-bersaglio (s.highlighted_hexes) con un disco giallo
## translucido e l'unità selezionata in azzurro.
func _add_highlights(s: GameState) -> void:
	for key in s.highlighted_hexes:
		var p := String(key).split(",")
		_hex_disc(int(p[0]), int(p[1]), s, Color(1.0, 0.95, 0.2, 0.5))
	if s.selected_unit_id != "":
		var u := s.unit_by_id(s.selected_unit_id)
		if u != null:
			_hex_disc(u.q, u.r, s, Color(0.1, 0.8, 1.0, 0.5))
	if s.fire_target_q >= 0:
		_hex_disc(s.fire_target_q, s.fire_target_r, s, Color(1.0, 0.2, 0.15, 0.55))


func _hex_disc(q: int, r: int, s: GameState, col: Color) -> void:
	var top_y := _top_y(s, q, r) + 0.04
	var cimg := _hex_img(q, r)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cw := Vector3(cimg.x * _world, top_y, cimg.y * _world)
	var cor: Array[Vector3] = []
	for i in range(6):
		var a := deg_to_rad(60.0 * i)
		var ci := cimg + (_hx * 0.92) * Vector2(cos(a), sin(a))
		cor.append(Vector3(ci.x * _world, top_y, ci.y * _world))
	for i in range(6):
		var j := (i + 1) % 6
		st.set_normal(Vector3.UP); st.add_vertex(cw)
		st.set_normal(Vector3.UP); st.add_vertex(cor[i])
		st.set_normal(Vector3.UP); st.add_vertex(cor[j])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	_dynamic.add_child(mi)


func _add_pieces(s: GameState) -> void:
	var by_hex := {}
	for u in s.units.values():
		var k := "%d,%d" % [u.q, u.r]
		if not by_hex.has(k):
			by_hex[k] = []
		by_hex[k].append(u)
	for k in by_hex:
		var arr: Array = by_hex[k]
		for i in arr.size():
			var u: Unit = arr[i]
			var top_y := _top_y(s, u.q, u.r)
			var ci := _hex_img(u.q, u.r)
			var off := Vector3(0.16 * i - 0.12, 0.12 * i, -0.16 * i + 0.12)
			var base := Vector3(ci.x * _world, top_y, ci.y * _world) + off
			var tex := _counter_tex(u)
			if tex != null:
				var sp := Sprite3D.new()
				sp.texture = tex
				sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				sp.shaded = false
				sp.pixel_size = 1.5 / float(tex.get_height())
				sp.position = base + Vector3(0.0, 0.75, 0.0)
				_dynamic.add_child(sp)
			else:
				var pm := MeshInstance3D.new()
				var pc := CylinderMesh.new()
				pc.top_radius = 0.3; pc.bottom_radius = 0.3; pc.height = 0.6
				pc.radial_segments = 16
				pm.mesh = pc
				pm.material_override = _mat(Color(0.66, 0.58, 0.30) \
					if u.faction == Domain.Faction.GERMAN else Color(0.28, 0.5, 0.28))
				pm.position = base + Vector3(0.0, 0.3, 0.0)
				_dynamic.add_child(pm)


func _counter_tex(u: Unit) -> Texture2D:
	if u.art_name == "":
		return null
	var folder: String = u.nation_art if u.nation_art != "" \
		else String(Domain.FACTION_ART_DIR.get(u.faction, ""))
	if folder == "":
		return null
	var path := "res://assets/counters/%s/%s.png" % [folder, u.art_name]
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _add_objectives(s: GameState) -> void:
	for o in s.objectives:
		var top_y := _top_y(s, o.q, o.r)
		var ci := _hex_img(o.q, o.r)
		var col := Color(0.9, 0.9, 0.9)
		if o.controller == Domain.Faction.GERMAN:
			col = Color(0.78, 0.7, 0.36)
		elif o.controller == Domain.Faction.RUSSIAN:
			col = Color(0.4, 0.66, 0.4)
		var pole := MeshInstance3D.new()
		var pc := CylinderMesh.new()
		pc.top_radius = 0.04; pc.bottom_radius = 0.04; pc.height = 1.1
		pc.radial_segments = 6
		pole.mesh = pc
		pole.material_override = _mat(Color(0.2, 0.2, 0.2))
		pole.position = Vector3(ci.x * _world, top_y + 0.55, ci.y * _world)
		_dynamic.add_child(pole)
		var lbl := Label3D.new()
		lbl.text = "%d" % o.vp
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.font_size = 80
		lbl.pixel_size = 0.011
		lbl.modulate = col
		lbl.outline_size = 18
		lbl.outline_modulate = Color(0, 0, 0, 0.85)
		lbl.position = Vector3(ci.x * _world, top_y + 1.25, ci.y * _world)
		_dynamic.add_child(lbl)


func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	return m


# ─── Volumi 3D: alberi, edifici, macerie ──────────────────────────────────────

func _decorate(hd: GameState.HexData, q: int, r: int, top: Vector3) -> void:
	match hd.terrain:
		Domain.TerrainType.WOODS:
			_add_tree(top, _jit(q, r, 0), 1.0)
			_add_tree(top, _jit(q, r, 1), 0.85)
			_add_tree(top, _jit(q, r, 2), 0.7)
		Domain.TerrainType.ORCHARD:
			_add_tree(top, _jit(q, r, 0), 0.8)
			_add_tree(top, _jit(q, r, 3), 0.7)
		Domain.TerrainType.BUILDING:
			_add_building(top)
		Domain.TerrainType.RUBBLE:
			_add_box(top + Vector3(0.2, 0.1, -0.1), Vector3(0.4, 0.2, 0.4), Color(0.45, 0.43, 0.40))
			_add_box(top + Vector3(-0.25, 0.07, 0.2), Vector3(0.3, 0.14, 0.3), Color(0.5, 0.47, 0.44))


func _jit(q: int, r: int, i: int) -> Vector3:
	var a := float(q * 12 + r * 7 + i * 53)
	return Vector3(sin(a) * 0.45, 0.0, cos(a * 1.7) * 0.45)


func _add_tree(top: Vector3, off: Vector3, scale: float) -> void:
	var trunk := MeshInstance3D.new()
	var tc := CylinderMesh.new()
	tc.top_radius = 0.05 * scale; tc.bottom_radius = 0.07 * scale; tc.height = 0.35 * scale
	tc.radial_segments = 6
	trunk.mesh = tc
	trunk.material_override = _mat(Color(0.35, 0.25, 0.15))
	trunk.position = top + off + Vector3(0.0, 0.175 * scale, 0.0)
	add_child(trunk)
	var foliage := MeshInstance3D.new()
	var fc := CylinderMesh.new()
	fc.top_radius = 0.0; fc.bottom_radius = 0.34 * scale; fc.height = 0.75 * scale
	fc.radial_segments = 8
	foliage.mesh = fc
	foliage.material_override = _mat(Color(0.10, 0.32, 0.12))
	foliage.position = top + off + Vector3(0.0, 0.7 * scale, 0.0)
	add_child(foliage)


func _add_building(top: Vector3) -> void:
	_add_box(top + Vector3(0.0, 0.3, 0.0), Vector3(0.95, 0.6, 0.85), Color(0.62, 0.5, 0.4))
	var roof := MeshInstance3D.new()
	var rc := CylinderMesh.new()
	rc.top_radius = 0.0; rc.bottom_radius = 0.72; rc.height = 0.4
	rc.radial_segments = 4
	roof.mesh = rc
	roof.rotation_degrees = Vector3(0.0, 45.0, 0.0)
	roof.material_override = _mat(Color(0.45, 0.22, 0.18))
	roof.position = top + Vector3(0.0, 0.8, 0.0)
	add_child(roof)


func _add_box(center: Vector3, size: Vector3, col: Color) -> void:
	var b := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	b.mesh = bm
	b.material_override = _mat(col)
	b.position = center
	add_child(b)


# ─── Bordi: muri, steccati, siepi, bocage ─────────────────────────────────────

func _add_side_features(s: GameState) -> void:
	for sf in s.side_features:
		var feat := int(sf.get("feature", Domain.HexsideFeature.NONE))
		var spec := _side_spec(feat)
		if spec.is_empty():
			continue
		var a: Vector2i = sf.get("a", Vector2i.ZERO)
		var b: Vector2i = sf.get("b", Vector2i.ZERO)
		var ha: GameState.HexData = s.hex_at(a.x, a.y)
		var hb: GameState.HexData = s.hex_at(b.x, b.y)
		var ea := ha.elevation if ha != null else 0
		var eb := hb.elevation if hb != null else 0
		var top_y := BASE_H + maxi(ea, eb) * ELEV_STEP
		var ca := _hex_img(a.x, a.y)
		var cb := _hex_img(b.x, b.y)
		var wa := Vector3(ca.x * _world, top_y, ca.y * _world)
		var wb := Vector3(cb.x * _world, top_y, cb.y * _world)
		var mid := (wa + wb) * 0.5
		var dir := (wb - wa)
		dir.y = 0.0
		dir = dir.normalized()
		var along := Vector3.UP.cross(dir).normalized()
		var h: float = spec["h"]
		var bx := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.02, h, spec["t"])
		bx.mesh = bm
		bx.material_override = _mat(spec["c"])
		bx.transform = Transform3D(Basis(along, Vector3.UP, dir), mid + Vector3(0.0, h * 0.5, 0.0))
		add_child(bx)


func _side_spec(feat: int) -> Dictionary:
	match feat:
		Domain.HexsideFeature.WALL:
			return { "h": 0.32, "t": 0.08, "c": Color(0.55, 0.53, 0.5) }
		Domain.HexsideFeature.HEDGE:
			return { "h": 0.36, "t": 0.18, "c": Color(0.16, 0.36, 0.14) }
		Domain.HexsideFeature.BOCAGE:
			return { "h": 0.5, "t": 0.26, "c": Color(0.12, 0.3, 0.12) }
		Domain.HexsideFeature.FENCE:
			return { "h": 0.26, "t": 0.05, "c": Color(0.4, 0.3, 0.18) }
	return {}


# ─── Camera + interazione ─────────────────────────────────────────────────────

func _update_camera() -> void:
	var off := Vector3(
		cos(_cam_pitch) * sin(_cam_yaw),
		sin(_cam_pitch),
		cos(_cam_pitch) * cos(_cam_yaw)) * _cam_dist
	_camera.position = _center + off
	_camera.look_at(_center, Vector3.UP)


## Traduce un punto del viewport nell'esagono (q,r) sotto di esso (raggio della
## camera ∩ piano del tabellone → esagono più vicino). (-1,-1) se fuori.
func _pick_hex(vpos: Vector2) -> Vector2i:
	if Game.state == null:
		return Vector2i(-1, -1)
	var origin := _camera.project_ray_origin(vpos)
	var dir := _camera.project_ray_normal(vpos)
	if absf(dir.y) < 1e-5:
		return Vector2i(-1, -1)
	var t := (BASE_H - origin.y) / dir.y
	if t < 0.0:
		return Vector2i(-1, -1)
	var hit := origin + dir * t
	var pim := Vector2(hit.x / _world, hit.z / _world)
	var best := Vector2i(-1, -1)
	var bestd := INF
	for key in Game.state.hexes:
		var p := String(key).split(",")
		var c := _hex_img(int(p[0]), int(p[1]))
		var d := pim.distance_to(c)
		if d < bestd:
			bestd = d
			best = Vector2i(int(p[0]), int(p[1]))
	if bestd > _hx * 1.1:
		return Vector2i(-1, -1)
	return best


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press_pos = mb.position
				_dragged = false
			else:
				if not _dragged:  # clic (non trascinamento) → seleziona/ordina
					var hx := _pick_hex(mb.position)
					if hx.x >= 0:
						Game.click_hex(hx.x, hx.y)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = maxf(8.0, _cam_dist - 2.0)
			_update_camera()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = minf(160.0, _cam_dist + 2.0)
			_update_camera()
	elif event is InputEventMouseMotion \
			and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		var mm := event as InputEventMouseMotion
		if mm.position.distance_to(_press_pos) > 5.0:
			_dragged = true
		_cam_yaw -= mm.relative.x * 0.01
		_cam_pitch = clampf(_cam_pitch - mm.relative.y * 0.01, 0.2, 1.45)
		_update_camera()
