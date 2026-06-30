## Mappa 3D INTERATTIVA (vista alternativa, embeddabile in un SubViewport).
## Il tabellone reale è la SKIN su esagoni flat-top estrusi per elevazione. Il
## terreno (skin, fianchi, alberi/edifici/muri) è statico; un layer DINAMICO
## (pedine, obiettivi, evidenziazioni) viene rigenerato a ogni cambiamento di
## stato. Un clic su un esagono è tradotto in (q,r) e instradato a Game.click_hex,
## quindi carte/LOS/movimento/fuoco funzionano come nella 2D. Camera orbitabile.
extends Node3D

const ELEV_STEP := 0.55
const BASE_H := 0.25
const SKIRT_FRAC := 0.18  ## allargamento della base dei rilievi (pendio): più ripido ma morbido, senza invadere l'esagono sotto

# Modelli 3D reali (Kenney «City Builder», CC0) per i decori del terreno; se non
# disponibili si ripiega sulle mesh procedurali. Vedi assets/models3d/CREDITS.md.
const MODEL_HOUSES := [
	"res://assets/models3d/building-small-a.glb",
	"res://assets/models3d/building-small-b.glb",
	"res://assets/models3d/building-small-c.glb",
]
const MODEL_TREES := "res://assets/models3d/grass-trees.glb"
const MODEL_GRASS := "res://assets/models3d/grass.glb"
## Collezione di alberi low-poly (Low-Poly Tree Collection 01): 200 alberi
## variati in un solo FBX, da cui si estraggono le singole mesh per il bosco.
const MODEL_TREE_COLLECTION := "res://assets/models3d/tree_collection.fbx"
const TREE_HEIGHT := 1.45  ## altezza desiderata di un albero, in unità mondo
## Soldati 3D (Meshy): più figure per pedina (squadra 4, team 2, leader 1, arma 1).
## Le squadre/team alternano due pose per varietà; i leader usano l'ufficiale.
## Modelli dedicati per fazione (Asse tedesco, Sovietici); se quelli di una
## fazione mancano si ripiega sull'altra con tinta verde-oliva come segnaposto.
const MODEL_SOLDIERS_DE := [
	"res://assets/models3d/soldier_de.glb",
	"res://assets/models3d/soldier_de_a.glb",
]
const MODEL_OFFICER_DE := "res://assets/models3d/officer_de.glb"
const MODEL_SOLDIERS_RU := [
	"res://assets/models3d/soldier_ru.glb",
	"res://assets/models3d/soldier_ru_a.glb",
]
const MODEL_OFFICER_RU := "res://assets/models3d/officer_ru.glb"
const MODEL_SOLDIERS_US := [
	"res://assets/models3d/soldier_us.glb",
	"res://assets/models3d/soldier_us_a.glb",
]
const MODEL_OFFICER_US := "res://assets/models3d/officer_us.glb"
var _model_cache: Dictionary = {}  ## path → PackedScene (o null se assente)
var _tree_pool: Array = []  ## Mesh dei singoli alberi (cache, estratte una volta)
var _badge_cache: Dictionary = {}  ## chiave valori → ImageTexture del badge
var _badge_pending: Dictionary = {}  ## chiave → [Sprite3D] in attesa del render

var _world := 1.0 / 59.2
var _ox := 129.0
var _oy := 69.0
var _hx := 59.2

var _cam_yaw := 0.6
var _cam_pitch := 0.85
var _cam_dist := 30.0
var _center := Vector3.ZERO
var _home_center := Vector3.ZERO  ## inquadratura iniziale (reset col tasto «0»)
var _home_dist := 30.0

var _dynamic: Node3D
var _fx: Node3D            ## layer effetti transitori (tracer, flash); non azzerato dai refresh
var _los_layer: Node3D    ## layer dello strumento Modalità LOS (linea + estremità)
var _los_drag: int = -1   ## estremità LOS trascinata (0=A, 1=B, -1=nessuna)
var _last_unit_pos := {}   ## id unità → Vector2i(q,r) noto (per animare lo spostamento)
var _pending_slide := {}   ## id unità → Vector3 posizione mondo di partenza dello slittamento
var _unit_heading := {}    ## id unità → yaw (rad): direzione verso cui guardano le figure
var _pieces := []          ## [{id, node}] pedine correnti (per il click preciso sulle pile)
var _tip: PanelContainer   ## pannello informativo al passaggio del mouse
var _tip_label: RichTextLabel
var _hover_hex := Vector2i(-9999, -9999)
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
	_los_layer = Node3D.new()  ## strumento Modalità LOS (aggiornato a parte, drag fluido)
	add_child(_los_layer)
	_build_tooltip()
	_refresh_dynamic(s)
	_camera.current = true
	_update_camera()
	if not Game.state_changed.is_connected(_on_state_changed):
		Game.state_changed.connect(_on_state_changed)
	if not Game.unit_moved.is_connected(_on_unit_moved):
		Game.unit_moved.connect(_on_unit_moved)
	if not Game.fire_resolved.is_connected(_on_fire_resolved):
		Game.fire_resolved.connect(_on_fire_resolved)
	if not Game.unit_eliminated.is_connected(_on_unit_eliminated):
		Game.unit_eliminated.connect(_on_unit_eliminated)
	if not Game.grenade_thrown.is_connected(_on_grenade_thrown):
		Game.grenade_thrown.connect(_on_grenade_thrown)
	if not Game.artillery_impact.is_connected(_on_artillery_impact):
		Game.artillery_impact.connect(_on_artillery_impact)


func _on_state_changed() -> void:
	if Game.state != null and active:
		_refresh_dynamic(Game.state)


# ─── Pannello informativo (hover) ─────────────────────────────────────────────

func _build_tooltip() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_tip = PanelContainer.new()
	_tip.visible = false
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mc := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mc.add_theme_constant_override(side, 8)
	_tip.add_child(mc)
	_tip_label = RichTextLabel.new()
	_tip_label.bbcode_enabled = true
	_tip_label.fit_content = true
	_tip_label.scroll_active = false
	_tip_label.custom_minimum_size = Vector2(240, 0)
	_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_child(_tip_label)
	layer.add_child(_tip)


## Aggiorna il pannello informativo per l'esagono sotto il cursore.
func _update_tooltip(vpos: Vector2) -> void:
	if not active or Game.state == null or _tip == null:
		_hide_tooltip()
		return
	var hx := _pick_hex(vpos)
	if hx.x < 0:
		_hide_tooltip()
		return
	if hx != _hover_hex:
		_hover_hex = hx
		var fly := _fire_flyover_text(hx)
		_tip_label.text = fly if fly != "" else _hex_info_text(Game.state, hx.x, hx.y)
	_tip.visible = true
	_tip.reset_size()
	var vs := get_viewport().get_visible_rect().size
	var pos := vpos + Vector2(18.0, 14.0)
	pos.x = minf(pos.x, vs.x - _tip.size.x - 4.0)
	pos.y = minf(pos.y, vs.y - _tip.size.y - 4.0)
	_tip.position = pos


func _hide_tooltip() -> void:
	_hover_hex = Vector2i(-9999, -9999)
	if _tip != null:
		_tip.visible = false


