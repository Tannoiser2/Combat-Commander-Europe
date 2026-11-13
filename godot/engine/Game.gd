## Regista della partita (autoload «Game»).
##
## Collega il motore a decisioni (Flow) con le viste (mappa 2D, mappa 3D,
## interfaccia) e con l'avversario artificiale (Bot):
##  · avvia la partita e fa «girare» il motore;
##  · quando la decisione spetta a un lato IA la fa prendere al Bot, con un
##    ritmo che permetta di seguire cosa succede;
##  · quando spetta all'umano avvisa l'interfaccia (decision_changed) e traduce
##    i tocchi su esagoni/pedine/carte/pulsanti nella scelta di un'opzione;
##  · distribuisce la cronaca (chronicle) un evento alla volta.
extends Node

signal state_changed()
signal decision_changed()               ## nuova decisione per l'umano (o nessuna)
signal chronicle(ev: Dictionary)        ## evento di cronaca da mostrare
signal stack_offered(indices: Array)    ## più opzioni nello stesso esagono: scegli
signal game_over(winner: int)
# Segnali usati dalle viste per le animazioni.
signal unit_moved(unit_id: String, q: int, r: int)
signal unit_eliminated(unit_id: String)
signal fire_resolved(result: Object)
signal grenade_thrown(fq: int, fr: int, tq: int, tr: int)
signal artillery_impact(q: int, r: int)

enum Mode { VS_AI, HOTSEAT, DEMO }

var flow: Flow = null
var state: GameState:
	get:
		return flow.s if flow != null else null
var bots: Dictionary = {}
var human: int = Flow.AX
var mode: int = Mode.VS_AI
var difficulty: int = 1
var speed: float = 1.0            ## moltiplicatore del ritmo (1 = normale)
var paused: bool = false
var busy: bool = false            ## cronaca in riproduzione / IA al lavoro

const SETTINGS_PATH := "user://settings.cfg"
var tutorial_enabled: bool = true

var _queue: Array = []
var _timer: Timer


func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	add_child(_timer)
	_timer.timeout.connect(_tick)
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		tutorial_enabled = bool(cfg.get_value("ui", "tutorial", true))
		speed = float(cfg.get_value("ui", "speed", 1.0))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "tutorial", tutorial_enabled)
	cfg.set_value("ui", "speed", speed)
	cfg.save(SETTINGS_PATH)


func set_tutorial(on: bool) -> void:
	tutorial_enabled = on
	save_settings()


# ─── Avvio ───────────────────────────────────────────────────────────────────

func start_new_game(human_faction: int = Flow.AX, scenario_num: int = 1,
		p_difficulty: int = 1, p_mode: int = Mode.VS_AI, seed_value: int = 0) -> void:
	human = human_faction
	mode = p_mode
	difficulty = p_difficulty
	flow = Flow.new_game(scenario_num, human_faction, seed_value)
	bots.clear()
	match mode:
		Mode.VS_AI:
			bots[flow.opp(human)] = Bot.new(flow, difficulty)
		Mode.DEMO:
			bots[Flow.AX] = Bot.new(flow, difficulty)
			bots[Flow.AL] = Bot.new(flow, difficulty)
	_queue.clear()
	paused = false
	flow.start()
	_after_engine()


## Il lato indicato è giocato da una persona?
func is_human(f: int) -> bool:
	return not bots.has(f)


## Lato dal cui punto di vista si mostra la mano (in hotseat: chi deve decidere).
func viewer() -> int:
	if mode == Mode.HOTSEAT and flow != null:
		if not flow.pending.is_empty():
			return int(flow.pending["who"])
		return flow.s.active_faction
	return human


## Decisione in sospeso per una persona ({} se non tocca a un umano o se la
## cronaca è ancora in corso).
func pending() -> Dictionary:
	if flow == null or flow.over or busy or flow.pending.is_empty():
		return {}
	if not is_human(int(flow.pending["who"])):
		return {}
	return flow.pending


# ─── Ritmo: cronaca e IA ─────────────────────────────────────────────────────

func _after_engine() -> void:
	for ev in flow.events:
		_queue.append(ev)
	flow.events.clear()
	_sync_legacy()
	state_changed.emit()
	busy = true
	decision_changed.emit()
	_schedule(0.01)


func _schedule(t: float) -> void:
	if paused:
		return
	_timer.start(maxf(0.01, t / maxf(0.25, speed)))


func set_paused(p: bool) -> void:
	paused = p
	if not p and busy:
		_schedule(0.05)


## Salta l'attesa: mostra subito tutta la cronaca in coda.
func skip() -> void:
	while not _queue.is_empty():
		_play_event(_queue.pop_front())
	_timer.stop()
	_tick()


func _event_delay(ev: Dictionary) -> float:
	match String(ev.get("kind", "")):
		"roll": return 0.75
		"fire", "melee": return 0.7
		"move": return 0.3
		"kill", "bad", "time", "end": return 0.8
		"turn": return 0.9
		"order": return 0.8
	return 0.45


func _tick() -> void:
	if flow == null:
		return
	if not _queue.is_empty():
		var ev: Dictionary = _queue.pop_front()
		_play_event(ev)
		# Le azioni proprie scorrono più svelte di quelle dell'avversario.
		var own := is_human(int(ev.get("who", -1))) and mode == Mode.VS_AI
		_schedule(_event_delay(ev) * (0.55 if own else 1.0))
		return
	if flow.over:
		busy = false
		_sync_legacy()
		state_changed.emit()
		decision_changed.emit()
		game_over.emit(flow.winner)
		return
	if flow.pending.is_empty():
		busy = false
		return
	var who := int(flow.pending["who"])
	if bots.has(who):
		var bot: Bot = bots[who]
		var i := bot.pick()
		flow.answer(i)
		_after_engine()
		return
	busy = false
	_sync_legacy()
	state_changed.emit()
	decision_changed.emit()


