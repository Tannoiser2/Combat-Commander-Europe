## Motore di flusso di Combat Commander: Europe — «a decisioni».
##
## Tutta la partita è una sequenza di DECISIONI: ogni volta che un giocatore
## (umano o IA, non fa differenza) deve scegliere qualcosa, il motore si ferma
## con `pending` valorizzato:
##   { "who": lato, "kind": tipo, "title": testo-guida, "options": [ ... ] }
## e riparte quando qualcuno chiama `answer(indice)`. Le opzioni elencate sono
## SEMPRE e SOLO le mosse legali in quel momento: l'interfaccia le mostra
## (pedine, esagoni, carte, pulsanti) e l'IA sceglie fra le stesse identiche
## opzioni. Così nessuno dei due può fare una mossa fuori regolamento.
##
## Quello che succede (tiri, spostamenti, esiti) viene accodato in `events`,
## che l'interfaccia svuota per la cronaca e le animazioni.
##
## NOTA per chi pilota il motore: dopo `start()` e dopo ogni `answer()` il
## motore ha già corso fino alla decisione successiva (o alla fine partita);
## basta rileggere `pending`/`over`. Non rispondere MAI dall'interno di una
## callback del motore.
class_name Flow
extends RefCounted

const AX := Domain.Faction.GERMAN   ## lato Asse (slot «german» dello stato)
const AL := Domain.Faction.RUSSIAN  ## lato Alleati (slot «russian» dello stato)

signal _answered
signal _never

var s: GameState
var pending: Dictionary = {}
var events: Array = []
var over: bool = false
var winner: int = -1
var end_reason: String = ""

var orders_max: Dictionary = { AX: 2, AL: 2 }
var orders_done: int = 0
var gave_order: bool = false
var turn_count: int = 1

var _answer: Dictionary = {}
var _pending_time: Array = []       ## lati che hanno innescato un avanzamento del Tempo
var _rng := RandomNumberGenerator.new()
var _moving_ids: Array = []         ## unità attualmente «attivate a Muovere»
var _opfire_ids: Array = []         ## unità attivate per il Fuoco di Opportunità in questa Mossa
var _team_seq: int = 0
var setup_zone: Array = []          ## zona di schieramento del giocatore umano (se prevista)
var manual_setup: bool = false

## Limite di scarto per nazione (scheda riassuntiva del giocatore).
const DISCARD_LIMIT := {
	"german": 5, "russian": 3, "american": 6, "british": 4, "italian": 2, "french": 1,
}
const NATION_PLURAL := {
	"german": "Tedeschi", "russian": "Sovietici", "american": "Americani",
	"british": "Britannici", "italian": "Italiani", "french": "Francesi",
	"romanian": "Rumeni", "canadian": "Canadesi", "anzac": "ANZAC",
	"brazilian": "Brasiliani", "polish": "Polacchi", "yugoslav": "Jugoslavi",
}


# ═══ Avvio ═══════════════════════════════════════════════════════════════════

## Prepara una nuova partita sullo scenario indicato. `human` = lato del
## giocatore umano (AX/AL), usato solo per orientare lo schieramento automatico.
static func new_game(scenario_num: int, human: int = AX, seed_value: int = 0) -> Flow:
	var f := Flow.new()
	if seed_value != 0:
		f._rng.seed = seed_value
		seed(seed_value)
	else:
		f._rng.randomize()
	var st := GameState.new()
	st.human_faction = human
	if scenario_num <= 1 or not ScenarioLoader.setup(st, scenario_num):
		st.edge_mode = 1
		Scenario1.setup(st)
		st.scenario_number = 1
		st.scenario_name = "Fat Lipki"
		f.orders_max[AX] = int(Scenario1.SETUP["german_orders"])
		f.orders_max[AL] = int(Scenario1.SETUP["russian_orders"])
		st.defender_faction = -1
		st.active_faction = st.initiative_holder
	else:
		var e := ScenarioLoader.entry(scenario_num)
		f.orders_max[AX] = int(e.get("ordini_axis", 2))
		f.orders_max[AL] = int(e.get("ordini_allies", 2))
	f.setup_zone = st.setup_zone.duplicate()
	st.setup_zone = []
	f.s = st
	f._assign_carriers()
	for u in st.units.values():
		UnitChart.apply_broken_side(u, UnitChart.nation_code(f.nation(u.faction)))
	st.german_deck = Cards.build_deck(st.axis_nation)
	st.russian_deck = Cards.build_deck(st.allied_nation)
	f._shuffle(st.german_deck)
	f._shuffle(st.russian_deck)
	for side in [AX, AL]:
		for _i in st.hand_size_of(side):
			f.hand(side).append(f.deck(side).pop_back())
	f._opening_cards()
	f.update_objectives()
	return f


## Avvia (o riprende) il ciclo dei turni. Ritorna appena c'è la prima decisione.
func start() -> void:
	say("[b]Scenario %d — %s[/b]" % [s.scenario_number, s.scenario_name], "turn")
	_run()


func _run() -> void:
	if manual_setup and not setup_zone.is_empty():
		await _setup(s.human_faction)
	while not over:
		await _turn(s.active_faction)
		if over:
			return
		s.active_faction = opp(s.active_faction)
		turn_count += 1
		s.turn_number = turn_count


## Schieramento iniziale del giocatore: può spostare le sue unità dentro la
## zona prevista dalla scheda, farle ridisporre in automatico, o confermare.
func _setup(f: int) -> void:
	say("Schieramento dei %s: disponi le tue unità nella zona evidenziata." % side_name(f), "turn", { "who": f })
	while not over:
		var opts: Array = []
		for u in men(f):
			opts.append({ "id": "unit", "unit": u.id, "label": "Sposta %s" % uname(u) })
		opts.append({ "id": "auto", "label": "Ridisponi tutto in automatico" })
		opts.append({ "id": "confirm", "label": "Pronto: inizia la partita" })
		var a := await ask(f, "setup", "SCHIERAMENTO · tocca una tua unità per spostarla dentro la zona, oppure conferma lo schieramento proposto.", opts, {})
		match String(a.get("id", "confirm")):
			"auto":
				s.setup_zone = setup_zone.duplicate()
				ScenarioLoader.auto_deploy_human(s)
				s.setup_zone = []
				_refit_weapons(f)
			"unit":
				var u: Unit = s.unit_by_id(String(a["unit"]))
				var o2: Array = []
				for h: Vector2i in setup_zone:
					var hd: GameState.HexData = s.hex_at(h.x, h.y)
					if hd == null or int(Domain.TERRAIN_MOVE_COST.get(hd.terrain, 1)) >= 99 or h == u.pos():
						continue
					if s.soldier_icons_at(h.x, h.y) + u.soldier_icons() <= 7 and not enemy_in(h, f):
						o2.append({ "id": "hex", "hex": h, "label": lbl(h) })
				o2.append({ "id": "no", "label": "Lascia %s dov'è" % u.unit_name })
				var b := await ask(f, "setup_place", "SCHIERAMENTO · tocca l'esagono della zona in cui mettere %s." % u.unit_name, o2, { "unit": u.id })
				if b.get("id") == "hex":
					s.set_unit_pos(u, b["hex"].x, b["hex"].y)
			_:
				break
	update_objectives()
	events.clear()
	say("[b]Scenario %d — %s[/b]: schieramento completato." % [s.scenario_number, s.scenario_name], "turn")


func _refit_weapons(f: int) -> void:
	for w in s.units.values():
		if w.is_weapon() and w.faction == f and w.carrier_id != "":
			var c: Unit = s.unit_by_id(w.carrier_id)
			if c != null:
				w.q = c.q
				w.r = c.r


## Risponde alla decisione in sospeso scegliendo l'opzione `index`.
func answer(index: int) -> void:
	if pending.is_empty():
		return
	var opts: Array = pending["options"]
	if index < 0 or index >= opts.size():
		return
	_answer = opts[index]
	pending = {}
	_answered.emit()


## Chiede una decisione a `who`. Se la partita è finita il flusso resta sospeso
## per sempre (niente più regole da eseguire).
func ask(who: int, kind: String, title: String, options: Array, extra: Dictionary = {}) -> Dictionary:
	if over:
		await _never
	pending = { "who": who, "kind": kind, "title": title, "options": options }
	pending.merge(extra)
	await _answered
	if over:
		await _never
	return _answer


# ═══ Utilità di base ═════════════════════════════════════════════════════════

func opp(f: int) -> int:
	return AL if f == AX else AX

func nation(f: int) -> String:
	return s.axis_nation if f == AX else s.allied_nation

func side_name(f: int) -> String:
	return String(NATION_PLURAL.get(nation(f), "Asse" if f == AX else "Alleati"))

func hand(f: int) -> Array[Card]:
	return s.german_hand if f == AX else s.russian_hand

func deck(f: int) -> Array[Card]:
	return s.german_deck if f == AX else s.russian_deck

func pile(f: int) -> Array[Card]:
	return s.german_discard if f == AX else s.russian_discard

func discard_limit(f: int) -> int:
	return int(DISCARD_LIMIT.get(Cards.DECK_FILE.get(nation(f), "german"), 4))

func is_defender(f: int) -> bool:
	return s.defender_faction == f

func lbl(h: Vector2i) -> String:
	return Domain.qr_to_label(h.x, h.y)

func uname(u: Unit) -> String:
	return "%s (%s)" % [u.unit_name, Domain.qr_to_label(u.q, u.r)]

func in_map(h: Vector2i) -> bool:
	return h.x >= 0 and h.x < s.map_cols and h.y >= 0 and h.y < s.map_rows

## Il bordo amico di `f` è in alto?
func _top(f: int) -> bool:
	return (f == AL) == (s.edge_mode == 1)


## Distanza (in mezze righe o colonne) dell'esagono dal bordo amico di `f`.
func edge_dist(f: int, h: Vector2i) -> int:
	if s.edge_mode == 0:
		return (s.map_cols - 1 - h.x) if f == AX else h.x
	var y2 := 2 * h.y + (h.x & 1)
	return y2 if _top(f) else (2 * (s.map_rows - 1) + 1) - y2


## L'esagono tocca il bordo amico di `f`?
func at_edge(f: int, h: Vector2i) -> bool:
	if s.edge_mode == 0:
		return h.x == (s.map_cols - 1 if f == AX else 0)
	return h.y == (0 if _top(f) else s.map_rows - 1)


func edge_hexes(f: int) -> Array:
	var out: Array = []
	for q in s.map_cols:
		for r in s.map_rows:
			if at_edge(f, Vector2i(q, r)):
				out.append(Vector2i(q, r))
	return out


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = t


## Accoda un evento di cronaca. `kind` colora la riga; `data` porta i dettagli
## utili alle animazioni (es. from/to di un fuoco).
func say(text: String, kind: String = "", data: Dictionary = {}) -> void:
	var ev := { "text": text, "kind": kind }
	ev.merge(data)
	events.append(ev)
	s.add_log(text, "", kind)


func add_vp(f: int, n: int, why: String = "") -> void:
	if n == 0:
		return
	s.bonus_vp += n if f == AX else -n
	update_objectives()
	say("%s: %+d PV%s." % [side_name(f), n, (" (" + why + ")") if why != "" else ""], "vp")


## Bilancia PV dal punto di vista del lato `f` (positiva = `f` è avanti).
func vp_for(f: int) -> int:
	return s.vp_tracker if f == AX else -s.vp_tracker


func men(f: int) -> Array[Unit]:
	return s.men_of(f)


func radio_of(f: int) -> Unit:
	for u in s.units.values():
		if u.faction == f and u.is_weapon() and u.unit_name.contains("Radio"):
			return u
	return null


func is_radio(u: Unit) -> bool:
	return u.is_weapon() and u.unit_name.contains("Radio")


func _assign_carriers() -> void:
	for w in s.units.values():
		if not w.is_weapon() or w.carrier_id != "" or is_radio(w):
			continue
		var best: Unit = null
		var best_d := 1 << 30
		for m in s.units.values():
			if not m.is_man() or m.faction != w.faction or s.weapon_carried_by(m.id) != null:
				continue
			var d := HexGrid.distance(w.q, w.r, m.q, m.r) * 2 + (1 if m.is_leader() else 0)
			if d < best_d:
				best_d = d
				best = m
		if best != null:
			w.q = best.q
			w.r = best.r
			w.carrier_id = best.id


func _opening_cards() -> void:
	for pair in [[AX, "axis"], [AL, "allies"]]:
		var f: int = pair[0]
		for code in ScenarioEffects.opening_cards(s.scenario_number, String(pair[1])):
			var parts := String(code).split("-")
			var num := int(parts[parts.size() - 1])
			var d := deck(f)
			for i in d.size():
				if int(d[i].number) == num:
					hand(f).append(d[i])
					d.remove_at(i)
					break


# ═══ Carte e dadi ════════════════════════════════════════════════════════════

## Pesca la carta in cima al mazzo di `f` (va negli scarti). Se era l'ultima,
## scatta un avanzamento del Tempo (6.1.2), elaborato al primo punto sicuro.
func draw_card(f: int) -> Card:
	var d := deck(f)
	if d.is_empty():
		_reshuffle(f)
	if d.is_empty():
		return null
	var c: Card = d.pop_back()
	pile(f).append(c)
	if d.is_empty() and not _pending_time.has(f):
		_pending_time.append(f)
		say("%s: mazzo esaurito — il Tempo avanzerà." % side_name(f), "time")
	return c


func _reshuffle(f: int) -> void:
	var d := deck(f)
	d.append_array(pile(f))
	pile(f).clear()
	_shuffle(d)


func _discard_from_hand(f: int, card: Card) -> void:
	hand(f).erase(card)
	pile(f).append(card)


func find_action(f: int, action_name: String) -> Card:
	for c in hand(f):
		if c.action_name == action_name:
			return c
	return null


func find_order(f: int, order: int) -> Card:
	for c in hand(f):
		if c.order == order:
			return c
	return null