## Flyover delle statistiche del Fuoco: passando col mouse su un bersaglio
## candidato durante l'assemblaggio (gruppo-prima-del-bersaglio), mostra FP
## d'attacco vs difesa stimata ed esito. "" fuori da quel contesto.
func _fire_flyover_text(hx: Vector2i) -> String:
	var s := Game.state
	if s == null or s.current_order != Domain.OrderType.FIRE:
		return ""
	if s.selected_unit_id == "" or s.fire_eligible_ids.is_empty() or s.fire_target_q >= 0:
		return ""
	if not s.highlighted_hexes.has("%d,%d" % [hx.x, hx.y]):
		return ""
	var pv := Game.fire_preview_at(hx.x, hx.y)
	if pv.is_empty():
		return ""
	var col := "#ffe066"
	match String(pv.get("verdict", "")):
		"favorevole":  col = "#6cff6c"
		"sfavorevole": col = "#ff7066"
	var txt := "[b]Fuoco su (%d,%d)[/b]" % [hx.x, hx.y]
	txt += "\n[color=#9fd]FP %d[/color]  vs  DIF %d" % [int(pv.get("fp", 0)), int(pv.get("defense", 0))]
	txt += "\ncopertura %d · difensori %d · tiratori %d" % [
		int(pv.get("cover", 0)), int(pv.get("defenders", 0)), int(pv.get("shooters", 0))]
	txt += "\n[color=%s]%s (margine %+d)[/color]" % [
		col, String(pv.get("verdict", "—")), int(pv.get("margin", 0))]
	txt += "\n[color=#aaa]clic per aprire il fuoco[/color]"
	return txt


## Testo informativo dell'esagono: terreno + copertura + marker + unità presenti.
func _hex_info_text(s: GameState, q: int, r: int) -> String:
	var txt := "[b]Esagono (%d,%d)[/b]" % [q, r]
	var hd: GameState.HexData = s.hex_at(q, r)
	if hd != null:
		var terr: String = Domain.TERRAIN_NAMES.get(hd.terrain, "?")
		var cov := Rules.cover_at(s, q, r, false)
		txt += "\n[color=#9fd]%s (cop. %d)[/color]" % [terr, cov]
		var feats: Array[String] = []
		if hd.elevation > 0:
			feats.append("quota %d" % hd.elevation)
		if hd.fortification != Domain.Fort.NONE:
			feats.append(Domain.FORT_NAMES.get(hd.fortification, "?"))
		if hd.has_foxhole: feats.append("buca")
		if hd.has_smoke: feats.append("fumo")
		if hd.has_blaze: feats.append("incendio")
		if hd.has_road: feats.append("strada")
		if feats.size() > 0:
			txt += "\n[color=#cc9]%s[/color]" % ", ".join(feats)
	for u in s.units_at(q, r):
		var fac: String = Domain.FACTION_SHORT.get(u.faction, "?")
		var st: Array[String] = []
		if not u.efficient: st.append("rotta")
		if u.suppressed: st.append("soppr.")
		if u.activated: st.append("att.")
		var stxt := "  [i]%s[/i]" % ", ".join(st) if st.size() > 0 else ""
		txt += "\n• %s (%s) PdF%d G%d M%d%s" % [u.unit_name, fac, u.fp, u.range, u.move, stxt]
	return txt


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
			# Direzione di marcia: le figure guarderanno verso il nuovo esagono.
			var nci := _hex_img(q, r)
			var dir := Vector2(nci.x - oci.x, nci.y - oci.y)
			if dir.length() > 0.001:
				_unit_heading[id] = atan2(dir.x, dir.y)


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
	_spawn_smoke_burst(from + Vector3(0, 0.05, 0), 3, 0.16, Color(0.78, 0.74, 0.6, 0.5))  # fumo alla bocca
	# Le unità appena rotte lampeggiano di rosso.
	for bid in result.broken:
		var bu := s.unit_by_id(bid)
		if bu != null:
			var bci := _hex_img(bu.q, bu.r)
			_spawn_flash(Vector3(bci.x * _world, _top_y(s, bu.q, bu.r) + 0.5, bci.y * _world),
				0.3, Color(1.0, 0.25, 0.2), 0.45)


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


## Sbuffo di fumo: alcune sferette grigie che salgono e svaniscono dalla posizione.
func _spawn_smoke_burst(pos: Vector3, n: int = 3, spread: float = 0.2,
		color: Color = Color(0.55, 0.55, 0.55, 0.6)) -> void:
	for i in n:
		var puff := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.1
		sph.height = 0.2
		puff.mesh = sph
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		puff.material_override = m
		var ang := float(i) * 2.4
		puff.position = pos + Vector3(cos(ang) * spread, 0.0, sin(ang) * spread)
		_fx.add_child(puff)
		var up := puff.position + Vector3(0.0, 0.5, 0.0)
		var tw := puff.create_tween()
		tw.set_parallel(true)
		tw.tween_property(puff, "position", up, 0.7)
		tw.tween_property(puff, "scale", Vector3(2.0, 2.0, 2.0), 0.7)
		tw.tween_property(m, "albedo_color:a", 0.0, 0.7)
		tw.chain().tween_callback(puff.queue_free)


## Esplosione: doppio lampo (fuoco) + sbuffo di fumo. `big` per artiglieria/granate.
func _explosion(pos: Vector3, big: bool = false) -> void:
	var r := 0.5 if big else 0.3
	_spawn_flash(pos, r, Color(1.0, 0.6, 0.2), 0.55 if big else 0.38)
	_spawn_flash(pos + Vector3(0.0, 0.12, 0.0), r * 0.6, Color(1.0, 0.92, 0.55), 0.24)
	_spawn_smoke_burst(pos + Vector3(0.0, 0.2, 0.0), 5 if big else 3,
		0.4 if big else 0.22, Color(0.3, 0.3, 0.3, 0.7))


## Esplosione ritardata (per l'onda d'urto sui 7 esagoni dell'artiglieria).
func _explosion_delayed(pos: Vector3, delay: float, big: bool = false) -> void:
	var t := get_tree().create_timer(delay)
	t.timeout.connect(func() -> void: _explosion(pos, big))


## Stacca la pedina dell'unità `id` dal layer dinamico (così sopravvive al refresh)
## e la restituisce; null se non c'è. La toglie anche dalla lista dei click.
func _detach_piece(id: String) -> Node3D:
	for i in range(_pieces.size() - 1, -1, -1):
		if _pieces[i]["id"] == id:
			var node: Node3D = _pieces[i]["node"]
			_pieces.remove_at(i)
			if is_instance_valid(node):
				node.reparent(_fx)  # fuori da _dynamic: non viene liberata dal rebuild
				return node
			return null
	return null


## Posizione lungo un arco parabolico da `from` a `to` con apice `height` (t in 0..1).
func _arc_pos(from: Vector3, to: Vector3, height: float, t: float) -> Vector3:
	var p := from.lerp(to, t)
	p.y += sin(t * PI) * height
	return p


## Setter per il tween dello slittamento con dondolio (camminata). `t` interpolato
## 0→1; gli altri argomenti sono passati con Callable.bind.
func _slide_step(t: float, node: Node3D, start: Vector3, base: Vector3) -> void:
	if is_instance_valid(node):
		node.position = start.lerp(base, t) + Vector3(0.0, sin(t * PI * 2.0) * 0.06, 0.0)


## Setter per il tween dell'arco della granata.
func _arc_step(t: float, node: Node3D, from: Vector3, to: Vector3, height: float) -> void:
	if is_instance_valid(node):
		node.position = _arc_pos(from, to, height, t)


## La granata atterra: esplode e si rimuove.
func _grenade_land(node: Node3D, at: Vector3) -> void:
	_explosion(at, true)
	if is_instance_valid(node):
		node.queue_free()


