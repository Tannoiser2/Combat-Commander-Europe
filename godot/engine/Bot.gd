## Avversario artificiale di Combat Commander: Europe.
##
## Non ha regole proprie: a ogni decisione del motore (Flow.pending) riceve le
## stesse opzioni LEGALI che vedrebbe un giocatore umano e ne sceglie una dando
## un punteggio a ciascuna (probabilità di rompere il bersaglio, distanza dagli
## obiettivi, copertura, esposizione al fuoco nemico…). Quindi non può barare né
## fare mosse fuori regolamento.
class_name Bot
extends RefCounted

var flow: Flow
var level: int = 1          ## 0 Recluta (più errori) · 1 Di linea · 2 Veterano
var rng := RandomNumberGenerator.new()

## P(2d6 − 2d6 > k) per k = −11..11 (indice k + 11).
static var _gt: Array = []
static var _eq: Array = []


func _init(p_flow: Flow, p_level: int = 1, p_seed: int = 0) -> void:
	flow = p_flow
	level = p_level
	if p_seed != 0:
		rng.seed = p_seed
	else:
		rng.randomize()
	if _gt.is_empty():
		var dist := {}
		for a in range(1, 7):
			for b in range(1, 7):
				for c in range(1, 7):
					for d in range(1, 7):
						var x := a + b - c - d
						dist[x] = int(dist.get(x, 0)) + 1
		for k in range(-11, 12):
			var g := 0
			for x in dist:
				if x > k:
					g += dist[x]
			_gt.append(float(g) / 1296.0)
			_eq.append(float(dist.get(k, 0)) / 1296.0)


static func p_gt(k: int) -> float:
	return float(_gt[clampi(k, -11, 11) + 11])

static func p_eq(k: int) -> float:
	return float(_eq[clampi(k, -11, 11) + 11])


# ─── Valutazioni di base ─────────────────────────────────────────────────────

func s() -> GameState:
	return flow.s


func unit_value(u: Unit) -> float:
	var v := 2.0
	if u.is_leader():
		v = 2.5 + u.f_command if u.has_sides else 2.5 + u.command
	elif u.type == Domain.UnitType.TEAM:
		v = 1.0
	if s().weapon_carried_by(u.id) != null:
		v += 0.7
	return v


## Valore atteso di un attacco con FP `fp` sull'esagono `h` contro il lato `d`.
func shot_value(fp: int, h: Vector2i, d: int, vs_ord: bool = false, movers: bool = false) -> float:
	var cover := Rules.cover_at(s(), h.x, h.y, vs_ord)
	var ev := 0.0
	for t in s().men_at(h.x, h.y):
		if t.faction != d:
			continue
		var m := flow.morale_of(t) + cover
		var pb := p_gt(m - fp) + (p_eq(m - fp) if movers else 0.0)
		ev += pb * unit_value(t) * (1.6 if not t.efficient else 1.0)
		if not movers and not t.suppressed:
			ev += p_eq(m - fp) * 0.3
	return ev


## Atteggiamento del lato: true = deve andare a prendersi i punti.
func attacking(f: int) -> bool:
	if flow.is_defender(f):
		return flow.vp_for(f) < -2 and s().time_marker >= s().sudden_death_space - 2
	if flow.is_defender(flow.opp(f)):
		return true
	return flow.vp_for(f) <= 3


## Quante unità nemiche efficienti possono sparare (vista + gittata) su `h`.
func exposure(h: Vector2i, f: int) -> float:
	var n := 0.0
	for e in s().units.values():
		if e.faction == f or not e.is_man() or not e.efficient:
			continue
		var best_r := Rules.range_with_command(s(), e)
		var w := s().weapon_carried_by(e.id)
		if w != null and w.efficient and not flow.is_radio(w):
			best_r = maxi(best_r, w.range)
		var dd := HexGrid.distance(e.q, e.r, h.x, h.y)
		if dd >= 1 and dd <= best_r and HexGrid.has_los(e.q, e.r, h.x, h.y, s()):
			n += 1.0 if e.type == Domain.UnitType.SQUAD else 0.5
	return n


func hex_safety(h: Vector2i, f: int) -> float:
	return Rules.cover_at(s(), h.x, h.y, false) * 1.5 - exposure(h, f) * 1.2