## Tiro di dadi di `f` (= carta pescata dal suo mazzo). `judge` riceve la somma
## (o il prodotto se `product`) e restituisce il lato SFAVORITO da quel risultato
## (-1 se a nessuno importa): se quel lato ha la carta Iniziativa può far
## ripetere il tiro cedendola (9.1). Gli inneschi della carta (Tempo!, Cecchino,
## Evento, Inceppamento) si applicano solo al tiro definitivo.
## Restituisce { "a": dado bianco, "b": dado rosso, "sum": totale, "card": Card }.
func roll(f: int, what: String, judge: Callable = Callable(), ctx: Dictionary = {}) -> Dictionary:
	var product: bool = ctx.get("product", false)
	var res := {}
	while true:
		var c := draw_card(f)
		var a := c.dice_white if c != null else _rng.randi_range(1, 6)
		var b := c.dice_red if c != null else _rng.randi_range(1, 6)
		var total := a * b if product else a + b
		res = { "a": a, "b": b, "sum": total, "card": c }
		say("%s tira per %s: [b]%d%s%d = %d[/b]%s" % [
			side_name(f), what, a, "×" if product else "+", b, total, _trigger_tag(c, ctx)],
			"roll", { "dice": [a, b], "who": f })
		if over:
			return res
		var holder := s.initiative_holder
		var unhappy: int = judge.call(total) if judge.is_valid() else -1
		if unhappy != holder:
			break
		var ans := await ask(holder, "reroll",
			"Hai la carta Iniziativa: vuoi far RIPETERE questo tiro (%s: %d)? La carta passa all'avversario." % [what, total],
			[{ "id": "keep", "label": "Tieni il tiro" }, { "id": "reroll", "label": "Ripeti il tiro (cedi l'Iniziativa)" }],
			{ "roll": res, "what": what })
		if ans.get("id", "keep") != "reroll":
			break
		s.initiative_holder = opp(holder)
		say("[b]%s usa l'Iniziativa[/b]: il tiro è annullato e si ripete. L'Iniziativa passa a %s." % [
			side_name(holder), side_name(opp(holder))], "init")
	if not ctx.get("no_trigger", false):
		await _apply_trigger(res["card"], f, ctx)
	return res


func _trigger_tag(c: Card, ctx: Dictionary) -> String:
	if c == null or ctx.get("no_trigger", false):
		return ""
	match String(c.consequence):
		"time": return "  [color=#e0b040]TEMPO![/color]"
		"sniper": return "  [color=#e06060]CECCHINO![/color]"
		"event": return "  [color=#70b0e0]EVENTO![/color]"
		"jam":
			return "  [color=#e08040]INCEPPAMENTO![/color]" if ctx.get("fire_weapons", null) != null else ""
	return ""


func _apply_trigger(c: Card, f: int, ctx: Dictionary) -> void:
	if c == null or over:
		return
	match String(c.consequence):
		"time":
			if not _pending_time.has(f):
				_pending_time.append(f)
		"sniper":
			await _sniper(f)
		"event":
			await _event(f)
		"jam":
			if ctx.has("fire_weapons"):
				for w: Unit in ctx["fire_weapons"]:
					_break_weapon(w, "Inceppamento")
	await _process_time()


func _break_weapon(w: Unit, why: String) -> void:
	if w == null or not s.units.has(w.id):
		return
	if w.efficient:
		w.efficient = false
		say("%s: %s si guasta." % [why, w.unit_name], "bad")
	else:
		s.units.erase(w.id)
		say("%s: %s, già guasta, è eliminata." % [why, w.unit_name], "bad")


## Esagono Casuale: si rivela la carta successiva e si legge il suo esagono.
func random_hex(f: int) -> Vector2i:
	var c := draw_card(f)
	if c == null:
		return Vector2i(_rng.randi_range(0, s.map_cols - 1), _rng.randi_range(0, s.map_rows - 1))
	var h := Domain.label_to_qr(c.random_hex_label)
	if not in_map(h):
		h = Vector2i(clampi(h.x, 0, s.map_cols - 1), clampi(h.y, 0, s.map_rows - 1))
	return h


func _sniper(f: int) -> void:
	var h := random_hex(f)
	var cands: Array = []
	for u in s.units.values():
		if u.is_man() and u.faction != f and HexGrid.distance(h.x, h.y, u.q, u.r) <= 1:
			cands.append(u)
	if cands.is_empty():
		say("Cecchino in %s: nessun nemico a tiro." % lbl(h), "fate", { "hex": h })
		return
	var opts: Array = []
	for u: Unit in cands:
		opts.append({ "id": "unit", "unit": u.id, "label": uname(u) })
	opts.append({ "id": "none", "label": "Non colpire nessuno" })
	var a := await ask(f, "sniper", "CECCHINO in %s: scegli un'unità nemica nell'esagono o adiacente da ROMPERE." % lbl(h), opts, { "hex": h })
	if a.get("id") == "unit":
		var v: Unit = s.unit_by_id(a["unit"])
		say("[b]Cecchino![/b] %s viene colpita." % uname(v), "fate", { "hex": h })
		await hit(v, "Cecchino")
		check_end()


func _event(f: int) -> void:
	var c := draw_card(f)
	if c == null:
		return
	say("[b]Evento — %s[/b] (per %s)" % [c.event_name.capitalize(), side_name(f)], "fate")
	if await _event_native(c, f):
		check_end()
		return
	var before := s.units.size()
	for line in Events.fire(s, c, f):
		say("   " + String(line), "fate")
	# Unità create dagli eventi (Eroe, Soldato semplice): dotale del lato rotto.
	if s.units.size() != before:
		for u in s.units.values():
			UnitChart.apply_broken_side(u, UnitChart.nation_code(nation(u.faction)))
	update_objectives()
	check_end()


# ═══ Unità: colpi, eliminazioni, vittoria ════════════════════════════════════

## Morale corrente ai fini di un tiro di difesa / recupero / rotta: lato
## corrente + Comando del leader nello stesso esagono − soppressione − filo.
func morale_of(u: Unit) -> int:
	return u.morale + Rules.unit_command_bonus(s, u) - (1 if u.suppressed else 0) - Rules.wire_penalty(s, u)


## L'unità «si rompe» (3.2): efficiente → rotta; già rotta → eliminata.
## Una Squadra può salvarsi con Ferite Leggere (A36).
func hit(u: Unit, why: String = "") -> void:
	if u == null or not s.units.has(u.id):
		return
	if u.type == Domain.UnitType.SQUAD:
		var c := find_action(u.faction, "FERITE LEGGERE")
		if c != null:
			var a := await ask(u.faction, "light_wounds",
				"%s sta per %s: giochi FERITE LEGGERE? (perdi 1 PV; la Squadra diventa un Team %s)" % [
					uname(u), "rompersi" if u.efficient else "essere ELIMINATA",
					"efficiente" if u.efficient else "rotto"],
				[{ "id": "play", "card": hand(u.faction).find(c), "label": "Gioca Ferite Leggere" },
				 { "id": "no", "label": "No" }], { "unit": u.id })
			if a.get("id") == "play":
				_discard_from_hand(u.faction, c)
				_light_wounds(u)
				return
	if u.efficient:
		u.efficient = false
		say("%s è [b]rotta[/b]%s." % [uname(u), (" — " + why) if why != "" else ""], "bad", { "unit": u.id, "fx": "break" })
	else:
		kill(u, why)


func _light_wounds(sq: Unit) -> void:
	add_vp(sq.faction, -1, "Ferite Leggere")
	var t := make_team(sq.faction, "Elite" if sq.unit_class == Domain.UnitClass.ELITE else "Line", sq.q, sq.r)
	t.activated = sq.activated
	t.suppressed = sq.suppressed
	t.veteran = sq.veteran
	if not sq.efficient:
		t.efficient = false
	var w := s.weapon_carried_by(sq.id)
	if w != null:
		w.carrier_id = t.id
	s.units.erase(sq.id)
	if _moving_ids.has(sq.id):
		_moving_ids.append(t.id)
	say("Ferite Leggere: %s si riduce a un Team." % uname(sq), "good", { "unit": t.id })


func make_team(f: int, quality: String, q: int, r: int) -> Unit:
	_team_seq += 1
	var nat := UnitChart.nation_code(nation(f))
	var id := "T-%s-%d" % [Domain.FACTION_SHORT.get(f, "U"), _team_seq]
	var t := UnitChart.build_unit(id, f, "%s Team" % quality, q, r, nat)
	var chart: Dictionary = UnitChart._data().get("units", {}).get(nat, {})
	var st: Dictionary = chart.get("Team " + quality, {})
	if not st.is_empty():
		t.fp = int(st.get("fp", t.fp)); t.fp_boxed = bool(st.get("fp_boxed", false))
		t.range = int(st.get("range", t.range)); t.range_boxed = bool(st.get("range_boxed", false))
		t.move = int(st.get("move", t.move)); t.morale = int(st.get("morale", t.morale))
	t.type = Domain.UnitType.TEAM
	t.q = q
	t.r = r
	UnitChart.apply_broken_side(t, nat)
	s.units[id] = t
	return t


func kill(u: Unit, why: String = "") -> void:
	if u == null or not s.units.has(u.id):
		return
	var v := GameState.elimination_vp(u) * (2 if s.chit_double_elim else 1)
	say("%s è [b]ELIMINATA[/b]%s%s." % [uname(u), (" — " + why) if why != "" else "",
		(" (+%d PV a %s)" % [v, side_name(opp(u.faction))]) if v > 0 else ""],
		"kill", { "unit": u.id, "fx": "kill", "hex": u.pos() })
	s.eliminate_unit(u.id)
	update_objectives()


## Controllo «appiccicoso» degli obiettivi (7.3.1) e bilancia PV pubblica.
func update_objectives() -> void:
	var bal := 0
	for obj in s.objectives:
		var ax := 0
		var al := 0
		for u in s.men_at(obj.q, obj.r):
			if u.faction == AX:
				ax += 1
			else:
				al += 1
		var before := obj.controller
		if ax > 0 and al == 0:
			obj.controller = AX
		elif al > 0 and ax == 0:
			obj.controller = AL
		if obj.controller != before and not events.is_empty():
			say("Obiettivo %d: ora controllato da %s." % [obj.id, side_name(obj.controller)], "vp", { "hex": Vector2i(obj.q, obj.r) })
		if obj.controller == AX:
			bal += obj.vp
		elif obj.controller == AL:
			bal -= obj.vp
	s.vp_tracker = bal + s.bonus_vp


## Resa e annientamento (6.3.1). Da chiamare dopo ogni perdita.
func check_end() -> void:
	if over:
		return
	var ax_lost := s.has_surrendered(AX) or s.men_of(AX).is_empty()
	var al_lost := s.has_surrendered(AL) or s.men_of(AL).is_empty()
	if not (ax_lost or al_lost):
		return
	if ax_lost and al_lost:
		_finish(s.initiative_holder, "Entrambi i lati sono crollati: decide la carta Iniziativa.")
	elif ax_lost:
		_finish(AL, "%s: %s." % [side_name(AX), "resa (troppe perdite)" if s.has_surrendered(AX) else "nessuna unità rimasta"])
	else:
		_finish(AX, "%s: %s." % [side_name(AL), "resa (troppe perdite)" if s.has_surrendered(AL) else "nessuna unità rimasta"])


func _finish_on_points(why: String) -> void:
	update_objectives()
	for line in ObjectiveChits.reveal_all(s):
		say(String(line), "vp")
	update_objectives()
	var w := s.initiative_holder
	if s.vp_tracker > 0:
		w = AX
	elif s.vp_tracker < 0:
		w = AL
	_finish(w, "%s Punti Vittoria finali: %d a favore di %s%s." % [why, absi(s.vp_tracker), side_name(w),
		" (parità: decide l'Iniziativa)" if s.vp_tracker == 0 else ""])


func _finish(w: int, why: String) -> void:
	if over:
		return
	over = true
	winner = w
	end_reason = why
	pending = {}
	s.phase = Domain.Phase.GAME_OVER
	say("[b]FINE PARTITA — vincono i %s.[/b] %s" % [side_name(w), why], "end")


# ═══ Turno ═══════════════════════════════════════════════════════════════════

func _turn(f: int) -> void:
	for u in s.units.values():
		u.activated = false
	s.rally_used.clear()
	_opfire_ids.clear()
	_moving_ids.clear()
	orders_done = 0
	say("[b]Turno %d — tocca ai %s[/b] (fino a %d Ordini)" % [turn_count, side_name(f), int(orders_max[f])], "turn", { "who": f })
	while not over:
		var opts: Array = []
		var blocked := {}
		var h := hand(f)
		for i in h.size():
			var why := "Hai già dato tutti gli Ordini del turno." if orders_done >= int(orders_max[f]) else order_block(f, h[i])
			if why == "":
				opts.append({ "id": "order", "card": i, "label": "Ordine: %s" % Domain.ORDER_LABELS.get(h[i].order, "?") })
			else:
				blocked[i] = why
		if orders_done == 0:
			opts.append({ "id": "discard", "label": "Scarta carte (al posto degli Ordini)" })
		opts.append({ "id": "end", "label": "Fine turno" if orders_done > 0 else "Passa senza scartare" })
		var a := await ask(f, "turn",
			"Gioca una carta come ORDINE (%d di %d usati), oppure termina il turno." % [orders_done, int(orders_max[f])]
			if orders_done > 0 else
			"Il tuo turno: gioca una carta come ORDINE (fino a %d), oppure scarta." % int(orders_max[f]),
			opts, { "blocked": blocked })
		match String(a.get("id", "end")):
			"order":
				var c: Card = hand(f)[int(a["card"])]
				await _play_order(f, c)
				orders_done += 1
			"discard":
				await _discard_turn(f)
				break
			_:
				break
	if over:
		return
	_overstack(AX)
	_overstack(AL)
	check_end()
	await _refill(f)