## Unità eliminata: la pedina sprofonda e svanisce, con un'esplosione.
func _on_unit_eliminated(id: String) -> void:
	if not active:
		return
	var pn := _detach_piece(id)
	if pn != null and is_instance_valid(pn):
		_explosion(pn.position + Vector3(0.0, 0.3, 0.0))
		var down := pn.position - Vector3(0.0, 1.3, 0.0)
		var tw := pn.create_tween()
		tw.set_parallel(true)
		tw.tween_property(pn, "position", down, 0.6)
		tw.tween_property(pn, "scale", Vector3(0.1, 0.1, 0.1), 0.6)
		tw.chain().tween_callback(pn.queue_free)
	elif _last_unit_pos.has(id) and Game.state != null:
		var p: Vector2i = _last_unit_pos[id]
		var ci := _hex_img(p.x, p.y)
		_explosion(Vector3(ci.x * _world, _top_y(Game.state, p.x, p.y) + 0.4, ci.y * _world))
	_last_unit_pos.erase(id)


## Bombe a mano: una granata arcua dal lanciatore al bersaglio, poi esplode.
func _on_grenade_thrown(fq: int, fr: int, tq: int, tr: int) -> void:
	if not active or Game.state == null:
		return
	var s := Game.state
	var fci := _hex_img(fq, fr)
	var tci := _hex_img(tq, tr)
	var from := Vector3(fci.x * _world, _top_y(s, fq, fr) + 0.8, fci.y * _world)
	var to := Vector3(tci.x * _world, _top_y(s, tq, tr) + 0.35, tci.y * _world)
	var g := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.09
	sph.height = 0.18
	g.mesh = sph
	g.material_override = _mat(Color(0.16, 0.19, 0.14))
	g.position = from
	_fx.add_child(g)
	var tw := g.create_tween()
	tw.tween_method(_arc_step.bind(g, from, to, 1.4), 0.0, 1.0, 0.55)
	tw.tween_callback(_grenade_land.bind(g, to))


## Artiglieria caduta: esplosione grande sul centro + onda sui 6 adiacenti.
func _on_artillery_impact(q: int, r: int) -> void:
	if not active or Game.state == null:
		return
	var s := Game.state
	var ci := _hex_img(q, r)
	_explosion(Vector3(ci.x * _world, _top_y(s, q, r) + 0.4, ci.y * _world), true)
	for nb in HexGrid.neighbors(q, r):
		if nb.x < 0 or nb.x >= s.map_cols or nb.y < 0 or nb.y >= s.map_rows:
			continue
		var nci := _hex_img(nb.x, nb.y)
		_explosion_delayed(Vector3(nci.x * _world, _top_y(s, nb.x, nb.y) + 0.3, nci.y * _world), 0.12, false)


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
	_draw_los_3d(s)


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
			# Fianchi del rilievo INCLINATI: la base (a BASE_H) è un po' più larga
			# della cima, così l'elevazione sembra una collina e non un gradino
			# verticale. L'allargamento cresce con radice dell'elevazione (non
			# lineare): i rilievi alti restano ripidi e il piede del pendio non
			# arriva a coprire l'esagono sottostante.
			var skirt := _hx * SKIRT_FRAC * sqrt(float(hd.elevation))
			var base_w: Array[Vector3] = []
			for i in range(6):
				var a := deg_to_rad(60.0 * i)
				var cb := cimg + (_hx + skirt) * Vector2(cos(a), sin(a))
				base_w.append(Vector3(cb.x * _world, BASE_H, cb.y * _world))
			for i in range(6):
				var j := (i + 1) % 6
				var tA := corners_w[i]
				var tB := corners_w[j]
				var bA := base_w[i]
				var bB := base_w[j]
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
	# "Casa" della camera (per il reinquadramento col tasto «0»).
	_home_center = _center
	_home_dist = _cam_dist


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
	# Durante una Mossa il colore dell'esagono indica il COSTO in PM (verde=poco →
	# rosso=tanto) con una targhetta col numero; l'alone arancio tenue mostra il
	# raggio di Comando del leader del gruppo. Gli altri ordini restano gialli.
	var cost_map := _move_cost_map(s)
	_add_command_aura(s, cost_map)
	for key in s.highlighted_hexes:
		var p := String(key).split(",")
		var hq := int(p[0])
		var hr := int(p[1])
		if cost_map.has(key):
			var c := int(cost_map[key])
			_hex_disc(hq, hr, s, _cost_disc(c))
			var ci := _hex_img(hq, hr)
			_badge(Vector3(ci.x * _world, _top_y(s, hq, hr) + 0.45, ci.y * _world),
				"%d" % c, Color(1.0, 1.0, 1.0, 0.97))
		else:
			_hex_disc(hq, hr, s, Color(1.0, 0.95, 0.2, 0.5))
	# Gruppo di comando attivato dall'ordine del leader (arancio).
	for gid in s.ordered_group:
		if gid == s.selected_unit_id:
			continue
		var gv := s.unit_by_id(gid)
		if gv != null:
			_hex_disc(gv.q, gv.r, s, Color(1.0, 0.55, 0.0, 0.35))
	# Anteprima del gruppo di comando (selezione di un leader prima dell'ordine).
	if s.ordered_group.is_empty():
		for pid in s.command_preview_ids:
			if pid == s.selected_unit_id:
				continue
			var pv := s.unit_by_id(pid)
			if pv != null:
				_hex_disc(pv.q, pv.r, s, Color(1.0, 0.55, 0.0, 0.35))
	# Fuoco PRIMA del bersaglio (gruppo-prima): pezzi inclusi (arancio) / esclusi
	# (grigio) e linee di mira da ogni tiratore verso OGNI bersaglio candidato.
	var fire_assembling: bool = s.current_order == Domain.OrderType.FIRE \
		and s.selected_unit_id != "" and not s.fire_eligible_ids.is_empty() and s.fire_target_q < 0
	if fire_assembling:
		for eid in s.fire_eligible_ids:
			if eid == s.selected_unit_id:
				continue
			var ev := s.unit_by_id(eid)
			if ev == null:
				continue
			var inc: bool = s.fire_group_ids.has(eid)
			_hex_disc(ev.q, ev.r, s,
				Color(1.0, 0.55, 0.0, 0.45) if inc else Color(0.6, 0.6, 0.6, 0.35))
		for key in s.highlighted_hexes:
			var pp := String(key).split(",")
			var tqh := int(pp[0])
			var trh := int(pp[1])
			for gid in s.fire_group_ids:
				var gu := s.unit_by_id(gid)
				if gu != null and Combat.can_fire(gu, tqh, trh, s):
					_los_line(gu.q, gu.r, tqh, trh, s, Color(0.95, 0.25, 0.2, 0.45))
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
		# Linee di mira dai pezzi che sparano verso il bersaglio (chi spara a chi).
		for gid in s.fire_group_ids:
			var gu := s.unit_by_id(gid)
			if gu != null and not (gu.q == s.fire_target_q and gu.r == s.fire_target_r):
				_los_line(gu.q, gu.r, s.fire_target_q, s.fire_target_r, s, Color(0.95, 0.2, 0.15, 0.85))
		# Targhetta di anteprima sopra il bersaglio: FP vs DIF stimata + esito.
		_add_fire_readout(s)
	# Finestra di reazione (Fuoco di Opportunità): mover rosso, tiratori gialli.
	if s.phase == Domain.Phase.REACTION_WINDOW:
		var mv := s.unit_by_id(s.opfire_mover_id)
		if mv != null:
			_hex_disc(mv.q, mv.r, s, Color(0.95, 0.15, 0.15, 0.5))
		for sid in s.opfire_shooter_ids:
			var sv := s.unit_by_id(sid)
			if sv != null:
				_hex_disc(sv.q, sv.r, s, Color(1.0, 0.7, 0.1, 0.45))
		# Finestra di Mimetizzazione: unità su cui puoi giocare la carta (ciano).
		for cid in s.conceal_offer_ids:
			var cv := s.unit_by_id(cid)
			if cv != null:
				_hex_disc(cv.q, cv.r, s, Color(0.1, 0.85, 1.0, 0.5))
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