## Dove vuole andare l'unità: esagono-meta, oppure la sua posizione se sta bene.
func goal_for(u: Unit) -> Vector2i:
	var f := u.faction
	var st := s()
	var best := u.pos()
	var best_sc := -1e9
	if attacking(f):
		for o in st.objectives:
			if o.controller == f and not flow.enemy_in(Vector2i(o.q, o.r), f):
				continue
			var dd := HexGrid.distance(u.q, u.r, o.q, o.r)
			var mates := 0
			for m in st.men_of(f):
				if m.id != u.id and HexGrid.distance(m.q, m.r, o.q, o.r) <= 1:
					mates += 1
			var sc := 6.0 + o.vp * 2.0 - dd * 1.5 - maxf(0.0, mates - 2) * 2.5
			var gh := Vector2i(o.q, o.r)
			if crowded(u, gh):
				# Obiettivo già pieno di amici: fermati nell'esagono adiacente più sicuro.
				var bs := -1e9
				for nb in HexGrid.neighbors(o.q, o.r):
					if flow.in_map(nb) and not crowded(u, nb) and HexGrid.step_cost(st, o.q, o.r, nb.x, nb.y) >= 0:
						var sv := hex_safety(nb, f) - _dist(u.pos(), nb) * 0.3
						if sv > bs:
							bs = sv
							gh = nb
				sc -= 3.0
			if sc > best_sc:
				best_sc = sc
				best = gh
		if best_sc > -1e8:
			return best
		# Tutti gli obiettivi in mano: avvicinati al nemico più vicino.
		var bd := 999
		for e in st.units.values():
			if e.faction != f and e.is_man():
				var dd2 := HexGrid.distance(u.q, u.r, e.q, e.r)
				if dd2 < bd:
					bd = dd2
					best = e.pos()
		return best
	# Difesa: presidia l'obiettivo proprio meno difeso; se già su uno, resta.
	for o in st.objectives:
		if o.controller != f:
			continue
		if u.q == o.q and u.r == o.r:
			return u.pos()
		var guards := 0
		for m in st.men_of(f):
			if HexGrid.distance(m.q, m.r, o.q, o.r) <= 1:
				guards += 1
		var dd3 := HexGrid.distance(u.q, u.r, o.q, o.r)
		var sc2 := o.vp * 2.0 - guards * 3.0 - dd3
		if guards == 0 and sc2 > best_sc:
			best_sc = sc2
			best = Vector2i(o.q, o.r)
	return best


## Entrando in `h` l'unità sforerebbe il limite di 7 figure?
func crowded(u: Unit, h: Vector2i) -> bool:
	var n := 0
	for m in s().men_at(h.x, h.y):
		if m.faction == u.faction and m.id != u.id:
			n += m.soldier_icons()
	return n + u.soldier_icons() > 7


func _dist(a: Vector2i, b: Vector2i) -> int:
	return HexGrid.distance(a.x, a.y, b.x, b.y)


func _noise(amount: float) -> float:
	var k := [1.0, 0.35, 0.08][clampi(level, 0, 2)] as float
	return rng.randf_range(-amount, amount) * k


func _idx(opts: Array, id: String) -> int:
	for i in opts.size():
		if String(opts[i].get("id", "")) == id:
			return i
	return -1


# ─── Scelta ──────────────────────────────────────────────────────────────────

## Indice dell'opzione scelta per la decisione in sospeso.
func pick() -> int:
	var p := flow.pending
	var opts: Array = p["options"]
	var f: int = p["who"]
	if opts.size() == 1:
		return 0
	match String(p["kind"]):
		"turn": return _pick_turn(f, opts)
		"discard": return _pick_discard(f, opts, p)
		"activate": return _pick_activate(f, opts, p)
		"group", "fire_group":
			var c := _idx(opts, "confirm")
			if c >= 0:
				return c
			var o := _idx(opts, "ordnance")
			return o if o >= 0 else 0
		"pick_mover": return 0
		"move": return _pick_move(f, opts, p)
		"advance": return _pick_advance(f, opts, p)
		"react": return _pick_react(f, opts, p)
		"fire_target": return _pick_target(f, opts)
		"fire_mods": return _pick_mods(f, opts, p)
		"defense": return _pick_defense(f, opts, p)
		"reroll":
			var what := String(p.get("what", ""))
			if what.contains("MORTE"):
				return _idx(opts, "reroll")
			return _idx(opts, "reroll") if rng.randf() < 0.3 else _idx(opts, "keep")
		"sniper", "ambush_victim":
			return _pick_unit(opts, String(p["kind"]) == "sniper")
		"light_wounds", "ambush", "no_quarter":
			return _idx(opts, "play")
		"rout_who":
			for i in opts.size():
				if int(opts[i].get("side", -1)) != f:
					return i
			return 0
		"retreat", "smoke", "dig_in":
			return _pick_safe_hex(f, opts)
		"arty_target": return _pick_arty(f, opts)
		"arty_kind": return _idx(opts, "he")
		"interrogation":
			for i in opts.size():
				if String(opts[i].get("label", "")).contains("Fuoco"):
					return i
			return 0
		"setup":
			return _idx(opts, "confirm")
		"deploy", "demolitions", "setup_place":
			return opts.size() - 1
	return 0


