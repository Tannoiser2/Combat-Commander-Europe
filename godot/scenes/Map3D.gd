## Mappa 3D (vista alternativa): il tabellone reale è usato come SKIN, drappeggiato
## su esagoni flat-top estrusi in base all'elevazione reale (esagoni ad altezza
## variabile). Scena SEPARATA dalla 2D. Camera orbitabile (trascina = ruota,
## rotella = zoom). «2»/ESC torna alla mappa 2D. Stato letto da GameState.
extends Node3D

const WORLD := 1.0 / 59.2   ## immagine→mondo: ~1 unità per raggio-esagono (cal_hex)
const ELEV_STEP := 0.55     ## rialzo per livello di elevazione
const BASE_H := 0.25        ## spessore minimo del prisma

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
			corners_w.append(Vector3(ci.x * WORLD, top_y, ci.y * WORLD))
			corners_uv.append(Vector2(ci.x / iw, ci.y / ih))
		var center_w := Vector3(cimg.x * WORLD, top_y, cimg.y * WORLD)
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

	_add_pieces(s, ox, oy, hx)

	_center = Vector3((minx + maxx) * 0.5, 0.0, (minz + maxz) * 0.5)
	_cam_dist = maxf(maxx - minx, maxz - minz) * 0.7 + 8.0


## Pedine: cilindro kaki (Ger) / verde (Rus) sopra l'esagono, all'altezza reale.
func _add_pieces(s: GameState, ox: float, oy: float, hx: float) -> void:
	for u in s.units.values():
		if not u.is_man():
			continue
		var hd: GameState.HexData = s.hex_at(u.q, u.r)
		var top_y := BASE_H + (hd.elevation if hd != null else 0) * ELEV_STEP
		var pm := MeshInstance3D.new()
		var pc := CylinderMesh.new()
		pc.top_radius = 0.32
		pc.bottom_radius = 0.32
		pc.height = 0.6
		pc.radial_segments = 16
		pm.mesh = pc
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.66, 0.58, 0.30) if u.faction == Domain.Faction.GERMAN \
			else Color(0.28, 0.5, 0.28)
		pm.material_override = mat
		var ci := _hex_img(u.q, u.r, ox, oy, hx)
		pm.position = Vector3(ci.x * WORLD, top_y + 0.3, ci.y * WORLD)
		add_child(pm)


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