## Mappa "q,r" → costo in PM, valida solo durante una Mossa con un mover scelto.
func _move_cost_map(s: GameState) -> Dictionary:
	if s.phase != Domain.Phase.PLAYER_MOVING or s.current_order != Domain.OrderType.MOVE:
		return {}
	if s.selected_unit_id == "":
		return {}
	var u := s.unit_by_id(s.selected_unit_id)
	if u == null:
		return {}
	return HexGrid.reachable_costs(u, s, int(s.group_mp.get(u.id, u.move)))


## Colore del disco in base al costo in PM: verde (1) → rosso (4+).
func _cost_disc(cost: int) -> Color:
	match cost:
		1:  return Color(0.30, 0.85, 0.30, 0.50)
		2:  return Color(0.85, 0.85, 0.25, 0.50)
		3:  return Color(0.95, 0.60, 0.15, 0.55)
		_:  return Color(0.95, 0.25, 0.20, 0.55)


## Alone tenue del raggio di Comando del leader del gruppo di Mossa, disegnato
## solo sugli esagoni NON raggiungibili (quelli raggiungibili hanno già il disco
## di costo) per evitare sovrapposizioni e z-fighting.
func _add_command_aura(s: GameState, cost_map: Dictionary) -> void:
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
			if q == leader.q and r == leader.r:
				continue
			if cost_map.has("%d,%d" % [q, r]):
				continue
			if HexGrid.distance(leader.q, leader.r, q, r) <= leader.command:
				_hex_disc(q, r, s, Color(1.0, 0.55, 0.0, 0.10))


## Targhetta di anteprima del fuoco sopra il bersaglio: FP attacco · DIF stimata
## · esito atteso (verde=favorevole, giallo=incerto, rosso=sfavorevole).
func _add_fire_readout(s: GameState) -> void:
	var pv := Game.fire_preview()
	if pv.is_empty():
		return
	var txt := "FP %d" % int(pv.get("fp", 0))
	var col := Color(1.0, 0.95, 0.5)
	if int(pv.get("defense", -1)) >= 0:
		txt += " vs DIF %d -> %s" % [int(pv["defense"]), pv.get("verdict", "")]
		match String(pv.get("verdict", "")):
			"favorevole":  col = Color(0.4, 1.0, 0.4)
			"sfavorevole": col = Color(1.0, 0.45, 0.4)
			_:             col = Color(1.0, 0.9, 0.4)
	var ci := _hex_img(s.fire_target_q, s.fire_target_r)
	var pos := Vector3(ci.x * _world, _top_y(s, s.fire_target_q, s.fire_target_r) + 1.2, ci.y * _world)
	_badge(pos, txt, col)


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


func _los_line(q1: int, r1: int, q2: int, r2: int, s: GameState, col: Color,
		parent: Node3D = null, radius: float = 0.025) -> void:
	if parent == null:
		parent = _dynamic
	var c1 := _hex_img(q1, r1)
	var c2 := _hex_img(q2, r2)
	var from := Vector3(c1.x * _world, _top_y(s, q1, r1) + 0.55, c1.y * _world)
	var to := Vector3(c2.x * _world, _top_y(s, q2, r2) + 0.55, c2.y * _world)
	var ln := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = from.distance_to(to)
	cyl.radial_segments = 6
	ln.mesh = cyl
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ln.material_override = m
	ln.transform = _aim_y((from + to) * 0.5, (to - from))
	parent.add_child(ln)


## Strumento Modalità LOS in 3D: linea colorata tra le due estremità tenendo
## conto dell'ALTEZZA degli esagoni (via _top_y), con i marcatori A/B e l'esito.
## Disegnato in _los_layer (aggiornabile da solo per un trascinamento fluido).
func _draw_los_3d(s: GameState) -> void:
	if _los_layer == null:
		return
	for c in _los_layer.get_children():
		c.queue_free()
	if not s.los_mode or s.los_a.x < 0 or s.los_b.x < 0:
		return
	var kind := HexGrid.los_kind(s.los_a.x, s.los_a.y, s.los_b.x, s.los_b.y, s)
	var col := _los_color_3d(kind)
	_los_line(s.los_a.x, s.los_a.y, s.los_b.x, s.los_b.y, s, col, _los_layer, 0.06)
	for i in 2:
		var q := s.los_a.x if i == 0 else s.los_b.x
		var r := s.los_a.y if i == 0 else s.los_b.y
		var ci := _hex_img(q, r)
		var top := Vector3(ci.x * _world, _top_y(s, q, r) + 0.55, ci.y * _world)
		var mk := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.16
		sph.height = 0.32
		mk.mesh = sph
		mk.material_override = _mat(col)
		mk.position = top
		_los_layer.add_child(mk)
		_los_badge(top + Vector3(0, 0.45, 0), "A" if i == 0 else "B", Color.WHITE)
	# Etichetta dell'esito a metà linea.
	var ca := _hex_img(s.los_a.x, s.los_a.y)
	var cb := _hex_img(s.los_b.x, s.los_b.y)
	var mid := Vector3((ca.x + cb.x) * 0.5 * _world,
		(_top_y(s, s.los_a.x, s.los_a.y) + _top_y(s, s.los_b.x, s.los_b.y)) * 0.5 + 1.1,
		(ca.y + cb.y) * 0.5 * _world)
	_los_badge(mid, _los_label_3d(s, kind), col)


## Targhetta (Label3D) nel layer LOS, indipendente da _dynamic.
func _los_badge(pos: Vector3, txt: String, col: Color) -> void:
	var lbl := Label3D.new()
	lbl.text = txt
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 56
	lbl.pixel_size = 0.012
	lbl.modulate = col
	lbl.outline_size = 16
	lbl.outline_modulate = Color(0.05, 0.05, 0.05, 0.95)
	lbl.no_depth_test = true
	lbl.position = pos
	_los_layer.add_child(lbl)


func _los_color_3d(kind: int) -> Color:
	match kind:
		HexGrid.LOS_CLEAR:    return Color(0.30, 1.0, 0.35, 0.95)
		HexGrid.LOS_HINDERED: return Color(1.0, 0.85, 0.2, 0.95)
		_:                    return Color(1.0, 0.25, 0.2, 0.95)


func _los_label_3d(s: GameState, kind: int) -> String:
	match kind:
		HexGrid.LOS_CLEAR:
			return "LOS LIBERA"
		HexGrid.LOS_HINDERED:
			return "LOS OSTACOLATA (-%d)" % HexGrid.los_hindrance(s.los_a.x, s.los_a.y, s.los_b.x, s.los_b.y, s)
		_:
			return "LOS BLOCCATA"


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
			var off := Vector3(0.26 * i - 0.18, 0.0, -0.26 * i + 0.18)
			# La selezione si indica colorando il fondo del badge (vedi _attach_badge),
			# non sollevando la pedina: meno invasivo e più chiaro.
			var base := Vector3(ci.x * _world, top_y, ci.y * _world) + off
			_last_unit_pos[u.id] = Vector2i(u.q, u.r)
			# Figure 3D dei soldati (tante quante le "soldier icons": squadra 4,
			# team 2, leader/arma 1) con segnalino sopra. Ripiego al segnalino
			# billboard se il modello non è disponibile.
			var holder := _spawn_unit_figures(u, sel)
			if holder != null:
				if _pending_slide.has(u.id):
					var start: Vector3 = _pending_slide[u.id]
					holder.position = start
					var tw := holder.create_tween()
					tw.tween_method(_slide_step.bind(holder, start, base), 0.0, 1.0, 0.32)
					_pending_slide.erase(u.id)
				else:
					holder.position = base
				_pieces.append({ "id": u.id, "node": holder })
				continue
			# ── Ripiego (modello assente): cilindro colorato + badge sopra ──
			var holder2 := Node3D.new()
			_dynamic.add_child(holder2)
			var pm := MeshInstance3D.new()
			var pc := CylinderMesh.new()
			pc.top_radius = 0.3; pc.bottom_radius = 0.3; pc.height = 0.6
			pc.radial_segments = 16
			pm.mesh = pc
			pm.material_override = _mat(Color(0.66, 0.58, 0.30) \
				if u.faction == Domain.Faction.GERMAN else Color(0.28, 0.5, 0.28))
			pm.position = Vector3(0.0, 0.3, 0.0)
			holder2.add_child(pm)
			_attach_badge(holder2, u, 1.1, sel)
			if _pending_slide.has(u.id):
				var start2: Vector3 = _pending_slide[u.id]
				holder2.position = start2
				var tw := holder2.create_tween()
				tw.tween_method(_slide_step.bind(holder2, start2, base), 0.0, 1.0, 0.32)
				_pending_slide.erase(u.id)
			else:
				holder2.position = base
			_pieces.append({ "id": u.id, "node": holder2 })