func _pick_unit(opts: Array, want_best: bool) -> int:
	var best := 0
	var best_v := -1e9
	for i in opts.size():
		var u: Unit = s().unit_by_id(String(opts[i].get("unit", "")))
		if u == null:
			continue
		var v := unit_value(u) * (1.6 if not u.efficient else 1.0)
		if not want_best:
			v = -unit_value(u) - (3.0 if not u.efficient else 0.0)
		if v > best_v:
			best_v = v
			best = i
	return best


func _pick_safe_hex(f: int, opts: Array) -> int:
	var best := 0
	var best_v := -1e9
	for i in opts.size():
		if not opts[i].has("hex"):
			continue
		var h: Vector2i = opts[i]["hex"]
		var v := hex_safety(h, f) + (2.0 if s().objective_at(h.x, h.y) != null else 0.0) + _noise(0.5)
		if v > best_v:
			best_v = v
			best = i
	return best


# ─── Turno: quale ordine giocare ─────────────────────────────────────────────

func _best_shot(f: int) -> float:
	var st := s()
	var d := flow.opp(f)
	var best := 0.0
	var seen := {}
	for e in st.men_of(d):
		if seen.has(e.hex_key()):
			continue
		seen[e.hex_key()] = true
		var pieces: Array = []
		for u in st.men_of(f):
			if u.activated:
				continue
			for pc in flow.pieces_of(u):
				if not pc.ordnance and flow.can_hit(pc, e.pos()):
					pieces.append(pc)
		if pieces.is_empty():
			continue
		pieces = flow._chain(pieces)
		best = maxf(best, shot_value(flow.group_fp(pieces, e.pos()), e.pos(), d))
	return best


func _melee_odds(f: int, extra_fp: int, h: Vector2i) -> float:
	var mine := flow._melee_fp(f, h) + extra_fp
	var theirs := flow._melee_fp(flow.opp(f), h)
	return p_gt(theirs - mine)


func _best_advance(f: int) -> float:
	var best := 0.0
	for u in s().men_of(f):
		if u.activated:
			continue
		for nb in HexGrid.neighbors(u.q, u.r):
			if not flow.can_advance(u, nb):
				continue
			if flow.enemy_in(nb, f):
				var odds := _melee_odds(f, u.fp + (1 if u.fp_boxed else 0), nb)
				if odds >= 0.6:
					best = maxf(best, 18.0 + odds * 14.0)
			else:
				var o := s().objective_at(nb.x, nb.y)
				if o != null and o.controller != f and attacking(f):
					best = maxf(best, 16.0 + o.vp)
	return best


func _order_score(f: int, c: Card) -> float:
	var st := s()
	match c.order:
		Domain.OrderType.FIRE:
			return 9.0 + 16.0 * _best_shot(f)
		Domain.OrderType.MOVE:
			var n := 0
			for u in st.men_of(f):
				if not u.activated and u.efficient and goal_for(u) != u.pos():
					n += 1
			if n == 0:
				return 0.0
			return (11.0 if attacking(f) else 7.0) + minf(n, 5) * 1.5
		Domain.OrderType.ADVANCE:
			return _best_advance(f)
		Domain.OrderType.RECOVER:
			return 10.0 + 7.0 * st.broken_men_of(f).size() + 2.0 * st.suppressed_men_of(f).size()
		Domain.OrderType.ROUT:
			var foe := flow.opp(f)
			if st.rally_used.has(foe) or st.broken_men_of(foe).is_empty():
				return 0.0
			return 9.0 + 4.0 * st.broken_men_of(foe).size()
		Domain.OrderType.ARTY:
			var r := flow.radio_of(f)
			if r != null and not r.efficient:
				return 12.0
			return 8.0 + 5.0 * _arty_best(f)[1]
		Domain.OrderType.ARTY_DENIED:
			return 13.0
	return 0.0


