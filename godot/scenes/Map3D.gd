## Mappa 3D (vista alternativa): il tabellone reale è usato come SKIN, drappeggiato
## su esagoni flat-top estrusi in base all'elevazione reale (esagoni ad altezza
## variabile). Scena SEPARATA dalla 2D. Camera orbitabile (trascina = ruota,
## rotella = zoom). «2»/ESC torna alla mappa 2D. Stato letto da GameState.
extends Node3D

const ELEV_STEP := 0.55     ## rialzo per livello di elevazione
const BASE_H := 0.25        ## spessore minimo del prisma

## immagine→mondo: 1 unità per raggio-esagono. Derivato dal cal_hex della mappa
## corrente (così funziona per QUALSIASI mappa degli scenari, non solo map1).
var _world := 1.0 / 59.2

var _cam_yaw := 0.6
var _cam_pitch := 0.85
var _cam_dist := 30.0
var _center := Vector3.ZERO

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	_add_lighting()
	var s := Game.state
	if s == null:
		Game.start_new_game(Domain.Faction.GERMAN, 1)
		s = Game.state
	_build(s)
	_camera.current = true
	_update_camera()
	_add_ui()


## Overlay 2D: pulsante per tornare alla mappa 2D.
func _add_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var btn := Button.new()
	btn.text = "▣ Vista 2D"
	btn.position = Vector2(16, 14)
	btn.custom_minimum_size = Vector2(130, 38)
	btn.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/Main.tscn"))
	layer.add_child(btn)
	var hint := Label.new()
	hint.text = "Trascina = ruota · rotella = zoom · «2»/ESC = 2D"
	hint.position = Vector2(160, 22)
	hint.modulate = Color(1, 1, 1, 0.7)
	layer.add_child(hint)


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


## Centro dell'esagono (q,r) in PIXEL dell'immagine del tabellone (stessa
## calibrazione della 2D: ox/oy/hex).
func _hex_img(q: int, r: int, ox: float, oy: float, hx: float) -> Vector2:
	return Vector2(ox + hx * 1.5 * q, oy + hx * sqrt(3.0) * (r + 0.5 * (q & 1)))


func _build(s: GameState) -> void:
	var tex := load("res://assets/maps_img/%s.jpg" % s.map_image) as Texture2D
	var iw := float(tex.get_width()) if tex != null else 1024.0
	var ih := float(tex.get_height()) if tex != null else 1024.0
	var ox: float = s.cal_ox
	var oy: float = s.cal_oy
	var hx: float = s.cal_hex
	_world = 1.0 / hx

	# Due superfici: i TOP esagonali col texture del tabellone, i FIANCHI a tinta unita.
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
		var cimg := _hex_img(q, r, ox, oy, hx)
		# Vertici (flat-top: angoli 0,60,…,300) in pixel immagine → mondo + UV.
		var corners_w: Array[Vector3] = []
		var corners_uv: Array[Vector2] = []
		for i in range(6):
			var a := deg_to_rad(60.0 * i)
			var ci := cimg + hx * Vector2(cos(a), sin(a))
			corners_w.append(Vector3(ci.x * _world, top_y, ci.y * _world))
			corners_uv.append(Vector2(ci.x / iw, ci.y / ih))
		var center_w := Vector3(cimg.x * _world, top_y, cimg.y * _world)
		var center_uv := Vector2(cimg.x / iw, cimg.y / ih)
		# Faccia superiore (ventaglio dal centro), texture del tabellone.
		for i in range(6):
			var j := (i + 1) % 6
			top_st.set_normal(Vector3.UP)
			top_st.set_uv(center_uv); top_st.add_vertex(center_w)
			top_st.set_uv(corners_uv[i]); top_st.add_vertex(corners_w[i])
			top_st.set_uv(corners_uv[j]); top_st.add_vertex(corners_w[j])
		# Fianchi: dal bordo superiore giù a y=0 (estrusione = altezza variabile).
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
	var side_mat := StandardMaterial3D.new()
	side_mat.albedo_color = Color(0.32, 0.26, 0.18)  # terra dei fianchi
	var side_mi := MeshInstance3D.new()
	side_mi.mesh = side_st.commit()
	side_mi.material_override = side_mat
	add_child(side_mi)

	_add_side_features(s, ox, oy, hx)
	_add_pieces(s, ox, oy, hx)
	_add_objectives(s, ox, oy, hx)

	_center = Vector3((minx + maxx) * 0.5, 0.0, (minz + maxz) * 0.5)
	_cam_dist = maxf(maxx - minx, maxz - minz) * 0.7 + 8.0


