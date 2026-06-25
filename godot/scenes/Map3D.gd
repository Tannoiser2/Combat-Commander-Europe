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
var _fx: Node3D            ## layer effetti transitori (tracer, flash); non azzerato dai refresh
var _last_unit_pos := {}   ## id unità → Vector2i(q,r) noto (per animare lo spostamento)
var _pending_slide := {}   ## id unità → Vector3 posizione mondo di partenza dello slittamento
var _pieces := []          ## [{id, node}] pedine correnti (per il click preciso sulle pile)
var _press_pos := Vector2.ZERO
var _dragged := false
var _touches := {}        ## indice dito → posizione (per il pinch a due dita)
var _pinch_dist := 0.0
var active := true   ## Main lo mette a false quando la 3D è nascosta (no refresh)

const ORBIT_SPEED := 0.004   ## sensibilità rotazione (più basso = più lento)

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
	_fx = Node3D.new()
	add_child(_fx)
	_refresh_dynamic(s)
	_camera.current = true
	_update_camera()
	if not Game.state_changed.is_connected(_on_state_changed):
		Game.state_changed.connect(_on_state_changed)
	if not Game.unit_moved.is_connected(_on_unit_moved):
		Game.unit_moved.connect(_on_unit_moved)
	if not Game.fire_resolved.is_connected(_on_fire_resolved):
		Game.fire_resolved.connect(_on_fire_resolved)


func _on_state_changed() -> void:
	if Game.state != null and active:
		_refresh_dynamic(Game.state)


## Lo spostamento di un'unità: memorizza la posizione di partenza così che, al
## successivo refresh, la pedina scivoli dall'esagono vecchio a quello nuovo.
func _on_unit_moved(id: String, q: int, r: int) -> void:
	if not active or Game.state == null:
		return
	if _last_unit_pos.has(id):
		var old: Vector2i = _last_unit_pos[id]
		if old != Vector2i(q, r):
			var oci := _hex_img(old.x, old.y)
			var oty := _top_y(Game.state, old.x, old.y)
			_pending_slide[id] = Vector3(oci.x * _world, oty + 0.75, oci.y * _world)


## Tiro risolto: tracciante dallo sparatore al bersaglio + lampo e impatto.
func _on_fire_resolved(result: Object) -> void:
	if not active or Game.state == null or result == null:
		return
	var atk := Game.state.unit_by_id(result.attacker_id)
	if atk == null:
		return
	var s := Game.state
	var fci := _hex_img(atk.q, atk.r)
	var from := Vector3(fci.x * _world, _top_y(s, atk.q, atk.r) + 0.9, fci.y * _world)
	var tci := _hex_img(result.target_q, result.target_r)
	var to := Vector3(tci.x * _world, _top_y(s, result.target_q, result.target_r) + 0.6, tci.y * _world)
	_spawn_tracer(from, to)
	_spawn_flash(from, 0.18, Color(1.0, 0.92, 0.45), 0.3)
	_spawn_flash(to, 0.34, Color(1.0, 0.5, 0.15), 0.65)


## Tracciante: cilindro sottile emissivo orientato da → a, che svanisce.
func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var tracer := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.03
	cyl.height = from.distance_to(to)
	cyl.radial_segments = 6
	tracer.mesh = cyl
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.95, 0.55)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.85, 0.3)
	m.emission_energy_multiplier = 2.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer.material_override = m
	tracer.transform = _aim_y((from + to) * 0.5, (to - from))
	_fx.add_child(tracer)
	var tw := tracer.create_tween()
	tw.tween_interval(0.12)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.32)
	tw.parallel().tween_property(m, "emission_energy_multiplier", 0.0, 0.32)
	tw.tween_callback(tracer.queue_free)


## Lampo/impatto: sfera emissiva che si espande e svanisce.
func _spawn_flash(pos: Vector3, radius: float, color: Color, dur: float) -> void:
	var fl := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = radius
	sph.height = radius * 2.0
	fl.mesh = sph
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.2
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fl.material_override = m
	fl.position = pos
	_fx.add_child(fl)
	var tw := fl.create_tween()
	tw.tween_property(fl, "scale", Vector3(2.2, 2.2, 2.2), dur)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, dur)
	tw.tween_callback(fl.queue_free)


## Transform che mappa l'asse Y del mesh sulla direzione `dir` (per i cilindri).
func _aim_y(origin: Vector3, dir: Vector3) -> Transform3D:
	var y := dir.normalized()
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Transform3D(Basis(x, y, z), origin)


## Rigenera il layer dinamico (pedine, obiettivi, evidenziazioni).
func refresh() -> void:
	if Game.state != null:
		_refresh_dynamic(Game.state)