func _pick_turn(f: int, opts: Array) -> int:
	var best := -1
	var best_v := 8.5
	for i in opts.size():
		if String(opts[i]["id"]) != "order":
			continue
		var c: Card = flow.hand(f)[int(opts[i]["card"])]
		var v := _order_score(f, c) + _noise(4.0)
		if v > best_v:
			best_v = v
			best = i
	if best >= 0:
		return best
	# Niente di utile da ordinare: scartare fa girare il mazzo (e il Tempo).
	var d := _idx(opts, "discard")
	if d >= 0 and not flow.hand(f).is_empty():
		return d
	return _idx(opts, "end")


## Carte poco utili da tenere: ordini che ora non servono a niente.
func _duds(f: int) -> Array:
	var out: Array = []
	var h := flow.hand(f)
	for i in h.size():
		var c: Card = h[i]
		if c.order == Domain.OrderType.FIRE:
			continue  # serve anche per il Fuoco di Opportunità
		if c.order == Domain.OrderType.RECOVER and c.action_name in ["FUOCO SOSTENUTO", "BOMBE A MANO", "MIMETIZZAZIONE", "IMBOSCATA"]:
			continue
		if flow.order_block(f, c) != "" or _order_score(f, c) < 6.0:
			out.append(i)
	return out


func _pick_discard(f: int, opts: Array, p: Dictionary) -> int:
	var sel: Array = p.get("selected_cards", [])
	var duds := _duds(f)
	if duds.is_empty() and sel.is_empty():
		# Nessuna carta inutile: cedi comunque la meno preziosa per pescare.
		var h := flow.hand(f)
		var worst := -1
		var worst_v := 1e9
		for i in h.size():
			var v := _order_score(f, h[i]) + (6.0 if h[i].order == Domain.OrderType.FIRE else 0.0)
			if v < worst_v:
				worst_v = v
				worst = i
		duds = [worst]
	for i in opts.size():
		if String(opts[i]["id"]) == "toggle" and not bool(opts[i]["on"]) \
				and duds.has(int(opts[i]["card"])) and not sel.has(int(opts[i]["card"])):
			return i
	return _idx(opts, "confirm")


func _pick_activate(f: int, opts: Array, p: Dictionary) -> int:
	var order := int(p.get("order", Domain.OrderType.MOVE))
	var best := 0
	var best_v := -1e9
	for i in opts.size():
		var u: Unit = s().unit_by_id(String(opts[i].get("unit", "")))
		if u == null:
			continue
		var grp: Array = [u]
		for fo in flow.followers_of(u):
			if flow.useful(fo, order):
				grp.append(fo)
		var v := 0.0
		match order:
			Domain.OrderType.FIRE:
				for g: Unit in grp:
					for pc in flow.pieces_of(g):
						if not flow.targets_of(pc).is_empty():
							v += 1.0 + Rules.fp_with_command(s(), pc) * 0.3
			Domain.OrderType.MOVE:
				for g: Unit in grp:
					if g.efficient and goal_for(g) != g.pos():
						v += 1.0 + _dist(g.pos(), goal_for(g)) * 0.1
			_:
				for g: Unit in grp:
					for nb in HexGrid.neighbors(g.q, g.r):
						if flow.can_advance(g, nb) and flow.enemy_in(nb, f):
							v += 2.0
					v += 0.5
		v += _noise(0.6)
		if v > best_v:
			best_v = v
			best = i
	return best


# ─── Movimento ───────────────────────────────────────────────────────────────