## Costruisce le figure 3D dei soldati per la pedina: tante quante le "soldier
## icons" dell'unità (squadra 4, team 2, leader 1, arma 1), disposte in formazione
## dentro l'esagono, con sopra il segnalino di gioco (identità/valori). L'Asse usa
## il modello com'è; gli Alleati una tinta verde-oliva come SEGNAPOSTO (in attesa
## di un modello dedicato). L'intero gruppo è ruotato nella direzione di marcia
## (o verso il fronte amico se l'unità non si è ancora mossa). Restituisce il
## holder, oppure null se il modello non è disponibile (→ ripiego al segnalino).
func _spawn_unit_figures(u: Unit, sel: bool) -> Node3D:
	var holder := Node3D.new()
	_dynamic.add_child(holder)
	# Le armi mostrano il loro modello (MG, mortaio, cannone) invece dei soldati.
	if u.is_weapon():
		var wh := _spawn_weapon(holder, u)
		if wh >= 0.0:
			holder.rotation.y = _unit_yaw(u)
			_attach_badge(holder, u, wh + 0.4, sel)
			return holder
	var count := maxi(1, u.soldier_icons())   # squadra 4, team 2, leader 1, arma → 1
	var target_h := 0.90  # uguale per tutte: la selezione è nel fondo del badge
	var offs := _figure_offsets(count)
	var placed := 0
	for fi in count:
		var pick := _figure_model(u, fi)
		var scene: PackedScene = pick["scene"]
		if scene == null:
			continue
		var fig := scene.instantiate()
		var ab := _merged_aabb(fig, Transform3D.IDENTITY)
		if ab.size == Vector3.ZERO:
			fig.queue_free()
			continue
		# Coerenza fra pose: i modelli sono tutti normalizzati alla stessa altezza
		# dal generatore, ma una posa accucciata/in fuoco (più larga/profonda che
		# alta) deve risultare più bassa di una in piedi. Riduco l'altezza in base
		# all'ingombro orizzontale rispetto a quello verticale.
		var pose := 1.0
		if ab.size.y > 0.001:
			var horiz := maxf(ab.size.x, ab.size.z)
			pose = clampf(1.0 - maxf(0.0, horiz / ab.size.y - 0.9) * 0.6, 0.78, 1.0)
		var sc := (target_h * pose) / ab.size.y if ab.size.y > 0.001 else 1.0
		var inner := Node3D.new()
		inner.scale = Vector3(sc, sc, sc)
		# Lieve sfasamento d'orientamento per non sembrare cloni perfetti.
		inner.rotation.y = _fig_jitter(u.id, fi)
		inner.position = offs[fi]
		holder.add_child(inner)
		fig.position = Vector3(
			-(ab.position.x + ab.size.x * 0.5),
			-ab.position.y,
			-(ab.position.z + ab.size.z * 0.5))
		inner.add_child(fig)
		# Tinta segnaposto solo se è stato usato il modello dell'altra fazione
		# (es. Sovietico mancante → modello tedesco verniciato di verde-oliva).
		if pick["foreign"]:
			_tint_soldier(fig, Color(0.62, 0.72, 0.45))
		placed += 1
	if placed == 0:
		holder.queue_free()
		return null
	# Orientamento del gruppo: direzione di marcia, o fronte amico di default.
	holder.rotation.y = _unit_yaw(u)
	# Badge numerico sopra la formazione (billboard): non ruota col gruppo perché
	# è sull'asse di rotazione e si orienta da solo verso la camera.
	_attach_badge(holder, u, target_h + 0.5, sel)
	return holder


## Posizioni locali (XZ) delle figure dentro la pedina, in formazione compatta
## rivolta verso il davanti locale (+Z). Fino a 4 figure (squadra).
func _figure_offsets(count: int) -> Array:
	const D := 0.20
	match count:
		1:
			return [Vector3.ZERO]
		2:
			return [Vector3(-D, 0.0, 0.0), Vector3(D, 0.0, 0.0)]
		3:
			return [Vector3(-D, 0.0, -D * 0.6), Vector3(D, 0.0, -D * 0.6),
				Vector3(0.0, 0.0, D * 0.9)]
		_:
			return [Vector3(-D, 0.0, -D), Vector3(D, 0.0, -D),
				Vector3(-D, 0.0, D), Vector3(D, 0.0, D)]


## Nazionalità dell'unità ai fini del modello 3D: dalla `nation_art` (Tedeschi /
## Russi / Americani); se assente, ripiego per fazione (Asse → Tedeschi).
func _unit_nation(u: Unit) -> String:
	match u.nation_art:
		"Tedeschi", "Russi", "Americani":
			return u.nation_art
		_:
			return "Tedeschi" if u.faction == Domain.Faction.GERMAN else "Russi"


func _pool_soldiers(nation: String) -> Array:
	match nation:
		"Russi":
			return MODEL_SOLDIERS_RU
		"Americani":
			return MODEL_SOLDIERS_US
		_:
			return MODEL_SOLDIERS_DE


func _pool_officer(nation: String) -> String:
	match nation:
		"Russi":
			return MODEL_OFFICER_RU
		"Americani":
			return MODEL_OFFICER_US
		_:
			return MODEL_OFFICER_DE


## Modello per la figura `fi` dell'unità, per nazionalità: l'ufficiale per i
## leader, altrimenti pose di soldato alternate per varietà. Se la nazione non ha
## il modello, ripiega su quello di un'altra nazione (segnalato da `foreign`, così
## il chiamante lo tinge come segnaposto). Restituisce { scene, foreign }.
func _figure_model(u: Unit, fi: int) -> Dictionary:
	var own := _unit_nation(u)
	var order: Array = [own]
	for nat in ["Tedeschi", "Russi", "Americani"]:
		if nat != own:
			order.append(nat)
	for idx in order.size():
		var nation: String = order[idx]
		var foreign := idx > 0
		if u.is_leader():
			var off := _model(_pool_officer(nation))
			if off != null:
				return { "scene": off, "foreign": foreign }
		var pool := _pool_soldiers(nation)
		for k in pool.size():
			var s := _model(pool[(fi + k) % pool.size()])
			if s != null:
				return { "scene": s, "foreign": foreign }
	return { "scene": null, "foreign": false }