func _refresh_dynamic(s: GameState) -> void:
	for c in _dynamic.get_children():
		c.queue_free()
	_pieces.clear()
	_add_status_markers(s)
	_add_highlights(s)
	_add_los_lines(s)
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

	# Superficie texturizzata (vassoio + cime dei rilievi) e superficie marrone
	# (spessore del bordo + fianchi dei rilievi).
	var tex_st := SurfaceTool.new()
	tex_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var brown_st := SurfaceTool.new()
	brown_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 1) VASSOIO RETTANGOLARE: l'intera immagine del tabellone (bordo marrone
	#    incluso) come piano a quota BASE_H → la mappa 3D è rettangolare come la reale.
	var ww := iw * _world
	var hh := ih * _world
	_tray_top(tex_st, ww, hh)
	# fianchi del perimetro (spessore del tabellone) da BASE_H giù a 0.
	_rect_wall(brown_st, Vector3(0, BASE_H, 0), Vector3(ww, BASE_H, 0))
	_rect_wall(brown_st, Vector3(ww, BASE_H, 0), Vector3(ww, BASE_H, hh))
	_rect_wall(brown_st, Vector3(ww, BASE_H, hh), Vector3(0, BASE_H, hh))
	_rect_wall(brown_st, Vector3(0, BASE_H, hh), Vector3(0, BASE_H, 0))

	# 2) RILIEVI: solo gli esagoni con elevazione > 0 sporgono sopra il vassoio.
	for key in s.hexes:
		var p := String(key).split(",")
		var q := int(p[0])
		var r := int(p[1])
		var hd: GameState.HexData = s.hexes[key]
		var top_y := BASE_H + hd.elevation * ELEV_STEP
		var cimg := _hex_img(q, r)
		if hd.elevation > 0:
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
				tex_st.set_normal(Vector3.UP)
				tex_st.set_uv(center_uv); tex_st.add_vertex(center_w)
				tex_st.set_uv(corners_uv[i]); tex_st.add_vertex(corners_w[i])
				tex_st.set_uv(corners_uv[j]); tex_st.add_vertex(corners_w[j])
			# fianchi del rilievo: dal bordo superiore giù al vassoio (BASE_H).
			for i in range(6):
				var j := (i + 1) % 6
				var tA := corners_w[i]
				var tB := corners_w[j]
				var bA := Vector3(tA.x, BASE_H, tA.z)
				var bB := Vector3(tB.x, BASE_H, tB.z)
				brown_st.add_vertex(tA); brown_st.add_vertex(bA); brown_st.add_vertex(tB)
				brown_st.add_vertex(tB); brown_st.add_vertex(bA); brown_st.add_vertex(bB)
		_decorate(hd, q, r, Vector3(cimg.x * _world, top_y, cimg.y * _world))

	tex_st.generate_normals()
	var top_mat := StandardMaterial3D.new()
	if tex != null:
		top_mat.albedo_texture = tex
	top_mat.roughness = 1.0
	var top_mi := MeshInstance3D.new()
	top_mi.mesh = tex_st.commit()
	top_mi.material_override = top_mat
	add_child(top_mi)

	brown_st.generate_normals()
	var side_mi := MeshInstance3D.new()
	side_mi.mesh = brown_st.commit()
	side_mi.material_override = _mat(Color(0.30, 0.22, 0.13))
	add_child(side_mi)

	_add_side_features(s)
	_center = Vector3(ww * 0.5, 0.0, hh * 0.5)
	_cam_dist = maxf(ww, hh) * 0.75 + 6.0


## Faccia superiore del vassoio: quad (0,0)-(ww,hh) con l'immagine completa.
func _tray_top(st: SurfaceTool, ww: float, hh: float) -> void:
	var a := Vector3(0, BASE_H, 0)
	var b := Vector3(ww, BASE_H, 0)
	var c := Vector3(ww, BASE_H, hh)
	var d := Vector3(0, BASE_H, hh)
	st.set_normal(Vector3.UP); st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_normal(Vector3.UP); st.set_uv(Vector2(1, 0)); st.add_vertex(b)
	st.set_normal(Vector3.UP); st.set_uv(Vector2(1, 1)); st.add_vertex(c)
	st.set_normal(Vector3.UP); st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_normal(Vector3.UP); st.set_uv(Vector2(1, 1)); st.add_vertex(c)
	st.set_normal(Vector3.UP); st.set_uv(Vector2(0, 1)); st.add_vertex(d)