func _play_event(ev: Dictionary) -> void:
	chronicle.emit(ev)
	match String(ev.get("kind", "")):
		"move":
			var to: Vector2i = ev.get("to", Vector2i(-1, -1))
			unit_moved.emit(String(ev.get("unit", "")), to.x, to.y)
		"kill":
			unit_eliminated.emit(String(ev.get("unit", "")))
		"fire":
			if ev.has("from") and ev.has("to") and state != null:
				state.last_fire_from = ev["from"]
				state.last_fire_to = ev["to"]
				state.last_fire_text = ""
				var pcs: Array = ev.get("pieces", [])
				if not pcs.is_empty():
					var fr := Combat.FireResult.new()
					fr.attacker_id = String(pcs[0])
					fr.target_q = ev["to"].x
					fr.target_r = ev["to"].y
					fr.fp_total = 5
					fire_resolved.emit(fr)
		_:
			if String(ev.get("fx", "")) == "arty" and ev.has("hex"):
				artillery_impact.emit(ev["hex"].x, ev["hex"].y)
	state_changed.emit()


# ─── Scelte dell'umano ───────────────────────────────────────────────────────

func choose(index: int) -> void:
	var p := pending()
	if p.is_empty():
		return
	flow.answer(index)
	_after_engine()


## Sceglie la prima opzione con quell'id (es. "confirm", "end", "pass").
func choose_id(id: String) -> bool:
	var p := pending()
	if p.is_empty():
		return false
	var opts: Array = p["options"]
	for i in opts.size():
		if String(opts[i].get("id", "")) == id:
			choose(i)
			return true
	return false


## Opzioni della decisione corrente che riguardano l'esagono (q,r): l'esagono
## stesso o una pedina/arma che vi si trova.
func options_at(q: int, r: int) -> Array:
	var out: Array = []
	var p := pending()
	if p.is_empty():
		return out
	var opts: Array = p["options"]
	for i in opts.size():
		var o: Dictionary = opts[i]
		if o.has("hex"):
			var h: Vector2i = o["hex"]
			if h.x == q and h.y == r:
				out.append(i)
		elif o.has("unit"):
			var u: Unit = state.unit_by_id(String(o["unit"]))
			if u != null and u.q == q and u.r == r:
				out.append(i)
	return out


## Tocco su un esagono della mappa (2D o 3D).
func click_hex(q: int, r: int) -> void:
	var idx := options_at(q, r)
	if idx.is_empty():
		return
	if idx.size() == 1:
		choose(idx[0])
	else:
		stack_offered.emit(idx)


## Tocco diretto su una pedina (vista 3D).
func select_unit(unit_id: String) -> void:
	var p := pending()
	if p.is_empty():
		return
	var opts: Array = p["options"]
	for i in opts.size():
		if String(opts[i].get("unit", "")) == unit_id:
			choose(i)
			return
	var u: Unit = state.unit_by_id(unit_id)
	if u != null:
		click_hex(u.q, u.r)


## Pedine che l'umano può toccare adesso (per gli anelli sulle mappe).
func actable_unit_ids() -> Array[String]:
	var out: Array[String] = []
	var p := pending()
	if p.is_empty():
		return out
	for o in p["options"]:
		if o.has("unit"):
			var u: Unit = state.unit_by_id(String(o["unit"]))
			if u == null:
				continue
			# Un'arma si indica tramite chi la porta.
			var id := u.carrier_id if (u.is_weapon() and u.carrier_id != "") else u.id
			if not out.has(id):
				out.append(id)
	return out


func toggle_fire_piece(_id: String) -> void:
	select_unit(_id)


func fire_preview() -> Dictionary:
	return {}


func fire_preview_at(_q: int, _r: int) -> Dictionary:
	return {}


## Tiene allineati i vecchi campi «di interfaccia» dello stato, che la vista 3D
## usa per evidenziare esagoni e pedine.
func _sync_legacy() -> void:
	var s := state
	if s == null:
		return
	s.highlighted_hexes.clear()
	s.fire_ready_ids.clear()
	s.ordered_group.clear()
	s.fire_group_ids.clear()
	s.fire_eligible_ids.clear()
	s.command_preview_ids.clear()
	s.fire_leader_ids.clear()
	s.selected_unit_id = ""
	s.fire_target_q = -1
	s.fire_target_r = -1
	s.current_order = -1
	s.human_faction = viewer()
	if flow.over:
		s.phase = Domain.Phase.GAME_OVER
		return
	var p := pending()
	s.phase = Domain.Phase.PLAYER_TURN if not p.is_empty() else Domain.Phase.AI_TURN
	if p.is_empty():
		return
	s.selected_unit_id = String(p.get("unit", p.get("leader", "")))
	for o in p["options"]:
		if o.has("hex"):
			var h: Vector2i = o["hex"]
			s.highlighted_hexes.append("%d,%d" % [h.x, h.y])
	for id in actable_unit_ids():
		s.fire_ready_ids.append(id)
	for id in p.get("selected", []):
		s.ordered_group.append(String(id))