## Posa il modello 3D dell'arma (MG/mortaio/cannone) dentro `holder`, scalato e
## appoggiato a terra. Restituisce l'altezza scalata (per piazzare il badge),
## oppure -1 se non c'è un modello adatto (→ ripiego ai soldati). Le armi si
## scalano sulla DIMENSIONE MASSIMA (sono basse e larghe: scalarle sull'altezza
## le rendeva enormi in larghezza) e restano più piccole dei soldati.
func _spawn_weapon(holder: Node3D, u: Unit) -> float:
	var path := _weapon_model_path(_unit_nation(u), _weapon_kind(u))
	if path == "":
		return -1.0
	var scene := _model(path)
	if scene == null:
		return -1.0
	var fig := scene.instantiate()
	var ab := _merged_aabb(fig, Transform3D.IDENTITY)
	if ab.size == Vector3.ZERO:
		fig.queue_free()
		return -1.0
	const WEAPON_SPAN := 0.46  # ingombro massimo dell'arma (ben < soldato ~0.9)
	var maxd := maxf(ab.size.x, maxf(ab.size.y, ab.size.z))
	var sc := WEAPON_SPAN / maxd if maxd > 0.001 else 1.0
	var inner := Node3D.new()
	inner.scale = Vector3(sc, sc, sc)
	holder.add_child(inner)
	fig.position = Vector3(
		-(ab.position.x + ab.size.x * 0.5),
		-ab.position.y,
		-(ab.position.z + ab.size.z * 0.5))
	inner.add_child(fig)
	return sc * ab.size.y


## "Tipo" dell'arma ai fini del modello: mortaio / cannone (dalla classe), oppure
## il sottotipo di mitragliatrice dal nome (.50 / pesante / media / leggera).
func _weapon_kind(u: Unit) -> String:
	if u.unit_class == Domain.UnitClass.MORTAR:
		return "mortar"
	if u.unit_class == Domain.UnitClass.AT:
		return "gun"
	var n := u.unit_name.to_lower()
	if n.contains(".50") or n.contains("50cal"):
		return "fifty_mg"
	if n.contains("heavy"):
		return "heavy_mg"
	if n.contains("medium"):
		return "medium_mg"
	return "light_mg"


## Percorso del modello arma per nazione+tipo, con catena di ripieghi (così i tipi
## senza modello dedicato usano l'arma più simile della stessa nazione).
func _weapon_model_path(nation: String, kind: String) -> String:
	var tag := "de"
	match nation:
		"Russi":
			tag = "ru"
		"Americani":
			tag = "us"
	for k in _weapon_fallbacks(kind):
		var p := "res://assets/models3d/wpn_%s_%s.glb" % [tag, k]
		if _model(p) != null:
			return p
	return ""


func _weapon_fallbacks(kind: String) -> Array:
	match kind:
		"mortar":
			return ["mortar"]
		"gun":
			return ["gun"]
		"fifty_mg":
			return ["fifty_mg", "heavy_mg", "medium_mg", "light_mg"]
		"heavy_mg":
			return ["heavy_mg", "medium_mg", "fifty_mg", "light_mg"]
		"medium_mg":
			return ["medium_mg", "heavy_mg", "light_mg"]
		_:
			return ["light_mg", "medium_mg", "heavy_mg"]


## Yaw della pedina: direzione di marcia memorizzata, altrimenti fronte di fazione
## (Asse a 0, Alleati a 180°) come orientamento di riposo.
func _unit_yaw(u: Unit) -> float:
	if _unit_heading.has(u.id):
		return _unit_heading[u.id]
	return PI if u.faction == Domain.Faction.RUSSIAN else 0.0


## Piccola variazione deterministica dell'orientamento di una figura (±~12°),
## così le 4 figure di una squadra non sembrano copie identiche.
func _fig_jitter(id: String, fi: int) -> float:
	var a := float(hash(id) % 97) + float(fi * 31)
	return sin(a) * 0.22


## Tinta (moltiplicativa, preservando la texture) su tutte le mesh della figura.
func _tint_soldier(node: Node, tint: Color) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		var src := mi.mesh.surface_get_material(0)
		var m: StandardMaterial3D
		if src is StandardMaterial3D:
			m = (src as StandardMaterial3D).duplicate()
		else:
			m = StandardMaterial3D.new()
		m.albedo_color = tint
		mi.material_override = m
	for c in node.get_children():
		_tint_soldier(c, tint)


# ─── Badge numerico sopra la pedina 3D ───────────────────────────────────────
# Il badge è una piccola UI (PanelContainer con angoli stondati + Label con font
# vero) renderizzata in un SubViewport 2D in una texture, messa in cache per
# insieme di valori. Il render richiede un frame, quindi si attacca in modo
# asincrono: la figura compare subito, il badge un istante dopo. In esecuzione
# senza GPU (test headless) la texture resta vuota: la pedina si vede comunque.

## Crea il segnaposto del badge (Sprite3D billboard) sopra `holder` a quota `y` e
## ne popola la texture (dalla cache o renderizzandola in modo asincrono).
func _attach_badge(holder: Node3D, u: Unit, y: float, sel: bool) -> void:
	var tokens := _badge_tokens(u)
	if tokens.is_empty():
		return
	var sp := Sprite3D.new()
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false
	sp.position = Vector3(0.0, y, 0.0)
	sp.modulate = Color(1, 1, 1, 1)
	holder.add_child(sp)
	var key := _badge_key(u, tokens, sel)
	if _badge_cache.has(key):
		_apply_badge(sp, _badge_cache[key])
	else:
		_render_badge(sp, u, tokens, key, sel)


## Imposta texture e scala del badge sullo Sprite3D, in base all'altezza texture.
func _apply_badge(sp: Sprite3D, tex: Texture2D) -> void:
	if not is_instance_valid(sp) or tex == null:
		return
	sp.texture = tex
	sp.pixel_size = 0.30 / float(maxi(1, tex.get_height()))


## Renderizza il badge in un SubViewport 2D, lo mette in cache e lo applica a tutti
## gli sprite in attesa della stessa chiave (dedup tra pedine identiche).
func _render_badge(sp: Sprite3D, u: Unit, tokens: Array, key: String, sel: bool) -> void:
	if _badge_pending.has(key):
		_badge_pending[key].append(sp)
		return
	_badge_pending[key] = [sp]

	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.size = Vector2i(8, 8)
	add_child(vp)
	var panel := _build_badge_control(u, tokens, sel)
	vp.add_child(panel)
	await get_tree().process_frame
	var ms := panel.get_combined_minimum_size()
	vp.size = Vector2i(maxi(8, ceili(ms.x)), maxi(8, ceili(ms.y)))
	panel.size = ms
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var tex: ImageTexture = null
	var img := vp.get_texture().get_image()
	if img != null and not img.is_empty():
		tex = ImageTexture.create_from_image(img)
		_badge_cache[key] = tex
	vp.queue_free()

	for s in _badge_pending[key]:
		_apply_badge(s, tex)
	_badge_pending.erase(key)


## Costruisce la UI del badge: pannello con angoli stondati e una riga di valori;
## i token "in box" hanno un riquadro stondato del loro colore. Il fondo indica lo
## stato: azzurro acceso se SELEZIONATA, rosso se rotta, altrimenti scuro neutro;
## il bordo è azzurro se selezionata, sennò tinto per fazione.
func _build_badge_control(u: Unit, tokens: Array, sel: bool) -> Control:
	var border := Color(0.40, 0.85, 1.0) if sel \
		else (Color(0.66, 0.70, 0.58) if u.faction == Domain.Faction.GERMAN \
		else Color(0.78, 0.60, 0.42))
	var bg := Color(0.42, 0.10, 0.10, 0.92) if not u.efficient \
		else (Color(0.10, 0.34, 0.52, 0.94) if sel else Color(0.10, 0.11, 0.13, 0.90))
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(3 if sel else 2)
	sb.border_color = border
	sb.content_margin_left = 8; sb.content_margin_right = 8
	sb.content_margin_top = 3; sb.content_margin_bottom = 3
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	panel.add_child(hb)
	for tok in tokens:
		var lbl := Label.new()
		lbl.text = tok["text"]
		lbl.add_theme_font_size_override("font_size", 30)
		lbl.add_theme_color_override("font_color", tok["color"])
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		lbl.add_theme_constant_override("outline_size", 5)
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if tok["box"]:
			var bsb := StyleBoxFlat.new()
			bsb.bg_color = Color(0, 0, 0, 0)
			bsb.set_corner_radius_all(6)
			bsb.set_border_width_all(2)
			bsb.border_color = tok["color"]
			bsb.content_margin_left = 5; bsb.content_margin_right = 5
			var bp := PanelContainer.new()
			bp.add_theme_stylebox_override("panel", bsb)
			bp.add_child(lbl)
			hb.add_child(bp)
		else:
			hb.add_child(lbl)
	return panel


