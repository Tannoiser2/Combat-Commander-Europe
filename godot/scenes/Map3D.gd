## Prototipo della mappa 3D (2.5D): il terreno esagonale è reso con prismi 3D la
## cui altezza dipende dall'elevazione; le unità sono cilindri colorati. Scena
## SEPARATA dalla mappa 2D (nessun rischio per il gioco esistente). Camera
## orbitabile (trascina = ruota, rotella = zoom). Riusa i dati di GameState.
extends Node3D

const HEX_R := 1.0          ## circumraggio dell'esagono (layout flat-top)
const ELEV_STEP := 0.7      ## rialzo per livello di elevazione
const BASE_H := 0.4         ## spessore base del prisma

## Terreno → colore (versione opaca per il 3D).
const TERRAIN_COLOR := {
	Domain.TerrainType.OPEN:          Color(0.56, 0.62, 0.34),
	Domain.TerrainType.BRUSH:         Color(0.46, 0.55, 0.30),
	Domain.TerrainType.WOODS:         Color(0.16, 0.34, 0.16),
	Domain.TerrainType.BUILDING:      Color(0.58, 0.47, 0.36),
	Domain.TerrainType.ORCHARD:       Color(0.40, 0.58, 0.28),
	Domain.TerrainType.FIELD:         Color(0.82, 0.73, 0.30),
	Domain.TerrainType.STREAM:        Color(0.22, 0.45, 0.68),
	Domain.TerrainType.MARSH:         Color(0.40, 0.46, 0.34),
	Domain.TerrainType.WATER_BARRIER: Color(0.16, 0.38, 0.62),
	Domain.TerrainType.GULLY:         Color(0.46, 0.42, 0.30),
	Domain.TerrainType.BRIDGE:        Color(0.60, 0.50, 0.38),
	Domain.TerrainType.HILL1:         Color(0.62, 0.52, 0.32),
	Domain.TerrainType.HILL2:         Color(0.66, 0.50, 0.28),
	Domain.TerrainType.ROAD:          Color(0.72, 0.62, 0.42),
	Domain.TerrainType.RUBBLE:        Color(0.46, 0.43, 0.40),
}

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


## Luce direzionale (sole) + ambiente con cielo e luce ambientale, così le facce
## non illuminate non risultano nere.
func _add_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -40.0, 0.0)
	sun.light_energy = 1.1
	add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.66, 0.82)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.82, 0.82, 0.88)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


## Posizione (x,z) del centro dell'esagono nel mondo 3D (layout flat-top, offset
## colonne — lo stesso della mappa 2D).
func _hex_world(q: int, r: int) -> Vector3:
	var x := 1.5 * HEX_R * q
	var z := sqrt(3.0) * HEX_R * (r + 0.5 * (q & 1))
	return Vector3(x, 0.0, z)


func _build(s: GameState) -> void:
	var maxx := 0.0
	var maxz := 0.0
	for key in s.hexes:
		var p := String(key).split(",")
		var q := int(p[0])
		var r := int(p[1])
		var hd: GameState.HexData = s.hexes[key]
		var h := BASE_H + hd.elevation * ELEV_STEP
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = HEX_R
		cyl.bottom_radius = HEX_R
		cyl.height = h
		cyl.radial_segments = 6
		mi.mesh = cyl
		var mat := StandardMaterial3D.new()
		mat.albedo_color = TERRAIN_COLOR.get(hd.terrain, Color(0.5, 0.55, 0.35))
		mi.material_override = mat
		var w := _hex_world(q, r)
		mi.position = Vector3(w.x, h * 0.5, w.z)
		add_child(mi)
		maxx = maxf(maxx, w.x)
		maxz = maxf(maxz, w.z)
	# Unità: cilindro color kaki (Ger) o verde (Rus) sopra l'esagono.
	for u in s.units.values():
		if not u.is_man():
			continue
		var hd2: GameState.HexData = s.hex_at(u.q, u.r)
		var top := BASE_H + (hd2.elevation if hd2 != null else 0) * ELEV_STEP
		var pm := MeshInstance3D.new()
		var pc := CylinderMesh.new()
		pc.top_radius = 0.34
		pc.bottom_radius = 0.34
		pc.height = 0.7
		pc.radial_segments = 14
		pm.mesh = pc
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(0.62, 0.56, 0.32) if u.faction == Domain.Faction.GERMAN \
			else Color(0.28, 0.5, 0.28)
		pm.material_override = pmat
		var w2 := _hex_world(u.q, u.r)
		pm.position = Vector3(w2.x, top + 0.35, w2.z)
		add_child(pm)
	_center = Vector3(maxx * 0.5, 0.0, maxz * 0.5)
	_cam_dist = maxf(maxx, maxz) * 0.8 + 10.0


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
			_cam_dist = minf(120.0, _cam_dist + 2.0)
			_update_camera()