## Parete verticale del perimetro tra due punti del bordo superiore, giù a y=0.
func _rect_wall(st: SurfaceTool, ta: Vector3, tb: Vector3) -> void:
	var ba := Vector3(ta.x, 0.0, ta.z)
	var bb := Vector3(tb.x, 0.0, tb.z)
	st.add_vertex(ta); st.add_vertex(ba); st.add_vertex(tb)
	st.add_vertex(tb); st.add_vertex(ba); st.add_vertex(bb)


# ─── Layer dinamico ───────────────────────────────────────────────────────────

## Evidenzia gli esagoni-bersaglio (s.highlighted_hexes) con un disco giallo
## translucido, l'unità selezionata in azzurro, e replica in 3D le stesse
## evidenziazioni della 2D: gruppo di comando, assemblaggio del gruppo di fuoco
## e finestra di Fuoco di Opportunità.
func _add_highlights(s: GameState) -> void:
	for key in s.highlighted_hexes:
		var p := String(key).split(",")
		_hex_disc(int(p[0]), int(p[1]), s, Color(1.0, 0.95, 0.2, 0.5))
	# Gruppo di comando attivato dall'ordine del leader (arancio).
	for gid in s.ordered_group:
		if gid == s.selected_unit_id:
			continue
		var gv := s.unit_by_id(gid)
		if gv != null:
			_hex_disc(gv.q, gv.r, s, Color(1.0, 0.55, 0.0, 0.35))
	# Assemblaggio del gruppo di fuoco: pezzi inclusi (arancio) / esclusi (grigio).
	if s.fire_target_q >= 0:
		for eid in s.fire_eligible_ids:
			if eid == s.selected_unit_id:
				continue
			var ev := s.unit_by_id(eid)
			if ev == null:
				continue
			var inc: bool = s.fire_group_ids.has(eid)
			_hex_disc(ev.q, ev.r, s,
				Color(1.0, 0.55, 0.0, 0.45) if inc else Color(0.6, 0.6, 0.6, 0.35))
	# Finestra di reazione (Fuoco di Opportunità): mover rosso, tiratori gialli.
	if s.phase == Domain.Phase.REACTION_WINDOW:
		var mv := s.unit_by_id(s.opfire_mover_id)
		if mv != null:
			_hex_disc(mv.q, mv.r, s, Color(0.95, 0.15, 0.15, 0.5))
		for sid in s.opfire_shooter_ids:
			var sv := s.unit_by_id(sid)
			if sv != null:
				_hex_disc(sv.q, sv.r, s, Color(1.0, 0.7, 0.1, 0.45))
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


## Linee di LOS dall'unità selezionata (se può sparare) verso i nemici in
## gittata: verde = LOS libera, giallo = libera ma con ostacolo (hindrance),
## rosso = bloccata. Aiuto tattico esclusivo della 3D.
func _add_los_lines(s: GameState) -> void:
	if s.selected_unit_id == "":
		return
	var sh := s.unit_by_id(s.selected_unit_id)
	if sh == null or not sh.efficient or sh.fp <= 0:
		return
	var rng := Rules.range_with_command(s, sh)
	for e in s.units.values():
		if e.faction == sh.faction:
			continue
		var d := HexGrid.distance(sh.q, sh.r, e.q, e.r)
		if d < 1 or d > rng:
			continue
		var col: Color
		if HexGrid.has_los(sh.q, sh.r, e.q, e.r, s):
			col = Color(0.2, 1.0, 0.3, 0.7) if HexGrid.los_hindrance(sh.q, sh.r, e.q, e.r, s) == 0 \
				else Color(1.0, 0.85, 0.2, 0.7)
		else:
			col = Color(1.0, 0.25, 0.2, 0.55)
		_los_line(sh.q, sh.r, e.q, e.r, s, col)