## Token (testo/colore/box) del badge, in ordine di lettura, secondo il tipo.
func _badge_tokens(u: Unit) -> Array:
	const WHITE := Color(0.97, 0.97, 0.93)
	const GOLD := Color(1.0, 0.84, 0.32)
	const BLUE := Color(0.58, 0.82, 1.0)
	const YELL := Color(0.98, 0.88, 0.45)
	var out := []
	if u.is_leader():
		out.append({ "text": "%+d" % u.command, "color": GOLD, "box": true })   # Comando
		out.append({ "text": str(u.morale), "color": BLUE, "box": true })       # Morale
		out.append({ "text": str(u.move), "color": YELL, "box": false })        # Movimento
	elif u.is_weapon():
		out.append({ "text": str(u.fp), "color": WHITE, "box": u.fp_boxed })
		out.append({ "text": str(u.range), "color": WHITE, "box": u.range_boxed })
		if u.move_penalty > 0:
			out.append({ "text": "-%d" % u.move_penalty, "color": YELL, "box": false })
	else:  # squadra / team
		out.append({ "text": str(u.fp), "color": WHITE, "box": u.fp_boxed })
		out.append({ "text": str(u.range), "color": WHITE, "box": u.range_boxed })
		out.append({ "text": str(u.move), "color": YELL, "box": false })
		out.append({ "text": str(u.morale), "color": BLUE, "box": true })
	return out


func _badge_key(u: Unit, tokens: Array, sel: bool) -> String:
	var parts := PackedStringArray()
	for t in tokens:
		parts.append("%s/%s/%d" % [t["text"], t["color"].to_html(), 1 if t["box"] else 0])
	return "%d|%d|%d|%s" % [u.faction, 1 if u.efficient else 0, 1 if sel else 0, "|".join(parts)]


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
	var fort_letters := { 1: "T", 2: "C", 3: "B", 4: "#", 5: "*" }
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
	# Armi a terra (senza portatore, 11.3): disco giallo = raccoglibili con «G».
	for u in s.units.values():
		if u.is_weapon() and u.carrier_id == "":
			_ground_disc(u.q, u.r, s, 0.5, Color(1.0, 0.85, 0.2, 0.45))


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

## Decorazioni 3D del terreno (alberi, edifici, macerie) DISATTIVATE su richiesta:
## i vecchi modelli non piacevano e ne arriveranno di nuovi. Per ora gli esagoni
## restano "puliti" — il tipo di terreno resta leggibile dalla skin del tabellone.
## (Le funzioni di supporto sotto sono inutilizzate, in attesa dei nuovi asset.)
func _decorate(_hd: GameState.HexData, _q: int, _r: int, _top: Vector3) -> void:
	return


## Pool di alberi della collezione FBX, estratti UNA volta. Per ogni albero si
## conserva la mesh E la base (rotazione/scala globale nella collezione): l'FBX è
## Z-up e il nodo lo raddrizza, quindi senza quella base la mesh resterebbe
## coricata. Tiene gli alberi più alti (in piedi), scartando i cespugli minuti.
func _trees() -> Array:
	if not _tree_pool.is_empty():
		return _tree_pool
	var ps := _model(MODEL_TREE_COLLECTION)
	if ps == null:
		return _tree_pool
	var inst := ps.instantiate()
	var entries: Array = []
	_collect_tree_meshes(inst, Transform3D.IDENTITY, entries)
	inst.queue_free()
	if entries.is_empty():
		return _tree_pool
	# Ordina per altezza DA IN PIEDI (mesh orientata dalla sua base).
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _upright_aabb(a).size.y > _upright_aabb(b).size.y)
	_tree_pool = entries.slice(0, mini(16, entries.size()))
	return _tree_pool


func _collect_tree_meshes(node: Node, xform: Transform3D, out: Array) -> void:
	var t := xform
	if node is Node3D:
		t = xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append({ "mesh": (node as MeshInstance3D).mesh, "basis": t.basis })
	for c in node.get_children():
		_collect_tree_meshes(c, t, out)


## AABB della mesh orientata dalla sua base (com'è in piedi nella collezione).
func _upright_aabb(entry: Dictionary) -> AABB:
	return Transform3D(entry["basis"], Vector3.ZERO) * (entry["mesh"] as Mesh).get_aabb()


## Posa un albero della collezione su `pos`, IN PIEDI e scalato all'altezza
## `target_h`. `seed` sceglie la varietà e l'orientamento. False se manca.
func _spawn_tree(pos: Vector3, target_h: float, seed: int) -> bool:
	var pool := _trees()
	if pool.is_empty():
		return false
	var entry: Dictionary = pool[seed % pool.size()]
	var ab := _upright_aabb(entry)  # ingombro da in piedi
	var sc := target_h / ab.size.y if ab.size.y > 0.001 else 1.0
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation = Vector3(0.0, deg_to_rad(60.0 * float(seed % 6)), 0.0)
	holder.scale = Vector3(sc, sc, sc)
	add_child(holder)
	# Applica la base (raddrizza l'albero), poi centra in X/Z e appoggia la base a y=0.
	var mi := MeshInstance3D.new()
	mi.mesh = entry["mesh"]
	mi.transform = Transform3D(entry["basis"], Vector3(
		-(ab.position.x + ab.size.x * 0.5),
		-ab.position.y,
		-(ab.position.z + ab.size.z * 0.5)))
	holder.add_child(mi)
	return true


## PackedScene del modello (con cache); null se il file non è importato/presente.
func _model(path: String) -> PackedScene:
	if not _model_cache.has(path):
		_model_cache[path] = load(path) as PackedScene if ResourceLoader.exists(path) else null
	return _model_cache[path]


## Istanzia un modello centrato sull'esagono `pos`, auto-scalato così che il suo
## ingombro orizzontale entri in `footprint` e con la base appoggiata su `pos.y`.
## Restituisce false se il modello non è disponibile (→ ripiego procedurale).
func _spawn_model_fit(scene: PackedScene, pos: Vector3, footprint: float, yaw_deg: float) -> bool:
	if scene == null:
		return false
	var inst := scene.instantiate()
	var aabb := _merged_aabb(inst, Transform3D.IDENTITY)
	if aabb.size == Vector3.ZERO:
		inst.queue_free()
		return false
	var span := maxf(aabb.size.x, aabb.size.z)
	var sc := footprint / span if span > 0.001 else 1.0
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation = Vector3(0.0, deg_to_rad(yaw_deg), 0.0)
	holder.scale = Vector3(sc, sc, sc)
	add_child(holder)
	# Trasla il modello così che il suo centro orizzontale e la base vadano a 0.
	inst.position = Vector3(
		-(aabb.position.x + aabb.size.x * 0.5),
		-aabb.position.y,
		-(aabb.position.z + aabb.size.z * 0.5))
	holder.add_child(inst)
	return true