## Pedine come SEGNALINI veri: ogni unità è uno sprite billboard con la grafica
## del suo counter, in piedi sull'esagono all'altezza reale. Le unità impilate
## sono scaglionate per restare leggibili.
func _add_pieces(s: GameState, ox: float, oy: float, hx: float) -> void:
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
			var hd: GameState.HexData = s.hex_at(u.q, u.r)
			var top_y := BASE_H + (hd.elevation if hd != null else 0) * ELEV_STEP
			var ci := _hex_img(u.q, u.r, ox, oy, hx)
			# scaglionamento dell'impilamento (diagonale + leggero rialzo)
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
				add_child(sp)
			else:
				var pm := MeshInstance3D.new()
				var pc := CylinderMesh.new()
				pc.top_radius = 0.3
				pc.bottom_radius = 0.3
				pc.height = 0.6
				pc.radial_segments = 16
				pm.mesh = pc
				pm.material_override = _mat(Color(0.66, 0.58, 0.30) \
					if u.faction == Domain.Faction.GERMAN else Color(0.28, 0.5, 0.28))
				pm.position = base + Vector3(0.0, 0.3, 0.0)
				add_child(pm)


## Texture del counter dell'unità (stessa logica della 2D: usa nation_art oppure,
## se vuota, la cartella della fazione). Restituisce null se non esiste.
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


## Marker degli obiettivi: un'astina con sopra il valore in VP, colorato in base
## al controllore (kaki=Ger, verde=Rus, bianco=neutro).
func _add_objectives(s: GameState, ox: float, oy: float, hx: float) -> void:
	for o in s.objectives:
		var hd: GameState.HexData = s.hex_at(o.q, o.r)
		var top_y := BASE_H + (hd.elevation if hd != null else 0) * ELEV_STEP
		var ci := _hex_img(o.q, o.r, ox, oy, hx)
		var col := Color(0.9, 0.9, 0.9)
		if o.controller == Domain.Faction.GERMAN:
			col = Color(0.78, 0.7, 0.36)
		elif o.controller == Domain.Faction.RUSSIAN:
			col = Color(0.4, 0.66, 0.4)
		var pole := MeshInstance3D.new()
		var pc := CylinderMesh.new()
		pc.top_radius = 0.04
		pc.bottom_radius = 0.04
		pc.height = 1.1
		pc.radial_segments = 6
		pole.mesh = pc
		pole.material_override = _mat(Color(0.2, 0.2, 0.2))
		pole.position = Vector3(ci.x * _world, top_y + 0.55, ci.y * _world)
		add_child(pole)
		var lbl := Label3D.new()
		lbl.text = "%d" % o.vp
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.font_size = 80
		lbl.pixel_size = 0.011
		lbl.modulate = col
		lbl.outline_size = 18
		lbl.outline_modulate = Color(0, 0, 0, 0.85)
		lbl.position = Vector3(ci.x * _world, top_y + 1.25, ci.y * _world)
		add_child(lbl)


func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	return m


# ─── Volumi 3D: alberi, edifici, macerie sopra l'esagono ──────────────────────

## Aggiunge volumi sopra l'esagono in base al terreno. `top` = centro della
## faccia superiore (alla quota reale).
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