func _pick_move(f: int, opts: Array, p: Dictionary) -> int:
	var u: Unit = s().unit_by_id(String(p.get("unit", "")))
	var stop := _idx(opts, "stop")
	if u == null:
		return stop
	var a := _idx(opts, "assault")
	if a >= 0:
		return a
	var ex := _idx(opts, "exit")
	if ex >= 0 and attacking(f) and s().objective_at(u.q, u.r) == null:
		return ex
	if not u.efficient:
		# Un'unità rotta cerca solo riparo, lontano dal nemico.
		var bi := stop
		var bv := hex_safety(u.pos(), f)
		for i in opts.size():
			if String(opts[i]["id"]) == "step":
				var v := hex_safety(opts[i]["hex"], f)
				if v > bv + 0.5:
					bv = v
					bi = i
		return bi
	var goal := goal_for(u)
	var here := _dist(u.pos(), goal)
	if crowded(u, u.pos()):
		# Non fermarti dove a fine turno ci sarebbero troppe figure.
		var bi2 := stop
		var bv2 := -1e9
		for i in opts.size():
			if String(opts[i]["id"]) == "step" and not crowded(u, opts[i]["hex"]):
				var v2 := -_dist(opts[i]["hex"], goal) * 3.0 + hex_safety(opts[i]["hex"], f)
				if v2 > bv2:
					bv2 = v2
					bi2 = i
		if bi2 != stop:
			return bi2
	if here == 0:
		return stop
	var best := stop
	var best_v := -1e9
	for i in opts.size():
		if String(opts[i]["id"]) != "step":
			continue
		var h: Vector2i = opts[i]["hex"]
		var dd := _dist(h, goal)
		if dd >= here:
			continue
		var v := -dd * 3.0 + hex_safety(h, f) - int(opts[i].get("cost", 1)) * 0.4 + _noise(0.8)
		if flow.s.hex_at(h.x, h.y).fortification in [Domain.Fort.MINES, Domain.Fort.WIRE]:
			v -= 6.0
		if crowded(u, h) and int(p.get("left", 0)) - int(opts[i].get("cost", 1)) < 1:
			v -= 20.0
		if v > best_v:
			best_v = v
			best = i
	if best == stop:
		return stop
	# Non uscire da una buona copertura per finire allo scoperto sotto tiro di
	# molti nemici, a meno che la meta sia vicina.
	var h2: Vector2i = opts[best]["hex"]
	if exposure(h2, f) >= 3.0 and Rules.cover_at(s(), h2.x, h2.y, false) <= 0 and here > 2 and level >= 1:
		var sm := _idx(opts, "smoke")
		if sm >= 0:
			return sm
		if exposure(u.pos(), f) < exposure(h2, f) and int(p.get("left", 0)) < 99 and rng.randf() < 0.5:
			return stop
	return best


func _pick_advance(f: int, opts: Array, p: Dictionary) -> int:
	var u: Unit = s().unit_by_id(String(p.get("unit", "")))
	var stay := _idx(opts, "stay")
	if u == null:
		return stay
	var best := stay
	var best_v := 0.0
	var goal := goal_for(u)
	var here := _dist(u.pos(), goal)
	for i in opts.size():
		var id := String(opts[i]["id"])
		if id == "exit" and attacking(f):
			return i
		if id != "hex":
			continue
		var h: Vector2i = opts[i]["hex"]
		var v := -1.0
		if flow.enemy_in(h, f):
			var odds := _melee_odds(f, u.fp + (1 if u.fp_boxed else 0), h)
			if odds >= 0.55:
				v = 10.0 + odds * 10.0
		elif u.efficient and not crowded(u, h):
			var dd := _dist(h, goal)
			if dd < here:
				v = 2.0 + hex_safety(h, f) * 0.5
				var o := s().objective_at(h.x, h.y)
				if o != null and o.controller != f:
					v += 8.0
		if v > best_v:
			best_v = v
			best = i
	return best


# ─── Fuoco ───────────────────────────────────────────────────────────────────

func _pick_react(f: int, opts: Array, p: Dictionary) -> int:
	var h: Vector2i = p["hex"]
	var st := s()
	var mi := _idx(opts, "mines")
	if mi >= 0:
		return mi
	var free := _idx(opts, "opfire")
	if free >= 0:
		var pcs := flow._opfire_ready(f, h)
		pcs = flow._chain(pcs)
		if shot_value(flow.group_fp(pcs, h), h, flow.opp(f), false, true) > 0.25:
			return free
	var card := _idx(opts, "opfire_card")
	if card >= 0:
		var pieces: Array = []
		for u in st.men_of(f):
			if u.activated:
				continue
			for pc in flow.pieces_of(u):
				if not pc.ordnance and flow.can_hit(pc, h):
					pieces.append(pc)
		pieces = flow._chain(pieces)
		var ev := shot_value(flow.group_fp(pieces, h), h, flow.opp(f), false, true)
		var near_obj := false
		for o in st.objectives:
			if HexGrid.distance(o.q, o.r, h.x, h.y) <= 1:
				near_obj = true
		var fires := 0
		for c in flow.hand(f):
			if c.order == Domain.OrderType.FIRE:
				fires += 1
		var need := 0.9 if fires <= 1 else 0.55
		if near_obj:
			need -= 0.25
		if ev + _noise(0.2) >= need:
			return card
	var wi := _idx(opts, "wire")
	if wi >= 0 and st.objective_at(h.x, h.y) == null:
		return wi
	return _idx(opts, "pass")