## AABB unito di tutte le mesh sotto `node`, nello spazio del genitore.
func _merged_aabb(node: Node, xform: Transform3D) -> AABB:
	var t := xform
	if node is Node3D:
		t = xform * (node as Node3D).transform
	var result := AABB()
	var got := false
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		result = t * (node as MeshInstance3D).mesh.get_aabb()
		got = true
	for c in node.get_children():
		var ca := _merged_aabb(c, t)
		if ca.size != Vector3.ZERO:
			result = result.merge(ca) if got else ca
			got = true
	return result


func _jit(q: int, r: int, i: int) -> Vector3:
	var a := float(q * 12 + r * 7 + i * 53)
	return Vector3(sin(a) * 0.45, 0.0, cos(a * 1.7) * 0.45)


## Alberello "da diorama": tronco affusolato + chioma a 3 volumi sferici
## sovrapposti (più realistica del cono singolo), con verde variato.
func _add_tree(top: Vector3, off: Vector3, scale: float) -> void:
	var base := top + off
	var trunk := MeshInstance3D.new()
	var tc := CylinderMesh.new()
	tc.top_radius = 0.035 * scale; tc.bottom_radius = 0.08 * scale; tc.height = 0.42 * scale
	tc.radial_segments = 6
	trunk.mesh = tc
	trunk.material_override = _mat(Color(0.34, 0.24, 0.15))
	trunk.position = base + Vector3(0.0, 0.21 * scale, 0.0)
	add_child(trunk)
	# Variazione di verde deterministica dalla posizione.
	var t := 0.5 + 0.5 * sin(off.x * 13.0 + off.z * 7.0)
	var green := Color(0.10, 0.30, 0.12).lerp(Color(0.16, 0.42, 0.16), t)
	_add_sphere(base + Vector3(0.0, 0.5 * scale, 0.0), 0.30 * scale, green)
	_add_sphere(base + Vector3(0.12 * scale, 0.7 * scale, -0.06 * scale), 0.24 * scale, green.darkened(0.06))
	_add_sphere(base + Vector3(-0.07 * scale, 0.86 * scale, 0.05 * scale), 0.17 * scale, green.lightened(0.06))


## Cespuglio: gruppetto di sfere basse e tozze.
func _add_bush(top: Vector3, off: Vector3, scale: float) -> void:
	var base := top + off
	var green := Color(0.14, 0.34, 0.13)
	_add_sphere(base + Vector3(0.0, 0.12 * scale, 0.0), 0.20 * scale, green)
	_add_sphere(base + Vector3(0.16 * scale, 0.10 * scale, 0.04 * scale), 0.15 * scale, green.lightened(0.05))
	_add_sphere(base + Vector3(-0.12 * scale, 0.09 * scale, -0.08 * scale), 0.14 * scale, green.darkened(0.05))


## Casa "da diorama": corpo intonacato + tetto a due falde (prisma), camino e
## porta. Posizione/colore leggermente variati per non farle tutte uguali.
func _add_building(top: Vector3, q: int, r: int) -> void:
	var yaw := 90.0 * float((q + r) % 2)  # alterna l'orientamento
	var wall := Color(0.74, 0.68, 0.56).lerp(Color(0.66, 0.58, 0.48), 0.5 + 0.5 * sin(float(q * 5 + r * 3)))
	var body := Vector3(0.88, 0.52, 0.78)
	_add_box_rot(top + Vector3(0.0, body.y * 0.5, 0.0), body, wall, yaw)
	# Tetto a falde: prisma triangolare (colmo lungo Z), appoggiato sul corpo.
	var roof := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(body.x + 0.12, 0.40, body.z + 0.12)
	roof.mesh = pm
	roof.material_override = _mat(Color(0.5, 0.24, 0.18))
	roof.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), top + Vector3(0.0, body.y + 0.20, 0.0))
	add_child(roof)
	# Camino e porta (dettagli da plastico).
	var chimney_local := Vector3(body.x * 0.28, body.y + 0.34, body.z * 0.2)
	_add_box_rot(top + chimney_local.rotated(Vector3.UP, deg_to_rad(yaw)), Vector3(0.12, 0.3, 0.12), Color(0.4, 0.28, 0.22), yaw)
	var door_local := Vector3(0.0, 0.16, body.z * 0.5 + 0.01)
	_add_box_rot(top + door_local.rotated(Vector3.UP, deg_to_rad(yaw)), Vector3(0.18, 0.30, 0.04), Color(0.25, 0.17, 0.12), yaw)


func _add_box(center: Vector3, size: Vector3, col: Color) -> void:
	_add_box_rot(center, size, col, 0.0)


func _add_box_rot(center: Vector3, size: Vector3, col: Color, yaw_deg: float) -> void:
	var b := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	b.mesh = bm
	b.material_override = _mat(col)
	b.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), center)
	add_child(b)


func _add_sphere(center: Vector3, radius: float, col: Color) -> void:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 8
	sm.rings = 5
	m.mesh = sm
	m.material_override = _mat(col)
	m.position = center
	add_child(m)


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
## Input della Modalità LOS in 3D: afferra l'estremità più vicina al click e la
## segue durante il trascinamento. Restituisce true se l'evento è stato gestito
## (così la camera non ruota); il wheel-zoom resta libero.
func _handle_los_input_3d(event: InputEvent) -> bool:
	var s := Game.state
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return false  # lascia passare il wheel-zoom
		if mb.pressed:
			var h := _pick_hex(mb.position)
			if h.x >= 0:
				var da := HexGrid.distance(h.x, h.y, s.los_a.x, s.los_a.y)
				var db := HexGrid.distance(h.x, h.y, s.los_b.x, s.los_b.y)
				_los_drag = 0 if da <= db else 1
				_set_los_endpoint_3d(_los_drag, h)
		else:
			_los_drag = -1
		return true
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _los_drag >= 0 and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			var h := _pick_hex(mm.position)
			if h.x >= 0:
				_set_los_endpoint_3d(_los_drag, h)
			return true
	return false


func _set_los_endpoint_3d(idx: int, h: Vector2i) -> void:
	if idx == 0:
		Game.state.los_a = h
	else:
		Game.state.los_b = h
	_draw_los_3d(Game.state)  # ridisegna solo il layer LOS: trascinamento fluido


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


## Spostamento (pan) della vista 3D nel piano del tabellone, come il trascinamento
## della 2D: trascina e la mappa segue il cursore. Scala con la distanza così il
## pan è uniforme a ogni zoom.
func _pan(rel: Vector2) -> void:
	var fwd := Vector3(-sin(_cam_yaw), 0.0, -cos(_cam_yaw))  # dalla camera verso il centro
	var right := Vector3(cos(_cam_yaw), 0.0, -sin(_cam_yaw))
	var k := _cam_dist * 0.0016
	_center += (right * (-rel.x) + fwd * rel.y) * k
	_update_camera()


## Reinquadra la vista 3D sull'inquadratura iniziale (tasto «0»).
func _reset_camera() -> void:
	_center = _home_center
	_cam_dist = _home_dist
	_cam_yaw = 0.6
	_cam_pitch = 0.85
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	# Modalità LOS: il tasto sinistro sposta le estremità (no rotazione camera).
	if Game.state != null and Game.state.los_mode and _handle_los_input_3d(event):
		return
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
				_hide_tooltip()
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
	elif event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and ke.keycode == KEY_0:
			_reset_camera()  # reinquadra la vista 3D
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		# Tasto destro o centrale = spostamento (pan), come in 2D.
		if (mm.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE)) != 0:
			_hide_tooltip()
			_pan(mm.relative)
		elif (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			if _touches.size() >= 2:
				return
			if mm.position.distance_to(_press_pos) > 5.0:
				_dragged = true
			_hide_tooltip()
			_orbit(mm.relative)
		else:
			# Senza pulsanti premuti: aggiorna il pannello informativo (hover).
			_update_tooltip(mm.position)