## Offset deterministico (niente RNG) per scostare gli alberi dentro l'esagono.
func _jit(q: int, r: int, i: int) -> Vector3:
	var a := float(q * 12 + r * 7 + i * 53)
	return Vector3(sin(a) * 0.45, 0.0, cos(a * 1.7) * 0.45)


func _add_tree(top: Vector3, off: Vector3, scale: float) -> void:
	var trunk := MeshInstance3D.new()
	var tc := CylinderMesh.new()
	tc.top_radius = 0.05 * scale
	tc.bottom_radius = 0.07 * scale
	tc.height = 0.35 * scale
	tc.radial_segments = 6
	trunk.mesh = tc
	trunk.material_override = _mat(Color(0.35, 0.25, 0.15))
	trunk.position = top + off + Vector3(0.0, 0.175 * scale, 0.0)
	add_child(trunk)
	var foliage := MeshInstance3D.new()
	var fc := CylinderMesh.new()
	fc.top_radius = 0.0
	fc.bottom_radius = 0.34 * scale
	fc.height = 0.75 * scale
	fc.radial_segments = 8
	foliage.mesh = fc
	foliage.material_override = _mat(Color(0.10, 0.32, 0.12))
	foliage.position = top + off + Vector3(0.0, 0.7 * scale, 0.0)
	add_child(foliage)


func _add_building(top: Vector3) -> void:
	_add_box(top + Vector3(0.0, 0.3, 0.0), Vector3(0.95, 0.6, 0.85), Color(0.62, 0.5, 0.4))
	var roof := MeshInstance3D.new()
	var rc := CylinderMesh.new()
	rc.top_radius = 0.0
	rc.bottom_radius = 0.72
	rc.height = 0.4
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

## Rende le caratteristiche dei lati (HEDGE/WALL/FENCE/BOCAGE) come segmenti lungo
## il bordo condiviso tra i due esagoni.
func _add_side_features(s: GameState, ox: float, oy: float, hx: float) -> void:
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
		var ca := _hex_img(a.x, a.y, ox, oy, hx)
		var cb := _hex_img(b.x, b.y, ox, oy, hx)
		var wa := Vector3(ca.x * _world, top_y, ca.y * _world)
		var wb := Vector3(cb.x * _world, top_y, cb.y * _world)
		var mid := (wa + wb) * 0.5
		var dir := (wb - wa)
		dir.y = 0.0
		dir = dir.normalized()
		var along := Vector3.UP.cross(dir).normalized()  # lungo il bordo (orizz.)
		var h: float = spec["h"]
		var bx := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.02, h, spec["t"])  # lunghezza ≈ lato esagono
		bx.mesh = bm
		bx.material_override = _mat(spec["c"])
		bx.transform = Transform3D(Basis(along, Vector3.UP, dir), mid + Vector3(0.0, h * 0.5, 0.0))
		add_child(bx)


## Altezza/spessore/colore per tipo di lato; vuoto se non è un muretto.
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


func _update_camera() -> void:
	var off := Vector3(
		cos(_cam_pitch) * sin(_cam_yaw),
		sin(_cam_pitch),
		cos(_cam_pitch) * cos(_cam_yaw)) * _cam_dist
	_camera.position = _center + off
	_camera.look_at(_center, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var kc := (event as InputEventKey).keycode
		if kc == KEY_2 or kc == KEY_ESCAPE:  # torna alla mappa 2D
			get_tree().change_scene_to_file("res://scenes/Main.tscn")
			return
	if event is InputEventMouseMotion \
			and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		var mm := event as InputEventMouseMotion
		_cam_yaw -= mm.relative.x * 0.01
		_cam_pitch = clampf(_cam_pitch - mm.relative.y * 0.01, 0.2, 1.45)
		_update_camera()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = maxf(8.0, _cam_dist - 2.0)
			_update_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = minf(160.0, _cam_dist + 2.0)
			_update_camera()