## Motivo per cui la carta NON può essere giocata come Ordine ora ("" = può).
func order_block(f: int, c: Card) -> String:
	match c.order:
		Domain.OrderType.PASS:
			return "Ordini Contraddittori: questa carta non vale come Ordine."
		Domain.OrderType.MOVE, Domain.OrderType.FIRE, Domain.OrderType.ADVANCE:
			if activation_options(f, c.order).is_empty():
				match c.order:
					Domain.OrderType.FIRE: return "Nessuna tua unità non ancora attivata ha un nemico in vista e a tiro."
					Domain.OrderType.MOVE: return "Nessuna tua unità non ancora attivata può muovere."
					_: return "Nessuna tua unità non ancora attivata può avanzare."
		Domain.OrderType.RECOVER:
			if s.rally_used.has(f):
				return "Sei già stato attivato per un Recupero o una Ritirata in questo turno."
			if s.broken_men_of(f).is_empty() and s.suppressed_men_of(f).is_empty():
				return "Non hai unità rotte o soppresse."
		Domain.OrderType.ROUT:
			if _rout_targets(f).is_empty():
				return "Nessun giocatore con unità rotte può essere bersaglio della Ritirata."
		Domain.OrderType.ARTY:
			var r := radio_of(f)
			if r == null:
				return "Non hai una Radio in gioco."
			if r.efficient and _spotters(f).is_empty():
				return "Serve un comandante efficiente non ancora attivato che faccia da osservatore."
		Domain.OrderType.ARTY_DENIED:
			if radio_of(opp(f)) == null:
				return "Il nemico non ha una Radio in gioco."
	return ""


func _play_order(f: int, c: Card) -> void:
	_discard_from_hand(f, c)
	say("[b]%s: ordine di %s[/b]" % [side_name(f), String(Domain.ORDER_LABELS.get(c.order, "?")).to_upper()], "order", { "card": c, "who": f })
	match c.order:
		Domain.OrderType.MOVE: await _order_move(f)
		Domain.OrderType.FIRE: await _order_fire(f)
		Domain.OrderType.ADVANCE: await _order_advance(f)
		Domain.OrderType.RECOVER: await _order_recover(f)
		Domain.OrderType.ROUT: await _order_rout(f)
		Domain.OrderType.ARTY: await _order_artillery(f)
		Domain.OrderType.ARTY_DENIED: _order_arty_denied(f)
	if over:
		return
	await _melees(f)
	update_objectives()
	check_end()
	await _process_time()


func _discard_turn(f: int) -> void:
	var limit := discard_limit(f)
	var sel: Array = []
	while true:
		var opts: Array = []
		var h := hand(f)
		for i in h.size():
			if sel.has(i) or sel.size() < limit:
				opts.append({ "id": "toggle", "card": i, "on": sel.has(i), "label": "%s carta %d" % ["Tieni" if sel.has(i) else "Scarta", i + 1] })
		opts.append({ "id": "confirm", "label": "Conferma: scarta %d carte" % sel.size() })
		var a := await ask(f, "discard", "Scegli le carte da scartare (massimo %d per i %s), poi conferma." % [limit, side_name(f)],
			opts, { "selected_cards": sel.duplicate() })
		if a.get("id") == "toggle":
			var i := int(a["card"])
			if sel.has(i):
				sel.erase(i)
			else:
				sel.append(i)
		else:
			break
	var cards: Array = []
	for i in sel:
		cards.append(hand(f)[i])
	for c: Card in cards:
		_discard_from_hand(f, c)
	say("%s passano e scartano %d carte." % [side_name(f), cards.size()], "order", { "who": f })
	if cards.is_empty():
		return
	# Reazioni dell'avversario allo scarto: Unità Nascosta (A35.4), Demolizioni (A31).
	var d := opp(f)
	await _hidden_unit(d)
	var dc := find_action(d, "DEMOLIZIONI")
	if dc != null:
		var hexes: Array = []
		for u in men(d):
			var hd: GameState.HexData = s.hex_at(u.q, u.r)
			if hd != null and (hd.has_foxhole or hd.fortification != Domain.Fort.NONE) and not hexes.has(u.pos()):
				hexes.append(u.pos())
		if not hexes.is_empty():
			var opts: Array = []
			for hx: Vector2i in hexes:
				opts.append({ "id": "hex", "hex": hx, "label": "Demolisci la fortificazione in %s" % lbl(hx) })
			opts.append({ "id": "no", "label": "Non giocare Demolizioni" })
			var a := await ask(d, "demolitions", "L'avversario ha scartato: puoi giocare DEMOLIZIONI su una fortificazione in un esagono con una tua unità.", opts, { "card": hand(d).find(dc) })
			if a.get("id") == "hex":
				_discard_from_hand(d, dc)
				var hd2: GameState.HexData = s.hex_at(a["hex"].x, a["hex"].y)
				hd2.has_foxhole = false
				hd2.fortification = Domain.Fort.NONE
				say("Demolizioni: fortificazione in %s eliminata." % lbl(a["hex"]), "order", { "hex": a["hex"] })


# ═══ Tabelle di Supporto ═════════════════════════════════════════════════════

const SUPPORT_PATH := "res://assets/scenarios/support_tables.json"
static var _support: Dictionary = {}


static func support_data() -> Dictionary:
	if _support.is_empty():
		var fa := FileAccess.open(SUPPORT_PATH, FileAccess.READ)
		if fa != null:
			var d: Variant = JSON.parse_string(fa.get_as_text())
			if d is Dictionary:
				_support = d
	return _support


func scenario_year() -> int:
	return int(ScenarioLoader.entry(s.scenario_number).get("anno", 1943))


## Voci della Tabella di Supporto della nazione di `f` nella colonna `roll`,
## disponibili nell'anno dello scenario.
func support_items(f: int, roll_sum: int, with_radio: bool) -> Array:
	var out: Array = []
	var year := scenario_year()
	for it: Dictionary in support_data().get(UnitChart.nation_code(nation(f)), []):
		if String(it.get("tipo", "")) == "radio" and not with_radio:
			continue
		for span in (it.get("col", {}) as Dictionary).get(str(roll_sum), []):
			if year >= int(span[0]) and year <= int(span[1]):
				out.append(it)
				break
	return out


## Tira sulla Tabella di Supporto e fa scegliere una voce. {} se non c'è nulla.
func _support_roll(f: int, why: String, with_radio: bool) -> Dictionary:
	var r := await roll(f, "la Tabella di Supporto (%s)" % why, Callable(), { "no_trigger": true })
	if over:
		return {}
	var items := support_items(f, int(r["sum"]), with_radio)
	if items.is_empty():
		say("   Tabella di Supporto, colonna %d: niente di disponibile nel %d." % [int(r["sum"]), scenario_year()], "fate")
		return {}
	if items.size() == 1:
		return items[0]
	var o: Array = []
	for it: Dictionary in items:
		o.append({ "id": "item", "item": it, "label": String(it["nome"]) })
	var a := await ask(f, "support", "TABELLA DI SUPPORTO · colonna %d, anno %d: scegli che cosa ricevere." % [int(r["sum"]), scenario_year()], o, {})
	return a.get("item", items[0])


## Crea in `h` l'unità (con la sua arma) descritta da una voce di supporto.
func _spawn_support(f: int, it: Dictionary, h: Vector2i) -> Unit:
	var nat := UnitChart.nation_code(nation(f))
	_team_seq += 1
	var id := "S-%s-%d" % [Domain.FACTION_SHORT.get(f, "U"), _team_seq]
	var u: Unit
	if String(it["tipo"]) == "team" and String(it["unita"]) != "Weapon Team":
		u = make_team(f, "Elite", h.x, h.y)
	else:
		u = UnitChart.build_unit(id, f, String(it["unita"]), h.x, h.y, nat)
		s.units[id] = u
		UnitChart.apply_broken_side(u, nat)
	var wl := String(it.get("arma", ""))
	if wl != "":
		var w: Unit
		if wl == "Flamethrower" or wl == "Satchel Charge":
			w = UnitChart._mk(id + "-W", f, Domain.UnitType.WEAPON, Domain.UnitClass.MG,
				"Lanciafiamme" if wl == "Flamethrower" else "Carica esplosiva")
			w.fp = 11 if wl == "Flamethrower" else 12
			w.range = 1
			w.q = h.x
			w.r = h.y
		else:
			w = UnitChart.build_unit(id + "-W", f, wl, h.x, h.y, nat)
		w.carrier_id = u.id
		s.units[w.id] = w
	return u


## Zona di schieramento originale del lato `f` (dalla scheda scenario).
func setup_area(f: int) -> Array:
	var e := ScenarioLoader.entry(s.scenario_number)
	if e.is_empty():
		return []
	return ScenarioLoader._setup_hexes(s, e, "axis" if f == AX else "allies")


## Unità Nascosta (A35.4): solo il Difensore, quando l'avversario scarta.
func _hidden_unit(d: int) -> void:
	if over or not is_defender(d):
		return
	var c := find_action(d, "UNITA' NASCOSTA")
	if c == null:
		return
	var spots: Array = []
	for h: Vector2i in setup_area(d):
		if s.units_at(h.x, h.y).is_empty() and Rules.cover_at(s, h.x, h.y, false) >= 1 \
				and int(Domain.TERRAIN_MOVE_COST.get(s.hex_at(h.x, h.y).terrain, 1)) < 99:
			spots.append(h)
	if spots.is_empty():
		return
	var a := await ask(d, "hidden_unit", "L'avversario ha scartato: giochi UNITA' NASCOSTA? Tiri sulla Tabella di Supporto e fai comparire un'unità nella tua zona di schieramento, in un esagono vuoto con copertura.",
		[{ "id": "play", "card": hand(d).find(c), "label": "Gioca Unità Nascosta" }, { "id": "no", "label": "No" }], {})
	if a.get("id") != "play":
		return
	_discard_from_hand(d, c)
	say("[b]%s: Unità Nascosta![/b]" % side_name(d), "order", { "card": c, "who": d })
	var it := await _support_roll(d, "Unità Nascosta", false)
	if it.is_empty() or over:
		return
	var o: Array = []
	for h: Vector2i in spots:
		o.append({ "id": "hex", "hex": h, "label": lbl(h) })
	var b := await ask(d, "place_unit", "UNITA' NASCOSTA · %s: scegli l'esagono (vuoto, con copertura, nella tua zona) in cui farla comparire." % String(it["nome"]), o, {})
	var h2: Vector2i = b.get("hex", spots[0])
	_spawn_support(d, it, h2)
	say("Compare %s in %s." % [String(it["nome"]), lbl(h2)], "good", { "hex": h2, "who": d })
	update_objectives()


## Esagoni dentro/adiacenti a `c` dove un'unità di `icons` figure può stare.
func _placeable_around(c: Vector2i, f: int, icons: int) -> Array:
	var out: Array = []
	var area: Array = [c]
	area.append_array(HexGrid.neighbors(c.x, c.y))
	for h: Vector2i in area:
		if not in_map(h):
			continue
		var hd: GameState.HexData = s.hex_at(h.x, h.y)
		if hd == null or hd.has_blaze or int(Domain.TERRAIN_MOVE_COST.get(hd.terrain, 1)) >= 99:
			continue
		var n := 0
		for m in s.men_at(h.x, h.y):
			if m.faction == f:
				n += m.soldier_icons()
		if n + icons <= 7:
			out.append(h)
	return out


func _refill(f: int) -> void:
	while not over and hand(f).size() < s.hand_size_of(f):
		var d := deck(f)
		if d.is_empty():
			_reshuffle(f)
			if d.is_empty():
				break
		hand(f).append(d.pop_back())
		if d.is_empty() and not _pending_time.has(f):
			_pending_time.append(f)
			say("%s: mazzo esaurito — il Tempo avanza." % side_name(f), "time")
			await _process_time()


## Sovraccarico (8.2): a fine turno ogni esagono con più di 7 figure perde unità.
func _overstack(f: int) -> void:
	var by_hex := {}
	for u in men(f):
		var k := u.hex_key()
		if not by_hex.has(k):
			by_hex[k] = []
		by_hex[k].append(u)
	for k in by_hex:
		var stack: Array = by_hex[k]
		var total := 0
		for u: Unit in stack:
			total += u.soldier_icons()
		while total > 7 and not stack.is_empty():
			stack.sort_custom(func(a: Unit, b: Unit) -> bool:
				if a.efficient != b.efficient:
					return not a.efficient
				return a.soldier_icons() < b.soldier_icons())
			var v: Unit = null
			for u: Unit in stack:
				if u.soldier_icons() >= total - 7:
					v = u
					break
			if v == null:
				v = stack[stack.size() - 1]
			stack.erase(v)
			total -= v.soldier_icons()
			kill(v, "sovraccarico: più di 7 figure nell'esagono a fine turno")


# ═══ Attivazione (O14.1) ═════════════════════════════════════════════════════