func _los_line(q1: int, r1: int, q2: int, r2: int, s: GameState, col: Color) -> void:
	var c1 := _hex_img(q1, r1)
	var c2 := _hex_img(q2, r2)
	var from := Vector3(c1.x * _world, _top_y(s, q1, r1) + 0.55, c1.y * _world)
	var to := Vector3(c2.x * _world, _top_y(s, q2, r2) + 0.55, c2.y * _world)
	var ln := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.025
	cyl.bottom_radius = 0.025
	cyl.height = from.distance_to(to)
	cyl.radial_segments = 5
	ln.mesh = cyl
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ln.material_override = m
	ln.transform = _aim_y((from + to) * 0.5, (to - from))
	_dynamic.add_child(ln)


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
			var sel := u.id == s.selected_unit_id
			var top_y := _top_y(s, u.q, u.r)
			var ci := _hex_img(u.q, u.r)
			var off := Vector3(0.16 * i - 0.12, 0.12 * i, -0.16 * i + 0.12)
			# La pedina selezionata si solleva sopra l'impilamento per essere vista.
			var lift := 0.7 if sel else 0.0
			var base := Vector3(ci.x * _world, top_y, ci.y * _world) + off + Vector3(0.0, lift, 0.0)
			var final_pos := base + Vector3(0.0, 0.75, 0.0)
			_last_unit_pos[u.id] = Vector2i(u.q, u.r)
			var tex := _counter_tex(u)
			if tex != null:
				var sp := Sprite3D.new()
				sp.texture = tex
				sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				sp.shaded = false
				sp.pixel_size = (1.85 if sel else 1.5) / float(tex.get_height())
				_dynamic.add_child(sp)
				# Se l'unità si è appena spostata, la pedina scivola da → a.
				if _pending_slide.has(u.id):
					sp.position = _pending_slide[u.id]
					var tw := sp.create_tween()
					tw.set_trans(Tween.TRANS_SINE)
					tw.tween_property(sp, "position", final_pos, 0.28)
					_pending_slide.erase(u.id)
				else:
					sp.position = final_pos
				_pieces.append({ "id": u.id, "node": sp })
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
				_pieces.append({ "id": u.id, "node": pm })


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


## Marcatori di stato sulla mappa (come la 2D): fumo, incendi, fortificazioni,
## buche e ultimo impatto d'artiglieria. Tutto nel layer dinamico.
func _add_status_markers(s: GameState) -> void:
	var fort_letters := { 1: "T", 2: "C", 3: "B", 4: "≋", 5: "✸" }
	var fort_colors := {
		1: Color(0.7, 0.9, 1.0), 2: Color(0.8, 0.8, 0.85), 3: Color(0.85, 0.85, 0.9),
		4: Color(1.0, 0.8, 0.3), 5: Color(1.0, 0.4, 0.3),
	}
	for key in s.hexes:
		var p := String(key).split(",")
		var q := int(p[0])
		var r := int(p[1])
		var hd: GameState.HexData = s.hexes[key]
		var top_y := _top_y(s, q, r)
		var ci := _hex_img(q, r)
		var cw := Vector3(ci.x * _world, top_y, ci.y * _world)
		if hd.has_foxhole:
			_ground_disc(q, r, s, 0.42, Color(0.12, 0.10, 0.07, 0.7))
		if hd.fortification != Domain.Fort.NONE:
			_badge(cw + Vector3(0.0, 1.35, 0.0),
				String(fort_letters.get(hd.fortification, "?")),
				fort_colors.get(hd.fortification, Color.WHITE))
		if hd.has_blaze:
			_hex_disc(q, r, s, Color(0.95, 0.45, 0.1, 0.5))
			_flame(cw)
		if hd.has_smoke:
			_smoke_puff(cw)
	# Ultimo impatto d'artiglieria: disco rosso translucido sugli esagoni colpiti.
	for ih in s.last_impact_hexes:
		_ground_disc(int(ih.x), int(ih.y), s, 0.95, Color(0.95, 0.15, 0.1, 0.28))


## Disco orizzontale (raggio = frazione dell'esagono) appoggiato sulla cima.
func _ground_disc(q: int, r: int, s: GameState, radius_frac: float, col: Color) -> void:
	var top_y := _top_y(s, q, r) + 0.05
	var ci := _hex_img(q, r)
	var cw := Vector3(ci.x * _world, top_y, ci.y * _world)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cor: Array[Vector3] = []
	for i in range(12):
		var a := deg_to_rad(30.0 * i)
		var ci2 := ci + (_hx * radius_frac) * Vector2(cos(a), sin(a))
		cor.append(Vector3(ci2.x * _world, top_y, ci2.y * _world))
	for i in range(12):
		var j := (i + 1) % 12
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


## Etichetta a cartello (lettera fortificazione) sospesa sopra l'esagono.
func _badge(pos: Vector3, txt: String, col: Color) -> void:
	var lbl := Label3D.new()
	lbl.text = txt
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 64
	lbl.pixel_size = 0.012
	lbl.modulate = col
	lbl.outline_size = 18
	lbl.outline_modulate = Color(0.05, 0.05, 0.05, 0.95)
	lbl.position = pos
	_dynamic.add_child(lbl)


## Nube di fumo: gruppo di sfere grigie translucide sopra l'esagono.
func _smoke_puff(cw: Vector3) -> void:
	var offs := [Vector3(0, 0.95, 0), Vector3(0.3, 1.15, 0.1), Vector3(-0.28, 1.1, -0.12)]
	for o in offs:
		var sm := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.42
		sph.height = 0.64
		sm.mesh = sph
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.82, 0.82, 0.86, 0.55)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.material_override = m
		sm.position = cw + o
		_dynamic.add_child(sm)