func _pick_target(f: int, opts: Array) -> int:
	var best := -1
	var best_v := 0.12
	var d := flow.opp(f)
	for i in opts.size():
		if String(opts[i]["id"]) != "hex":
			continue
		var h: Vector2i = opts[i]["hex"]
		var fp := int(opts[i].get("fp", 4))
		var v := shot_value(fp, h, d) + _noise(0.15)
		if v > best_v:
			best_v = v
			best = i
	if best >= 0:
		return best
	var e := _idx(opts, "end")
	if e >= 0:
		return e
	return 0


func _pick_mods(f: int, opts: Array, p: Dictionary) -> int:
	var go := _idx(opts, "go")
	var h: Vector2i = p["hex"]
	var fp := int(p.get("fp", 0))
	var d := flow.opp(f)
	var base := shot_value(fp, h, d)
	for i in opts.size():
		var id := String(opts[i]["id"])
		if id == "go":
			continue
		var c: Card = flow.hand(f)[int(opts[i]["card"])]
		# Non bruciare un ordine prezioso per un +2 marginale.
		var keep := 0.0
		if c.order in [Domain.OrderType.FIRE, Domain.OrderType.RECOVER, Domain.OrderType.ADVANCE]:
			keep = 0.45
		elif c.order == Domain.OrderType.MOVE and attacking(f):
			keep = 0.35
		if id == "spray":
			if shot_value(fp, opts[i]["hex"], d) > keep:
				return i
			continue
		var gain := shot_value(fp + 2, h, d) - base
		if id == "sustained":
			gain -= 0.08
		if gain > keep + 0.12:
			return i
	return go


func _pick_defense(f: int, opts: Array, p: Dictionary) -> int:
	var h: Vector2i = p["hex"]
	var total := int(p.get("total", 0))
	var pb := _idx(opts, "pillbox")
	if pb >= 0:
		return pb
	# Quanto è grave l'attacco per chi sta nell'esagono?
	var danger := 0.0
	var cover := Rules.cover_at(s(), h.x, h.y, false)
	for t in s().men_at(h.x, h.y):
		if t.faction == f:
			var m := flow.morale_of(t) + cover
			danger += (1.0 - _p_2d6_ge(total - m + 1)) * unit_value(t)
	if danger < 1.0:
		return _idx(opts, "no")
	var en := _idx(opts, "entrench")
	if en >= 0 and cover < 3:
		return en
	var co := _idx(opts, "conceal")
	if co >= 0:
		return co
	return _idx(opts, "no")


## P(2d6 ≥ n)
func _p_2d6_ge(n: int) -> float:
	if n <= 2:
		return 1.0
	if n > 12:
		return 0.0
	var ways := 0
	for a in range(1, 7):
		for b in range(1, 7):
			if a + b >= n:
				ways += 1
	return ways / 36.0


# ─── Artiglieria ─────────────────────────────────────────────────────────────

## [esagono migliore, valore] per un tiro d'artiglieria osservabile.
func _arty_best(f: int) -> Array:
	var st := s()
	var best := Vector2i(-1, -1)
	var best_v := 0.0
	var spot := flow._spotters(f)
	if spot.is_empty():
		return [best, 0.0]
	var seen := {}
	for e in st.men_of(flow.opp(f)):
		if seen.has(e.hex_key()):
			continue
		seen[e.hex_key()] = true
		var ok := false
		for L: Unit in spot:
			if HexGrid.has_los(L.q, L.r, e.q, e.r, st):
				ok = true
		if not ok:
			continue
		var v := _blast_value(f, e.pos())
		if v > best_v:
			best_v = v
			best = e.pos()
	return [best, best_v]


func _blast_value(f: int, h: Vector2i) -> float:
	var v := 0.0
	var area: Array = [h]
	area.append_array(HexGrid.neighbors(h.x, h.y))
	for hx: Vector2i in area:
		for u in s().men_at(hx.x, hx.y):
			v += unit_value(u) * (0.5 if u.faction != f else -0.8)
	return v


func _pick_arty(f: int, opts: Array) -> int:
	var best := 0
	var best_v := -1e9
	for i in opts.size():
		var v := _blast_value(f, opts[i]["hex"])
		if v > best_v:
			best_v = v
			best = i
	return best