## Seguaci che un comandante può attivare: uomini non-leader, non ancora
## attivati, entro il suo raggio di Comando.
func followers_of(L: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	if not L.is_leader() or L.command <= 0:
		return out
	for u in men(L.faction):
		if u.id != L.id and not u.is_leader() and not u.activated \
				and HexGrid.distance(L.q, L.r, u.q, u.r) <= L.command:
			out.append(u)
	return out


## L'unità può fare qualcosa di utile con quell'ordine? (`th` = esagono
## bersaglio obbligato per il Fuoco di Opportunità, altrimenti (-1,-1).)
func useful(u: Unit, order: int, th: Vector2i = Vector2i(-1, -1)) -> bool:
	match order:
		Domain.OrderType.MOVE:
			var left := Rules.move_allowance(s, u)
			for nb in HexGrid.neighbors(u.q, u.r):
				if step_cost(u, nb, left, 0) >= 0:
					return true
			return left >= 1 and at_edge(opp(u.faction), u.pos())
		Domain.OrderType.ADVANCE:
			for nb in HexGrid.neighbors(u.q, u.r):
				if can_advance(u, nb):
					return true
			return at_edge(opp(u.faction), u.pos())
		Domain.OrderType.FIRE:
			for p in pieces_of(u):
				if th.x >= 0:
					if not p.ordnance and can_hit(p, th):
						return true
				elif not targets_of(p).is_empty():
					return true
	return false


func activation_options(f: int, order: int, th: Vector2i = Vector2i(-1, -1)) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in men(f):
		if u.activated:
			continue
		if useful(u, order, th):
			out.append(u)
		elif u.is_leader():
			for fo in followers_of(u):
				if useful(fo, order, th):
					out.append(u)
					break
	return out


func _choose_activation(f: int, order: int, th: Vector2i = Vector2i(-1, -1)) -> Array[Unit]:
	var cands := activation_options(f, order, th)
	var group: Array[Unit] = []
	if cands.is_empty():
		return group
	var oname := String(Domain.ORDER_LABELS.get(order, "?")).to_upper()
	if th.x >= 0:
		oname = "FUOCO DI OPPORTUNITÀ"
	var opts: Array = []
	for u in cands:
		var n := followers_of(u).size()
		opts.append({ "id": "unit", "unit": u.id,
			"label": ("%s — COMANDANTE: può attivare altre %d unità" % [uname(u), n]) if n > 0 else uname(u) })
	var a := await ask(f, "activate",
		"%s · passo 1: scegli CHI ATTIVARE. Un comandante (bordo dorato) attiva anche gli uomini entro il suo raggio di Comando; ogni altra unità si attiva da sola." % oname,
		opts, { "order": order })
	var lead: Unit = s.unit_by_id(String(a.get("unit", "")))
	if lead == null:
		return group
	group.append(lead)
	var fol := followers_of(lead)
	if not fol.is_empty():
		var sel: Array = []
		for u in fol:
			if useful(u, order, th):
				sel.append(u.id)
		while true:
			var o2: Array = []
			for u in fol:
				o2.append({ "id": "toggle", "unit": u.id, "on": sel.has(u.id),
					"label": "%s %s" % ["Escludi" if sel.has(u.id) else "Includi", uname(u)] })
			o2.append({ "id": "confirm", "label": "Conferma: %s + %d unità" % [lead.unit_name, sel.size()] })
			var b := await ask(f, "group",
				"%s · passo 2: %s comanda entro un raggio di %d. Tocca gli uomini per includerli o escluderli, poi CONFERMA." % [oname, lead.unit_name, lead.command],
				o2, { "leader": lead.id, "radius": lead.command, "selected": sel.duplicate(), "order": order })
			if b.get("id") == "toggle":
				var id := String(b["unit"])
				if sel.has(id):
					sel.erase(id)
				else:
					sel.append(id)
			else:
				break
		for u in fol:
			if sel.has(u.id):
				group.append(u)
	var names: Array = []
	for u in group:
		u.activated = true
		names.append(u.unit_name)
	say("Attivati: %s." % ", ".join(names), "order", { "units": group.map(func(x: Unit) -> String: return x.id), "who": f })
	return group


# ═══ MOSSA (O21) ═════════════════════════════════════════════════════════════

## Costo in PM per entrare in `to` (−1 se non si può). `left` = PM rimasti,
## `spent` = PM già spesi in questa Mossa.
func step_cost(u: Unit, to: Vector2i, left: int, spent: int) -> int:
	if not in_map(to):
		return -1
	var c := HexGrid.step_cost(s, u.q, u.r, to.x, to.y)
	if c < 0:
		return -1
	for m in s.men_at(to.x, to.y):
		if m.faction != u.faction:
			return -1
	var here: GameState.HexData = s.hex_at(u.q, u.r)
	if here != null and here.fortification == Domain.Fort.WIRE:
		# F106: uscire dal Filo costa TUTTI i PM (quindi solo come primo passo).
		if spent > 0 or left < c:
			return -1
		return left
	return c if c <= left else -1


func _order_move(f: int) -> void:
	_opfire_ids.clear()
	var group := await _choose_activation(f, Domain.OrderType.MOVE)
	_moving_ids.clear()
	for u in group:
		_moving_ids.append(u.id)
	var todo: Array = _moving_ids.duplicate()
	var moved_any := false
	while not over and not todo.is_empty():
		var opts: Array = []
		for id in todo:
			var u: Unit = s.unit_by_id(id)
			if u != null and useful(u, Domain.OrderType.MOVE):
				opts.append({ "id": "unit", "unit": id, "label": "Muovi %s (%d PM)" % [uname(u), Rules.move_allowance(s, u)] })
		if opts.is_empty():
			break
		var u2: Unit = null
		if opts.size() == 1 and not moved_any:
			u2 = s.unit_by_id(String(opts[0]["unit"]))
		else:
			if moved_any:
				opts.append({ "id": "end", "label": "Termina la Mossa" })
			var a := await ask(f, "pick_mover", "MOSSA · scegli quale unità attivata muove adesso.", opts, { "order": Domain.OrderType.MOVE })
			if a.get("id") != "unit":
				break
			u2 = s.unit_by_id(String(a["unit"]))
		todo.erase(u2.id)
		# O21.2: le unità attivate che partono dallo stesso esagono possono
		# muovere insieme, restando unite per tutta la Mossa.
		var stack: Array = [u2]
		var mates: Array = []
		for id in todo:
			var m: Unit = s.unit_by_id(id)
			if m != null and m.pos() == u2.pos():
				mates.append(m)
		if not mates.is_empty():
			var sel: Array = mates.map(func(x: Unit) -> String: return x.id)
			while true:
				var o2: Array = []
				for m: Unit in mates:
					o2.append({ "id": "toggle", "unit": m.id, "on": sel.has(m.id),
						"label": "%s %s" % ["Lascia indietro" if sel.has(m.id) else "Porta anche", uname(m)] })
				o2.append({ "id": "confirm", "label": ("Muovi %s da sola" % u2.unit_name) if sel.is_empty() else ("Muovi insieme: %s + %d" % [u2.unit_name, sel.size()]) })
				var b := await ask(f, "move_together",
					"MOSSA · nello stesso esagono ci sono altre unità attivate: possono MUOVERE INSIEME a %s (restano unite e vanno al passo della più lenta)." % u2.unit_name,
					o2, { "unit": u2.id, "selected": sel.duplicate() })
				if b.get("id") == "toggle":
					var id2 := String(b["unit"])
					if sel.has(id2):
						sel.erase(id2)
					else:
						sel.append(id2)
				else:
					break
			for m: Unit in mates:
				if sel.has(m.id):
					stack.append(m)
					todo.erase(m.id)
		if await _move_stack(f, stack):
			moved_any = true
	_moving_ids.clear()
	_opfire_ids.clear()


## Muove un'unità (o un gruppo che resta unito) un esagono alla volta.
## Ritorna true se ha attraversato almeno un lato.
func _move_stack(f: int, stack: Array) -> bool:
	var spent := 0
	var moved := false
	var road_bonus := 0
	while not over:
		stack = stack.filter(func(x: Unit) -> bool: return s.units.has(x.id))
		if stack.is_empty():
			break
		var u: Unit = stack[0]
		# Il gruppo va al passo dell'unità più lenta.
		var left := 99
		for m: Unit in stack:
			left = mini(left, Rules.move_allowance(s, m) + road_bonus - spent)
		var opts: Array = []
		for nb in HexGrid.neighbors(u.q, u.r):
			var c := -1
			for m: Unit in stack:
				var cm := step_cost(m, nb, left, spent)
				if cm < 0:
					c = -1
					break
				c = maxi(c, cm)
			if c >= 0:
				opts.append({ "id": "step", "hex": nb, "cost": c, "label": "%s (%d PM)" % [lbl(nb), c] })
		if left >= 1 and at_edge(opp(f), u.pos()):
			var v := 0
			for m: Unit in stack:
				v += GameState.elimination_vp(m) * (2 if s.chit_double_exit else 1)
			opts.append({ "id": "exit", "label": "Esci dalla mappa (+%d PV)" % v })
		var sg := find_action(f, "GRANATE FUMOGENE")
		if sg != null:
			for m: Unit in stack:
				if m.move_boxed:
					opts.append({ "id": "smoke", "card": hand(f).find(sg), "by": m.id, "label": "Azione: Granate Fumogene" })
					break
		var af := find_action(f, "FUOCO D'ASSALTO")
		if af != null and not _assault_pieces(u).is_empty():
			opts.append({ "id": "assault", "card": hand(f).find(af), "label": "Azione: Fuoco d'Assalto" })
		if opts.is_empty():
			break
		var who := u.unit_name
		if stack.size() == 2:
			who = "%s con %s" % [u.unit_name, (stack[1] as Unit).unit_name]
		elif stack.size() > 2:
			who = "%s con altre %d unità" % [u.unit_name, stack.size() - 1]
		opts.append({ "id": "stop", "label": "Ferma qui %s" % who })
		var a := await ask(f, "move", "MOSSA · %s: %d PM rimasti. Tocca un esagono adiacente evidenziato per avanzare di un passo." % [who, maxi(left, 0)],
			opts, { "unit": u.id, "left": left, "selected": stack.map(func(x: Unit) -> String: return x.id) })
		match String(a.get("id", "stop")):
			"step":
				var to: Vector2i = a["hex"]
				var from := u.pos()
				spent += int(a["cost"])
				for m: Unit in stack:
					s.set_unit_pos(m, to.x, to.y)
				moved = true
				# T93: +1 al Movimento da quando si entra in un esagono con Strada.
				if road_bonus == 0 and s.hex_at(to.x, to.y).has_road:
					road_bonus = 1
				say("%s muove in %s (%d PM spesi)." % [who, lbl(to), spent], "move", { "unit": u.id, "from": from, "to": to, "who": f })
				update_objectives()
				for m: Unit in stack:
					if s.units.has(m.id):
						await _mines_on(m, from, to)
				var alive: Array = stack.filter(func(x: Unit) -> bool: return s.units.has(x.id))
				if not alive.is_empty():
					await _react_to_entry(f, alive, to, "move")
				check_end()
				await _process_time()
			"exit":
				for m: Unit in stack:
					if s.units.has(m.id):
						_exit_unit(f, m)
				return true
			"smoke":
				await _smoke_grenades(f, s.unit_by_id(String(a.get("by", u.id))), hand(f)[int(a["card"])])
			"assault":
				await _assault_fire(f, u, hand(f)[int(a["card"])])
			_:
				break
	return moved


func _exit_unit(f: int, u: Unit) -> void:
	var from := u.pos()
	var nm := u.unit_name
	var v := s.exit_unit_for_vp(u.id)
	_moving_ids.erase(u.id)
	say("%s esce dalla mappa: +%d PV ai %s. Rientrerà come rinforzo." % [nm, v, side_name(f)], "vp", { "hex": from, "who": f })
	update_objectives()
	if s.men_of(f).is_empty():
		_finish_on_points("L'ultima unità dei %s ha lasciato la mappa." % side_name(f))


func _smoke_grenades(f: int, u: Unit, c: Card) -> void:
	var opts: Array = []
	var around: Array = [u.pos()]
	around.append_array(HexGrid.neighbors(u.q, u.r))
	for h: Vector2i in around:
		var hd: GameState.HexData = s.hex_at(h.x, h.y)
		if hd != null and not hd.has_blaze and not Rules.is_water_hex(s, h.x, h.y):
			opts.append({ "id": "hex", "hex": h, "label": "Fumo in %s" % lbl(h) })
	opts.append({ "id": "no", "label": "Annulla" })
	var a := await ask(f, "smoke", "GRANATE FUMOGENE: scegli dove mettere il fumo (esagono dell'unità o adiacente).", opts, { "unit": u.id })
	if a.get("id") != "hex":
		return
	_discard_from_hand(f, c)
	s.hex_at(a["hex"].x, a["hex"].y).has_smoke = true
	say("%s lancia Granate Fumogene in %s." % [u.unit_name, lbl(a["hex"])], "order", { "hex": a["hex"], "fx": "smoke", "who": f })


func _assault_pieces(u: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	for id in _moving_ids:
		var m: Unit = s.unit_by_id(id)
		if m == null:
			continue
		for p in pieces_of(m):
			if p.fp_boxed and not targets_of(p).is_empty():
				out.append(p)
	return out


func _assault_fire(f: int, _u: Unit, c: Card) -> void:
	var pool := _assault_pieces(_u)
	if pool.is_empty():
		return
	_discard_from_hand(f, c)
	say("%s giocano Fuoco d'Assalto." % side_name(f), "order", { "who": f })
	await _fire_once(f, pool, Vector2i(-1, -1), {})


## Attacco delle Mine (F103): 6 FP contro Morale, copertura 0, a chi entra o esce.
func _mines_on(u: Unit, from: Vector2i, to: Vector2i) -> void:
	for h: Vector2i in [from, to]:
		var hd: GameState.HexData = s.hex_at(h.x, h.y)
		if hd == null or hd.fortification != Domain.Fort.MINES or not s.units.has(u.id):
			continue
		await _mine_attack(u, h)


func _mine_attack(u: Unit, h: Vector2i) -> void:
	var own := u.faction
	var atk := await roll(opp(own), "l'attacco delle Mine in %s" % lbl(h), func(t: int) -> int: return own if t >= 8 else -1)
	if not s.units.has(u.id):
		return
	var total: int = 6 + int(atk["sum"])
	var m := morale_of(u)
	var dr := await roll(own, "la difesa di %s dalle Mine" % u.unit_name,
		func(t: int) -> int: return own if m + t <= total else opp(own))
	if not s.units.has(u.id):
		return
	var dt: int = m + int(dr["sum"])
	if dt < total:
		await hit(u, "Mine (%d contro %d)" % [total, dt])
	elif dt == total:
		await hit(u, "Mine (pari, in movimento)")
	else:
		say("%s supera le Mine (%d contro %d)." % [u.unit_name, dt, total], "good")


## Finestra di reazione dell'avversario dopo che `units` sono entrate in `h`.
func _react_to_entry(f: int, units: Array, h: Vector2i, kind: String) -> void:
	var d := opp(f)
	var fired := false
	while not over:
		var alive: Array = units.filter(func(x: Unit) -> bool: return s.units.has(x.id) and x.pos() == h)
		if alive.is_empty():
			return
		var hd: GameState.HexData = s.hex_at(h.x, h.y)
		var opts: Array = []
		if is_defender(d) and not hd.has_foxhole and hd.fortification == Domain.Fort.NONE and not Rules.is_water_hex(s, h.x, h.y):
			var mc := find_action(d, "MINE NASCOSTE")
			if mc != null:
				opts.append({ "id": "mines", "card": hand(d).find(mc), "label": "Azione: Mine Nascoste in %s" % lbl(h) })
			var wc := find_action(d, "FILO SPINATO NASCOSTO")
			if wc != null:
				opts.append({ "id": "wire", "card": hand(d).find(wc), "label": "Azione: Filo Spinato Nascosto in %s" % lbl(h) })
		if kind == "move" and not fired:
			if not _opfire_ready(d, h).is_empty():
				opts.append({ "id": "opfire", "label": "Fuoco di Opportunità (unità già attivate, gratis)" })
			var fc := find_order(d, Domain.OrderType.FIRE)
			if fc != null and not activation_options(d, Domain.OrderType.FIRE, h).is_empty():
				opts.append({ "id": "opfire_card", "card": hand(d).find(fc), "label": "Gioca FUOCO: Fuoco di Opportunità" })
		if opts.is_empty():
			return
		opts.append({ "id": "pass", "label": "Lascia passare" })
		var a := await ask(d, "react", "REAZIONE · %s entra in %s. Vuoi reagire?" % [alive[0].unit_name, lbl(h)],
			opts, { "hex": h, "unit": alive[0].id })
		match String(a.get("id", "pass")):
			"mines":
				_discard_from_hand(d, hand(d)[int(a["card"])])
				hd.fortification = Domain.Fort.MINES
				say("[b]Mine Nascoste![/b] Campo minato in %s." % lbl(h), "bad", { "hex": h, "who": d })
				for u: Unit in alive:
					if s.units.has(u.id):
						await _mine_attack(u, h)
			"wire":
				_discard_from_hand(d, hand(d)[int(a["card"])])
				hd.fortification = Domain.Fort.WIRE
				say("[b]Filo Spinato Nascosto![/b] Reticolati in %s." % lbl(h), "bad", { "hex": h, "who": d })
			"opfire_card":
				_discard_from_hand(d, hand(d)[int(a["card"])])
				say("[b]%s: Fuoco di Opportunità![/b]" % side_name(d), "order", { "who": d })
				var g := await _choose_activation(d, Domain.OrderType.FIRE, h)
				for u in g:
					_opfire_ids.append(u.id)
				await _fire_once(d, _opfire_ready(d, h), h, { "opfire": true })
				fired = true
			"opfire":
				await _fire_once(d, _opfire_ready(d, h), h, { "opfire": true })
				fired = true
			_:
				return
		check_end()


## Pezzi (unità/armi non ordnance) già attivati per l'Op Fire che vedono `h`.
func _opfire_ready(d: int, h: Vector2i) -> Array[Unit]:
	var out: Array[Unit] = []
	for id in _opfire_ids:
		var u: Unit = s.unit_by_id(id)
		if u == null or u.faction != d:
			continue
		for p in pieces_of(u):
			if not p.ordnance and can_hit(p, h):
				out.append(p)
	return out


# ═══ FUOCO (O20) ═════════════════════════════════════════════════════════════

## «Pezzi» con cui un'unità può sparare: sé stessa (se ha FP) e la sua arma.
func pieces_of(u: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	if u == null or not s.units.has(u.id):
		return out
	if u.is_man() and u.fp > 0:
		out.append(u)
	var w := s.weapon_carried_by(u.id)
	if w != null and not is_radio(w) and w.efficient and Rules.weapon_usable(s, w):
		out.append(w)
	return out


func hindrance(p: Unit, h: Vector2i) -> int:
	return HexGrid.los_hindrance(p.q, p.r, h.x, h.y, s) + maxi(0, s.global_hindrance)


func enemy_in(h: Vector2i, f: int) -> bool:
	for m in s.men_at(h.x, h.y):
		if m.faction != f:
			return true
	return false


## Il pezzo può sparare all'esagono `h`? (gittata, linea di vista, nemici, FP≥1)
func can_hit(p: Unit, h: Vector2i) -> bool:
	if p == null or not s.units.has(p.id) or not in_map(h):
		return false
	var d := HexGrid.distance(p.q, p.r, h.x, h.y)
	if d < 1 or d < p.min_range or d > Rules.range_with_command(s, p):
		return false
	if not enemy_in(h, p.faction):
		return false
	if p.is_weapon():
		if not p.efficient or not Rules.weapon_usable(s, p):
			return false
	elif p.fp <= 0:
		return false
	if not HexGrid.has_los(p.q, p.r, h.x, h.y, s):
		return false
	if not p.ordnance and Rules.fp_with_command(s, p) - hindrance(p, h) < 1:
		return false
	return true


func targets_of(p: Unit) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen := {}
	for e in s.units.values():
		if e.faction == p.faction or not e.is_man() or seen.has(e.hex_key()):
			continue
		seen[e.hex_key()] = true
		if can_hit(p, e.pos()):
			out.append(e.pos())
	return out


## FP di un gruppo di fuoco contro `h` (O20.3.1.2): il pezzo migliore + 1 per
## ogni altro pezzo, meno l'ostacolo più grande lungo le linee di vista.
func group_fp(pieces: Array, h: Vector2i) -> int:
	if pieces.is_empty():
		return 0
	var best := -99
	var hind := 0
	for p: Unit in pieces:
		best = maxi(best, Rules.fp_with_command(s, p))
		if not p.ordnance:
			hind = maxi(hind, hindrance(p, h))
	return best + pieces.size() - 1 - hind + height_mod(pieces, h)


## Vantaggio d'altura (T88.2): −1 FP se il bersaglio è più in alto di un pezzo
## che spara, +1 se è più in basso di un pezzo che spara.
func height_mod(pieces: Array, h: Vector2i) -> int:
	var te := HexGrid.elev_of(s, h.x, h.y)
	var mod := 0
	for p: Unit in pieces:
		var pe := HexGrid.elev_of(s, p.q, p.r)
		if te > pe:
			return -1
		if te < pe:
			mod = 1
	return mod


## Tiene solo i pezzi i cui esagoni formano una catena di adiacenza col pezzo
## più forte (O20.3.1).
func _chain(pieces: Array) -> Array:
	if pieces.size() <= 1:
		return pieces
	var best: Unit = pieces[0]
	for p: Unit in pieces:
		if Rules.fp_with_command(s, p) > Rules.fp_with_command(s, best):
			best = p
	var hexes := { best.hex_key(): best.pos() }
	var grown := true
	while grown:
		grown = false
		for p: Unit in pieces:
			if hexes.has(p.hex_key()):
				continue
			for k in hexes.keys():
				var hx: Vector2i = hexes[k]
				if HexGrid.distance(hx.x, hx.y, p.q, p.r) <= 1:
					hexes[p.hex_key()] = p.pos()
					grown = true
					break
	return pieces.filter(func(p: Unit) -> bool: return hexes.has(p.hex_key()))


func piece_label(p: Unit) -> String:
	if p.is_weapon():
		var c := s.unit_by_id(p.carrier_id)
		return "%s di %s (FP %d)" % [p.unit_name, c.unit_name if c != null else "?", Rules.fp_with_command(s, p)]
	return "%s (FP %d)" % [uname(p), Rules.fp_with_command(s, p)]


func _choose_group(f: int, pool: Array, h: Vector2i) -> Array:
	var norm: Array = []
	var ords: Array = []
	for p: Unit in pool:
		if can_hit(p, h):
			if p.ordnance:
				ords.append(p)
			else:
				norm.append(p)
	if norm.is_empty() and ords.is_empty():
		return []
	if norm.size() + ords.size() == 1:
		return norm if ords.is_empty() else ords
	var sel: Array = _chain(norm).map(func(p: Unit) -> String: return p.id)
	while true:
		var opts: Array = []
		for p: Unit in norm:
			opts.append({ "id": "toggle", "unit": p.id, "piece": true, "on": sel.has(p.id),
				"label": "%s %s" % ["Togli" if sel.has(p.id) else "Aggiungi", piece_label(p)] })
		for p: Unit in ords:
			opts.append({ "id": "ordnance", "unit": p.id, "piece": true, "label": "Spara da solo: %s (deve prima colpire)" % piece_label(p) })
		var cur: Array = _chain(norm.filter(func(p: Unit) -> bool: return sel.has(p.id)))
		var fp := group_fp(cur, h)
		if not cur.is_empty() and fp >= 1:
			opts.append({ "id": "confirm", "label": "FUOCO! %d pezzi, FP %d" % [cur.size(), fp] })
		var a := await ask(f, "fire_group",
			"FUOCO su %s · componi il GRUPPO DI FUOCO: il pezzo più forte dà il suo FP, ogni altro aggiunge +1. Poi conferma." % lbl(h),
			opts, { "hex": h, "selected": sel.duplicate(), "fp": fp })
		match String(a.get("id", "")):
			"toggle":
				var id := String(a["unit"])
				if sel.has(id):
					sel.erase(id)
				else:
					sel.append(id)
			"ordnance":
				return [s.unit_by_id(String(a["unit"]))]
			_:
				return cur
	return []


## Un attacco di fuoco: scelta del bersaglio (se `th` non è fissato), del
## gruppo, poi risoluzione. Ritorna i pezzi che hanno sparato ([] = rinuncia).
func _fire_once(f: int, pool: Array, th: Vector2i, opts: Dictionary) -> Array:
	var h := th
	if h.x < 0:
		var hexes := {}
		for p: Unit in pool:
			for t in targets_of(p):
				hexes[t] = true
		if hexes.is_empty():
			return []
		var o: Array = []
		for t: Vector2i in hexes.keys():
			var grp: Array = []
			for p: Unit in pool:
				if can_hit(p, t) and not p.ordnance:
					grp.append(p)
			grp = _chain(grp)
			var cov := Rules.cover_at(s, t.x, t.y, false)
			var ofp := group_fp(grp, t)
			if grp.is_empty():
				for p: Unit in pool:
					if p.ordnance and can_hit(p, t):
						ofp = maxi(ofp, p.fp)
			o.append({ "id": "hex", "hex": t, "fp": ofp,
				"label": "%s — %s, copertura %+d" % [lbl(t), ("FP %d" % group_fp(grp, t)) if not grp.is_empty() else "solo armi a tiro curvo", cov] })
		if opts.get("can_end", false):
			o.append({ "id": "end", "label": "Termina il Fuoco" })
		var a := await ask(f, "fire_target", "FUOCO · scegli l'esagono BERSAGLIO fra quelli evidenziati in rosso.", o, {})
		if a.get("id") != "hex":
			return []
		h = a["hex"]
	var grp2 := await _choose_group(f, pool, h)
	if grp2.is_empty():
		return []
	await _fire_attack(f, grp2, h, opts)
	return grp2


func _order_fire(f: int) -> void:
	var group := await _choose_activation(f, Domain.OrderType.FIRE)
	var pool: Array = []
	for u in group:
		pool.append_array(pieces_of(u))
	var first := true
	while not over:
		pool = pool.filter(func(p: Unit) -> bool: return s.units.has(p.id) and not targets_of(p).is_empty())
		if pool.is_empty():
			break
		var used := await _fire_once(f, pool, Vector2i(-1, -1), { "can_end": not first })
		if used.is_empty():
			break
		for p in used:
			pool.erase(p)
		first = false


func _fire_mods(f: int, pieces: Array, hexes: Array, opts: Dictionary) -> Array:
	var out: Array = []
	var h: Vector2i = hexes[0]
	var has_mg := false
	var has_squad := false
	var adjacent := false
	var boxed_range := true
	var big_weapon := false
	for p: Unit in pieces:
		if p.is_weapon() and (p.unit_class == Domain.UnitClass.MG or p.unit_class == Domain.UnitClass.MORTAR):
			has_mg = true
		if p.is_weapon() and p.fp >= 5:
			big_weapon = true
		if p.type == Domain.UnitType.SQUAD or p.type == Domain.UnitType.TEAM:
			has_squad = true
		if HexGrid.distance(p.q, p.r, h.x, h.y) == 1:
			adjacent = true
		if not p.range_boxed:
			boxed_range = false
	var moving_target := false
	for m in s.men_at(h.x, h.y):
		if _moving_ids.has(m.id):
			moving_target = true
	var hd := hand(f)
	for i in hd.size():
		var c: Card = hd[i]
		match c.action_name:
			"FUOCO SOSTENUTO":
				if has_mg:
					out.append({ "id": "sustained", "card": i, "label": "Azione: Fuoco Sostenuto (+2; con un doppio l'arma si guasta)" })
			"FUOCO MIRATO":
				if has_squad:
					out.append({ "id": "plus2", "card": i, "label": "Azione: Fuoco Mirato (+2)" })
			"BOMBE A MANO":
				if adjacent:
					out.append({ "id": "plus2", "card": i, "label": "Azione: Bombe a Mano (+2)" })
			"FUOCO INCROCIATO":
				if moving_target:
					out.append({ "id": "plus2", "card": i, "label": "Azione: Fuoco Incrociato (+2 su unità in movimento)" })
			"BUONA MIRA":
				if is_defender(f) and big_weapon:
					out.append({ "id": "plus2", "card": i, "label": "Azione: Buona Mira (+2)" })
			"SVENTAGLIATA DI FUOCO":
				if hexes.size() == 1 and boxed_range:
					for nb in HexGrid.neighbors(h.x, h.y):
						if not in_map(nb) or not enemy_in(nb, f):
							continue
						var all_ok := true
						for p: Unit in pieces:
							if not can_hit(p, nb):
								all_ok = false
						if all_ok:
							out.append({ "id": "spray", "card": i, "hex": nb, "label": "Azione: Sventagliata — colpisci anche %s" % lbl(nb) })
	return out


## Risoluzione completa di un attacco di fuoco (O20.2–O20.3.4).
func _fire_attack(f: int, pieces: Array, h: Vector2i, opts: Dictionary) -> void:
	var d := opp(f)
	var lead: Unit = pieces[0]
	var names: Array = pieces.map(func(p: Unit) -> String: return p.unit_name)
	var from := lead.pos()
	say("%s fa fuoco su %s con %s." % [side_name(f), lbl(h), ", ".join(names)], "fire",
		{ "from": from, "to": h, "who": f, "fx": "fire", "pieces": pieces.map(func(p: Unit) -> String: return p.id) })
	if lead.ordnance:
		var dist := HexGrid.distance(lead.q, lead.r, h.x, h.y)
		var hind := hindrance(lead, h)
		var need := dist + hind
		var tr := await roll(f, "colpire il bersaglio (serve più di %d)" % need,
			func(t: int) -> int: return f if t <= need else d, { "product": true })
		if over:
			return
		if int(tr["sum"]) <= need:
			say("%s manca il bersaglio." % lead.unit_name, "miss")
			return
		say("%s è sul bersaglio!" % lead.unit_name, "fire")
	var fp := group_fp(pieces, h)
	var bonus := 0
	var hexes: Array = [h]
	var sustained := false
	while not over:
		var o := _fire_mods(f, pieces, hexes, opts)
		if o.is_empty():
			break
		o.append({ "id": "go", "label": "Tira i dadi (FP %d)" % (fp + bonus) })
		var a := await ask(f, "fire_mods", "FUOCO su %s · FP %d. Puoi rinforzare l'attacco con un'AZIONE dalla mano, poi tira i dadi." % [lbl(h), fp + bonus],
			o, { "hex": h, "fp": fp + bonus })
		if a.get("id", "go") == "go":
			break
		var c: Card = hand(f)[int(a["card"])]
		_discard_from_hand(f, c)
		match String(a["id"]):
			"spray":
				hexes.append(a["hex"])
				say("Azione: Sventagliata di Fuoco — colpito anche %s." % lbl(a["hex"]), "order", { "card": c, "who": f })
			"sustained":
				sustained = true
				bonus += 2
				say("Azione: Fuoco Sostenuto (+2).", "order", { "card": c, "who": f })
			_:
				bonus += 2
				say("Azione: %s (+2)." % c.action_name.capitalize(), "order", { "card": c, "who": f })
	if over:
		return
	if fp + bonus < 1:
		say("Il fuoco è troppo ostacolato: nessun attacco.", "miss")
		return
	var weapons: Array = pieces.filter(func(p: Unit) -> bool: return p.is_weapon())
	var ar := await roll(f, "l'attacco (FP %d)" % (fp + bonus),
		func(t: int) -> int: return d if t >= 9 else (f if t <= 5 else -1), { "fire_weapons": weapons })
	if over:
		return
	var total: int = fp + bonus + int(ar["sum"])
	if sustained and int(ar["a"]) == int(ar["b"]):
		for w: Unit in weapons:
			if w.unit_class == Domain.UnitClass.MG or w.unit_class == Domain.UnitClass.MORTAR:
				_break_weapon(w, "Fuoco Sostenuto con un doppio")
				break
	say("Totale d'attacco: [b]%d[/b]." % total, "fire")
	total = await _defense_actions(d, hexes, total, lead.ordnance)
	for hx: Vector2i in hexes:
		await _defend_hex(f, d, hx, total, lead.ordnance, opts.get("opfire", false))
	update_objectives()
	check_end()


## Tiri di difesa (O20.3.4) di tutte le unità del lato `d` nell'esagono.
func _defend_hex(f: int, d: int, hx: Vector2i, total: int, vs_ord: bool, vs_movers: bool, both_sides: bool = false) -> void:
	var targets: Array = s.men_at(hx.x, hx.y).filter(func(m: Unit) -> bool: return both_sides or m.faction == d)
	targets.sort_custom(func(a: Unit, b: Unit) -> bool: return (1 if a.is_leader() else 0) < (1 if b.is_leader() else 0))
	for t: Unit in targets:
		if over or not s.units.has(t.id):
			continue
		var own := t.faction
		var cover := Rules.cover_at(s, hx.x, hx.y, vs_ord)
		var m := morale_of(t) + cover
		var moving: bool = vs_movers and _moving_ids.has(t.id)
		var dr := await roll(own, "la difesa di %s (Morale %d, copertura %+d)" % [t.unit_name, m - cover, cover],
			func(x: int) -> int: return own if m + x <= total else opp(own))
		if over or not s.units.has(t.id):
			continue
		var dt: int = m + int(dr["sum"])
		if dt < total:
			await hit(t, "difesa %d contro %d" % [dt, total])
		elif dt == total:
			if moving:
				await hit(t, "pareggio mentre muove (%d)" % dt)
			elif not t.suppressed:
				t.suppressed = true
				say("%s è [b]soppressa[/b] (pareggio %d)." % [uname(t), dt], "bad", { "unit": t.id })
			else:
				say("%s resta soppressa (pareggio %d)." % [uname(t), dt], "")
		else:
			say("%s regge (%d contro %d)." % [uname(t), dt, total], "good", { "unit": t.id })


func _defense_actions(d: int, hexes: Array, total: int, vs_ord: bool) -> int:
	while not over:
		var o: Array = []
		var cov := 0
		for hx: Vector2i in hexes:
			cov = maxi(cov, Rules.cover_at(s, hx.x, hx.y, vs_ord))
		var c1 := find_action(d, "MIMETIZZAZIONE")
		if c1 != null and cov > 0:
			o.append({ "id": "conceal", "card": hand(d).find(c1), "label": "Azione: Mimetizzazione (−%d all'attacco)" % cov })
		if is_defender(d):
			for hx: Vector2i in hexes:
				var hd: GameState.HexData = s.hex_at(hx.x, hx.y)
				if hd.has_foxhole or hd.fortification != Domain.Fort.NONE or Rules.is_water_hex(s, hx.x, hx.y):
					continue
				var c2 := find_action(d, "TRINCERAMENTI NASCOSTI")
				if c2 != null and hd.terrain != Domain.TerrainType.BUILDING:
					o.append({ "id": "entrench", "card": hand(d).find(c2), "hex": hx, "label": "Azione: Trinceramenti Nascosti in %s" % lbl(hx) })
				var c3 := find_action(d, "CASAMATTA NASCOSTA")
				if c3 != null and s.objective_at(hx.x, hx.y) != null:
					o.append({ "id": "pillbox", "card": hand(d).find(c3), "hex": hx, "label": "Azione: Casamatta Nascosta in %s" % lbl(hx) })
		if o.is_empty():
			return total
		o.append({ "id": "no", "label": "Nessuna azione: tira la difesa" })
		var a := await ask(d, "defense", "DIFESA · attacco totale %d su %s. Vuoi giocare un'AZIONE prima dei tiri di difesa?" % [total, lbl(hexes[0])],
			o, { "hex": hexes[0], "total": total })
		var id := String(a.get("id", "no"))
		if id == "no":
			return total
		var c: Card = hand(d)[int(a["card"])]
		_discard_from_hand(d, c)
		match id:
			"conceal":
				total -= cov
				say("Azione: Mimetizzazione — l'attacco scende a %d." % total, "order", { "card": c, "who": d })
			"entrench":
				s.hex_at(a["hex"].x, a["hex"].y).has_foxhole = true
				say("Azione: Trinceramenti Nascosti in %s." % lbl(a["hex"]), "order", { "card": c, "who": d, "hex": a["hex"] })
			"pillbox":
				s.hex_at(a["hex"].x, a["hex"].y).fortification = Domain.Fort.PILLBOX
				say("Azione: Casamatta Nascosta in %s." % lbl(a["hex"]), "order", { "card": c, "who": d, "hex": a["hex"] })
	return total


# ═══ AVANZATA e CORPO A CORPO (O16) ══════════════════════════════════════════

func can_advance(u: Unit, to: Vector2i) -> bool:
	if not in_map(to):
		return false
	var hd: GameState.HexData = s.hex_at(to.x, to.y)
	if hd == null or hd.has_blaze or int(Domain.TERRAIN_MOVE_COST.get(hd.terrain, 1)) >= 99:
		return false
	if s.side_feature_between(u.pos(), to) == Domain.HexsideFeature.CLIFF and s.weapon_carried_by(u.id) != null:
		return false
	return true


func _order_advance(f: int) -> void:
	var group := await _choose_activation(f, Domain.OrderType.ADVANCE)
	var todo: Array = group.map(func(u: Unit) -> String: return u.id)
	var any := false
	while not over and not todo.is_empty():
		var opts: Array = []
		for id in todo:
			var u: Unit = s.unit_by_id(id)
			if u != null and useful(u, Domain.OrderType.ADVANCE):
				opts.append({ "id": "unit", "unit": id, "label": "Avanza con %s" % uname(u) })
		if opts.is_empty():
			break
		var u2: Unit = null
		if opts.size() == 1 and not any:
			u2 = s.unit_by_id(String(opts[0]["unit"]))
		else:
			if any:
				opts.append({ "id": "end", "label": "Termina l'Avanzata" })
			var a := await ask(f, "pick_mover", "AVANZATA · scegli quale unità attivata avanza adesso (un solo esagono, anche in mezzo ai nemici).", opts, { "order": Domain.OrderType.ADVANCE })
			if a.get("id") != "unit":
				break
			u2 = s.unit_by_id(String(a["unit"]))
		todo.erase(u2.id)
		var o2: Array = []
		for nb in HexGrid.neighbors(u2.q, u2.r):
			if can_advance(u2, nb):
				o2.append({ "id": "hex", "hex": nb, "label": "%s%s" % [lbl(nb), " — CORPO A CORPO" if enemy_in(nb, f) else ""] })
		if at_edge(opp(f), u2.pos()):
			o2.append({ "id": "exit", "label": "Esci dalla mappa (+PV)" })
		o2.append({ "id": "stay", "label": "%s resta ferma" % u2.unit_name })
		var b := await ask(f, "advance", "AVANZATA · %s: tocca l'esagono adiacente in cui avanzare." % u2.unit_name, o2, { "unit": u2.id })
		match String(b.get("id", "stay")):
			"hex":
				var from := u2.pos()
				var to: Vector2i = b["hex"]
				s.set_unit_pos(u2, to.x, to.y)
				any = true
				say("%s avanza in %s." % [u2.unit_name, lbl(to)], "move", { "unit": u2.id, "from": from, "to": to, "who": f })
				update_objectives()
				await _mines_on(u2, from, to)
				if s.units.has(u2.id):
					await _react_to_entry(f, [u2], to, "advance")
				check_end()
			"exit":
				_exit_unit(f, u2)
				any = true


func _melee_hex() -> Vector2i:
	var sides := {}
	for u in s.units.values():
		if not u.is_man():
			continue
		var k: String = u.hex_key()
		if not sides.has(k):
			sides[k] = [false, false, u.pos()]
		sides[k][0 if u.faction == AX else 1] = true
	for k in sides:
		if sides[k][0] and sides[k][1]:
			return sides[k][2]
	return Vector2i(-1, -1)


func _melees(active: int) -> void:
	while not over:
		var h := _melee_hex()
		if h.x < 0:
			return
		await _melee(active, h)


func _melee_fp(f: int, h: Vector2i) -> int:
	var t := 0
	for u in s.men_at(h.x, h.y):
		if u.faction == f:
			t += u.fp + (1 if u.fp_boxed else 0)
	return t


func _side_at(f: int, h: Vector2i) -> Array:
	return s.men_at(h.x, h.y).filter(func(u: Unit) -> bool: return u.faction == f)


func _melee(active: int, h: Vector2i) -> void:
	var inactive := opp(active)
	say("[b]CORPO A CORPO in %s![/b]" % lbl(h), "melee", { "hex": h, "fx": "melee" })
	for side: int in [inactive, active]:
		while not over:
			var c := find_action(side, "IMBOSCATA")
			var foes := _side_at(opp(side), h)
			if c == null or foes.is_empty() or _side_at(side, h).is_empty():
				break
			var a := await ask(side, "ambush", "CORPO A CORPO in %s · giochi IMBOSCATA? L'avversario deve rompere una sua unità prima dei tiri." % lbl(h),
				[{ "id": "play", "card": hand(side).find(c), "label": "Gioca Imboscata" }, { "id": "no", "label": "No" }], { "hex": h })
			if a.get("id") != "play":
				break
			_discard_from_hand(side, c)
			say("%s: [b]Imboscata![/b]" % side_name(side), "order", { "card": c, "who": side })
			var victim: Unit = foes[0]
			if foes.size() > 1:
				var o: Array = []
				for u: Unit in foes:
					o.append({ "id": "unit", "unit": u.id, "label": "%s%s" % [uname(u), "" if u.efficient else " (già rotta: eliminata)"] })
				var b := await ask(opp(side), "ambush_victim", "IMBOSCATA nemica in %s · scegli quale tua unità si rompe." % lbl(h), o, { "hex": h })
				victim = s.unit_by_id(String(b.get("unit", victim.id)))
			await hit(victim, "Imboscata")
	if over:
		return
	if _side_at(active, h).is_empty() or _side_at(inactive, h).is_empty():
		say("Il corpo a corpo finisce senza tiri: un lato non ha più unità.", "melee")
		check_end()
		return
	var ifp := _melee_fp(inactive, h)
	var afp := _melee_fp(active, h)
	var bunker := s.hex_at(h.x, h.y).fortification in [Domain.Fort.BUNKER, Domain.Fort.PILLBOX]
	var ri := await roll(inactive, "il corpo a corpo dei %s (forza %d)" % [side_name(inactive), ifp],
		func(t: int) -> int: return inactive if t <= 5 else (active if t >= 9 else -1))
	if over:
		return
	var itot: int = _melee_fp(inactive, h) + int(ri["sum"])
	var abase := _melee_fp(active, h)
	var ra := await roll(active, "il corpo a corpo dei %s (forza %d, da battere %d)" % [side_name(active), abase, itot],
		func(t: int) -> int: return active if abase + t <= itot else inactive)
	if over:
		return
	var atot: int = _melee_fp(active, h) + int(ra["sum"])
	say("Corpo a corpo: %s %d — %s %d." % [side_name(active), atot, side_name(inactive), itot], "melee", { "hex": h })
	var losers: Array = []
	if atot < itot or (atot == itot):
		losers.append_array(_side_at(active, h))
	if itot < atot or (atot == itot and not bunker):
		losers.append_array(_side_at(inactive, h))
	for u: Unit in losers:
		kill(u, "corpo a corpo")
	for side: int in [active, inactive]:
		if over or _side_at(side, h).is_empty():
			continue
		var nq := find_action(side, "LOTTA SENZA QUARTIERE")
		var ok := nation(side) == "russian" or (nation(side) == "german" and nation(opp(side)) == "russian")
		if nq != null and ok:
			var a2 := await ask(side, "no_quarter", "Hai vinto il corpo a corpo: giochi LOTTA SENZA QUARTIERE (+2 PV)?",
				[{ "id": "play", "card": hand(side).find(nq), "label": "Gioca (+2 PV)" }, { "id": "no", "label": "No" }], { "hex": h })
			if a2.get("id") == "play":
				_discard_from_hand(side, nq)
				add_vp(side, 2, "Lotta senza quartiere")
	update_objectives()
	check_end()


# ═══ RECUPERO (O22) e RITIRATA (O23) ═════════════════════════════════════════

func _rally_morale(u: Unit) -> int:
	return morale_of(u) + Rules.cover_at(s, u.q, u.r, false)


func _order_recover(f: int) -> void:
	s.rally_used.append(f)
	var n := 0
	for u in men(f):
		if u.suppressed:
			u.suppressed = false
			n += 1
	if n > 0:
		say("Recupero: tolta la soppressione a %d unità." % n, "good", { "who": f })
	var broken: Array = s.broken_men_of(f)
	broken.sort_custom(func(a: Unit, b: Unit) -> bool: return (0 if a.is_leader() else 1) < (0 if b.is_leader() else 1))
	for u: Unit in broken:
		if over or not s.units.has(u.id) or u.efficient:
			continue
		var m := _rally_morale(u)
		var r := await roll(f, "il recupero di %s (serve meno di %d)" % [u.unit_name, m],
			func(t: int) -> int: return f if t >= m else opp(f))
		if over or not s.units.has(u.id):
			continue
		if int(r["sum"]) < m:
			u.efficient = true
			say("%s [b]si riprende[/b]." % uname(u), "good", { "unit": u.id })
		elif int(r["sum"]) == m:
			u.suppressed = true
			say("%s resta rotta ed è soppressa." % uname(u), "bad", { "unit": u.id })
		else:
			say("%s resta rotta." % uname(u), "", { "unit": u.id })


func _rout_targets(_f: int) -> Array:
	var out: Array = []
	for p in [AX, AL]:
		if not s.rally_used.has(p) and not s.broken_men_of(p).is_empty():
			out.append(p)
	return out


func _order_rout(f: int) -> void:
	var tg := _rout_targets(f)
	if tg.is_empty():
		return
	var p: int = tg[0]
	if tg.size() > 1:
		var o: Array = []
		for side: int in [opp(f), f]:
			o.append({ "id": "side", "side": side, "label": "Ritirata sulle unità rotte %s (%d)" % [
				"NEMICHE" if side != f else "TUE", s.broken_men_of(side).size()] })
		var a := await ask(f, "rout_who", "RITIRATA · scegli quale giocatore deve tirare per le sue unità rotte.", o, {})
		p = int(a.get("side", opp(f)))
	s.rally_used.append(p)
	say("Ritirata sulle unità rotte dei %s." % side_name(p), "order", { "who": f })
	for u: Unit in s.broken_men_of(p):
		if over or not s.units.has(u.id) or u.efficient:
			continue
		var m := _rally_morale(u)
		var r := await roll(f, "la ritirata di %s (Morale %d)" % [u.unit_name, m],
			func(t: int) -> int: return p if t >= m else opp(p))
		if over or not s.units.has(u.id):
			continue
		var t: int = int(r["sum"])
		if t > m:
			await _retreat(u, t - m)
		elif t == m:
			if not u.suppressed:
				u.suppressed = true
				say("%s è soppressa." % uname(u), "bad", { "unit": u.id })
		else:
			say("%s tiene la posizione." % uname(u), "good", { "unit": u.id })
	update_objectives()
	check_end()


func _retreat(u: Unit, n: int) -> void:
	say("%s deve ritirarsi di %d esagoni." % [uname(u), n], "bad", { "unit": u.id })
	for i in n:
		if over or not s.units.has(u.id):
			return
		if at_edge(u.faction, u.pos()):
			kill(u, "in rotta fuori dalla mappa")
			return
		var good: Array = []
		for nb in HexGrid.neighbors(u.q, u.r):
			if not in_map(nb) or edge_dist(u.faction, nb) >= edge_dist(u.faction, u.pos()):
				continue
			if HexGrid.step_cost(s, u.q, u.r, nb.x, nb.y) >= 0 and not enemy_in(nb, u.faction):
				good.append(nb)
		if good.is_empty():
			kill(u, "ritirata impossibile")
			return
		var to: Vector2i = good[0]
		if good.size() > 1:
			var o: Array = []
			for g: Vector2i in good:
				o.append({ "id": "hex", "hex": g, "label": lbl(g) })
			var a := await ask(u.faction, "retreat", "RITIRATA · %s deve arretrare ancora di %d esagoni verso il proprio bordo: scegli dove." % [u.unit_name, n - i],
				o, { "unit": u.id })
			to = a.get("hex", to)
		var from := u.pos()
		s.set_unit_pos(u, to.x, to.y)
		say("%s si ritira in %s." % [u.unit_name, lbl(to)], "move", { "unit": u.id, "from": from, "to": to, "who": u.faction })
		await _mines_on(u, from, to)
	update_objectives()


# ═══ ARTIGLIERIA (O17, O18) ══════════════════════════════════════════════════

func _spotters(f: int) -> Array:
	return men(f).filter(func(u: Unit) -> bool: return u.is_leader() and u.efficient and not u.activated)


func _order_arty_denied(f: int) -> void:
	var r := radio_of(opp(f))
	if r == null:
		return
	if r.efficient:
		r.efficient = false
		say("Artiglieria Negata: la Radio dei %s è fuori uso." % side_name(opp(f)), "bad", { "who": f })
	else:
		s.units.erase(r.id)
		say("Artiglieria Negata: la Radio dei %s, già fuori uso, è eliminata." % side_name(opp(f)), "bad", { "who": f })


func _order_artillery(f: int) -> void:
	var radio := radio_of(f)
	if radio == null:
		return
	if not radio.efficient:
		radio.efficient = true
		say("Accesso alla Batteria: la Radio dei %s torna operativa." % side_name(f), "good", { "who": f })
		return
	var sp := _spotters(f)
	if sp.is_empty():
		return
	var L: Unit = sp[0]
	if sp.size() > 1:
		var o: Array = []
		for u: Unit in sp:
			o.append({ "id": "unit", "unit": u.id, "label": "Osservatore: %s" % uname(u) })
		var a := await ask(f, "spotter", "ARTIGLIERIA · scegli il comandante che fa da OSSERVATORE.", o, {})
		L = s.unit_by_id(String(a.get("unit", L.id)))
	L.activated = true
	var o2: Array = []
	for q in s.map_cols:
		for r in s.map_rows:
			if (q != L.q or r != L.r) and HexGrid.has_los(L.q, L.r, q, r, s):
				o2.append({ "id": "hex", "hex": Vector2i(q, r), "label": lbl(Vector2i(q, r)) })
	if o2.is_empty():
		return
	var b := await ask(f, "arty_target", "ARTIGLIERIA · scegli l'esagono su cui chiamare il tiro (in vista di %s). Colpirà anche i 6 esagoni adiacenti." % L.unit_name, o2, { "unit": L.id })
	var th: Vector2i = b.get("hex", L.pos())
	var k := await ask(f, "arty_kind", "ARTIGLIERIA su %s · tiro esplosivo o cortina fumogena?" % lbl(th),
		[{ "id": "he", "label": "Tiro esplosivo (FP %d)" % Rules.radio_fp_for(radio.unit_name) }, { "id": "smoke", "label": "Cortina fumogena (7 esagoni)" }], { "hex": th })
	var smoke: bool = k.get("id") == "smoke"
	var dist := HexGrid.distance(L.q, L.r, th.x, th.y)
	var hind := hindrance(L, th)
	var need := dist + hind
	say("%s chiama l'artiglieria su %s." % [L.unit_name, lbl(th)], "fire", { "from": L.pos(), "to": th, "who": f })
	var tr := await roll(f, "la precisione dell'artiglieria (serve più di %d)" % need,
		func(t: int) -> int: return f if t <= need else opp(f), { "product": true })
	if over:
		return
	var accurate: bool = int(tr["sum"]) > need
	var dc := draw_card(f)
	var wd := dc.dice_white if dc != null else _rng.randi_range(1, 6)
	var cd := dc.dice_red if dc != null else _rng.randi_range(1, 6)
	var c := Rules.artillery_drift(s, th.x, th.y, accurate, wd, cd)
	if c.x < 0:
		say("Il colpo %s e finisce fuori mappa: nessun effetto." % ("è preciso ma devia" if accurate else "è impreciso"), "miss")
		await _process_time()
		return
	say("Il tiro %s: cade in [b]%s[/b]." % ["è preciso" if accurate else "è impreciso e devia", lbl(c)], "fire", { "hex": c, "fx": "arty" })
	var blast: Array = [c]
	for nb in HexGrid.neighbors(c.x, c.y):
		if in_map(nb):
			blast.append(nb)
	s.last_impact_hexes = blast
	if smoke:
		Combat.resolve_smoke_barrage(s, c.x, c.y)
		say("Cortina fumogena su %s e dintorni." % lbl(c), "order", { "hex": c, "fx": "smoke" })
		await _process_time()
		return
	var fp := Rules.radio_fp_for(radio.unit_name)
	for hx: Vector2i in blast:
		if over:
			return
		var hd: GameState.HexData = s.hex_at(hx.x, hx.y)
		var has_fort := hd != null and (hd.has_foxhole or hd.fortification != Domain.Fort.NONE)
		if s.men_at(hx.x, hx.y).is_empty() and not has_fort:
			continue
		var ir := await roll(f, "l'impatto in %s (FP %d)" % [lbl(hx), fp], Callable(), {})
		if over:
			return
		if has_fort and int(ir["sum"]) == Rules.artillery_fort_vulnerability(fp):
			hd.has_foxhole = false
			hd.fortification = Domain.Fort.NONE
			say("La fortificazione in %s è distrutta." % lbl(hx), "bad", { "hex": hx })
		await _defend_hex(f, opp(f), hx, fp + int(ir["sum"]), true, false, true)
	update_objectives()
	check_end()


# ═══ TEMPO (6) ═══════════════════════════════════════════════════════════════

func _process_time() -> void:
	while not over and not _pending_time.is_empty():
		var f: int = _pending_time.pop_front()
		await _advance_time(f)


func _advance_time(f: int) -> void:
	_reshuffle(f)
	s.time_marker += 1
	say("[b]TEMPO![/b] Il segnalino avanza alla casella %d (Morte Subitanea dalla %d). I %s rimescolano il mazzo." % [
		s.time_marker, s.sudden_death_space, side_name(f)], "time", { "fx": "time" })
	if s.time_marker >= s.sudden_death_space:
		update_objectives()
		if s.chit_control_all and not s.objectives.is_empty():
			var first := s.objectives[0].controller
			var all_same := first != -1
			for o in s.objectives:
				if o.controller != first:
					all_same = false
			if all_same:
				_finish(first, "Controllano tutti gli obiettivi (chit V) al momento della Morte Subitanea.")
				return
		var space := s.time_marker
		var fin := s.vp_tracker + ObjectiveChits.secret_balance(s)
		var lead := s.initiative_holder
		if fin > 0:
			lead = AX
		elif fin < 0:
			lead = AL
		var r := await roll(f, "la MORTE SUBITANEA (la partita finisce con meno di %d)" % space,
			func(t: int) -> int: return opp(lead) if t < space else lead, { "no_trigger": true })
		if over:
			return
		if int(r["sum"]) < space:
			_finish_on_points("Morte Subitanea.")
			return
		say("La partita continua.", "time")
	if s.defender_faction == AX or s.defender_faction == AL:
		add_vp(s.defender_faction, 1, "il Difensore guadagna 1 PV a ogni Tempo")
	for key in s.hexes:
		var hd: GameState.HexData = s.hexes[key]
		if hd.has_smoke:
			hd.has_smoke = false
			say("Tempo: un segnalino Fumo viene rimosso.", "time")
			break
	_reinforcements()
	# Passo 6: entrambi possono giocare Trincerarsi (A32), prima chi non ha innescato.
	for side: int in [opp(f), f]:
		while not over:
			var c := find_action(side, "TRINCERARSI")
			if c == null:
				break
			var o: Array = []
			var seen := {}
			for u in men(side):
				var hd2: GameState.HexData = s.hex_at(u.q, u.r)
				if seen.has(u.hex_key()) or hd2 == null or hd2.has_foxhole or hd2.has_blaze \
						or hd2.fortification != Domain.Fort.NONE or Rules.is_water_hex(s, u.q, u.r):
					continue
				seen[u.hex_key()] = true
				o.append({ "id": "hex", "hex": u.pos(), "label": "Buche in %s" % lbl(u.pos()) })
			if o.is_empty():
				break
			o.append({ "id": "no", "label": "Non trincerarsi" })
			var a := await ask(side, "dig_in", "TEMPO · puoi giocare TRINCERARSI: scegli un esagono con una tua unità dove scavare le Buche.", o, { "card": hand(side).find(c) })
			if a.get("id") != "hex":
				break
			_discard_from_hand(side, c)
			s.hex_at(a["hex"].x, a["hex"].y).has_foxhole = true
			say("%s: Trincerarsi — Buche in %s." % [side_name(side), lbl(a["hex"])], "order", { "card": c, "who": side, "hex": a["hex"] })


func _edge_hex(f: int, need_icons: int) -> Vector2i:
	var cands := edge_hexes(f)
	var best: Vector2i = cands[cands.size() / 2] if not cands.is_empty() else Vector2i(0, 0)
	var best_n := 99
	for h: Vector2i in cands:
		var hd: GameState.HexData = s.hex_at(h.x, h.y)
		if hd == null or hd.has_blaze or int(Domain.TERRAIN_MOVE_COST.get(hd.terrain, 1)) >= 99 or enemy_in(h, f):
			continue
		var n := s.soldier_icons_at(h.x, h.y)
		if n + need_icons <= 7 and n < best_n:
			best_n = n
			best = h
	return best


func _reinforcements() -> void:
	var waiting: Array = []
	for grp in s.reinforcements:
		if int(grp.get("space", 99)) > s.time_marker:
			waiting.append(grp)
			continue
		var f := int(grp.get("faction", AX))
		var n := 0
		for fo in grp.get("forces", []):
			for _k in int(fo.get("n", 1)):
				_team_seq += 1
				var id := "R-%s-%d" % [Domain.FACTION_SHORT.get(f, "U"), _team_seq]
				var pos := _edge_hex(f, 4)
				var nat := String(fo.get("nat", ""))
				var u := UnitChart.build_unit(id, f, String(fo.get("tipo", "")), pos.x, pos.y, nat)
				s.units[id] = u
				UnitChart.apply_broken_side(u, UnitChart.nation_code(nation(f)))
				n += 1
		if n > 0:
			_assign_carriers()
			say("Rinforzi per i %s: %d unità entrano dal loro bordo." % [side_name(f), n], "good", { "who": f })
	s.reinforcements = waiting
	var out: Array = []
	for e in s.exited_units:
		if int(e.get("space", 99)) > s.time_marker:
			out.append(e)
			continue
		var u: Unit = e["unit"]
		var pos := _edge_hex(u.faction, u.soldier_icons())
		u.q = pos.x
		u.r = pos.y
		u.activated = false
		s.units[u.id] = u
		var w: Unit = e.get("weapon")
		if w != null:
			w.q = pos.x
			w.r = pos.y
			w.carrier_id = u.id
			s.units[w.id] = w
		say("%s rientra dal proprio bordo come rinforzo." % u.unit_name, "good", { "unit": u.id })
	s.exited_units = out


# ═══ Eventi gestiti qui (gli altri restano in Events.gd) ═════════════════════

## Ritorna true se l'evento è stato risolto da questa funzione.
func _event_native(c: Card, f: int) -> bool:
	match c.event_name:
		"CRATERI", "TRAPPOLA ESPLOSIVA":
			var h := random_hex(f)
			var hd: GameState.HexData = s.hex_at(h.x, h.y)
			if hd == null or hd.has_blaze or hd.has_foxhole or hd.fortification != Domain.Fort.NONE or Rules.is_water_hex(s, h.x, h.y):
				say("   Esagono casuale %s: nessun effetto." % lbl(h), "fate", { "hex": h })
			elif c.event_name == "CRATERI":
				hd.has_foxhole = true
				say("   Crateri: Buche in %s." % lbl(h), "fate", { "hex": h })
			else:
				hd.fortification = Domain.Fort.MINES
				say("   Trappola esplosiva: Mine in %s." % lbl(h), "fate", { "hex": h })
			return true
		"NEBBIA DI GUERRA":
			for side: int in [AX, AL]:
				var hd2 := hand(side)
				if not hd2.is_empty():
					var c2: Card = hd2[_rng.randi_range(0, hd2.size() - 1)]
					_discard_from_hand(side, c2)
			say("   Nebbia di guerra: ogni giocatore perde una carta a caso dalla mano.", "fate")
			return true
		"SPIONAGGIO":
			var foe := opp(f)
			if hand(foe).is_empty():
				return true
			var o: Array = []
			var hf := hand(foe)
			for i in hf.size():
				o.append({ "id": "card", "index": i, "label": "Scarta: %s / %s" % [
					String(Domain.ORDER_LABELS.get(hf[i].order, "?")), hf[i].action_name.capitalize()] })
			o.append({ "id": "no", "label": "Non scartare nulla" })
			var a := await ask(f, "interrogation", "SPIONAGGIO · vedi la mano dell'avversario: puoi fargli scartare una carta.", o, {})
			if a.get("id") == "card":
				_discard_from_hand(foe, hf[int(a["index"])])
				say("   Spionaggio: i %s scartano una carta scelta dall'avversario." % side_name(foe), "fate")
			return true
		"DIVIDERSI":
			var o2: Array = []
			for u in men(f):
				if u.type == Domain.UnitType.SQUAD:
					o2.append({ "id": "unit", "unit": u.id, "label": "Dividi %s in due Team" % uname(u) })
			if o2.is_empty():
				say("   Dividersi: nessuna Squadra da dividere.", "fate")
				return true
			o2.append({ "id": "no", "label": "Non dividere nessuna Squadra" })
			var b := await ask(f, "deploy", "DIVIDERSI · puoi sostituire una tua Squadra con due Team.", o2, {})
			if b.get("id") == "unit":
				_deploy(s.unit_by_id(String(b["unit"])))
			return true
		"RINFORZI":
			var it := await _support_roll(f, "Rinforzi", true)
			if it.is_empty() or over:
				return true
			if String(it["tipo"]) == "radio":
				if radio_of(f) != null:
					say("   Rinforzi: %s, ma hai già una Radio: nessun effetto." % String(it["nome"]), "fate")
				else:
					_team_seq += 1
					var rd := UnitChart.build_unit("S-%s-%d" % [Domain.FACTION_SHORT.get(f, "U"), _team_seq], f, String(it["arma"]), -1, -1,
						UnitChart.nation_code(nation(f)))
					s.units[rd.id] = rd
					_assign_radio(rd)
					say("   Rinforzi: i %s ricevono una %s." % [side_name(f), String(it["nome"])], "fate")
				return true
			var o3: Array = []
			for h: Vector2i in edge_hexes(f):
				var hd3: GameState.HexData = s.hex_at(h.x, h.y)
				if hd3 == null or hd3.has_blaze or int(Domain.TERRAIN_MOVE_COST.get(hd3.terrain, 1)) >= 99 or enemy_in(h, f):
					continue
				if s.soldier_icons_at(h.x, h.y) + 4 <= 7:
					o3.append({ "id": "hex", "hex": h, "label": lbl(h) })
			if o3.is_empty():
				say("   Rinforzi: nessun esagono libero sul bordo amico.", "fate")
				return true
			var c3 := await ask(f, "place_unit", "RINFORZI · %s: scegli l'esagono del tuo bordo in cui entra." % String(it["nome"]), o3, {})
			var h3: Vector2i = c3.get("hex", o3[0]["hex"])
			_spawn_support(f, it, h3)
			say("   Rinforzi: %s entra in %s." % [String(it["nome"]), lbl(h3)], "fate", { "hex": h3 })
			return true
		"SACCHEGGIO":
			var weapons: Array = s.graves.filter(func(x: Unit) -> bool: return x.is_weapon())
			var bare: Array = men(f).filter(func(x: Unit) -> bool: return s.weapon_carried_by(x.id) == null)
			if weapons.is_empty() or bare.is_empty():
				say("   Saccheggio: nessuna arma eliminata da recuperare (o nessuna unità senza arma).", "fate")
				return true
			var o4: Array = []
			for w: Unit in weapons:
				o4.append({ "id": "weapon", "weapon": w, "label": "Recupera %s (FP %d, gittata %d)" % [w.unit_name, w.fp, w.range] })
			o4.append({ "id": "no", "label": "Non recuperare nulla" })
			var a4 := await ask(f, "scrounge", "SACCHEGGIO · puoi rimettere in gioco un'arma eliminata, affidandola a una tua unità senza arma.", o4, {})
			if a4.get("id") != "weapon":
				return true
			var wpn: Unit = a4["weapon"]
			var o5: Array = []
			for m: Unit in bare:
				o5.append({ "id": "unit", "unit": m.id, "label": uname(m) })
			var a5 := await ask(f, "scrounge_to", "SACCHEGGIO · scegli a quale tua unità dare %s." % wpn.unit_name, o5, {})
			var tgt: Unit = s.unit_by_id(String(a5.get("unit", bare[0].id)))
			s.graves.erase(wpn)
			wpn.faction = f
			wpn.efficient = true
			wpn.carrier_id = tgt.id
			wpn.q = tgt.q
			wpn.r = tgt.r
			s.units[wpn.id] = wpn
			say("   Saccheggio: %s recupera %s." % [uname(tgt), wpn.unit_name], "fate", { "hex": tgt.pos() })
			return true
		"PROCEDERE FERITI":
			var dead: Array = s.graves.filter(func(x: Unit) -> bool: return x.is_man())
			if dead.is_empty():
				say("   Procedere Feriti: nessuna unità eliminata da far rientrare.", "fate")
				return true
			var o6: Array = []
			for x: Unit in dead:
				o6.append({ "id": "grave", "grave": x, "label": "%s (%s)" % [x.unit_name, side_name(x.faction)] })
			var a6 := await ask(f, "walking_wounded", "PROCEDERE FERITI · scegli un'unità eliminata (tua o nemica): torna in gioco ROTTA dentro o accanto a un esagono casuale.", o6, {})
			var back: Unit = a6.get("grave", dead[0])
			var rh := random_hex(f)
			var spots2 := _placeable_around(rh, back.faction, back.soldier_icons())
			spots2 = spots2.filter(func(h: Vector2i) -> bool: return not enemy_in(h, back.faction))
			if spots2.is_empty():
				say("   Procedere Feriti: esagono casuale %s, nessun posto dove metterla." % lbl(rh), "fate", { "hex": rh })
				return true
			var o7: Array = []
			for h: Vector2i in spots2:
				o7.append({ "id": "hex", "hex": h, "label": lbl(h) })
			var a7 := await ask(f, "place_unit", "PROCEDERE FERITI · esagono casuale %s: scegli dove rientra %s (dentro o adiacente)." % [lbl(rh), back.unit_name], o7, { "hex": rh })
			var h7: Vector2i = a7.get("hex", spots2[0])
			s.graves.erase(back)
			back.q = h7.x
			back.r = h7.y
			back.activated = false
			back.suppressed = false
			back.efficient = false
			s.units[back.id] = back
			s.casualties[back.faction] = maxi(0, int(s.casualties.get(back.faction, 0)) - 1)
			say("   Procedere Feriti: %s dei %s rientra rotta in %s." % [back.unit_name, side_name(back.faction), lbl(h7)], "fate", { "hex": h7 })
			update_objectives()
			return true
		"White Phosphorus":
			var o8: Array = []
			var seen8 := {}
			for u in men(f):
				if u.type != Domain.UnitType.SQUAD or not u.efficient:
					continue
				for nb in HexGrid.neighbors(u.q, u.r):
					if not in_map(nb) or seen8.has(nb):
						continue
					var hd8: GameState.HexData = s.hex_at(nb.x, nb.y)
					if hd8 == null or hd8.has_blaze or Rules.is_water_hex(s, nb.x, nb.y):
						continue
					seen8[nb] = true
					o8.append({ "id": "hex", "hex": nb, "label": "Fosforo in %s" % lbl(nb) })
			if o8.is_empty():
				say("   Fosforo bianco: nessuna tua Squadra efficiente può lanciarlo.", "fate")
				return true
			o8.append({ "id": "no", "label": "Non usare il fosforo" })
			var a8 := await ask(f, "phosphorus", "FOSFORO BIANCO · puoi mettere Fumo in un esagono adiacente a una tua Squadra efficiente: chi ha unità in quell'esagono deve romperne una.", o8, {})
			if a8.get("id") != "hex":
				return true
			var h8: Vector2i = a8["hex"]
			s.hex_at(h8.x, h8.y).has_smoke = true
			say("   Fosforo bianco in %s." % lbl(h8), "fate", { "hex": h8, "fx": "smoke" })
			for side: int in [opp(f), f]:
				var here := _side_at(side, h8)
				if here.is_empty():
					continue
				var victim: Unit = here[0]
				if here.size() > 1:
					var o9: Array = []
					for x: Unit in here:
						o9.append({ "id": "unit", "unit": x.id, "label": uname(x) })
					var a9 := await ask(side, "ambush_victim", "FOSFORO BIANCO in %s · scegli quale tua unità si rompe." % lbl(h8), o9, { "hex": h8 })
					victim = s.unit_by_id(String(a9.get("unit", victim.id)))
				await hit(victim, "Fosforo bianco")
			return true
	return false


## Affida una Radio appena ricevuta a un comandante (o a chi capita).
func _assign_radio(rd: Unit) -> void:
	var best: Unit = null
	for m in men(rd.faction):
		if s.weapon_carried_by(m.id) == null and (best == null or (m.is_leader() and not best.is_leader())):
			best = m
	if best == null and not men(rd.faction).is_empty():
		best = men(rd.faction)[0]
	if best != null:
		rd.q = best.q
		rd.r = best.r


func _deploy(sq: Unit) -> void:
	if sq == null:
		return
	var q := "Elite" if sq.unit_class == Domain.UnitClass.ELITE else "Line"
	var w := s.weapon_carried_by(sq.id)
	for i in 2:
		var t := make_team(sq.faction, q, sq.q, sq.r)
		t.activated = sq.activated
		if not sq.efficient:
			t.efficient = false
		if i == 0:
			t.suppressed = sq.suppressed
			t.veteran = sq.veteran
			if w != null:
				w.carrier_id = t.id
	say("   Dividersi: %s diventa due Team." % uname(sq), "fate", { "hex": sq.pos() })
	s.units.erase(sq.id)