## Fiamma: cono arancione emissivo sopra l'esagono in fiamme.
func _flame(cw: Vector3) -> void:
	var fl := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.3
	cone.height = 0.7
	cone.radial_segments = 8
	fl.mesh = cone
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.55, 0.12)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.5, 0.05)
	m.emission_energy_multiplier = 1.6
	fl.material_override = m
	fl.position = cw + Vector3(0.0, 0.45, 0.0)
	_dynamic.add_child(fl)


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


## Pedina (billboard) sotto il cursore: proietta i centri delle pedine sullo
## schermo e sceglie quella più vicina al click, preferendo la più frontale
## (vicina alla camera) in una pila. "" se nessuna è abbastanza vicina.
func _pick_piece(vpos: Vector2) -> String:
	if _pieces.is_empty():
		return ""
	var thr := get_viewport().get_visible_rect().size.y * 0.06
	var best := ""
	var best_cam := INF
	for p in _pieces:
		var node: Node3D = p["node"]
		if not is_instance_valid(node):
			continue
		var gp := node.global_position
		if _camera.is_position_behind(gp):
			continue
		var sp := _camera.unproject_position(gp)
		if vpos.distance_to(sp) > thr:
			continue
		var cd := _camera.global_position.distance_to(gp)
		if cd < best_cam:
			best_cam = cd
			best = p["id"]
	return best


## Selezione/azione diretta sulla pedina cliccata in una pila. Restituisce true
## se gestita; false per ricadere sul normale click dell'esagono.
func _try_direct_select(pid: String) -> bool:
	var s := Game.state
	if s == null:
		return false
	var pu := s.unit_by_id(pid)
	if pu == null:
		return false
	# Selezione precisa nella fase di scelta dell'unità.
	if s.phase == Domain.Phase.PLAYER_TURN:
		if pu.faction == s.human_faction and not pu.activated:
			Game.select_unit(pid)
			return true
		return false
	# Inclusione/esclusione precisa di un pezzo nel gruppo di fuoco impilato.
	if s.phase == Domain.Phase.PLAYER_MOVING \
			and s.current_order == Domain.OrderType.FIRE and s.fire_target_q >= 0:
		if s.fire_eligible_ids.has(pid) and pid != s.selected_unit_id \
				and not (pu.q == s.fire_target_q and pu.r == s.fire_target_r):
			Game.toggle_fire_piece(pid)
			return true
	return false


func _zoom(factor: float) -> void:
	_cam_dist = clampf(_cam_dist * factor, 6.0, 200.0)
	_update_camera()


func _orbit(rel: Vector2) -> void:
	_cam_yaw -= rel.x * ORBIT_SPEED
	_cam_pitch = clampf(_cam_pitch - rel.y * ORBIT_SPEED, 0.2, 1.45)
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	# Gesti del trackpad: pinch (magnify) e pan a due dita.
	if event is InputEventMagnifyGesture:
		_zoom(1.0 / maxf(0.2, (event as InputEventMagnifyGesture).factor))
		return
	if event is InputEventPanGesture:
		_zoom(1.0 + (event as InputEventPanGesture).delta.y * 0.04)
		return
	# Touch screen: 1 dito = ruota, 2 dita = pinch-zoom.
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
		if _touches.size() < 2:
			_pinch_dist = 0.0
		return
	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touches[sd.index] = sd.position
		if _touches.size() >= 2:
			var pts: Array = _touches.values()
			var d: float = (pts[0] as Vector2).distance_to(pts[1])
			if _pinch_dist > 0.0 and d > 1.0:
				_zoom(_pinch_dist / d)
			_pinch_dist = d
		else:
			_orbit(sd.relative)
		return
	# Mouse (desktop).
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press_pos = mb.position
				_dragged = false
			elif not _dragged:
				# Prima prova il click preciso sulla pedina; altrimenti l'esagono.
				var pid := _pick_piece(mb.position)
				if pid == "" or not _try_direct_select(pid):
					var hx := _pick_hex(mb.position)
					if hx.x >= 0:
						Game.click_hex(hx.x, hx.y)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(0.9)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.0 / 0.9)
	elif event is InputEventMouseMotion \
			and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		if _touches.size() >= 2:
			return
		var mm := event as InputEventMouseMotion
		if mm.position.distance_to(_press_pos) > 5.0:
			_dragged = true
		_orbit(mm.relative)
