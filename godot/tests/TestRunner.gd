## Test del motore di gioco — eseguibile headless, senza dipendenze da asset.
##   godot --headless --path godot res://tests/TestRunner.tscn
## Esce con codice 0 se tutti i controlli passano, 1 altrimenti, e stampa
## "TEST_RESULT: PASS" / "TEST_RESULT: FAIL" per il filtro CI.
extends Node

var _failures: Array[String] = []
var _checks := 0
var _rng := RandomNumberGenerator.new()

# Alias di fazione/tipo (gli autoload non sono espressioni costanti).
var GER: int
var RUS: int
var SQUAD: int
var LEADER: int
var RIFLE: int
var ELITE: int


func _ready() -> void:
	_rng.seed = 1234567
	GER = Domain.Faction.GERMAN
	RUS = Domain.Faction.RUSSIAN
	SQUAD = Domain.UnitType.SQUAD
	LEADER = Domain.UnitType.LEADER
	RIFLE = Domain.UnitClass.RIFLE
	ELITE = Domain.UnitClass.ELITE

	print("══ Test motore CC:E ══")
	_test_fire_break_then_eliminate()
	_test_fire_no_effect()
	_test_leadership_and_group()
	_test_command_multihex()
	_test_command_stats()
	_test_recover()
	_test_melee_winner_and_losses()
	_test_rout_retreat()
	_test_rout_trapped()
	_test_ai_best_fire()
	_test_ai_best_advance()
	_test_ai_choose_play()
	_test_fate_draw_and_reshuffle()
	_test_fate_time()
	_test_fate_sniper()
	_test_fate_jam()
	_test_los_hexside()
	_test_los_hindrance()
	_test_step_cost()
	_test_event_air_support()
	_test_event_rubble()
	_test_event_kia()
	_test_event_suppressing_fire()
	_test_event_medic()
	_test_event_malfunction()
	_test_event_breeze()
	_test_event_commissar()
	_test_event_hero()
	_test_elimination_vp()
	_test_spray_fire()
	_test_fortifications()
	_test_objectives_vp()
	_test_op_fire()
	_test_actions()
	_test_grenade()
	_test_melee_tie()
	_test_stacking()
	_test_fire_suppress()
	_test_fire_moving_break()
	_test_maps_load()
	_test_unit_chart()
	_test_scenarios_load()
	_test_scenario_fidelity()
	_test_setup_depth()
	_test_surrender()
	_test_sudden_death_roll()
	_test_ordnance()
	_test_counter_art()
	_test_decks()
	_test_save_load()
	_test_audio()
	_report()


# ─── Helper ────────────────────────────────────────────────────────────────────

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("  [ok] ", msg)
	else:
		_failures.append(msg)
		print("  [NO] ", msg)


func _new_state(cols: int = 5, rows: int = 5) -> GameState:
	var s := GameState.new()
	s.map_cols = cols
	s.map_rows = rows
	for q in cols:
		for r in rows:
			s.hexes["%d,%d" % [q, r]] = GameState.HexData.new(Domain.TerrainType.OPEN)
	return s


func _mk(
	id: String, faction: int, type: int, cls: int, q: int, r: int,
	fp: int = 5, morale: int = 7, rng_val: int = 6, cmd: int = 0
) -> Unit:
	var u := Unit.new(id, faction, type, cls, id)
	u.fp = fp
	u.range = rng_val
	u.move = 4
	u.morale = morale
	u.command = cmd
	u.q = q
	u.r = r
	return u


# ─── Test ───────────────────────────────────────────────────────────────────────

func _test_fire_break_then_eliminate() -> void:
	print("· Fuoco: rottura poi eliminazione")
	var s := _new_state()
	var atk := _mk("ger", GER, SQUAD, RIFLE, 0, 0, 40, 7)  # FP enorme → colpisce sempre
	var tgt := _mk("rus", RUS, SQUAD, RIFLE, 0, 1, 5, 7)
	s.units[atk.id] = atk
	s.units[tgt.id] = tgt

	var r1 := Combat.resolve_fire(atk, 0, 1, s, Vector2i(6, 6), Vector2i(1, 1))
	_check(r1.broken.has("rus"), "unità efficiente colpita si rompe")
	_check(s.units.has("rus"), "unità rotta resta in gioco")
	_check(s.units.has("rus") and not s.units["rus"].efficient, "unità marcata come rotta")

	var r2 := Combat.resolve_fire(atk, 0, 1, s, Vector2i(6, 6), Vector2i(1, 1))
	_check(r2.eliminated.has("rus"), "unità già rotta colpita viene eliminata")
	_check(not s.units.has("rus"), "unità eliminata rimossa dallo stato")


func _test_fire_no_effect() -> void:
	print("· Fuoco: nessun effetto sotto morale")
	var s := _new_state()
	var atk := _mk("ger", GER, SQUAD, RIFLE, 0, 0, 1, 7)
	var tgt := _mk("rus", RUS, SQUAD, RIFLE, 0, 1, 5, 99)  # morale irraggiungibile
	s.units[atk.id] = atk
	s.units[tgt.id] = tgt
	var r := Combat.resolve_fire(atk, 0, 1, s, Vector2i(6, 6), Vector2i(1, 1))
	_check(r.broken.is_empty() and r.eliminated.is_empty() and r.suppressed.is_empty(), "difesa > attacco → nessun effetto")
	_check(s.units["rus"].efficient, "bersaglio resta efficiente")


func _test_leadership_and_group() -> void:
	print("· Comando e gruppo di fuoco")
	var s := _new_state()
	var sq := _mk("ger-sq", GER, SQUAD, RIFLE, 0, 0, 5, 7)
	var ld := _mk("ger-ld", GER, LEADER, ELITE, 0, 0, 1, 9, 6, 2)  # comando 2
	s.units[sq.id] = sq
	s.units[ld.id] = ld
	_check(Rules.command_bonus_at(s, 0, 0, GER) == 2, "bonus comando = miglior leader nell'esagono")
	_check(Rules.command_bonus_at(s, 0, 0, RUS) == 0, "nessun bonus comando per fazione assente")
	var grp := Combat.fire_group(sq, 0, 1, s)
	_check(grp.size() == 2, "gruppo di fuoco include le unità co-locate in gittata")


func _test_command_multihex() -> void:
	print("· Comando multi-esagono: gruppo di fuoco da esagoni diversi")
	var s := _new_state(6, 3)
	var sq1 := _mk("g1", GER, SQUAD, RIFLE, 0, 0, 5, 7)
	var ld := _mk("gl", GER, LEADER, ELITE, 0, 0, 1, 9, 6, 2)  # comando 2
	var sq2 := _mk("g2", GER, SQUAD, RIFLE, 1, 0, 5, 7)        # esagono adiacente
	var tgt := _mk("r", RUS, SQUAD, RIFLE, 3, 0, 5, 7)
	for u in [sq1, ld, sq2, tgt]:
		s.units[u.id] = u
	var grp := Combat.fire_group(sq1, 3, 0, s)
	_check(grp.any(func(u: Unit) -> bool: return u.id == "g2"),
		"con leader: unità entro il comando entra nel gruppo da un altro esagono")
	# Senza leader: solo unità co-locate.
	s.units.erase("gl")
	var grp2 := Combat.fire_group(sq1, 3, 0, s)
	_check(not grp2.any(func(u: Unit) -> bool: return u.id == "g2"),
		"senza leader: niente gruppo multi-esagono")


func _test_command_stats() -> void:
	print("· Comando: gittata/movimento/FP/armi/difesa (3.3.1.2-.3)")
	var s := _new_state(8, 3)
	var sq := _mk("g-sq", GER, SQUAD, RIFLE, 0, 0, 5, 7, 6)        # FP5 gittata6 mov4
	var ld := _mk("g-ld", GER, LEADER, ELITE, 0, 0, 1, 9, 6, 2)    # comando 2, co-locato
	s.units[sq.id] = sq
	s.units[ld.id] = ld
	_check(Rules.range_with_command(s, sq) == 8, "gittata squadra + comando (6+2)")
	_check(Rules.move_with_command(s, sq) == 6, "movimento squadra + comando (4+2)")
	_check(Rules.fp_with_command(s, sq) == 7, "FP squadra + comando (5+2)")
	_check(Rules.range_with_command(s, ld) == 6, "il leader non estende la propria gittata")
	_check(Rules.unit_command_bonus(s, ld) == 0, "il Comando non si applica ai leader stessi")

	# Arma normale: weapon command su FP/gittata; ordnance esclusa (3.3.1.3).
	var wpn := _mk("g-w", GER, Domain.UnitType.WEAPON, RIFLE, 0, 0, 8, 7, 10)
	s.units[wpn.id] = wpn
	_check(Rules.range_with_command(s, wpn) == 12, "arma: gittata + comando (10+2)")
	_check(Rules.fp_with_command(s, wpn) == 10, "arma: FP + comando (8+2)")
	wpn.ordnance = true
	_check(Rules.range_with_command(s, wpn) == 10, "ordnance: gittata NON modificata dal comando")
	_check(Rules.fp_with_command(s, wpn) == 8, "ordnance: FP NON modificato dal comando")

	# Difesa (3.3.1.2): un leader co-locato alza la Morale dei difensori → protegge.
	var s2 := _new_state(4, 3)
	var atk := _mk("a", RUS, SQUAD, RIFLE, 0, 0, 5, 7, 6)
	var dsq := _mk("d", GER, SQUAD, RIFLE, 0, 1, 5, 7, 6)
	var dld := _mk("dl", GER, LEADER, ELITE, 0, 1, 1, 9, 6, 3)     # comando 3 nel bersaglio
	for u in [atk, dsq, dld]:
		s2.units[u.id] = u
	# Attacco 5+dadi(3,3)=11; difesa squadra 7+0+dadi(1,1)=2 +cmd3 = 12 > 11 → regge.
	Combat.resolve_fire(atk, 0, 1, s2, Vector2i(3, 3), Vector2i(1, 1))
	_check(s2.units.has("d") and s2.units["d"].efficient, "difensore protetto dal Comando (non si rompe)")

	var s3 := _new_state(4, 3)
	var atk3 := _mk("a", RUS, SQUAD, RIFLE, 0, 0, 5, 7, 6)
	var dsq3 := _mk("d", GER, SQUAD, RIFLE, 0, 1, 5, 7, 6)         # stessa squadra, NESSUN leader
	s3.units[atk3.id] = atk3
	s3.units[dsq3.id] = dsq3
	Combat.resolve_fire(atk3, 0, 1, s3, Vector2i(3, 3), Vector2i(1, 1))
	_check(s3.units.has("d") and not s3.units["d"].efficient, "senza leader: la stessa squadra si rompe")


func _test_recover() -> void:
	print("· Recupero (tiro di morale)")
	var s := _new_state()
	var u := _mk("rus", RUS, SQUAD, RIFLE, 2, 2, 5, 12)  # morale 12 → 2d6 sempre ≤ 12
	u.break_unit()
	s.units[u.id] = u
	var r := Rules.try_recover(s, u, Vector2i(6, 6))  # 12 ≤ 12 → riuscito
	_check(r["success"] and u.efficient, "morale 12 → recupero sempre riuscito")

	var u2 := _mk("rus2", RUS, SQUAD, RIFLE, 4, 4, 5, 1)  # morale 1
	u2.break_unit()
	s.units[u2.id] = u2
	var r2 := Rules.try_recover(s, u2, Vector2i(1, 1))  # 2 > 1 → fallito
	_check(not r2["success"] and not u2.efficient, "morale 1 → recupero sempre fallito")


func _test_melee_winner_and_losses() -> void:
	print("· Corpo a corpo (O21)")
	var s := _new_state()
	var a := _mk("ger-a", GER, SQUAD, RIFLE, 1, 1, 30, 7)  # forte
	var d1 := _mk("rus-1", RUS, SQUAD, RIFLE, 1, 1, 1, 7)
	var d2 := _mk("rus-2", RUS, SQUAD, RIFLE, 1, 1, 1, 7)
	s.units[a.id] = a
	s.units[d1.id] = d1
	s.units[d2.id] = d2
	var attackers: Array[Unit] = [a]
	var defenders: Array[Unit] = [d1, d2]
	var mr := Rules.resolve_melee(s, attackers, defenders, Vector2i(1, 1), Vector2i(6, 6))
	_check(mr.winner == GER, "vince il lato con totale più alto")
	_check(mr.eliminated.has("rus-1") and mr.eliminated.has("rus-2"), "il lato perdente perde TUTTE le unità")
	_check(not s.units.has("rus-1") and not s.units.has("rus-2"), "perdenti rimossi dallo stato")
	_check(s.units.has("ger-a"), "vincitore resta in gioco")


func _test_rout_retreat() -> void:
	print("· Rotta: ritirata verso il bordo amico")
	var s := _new_state()
	var u := _mk("ger", GER, SQUAD, RIFLE, 1, 2, 5, 0)  # morale 0 → passi = tiro > 0
	u.break_unit()
	s.units[u.id] = u
	var r := Rules.rout_unit(s, u, Vector2i(3, 3))  # passi = 6 - 0 = 6 > 0
	_check(not r["eliminated"], "non eliminata se ha via di fuga")
	_check(u.q > 1, "si ritira verso est (bordo tedesco, q cresce)")


func _test_rout_trapped() -> void:
	print("· Rotta: eliminazione se intrappolata")
	var s := _new_state()
	var u := _mk("ger", GER, SQUAD, RIFLE, 2, 2, 5, 12)  # morale 12 → passi ≤ 0
	u.break_unit()
	var e := _mk("rus", RUS, SQUAD, RIFLE, 3, 2, 5, 7)   # nemico adiacente
	s.units[u.id] = u
	s.units[e.id] = e
	var r := Rules.rout_unit(s, u, Vector2i(6, 6))  # passi = 12 - 12 = 0 → bloccata
	_check(r["eliminated"], "intrappolata + nemico adiacente → eliminata")
	_check(not s.units.has("ger"), "unità intrappolata rimossa")


func _test_ai_best_fire() -> void:
	print("· IA: scelta del fuoco")
	var s := _new_state()
	var ai := _mk("rus", RUS, SQUAD, RIFLE, 0, 0, 6, 7)
	var foe := _mk("ger", GER, SQUAD, RIFLE, 0, 1, 5, 7)
	s.units[ai.id] = ai
	s.units[foe.id] = foe
	var f := AI.best_fire(s, RUS)
	_check(not f.is_empty(), "IA trova un bersaglio di fuoco")
	_check(String(f.get("attacker_id", "")) == "rus", "IA sceglie lo sparatore corretto")
	_check(int(f.get("q", -9)) == 0 and int(f.get("r", -9)) == 1, "IA sceglie l'esagono bersaglio")
	s.units.erase("ger")
	_check(AI.best_fire(s, RUS).is_empty(), "IA non spara senza bersagli")


func _test_ai_best_advance() -> void:
	print("· IA: scelta dell'avanzata")
	var s := _new_state()
	var strong := _mk("rus", RUS, SQUAD, RIFLE, 1, 1, 8, 7)
	var weak := _mk("ger", GER, SQUAD, RIFLE, 2, 1, 1, 7)  # adiacente a (1,1)
	s.units[strong.id] = strong
	s.units[weak.id] = weak
	var a := AI.best_advance(s, RUS)
	_check(not a.is_empty(), "IA trova un'avanzata vantaggiosa")
	_check(String(a.get("unit_id", "")) == "rus", "IA sceglie l'attaccante corretto")
	weak.fp = 20
	_check(AI.best_advance(s, RUS).is_empty(), "IA non avanza contro un nemico più forte")


func _test_ai_choose_play() -> void:
	print("· IA: scelta dell'ordine dalla mano")
	var s := _new_state()
	var ai := _mk("rus", RUS, SQUAD, RIFLE, 0, 0, 6, 7)
	var foe := _mk("ger", GER, SQUAD, RIFLE, 0, 1, 5, 7)
	s.units[ai.id] = ai
	s.units[foe.id] = foe
	var move_card := Card.new()
	move_card.order = Domain.OrderType.MOVE
	var fire_card := Card.new()
	fire_card.order = Domain.OrderType.FIRE
	s.russian_hand.append(move_card)
	s.russian_hand.append(fire_card)
	var play := AI.choose_play(s, RUS)
	_check(not play.is_empty(), "IA sceglie un ordine")
	_check(int(play.get("order", -1)) == Domain.OrderType.FIRE, "IA preferisce il Fuoco al Movimento se può colpire")
	_check(int(play.get("card_index", -1)) == 1, "IA punta alla carta Fuoco in mano")


func _fate_card(white: int, red: int, consequence: String = "") -> Card:
	var c := Card.new()
	c.dice_white = white
	c.dice_red = red
	c.consequence = consequence
	return c


func _test_fate_draw_and_reshuffle() -> void:
	print("· Fato: pescata e rimescolo")
	var s := _new_state()
	s.russian_deck.append(_fate_card(1, 2))
	s.russian_deck.append(_fate_card(3, 4))
	var d1 := Fate.draw(s, RUS)
	var d2 := Fate.draw(s, RUS)
	_check(d1 != null and d2 != null, "Fate.draw restituisce le carte")
	_check(s.russian_deck.is_empty(), "il mazzo si svuota dopo le pescate")
	_check(s.russian_discard.size() == 2, "le carte pescate vanno negli scarti")
	var d3 := Fate.draw(s, RUS)
	_check(d3 != null, "Fate.draw rimescola gli scarti quando il mazzo è vuoto")


func _test_fate_time() -> void:
	print("· Fato: conseguenza TEMPO")
	var s := _new_state()
	s.time_marker = 2
	s.sudden_death_space = 7
	var lines := Fate.apply_consequence(s, _fate_card(1, 1, "time"), RUS)
	_check(s.time_marker == 3, "TEMPO! avanza la traccia del tempo")
	_check(lines.size() > 0, "la conseguenza produce un messaggio di log")


func _test_fate_sniper() -> void:
	print("· Fato: conseguenza CECCHINO")
	var s := _new_state()
	var foe := _mk("ger", GER, SQUAD, RIFLE, 1, 1, 5, 7)  # B2 = (1,1)
	s.units[foe.id] = foe
	var card := _fate_card(6, 6, "sniper")
	card.random_hex_label = "B2"
	Fate.apply_consequence(s, card, RUS)  # cecchino russo colpisce il tedesco
	_check(not foe.efficient, "il cecchino rompe il nemico nell'esagono indicato")


func _test_fate_jam() -> void:
	print("· Fato: conseguenza INCEPPAMENTO")
	var s := _new_state()
	var mg := _mk("mg", RUS, Domain.UnitType.WEAPON, Domain.UnitClass.MG, 2, 2, 4, 7)
	s.units[mg.id] = mg
	Fate.apply_consequence(s, _fate_card(1, 1, "jam"), RUS, { "kind": "fire", "weapons": ["mg"] })
	_check(not mg.efficient, "l'inceppamento mette l'arma fuori uso")


func _side(a: Vector2i, b: Vector2i, feat: int) -> Dictionary:
	return { "a": a, "b": b, "feature": feat }


func _test_los_hexside() -> void:
	print("· LOS: lati di esagono (muro/varco)")
	# Sulla linea (0,0)→(3,0) il lato intermedio è tra (1,0) e (2,0).
	_check(HexGrid.has_los(0, 0, 3, 0, _new_state()), "LOS libera senza ostacoli")

	var sw := _new_state()
	sw.side_features.append(_side(Vector2i(1, 0), Vector2i(2, 0), Domain.HexsideFeature.WALL))
	_check(not HexGrid.has_los(0, 0, 3, 0, sw), "un muro su un lato intermedio blocca la LOS")

	var sg := _new_state()
	sg.side_features.append(_side(Vector2i(1, 0), Vector2i(2, 0), Domain.HexsideFeature.LOS_CLEAR))
	_check(HexGrid.has_los(0, 0, 3, 0, sg), "un varco (LOS_CLEAR) lascia libera la LOS")

	var se := _new_state()
	se.side_features.append(_side(Vector2i(0, 0), Vector2i(1, 0), Domain.HexsideFeature.WALL))
	_check(HexGrid.has_los(0, 0, 3, 0, se), "un muro sul lato di estremità non blocca")


func _test_los_hindrance() -> void:
	print("· LOS: hindrance (frutteto)")
	var s := _new_state()
	_check(HexGrid.los_hindrance(0, 0, 3, 0, s) == 0, "nessun hindrance su terreno aperto")
	s.hexes["1,0"].terrain = Domain.TerrainType.ORCHARD
	s.hexes["2,0"].terrain = Domain.TerrainType.ORCHARD
	_check(HexGrid.los_hindrance(0, 0, 3, 0, s) == 2, "due frutteti intermedi danno hindrance 2")


func _test_step_cost() -> void:
	print("· Movimento: costo dei lati e tariffa strada")
	_check(HexGrid.step_cost(_new_state(), 0, 0, 1, 0) == 1, "terreno aperto costa 1")

	var sw := _new_state()
	sw.side_features.append(_side(Vector2i(0, 0), Vector2i(1, 0), Domain.HexsideFeature.WALL))
	_check(HexGrid.step_cost(sw, 0, 0, 1, 0) == 2, "attraversare un muro costa +1")

	var sc := _new_state()
	sc.side_features.append(_side(Vector2i(0, 0), Vector2i(1, 0), Domain.HexsideFeature.CLIFF))
	_check(HexGrid.step_cost(sc, 0, 0, 1, 0) == -1, "un dirupo è impassabile")

	var sr := _new_state()
	sr.hexes["0,0"].has_road = true
	sr.hexes["1,0"].has_road = true
	sr.hexes["1,0"].terrain = Domain.TerrainType.WOODS
	_check(HexGrid.step_cost(sr, 0, 0, 1, 0) == 1, "lungo la strada anche il bosco costa 1")


func _ev(name: String) -> Card:
	var c := Card.new()
	c.event_name = name
	return c


func _test_event_air_support() -> void:
	print("· Evento: Supporto aereo")
	var s := _new_state()
	var a := _mk("ger", GER, SQUAD, RIFLE, 1, 1, 5, 7)  # B2 = (1,1)
	var b := _mk("rus", RUS, SQUAD, RIFLE, 1, 1, 5, 7)
	s.units[a.id] = a
	s.units[b.id] = b
	var card := _ev("SUPPORTO AEREO")
	card.consequence = "event"  # così Fate.apply_consequence instrada verso Events.fire
	card.random_hex_label = "B2"
	var lines := Fate.apply_consequence(s, card, GER)
	_check(not a.efficient and not b.efficient, "Supporto aereo rompe tutte le unità nell'esagono")
	_check(lines.size() >= 2, "l'evento, via Fate, registra gli effetti")


func _test_event_rubble() -> void:
	print("· Evento: Macerie")
	var s := _new_state()
	var card := _ev("MACERIE")
	card.random_hex_label = "C3"  # (2,2)
	Events.fire(s, card, GER)
	var hd := s.hex_at(2, 2)
	_check(hd != null and hd.terrain == Domain.TerrainType.RUBBLE, "Macerie converte l'esagono in Rubble")


func _test_event_kia() -> void:
	print("· Evento: Ucciso in azione")
	var s := _new_state()
	var foe := _mk("rus", RUS, SQUAD, RIFLE, 0, 0, 5, 7)
	foe.break_unit()
	s.units[foe.id] = foe
	Events.fire(s, _ev("UCCISO IN AZIONE"), GER)
	_check(not s.units.has("rus"), "Ucciso in azione elimina un'unità rotta nemica")


func _test_event_suppressing_fire() -> void:
	print("· Evento: Fuoco di soppressione")
	var s := _new_state()
	var mg := _mk("mg", GER, Domain.UnitType.WEAPON, Domain.UnitClass.MG, 0, 0, 4, 7)
	var foe := _mk("rus", RUS, SQUAD, RIFLE, 0, 1, 5, 7)  # adiacente, LOS libera
	s.units[mg.id] = mg
	s.units[foe.id] = foe
	Events.fire(s, _ev("FUOCO DI SOPPRESSIONE"), GER)
	_check(foe.suppressed, "Fuoco di soppressione sopprime il nemico in gittata/LOS dell'MG")


func _test_event_medic() -> void:
	print("· Evento: Medico (rally)")
	var s := _new_state()
	var u := _mk("ger", GER, SQUAD, RIFLE, 0, 0, 5, 7)
	u.break_unit()
	s.units[u.id] = u
	Events.fire(s, _ev("MEDICO"), GER)
	_check(s.units["ger"].efficient, "Medico ripristina un'unità rotta amica")


func _test_event_malfunction() -> void:
	print("· Evento: Malfunzionamento (arma più vicina si rompe)")
	var s := _new_state()
	var w := _mk("mg", GER, Domain.UnitType.WEAPON, Domain.UnitClass.MG, 0, 0, 4, 7)
	s.units[w.id] = w
	var card := _ev("MALFUNZIONAMENTO")
	card.random_hex_label = "A1"  # (0,0)
	Events.fire(s, card, RUS)
	_check(not s.units["mg"].efficient, "Malfunzionamento rompe l'arma efficiente più vicina")


func _test_event_breeze() -> void:
	print("· Evento: Brezza (rimuove il fumo)")
	var s := _new_state()
	s.hex_at(1, 1).has_smoke = true
	s.hex_at(2, 2).has_smoke = true
	Events.fire(s, _ev("BREZZA"), GER)
	_check(not s.hex_at(1, 1).has_smoke and not s.hex_at(2, 2).has_smoke, "Brezza rimuove tutti i fumi")


func _test_event_commissar() -> void:
	print("· Evento: Commissario (tiro vs morale)")
	var s := _new_state()
	var lo := _mk("rus-lo", RUS, SQUAD, RIFLE, 0, 0, 5, 4)  # morale basso 4
	lo.break_unit()
	s.units[lo.id] = lo
	var hi := _ev("COMMISSARIO")
	hi.dice_white = 6
	hi.dice_red = 6  # tiro 12 > 4 → eliminata
	Events.fire(s, hi, GER)
	_check(not s.units.has("rus-lo"), "Commissario: tiro > morale → unità russa eliminata")

	var s2 := _new_state()
	var ok := _mk("rus-ok", RUS, SQUAD, RIFLE, 0, 0, 5, 11)  # morale alto 11
	ok.break_unit()
	s2.units[ok.id] = ok
	var c2 := _ev("COMMISSARIO")
	c2.dice_white = 1
	c2.dice_red = 1  # tiro 2 ≤ 11 → ripristinata
	Events.fire(s2, c2, GER)
	_check(s2.units.has("rus-ok") and s2.units["rus-ok"].efficient, "Commissario: tiro ≤ morale → ripristinata")


func _test_event_hero() -> void:
	print("· Evento: Eroe (E58)")
	var s := _new_state()
	var host := _mk("ger", GER, SQUAD, RIFLE, 1, 1, 5, 7)
	s.units[host.id] = host
	Events.fire(s, _ev("EROE"), GER)
	var hero: Unit = s.units.get("HERO-GER")
	_check(hero != null and hero.hero and hero.is_leader(), "Eroe creato come leader a figura singola")
	_check(hero != null and hero.q == 1 and hero.r == 1, "Eroe compare in un esagono amico")
	Events.fire(s, _ev("EROE"), GER)
	var heroes := 0
	for u in s.units.values():
		if u.hero:
			heroes += 1
	_check(heroes == 1, "un solo Eroe per fazione (non duplicato)")
	# L'Eroe non conta sul Casualty Track.
	var before := int(s.casualties.get(GER, 0))
	s.eliminate_unit("HERO-GER")
	_check(int(s.casualties.get(GER, 0)) == before, "Eroe eliminato NON conta come perdita")


func _test_elimination_vp() -> void:
	print("· VP da eliminazione (7.1)")
	var s := _new_state()
	var rsq := _mk("r", RUS, SQUAD, RIFLE, 0, 0)
	var rld := _mk("rl", RUS, LEADER, ELITE, 0, 0, 1, 9, 6, 2)  # comando 2
	var gsq := _mk("g", GER, SQUAD, RIFLE, 1, 1)
	var hero := _mk("h", GER, LEADER, ELITE, 2, 2, 2, 10, 4, 1)
	hero.hero = true
	for u in [rsq, rld, gsq, hero]:
		s.units[u.id] = u
	s.eliminate_unit("r")
	_check(s.bonus_vp == 2, "squadra russa eliminata → +2 VP ai tedeschi")
	s.eliminate_unit("rl")
	_check(s.bonus_vp == 5, "leader russo (cmd2) eliminato → +3 VP (1+2)")
	s.eliminate_unit("g")
	_check(s.bonus_vp == 3, "squadra tedesca eliminata → -2 VP")
	var before := s.bonus_vp
	s.eliminate_unit("h")
	_check(s.bonus_vp == before, "Eroe eliminato → 0 VP")
	Game.state = s
	Game._update_objectives()
	_check(s.vp_tracker == s.bonus_vp, "la bilancia VP include i VP non-obiettivo")


func _test_spray_fire() -> void:
	print("· Sventagliata (A40): due esagoni adiacenti con un solo tiro")
	var s := _new_state(6, 6)
	var atk := _mk("g", GER, SQUAD, RIFLE, 2, 3, 10, 7, 6)  # FP alto
	s.units[atk.id] = atk
	var d1 := _mk("r1", RUS, SQUAD, RIFLE, 2, 2, 5, 3)  # bersaglio primario
	var d2 := _mk("r2", RUS, SQUAD, RIFLE, 3, 2, 5, 3)  # secondo esagono
	s.units[d1.id] = d1
	s.units[d2.id] = d2
	var grp: Array[Unit] = [atk]
	# Senza sventagliata: solo il primario è colpito.
	var only := Combat.resolve_fire(atk, 2, 2, s, Vector2i(6, 6), Vector2i(1, 1), grp, 0)
	_check(_was_affected(only, "r1") and not _was_affected(only, "r2"),
		"Senza sventagliata colpisce solo il bersaglio primario")
	# Con sventagliata: stesso tiro su entrambi gli esagoni.
	var d3 := _mk("r3", RUS, SQUAD, RIFLE, 2, 2, 5, 3)
	var d4 := _mk("r4", RUS, SQUAD, RIFLE, 3, 2, 5, 3)
	var s2 := _new_state(6, 6)
	var atk2 := _mk("g2", GER, SQUAD, RIFLE, 2, 3, 10, 7, 6)
	s2.units[atk2.id] = atk2
	s2.units[d3.id] = d3
	s2.units[d4.id] = d4
	var grp2: Array[Unit] = [atk2]
	var res := Combat.resolve_fire(atk2, 2, 2, s2, Vector2i(6, 6), Vector2i(1, 1), grp2, 0, 3, 2)
	_check(_was_affected(res, "r3"), "Sventagliata colpisce il bersaglio primario")
	_check(_was_affected(res, "r4"), "Sventagliata colpisce anche il secondo esagono")


## Vero se l'unità compare tra gli effetti del fuoco (rotta/eliminata/soppressa).
func _was_affected(res, uid: String) -> bool:
	return res.broken.has(uid) or res.eliminated.has(uid) or res.suppressed.has(uid)


func _test_fortifications() -> void:
	print("· Fortificazioni: copertura, filo, mine, posa")
	var s := _new_state()
	var hd := s.hex_at(1, 1)
	hd.fortification = Domain.Fort.BUNKER
	_check(Rules.cover_at(s, 1, 1, false) == 6, "Bunker → copertura 6")
	_check(Rules.cover_at(s, 1, 1, true) == 7, "Bunker vs ordnance → 7")
	hd.fortification = Domain.Fort.TRENCH
	_check(Rules.cover_at(s, 1, 1, false) == 4, "Trincea → copertura 4")

	# Filo spinato: −1 a FP/Gittata/Morale.
	var u := _mk("g", GER, SQUAD, RIFLE, 2, 2, 6, 7, 6)
	s.units[u.id] = u
	s.hex_at(2, 2).fortification = Domain.Fort.WIRE
	_check(Rules.wire_penalty(s, u) == 1, "Filo: penalità 1")
	_check(Rules.fp_with_command(s, u) == 5, "Filo: FP -1 (6→5)")
	_check(Rules.range_with_command(s, u) == 5, "Filo: gittata -1 (6→5)")

	# Posa via azione.
	var s2 := _new_state()
	var g2 := _mk("g", GER, SQUAD, RIFLE, 0, 0, 5, 7)
	s2.units[g2.id] = g2
	var card := Card.new()
	card.action_name = "MINE NASCOSTE"
	Actions.play(s2, card, GER)
	_check(s2.hex_at(0, 0).fortification == Domain.Fort.MINES, "MINE NASCOSTE posa le mine sull'esagono amico")

	# Attacco mine (esiti deterministici tramite morale estremo).
	Game.state = s2
	var hit := _mk("rh", RUS, SQUAD, RIFLE, 0, 0, 5, -50)  # difesa sempre < attacco
	s2.units[hit.id] = hit
	_check(Game._mine_attack_on_move(hit, 1, 0), "Mine: chi entra nell'esagono minato è colpito")
	_check(not s2.units["rh"].efficient or not s2.units.has("rh"), "Mine: l'unità colpita si rompe/elimina")
	var miss := _mk("rm", RUS, SQUAD, RIFLE, 0, 0, 5, 99)  # difesa sempre > attacco
	s2.units[miss.id] = miss
	_check(not Game._mine_attack_on_move(miss, 1, 0), "Mine: con morale altissimo l'attacco fallisce")
	var nomine := _mk("rn", RUS, SQUAD, RIFLE, 3, 3, 5, 5)
	s2.units[nomine.id] = nomine
	_check(not Game._mine_attack_on_move(nomine, 2, 3), "Mine: nessun attacco fuori da esagoni minati")


func _test_objectives_vp() -> void:
	print("· Obiettivi: controllo e VP live")
	var s := _new_state()
	s.objectives.append(Objective.new(1, 1, 1, 3))  # obiettivo a (1,1), 3 VP
	s.objectives.append(Objective.new(2, 3, 3, 2))  # obiettivo a (3,3), 2 VP
	var g := _mk("ger", GER, SQUAD, RIFLE, 1, 1, 5, 7)
	s.units[g.id] = g
	Game.state = s
	var sweep := Game._update_objectives()
	_check(s.objectives[0].controller == GER, "obiettivo presidiato è controllato")
	_check(s.vp_tracker == 3, "VP = valore dell'obiettivo controllato")
	_check(sweep == -1, "non tutti gli obiettivi controllati → niente vittoria automatica")

	var g2 := _mk("ger2", GER, SQUAD, RIFLE, 3, 3, 5, 7)
	s.units[g2.id] = g2
	var sweep2 := Game._update_objectives()
	_check(s.vp_tracker == 5, "VP cumulati su entrambi gli obiettivi")
	_check(sweep2 == GER, "controllo di TUTTI gli obiettivi → vittoria automatica")
	Game.state = null


func _test_op_fire() -> void:
	print("· Fuoco di opportunità (A33)")
	var s := _new_state()
	var mover := _mk("ger", GER, SQUAD, RIFLE, 2, 2, 5, 7)
	var mg := _mk("rus-mg", RUS, Domain.UnitType.WEAPON, Domain.UnitClass.MG, 2, 0, 4, 7)
	s.units[mover.id] = mover
	s.units[mg.id] = mg
	var elig := OpFire.eligible_shooters(s, mover, RUS)
	_check(elig.size() == 1 and elig[0].id == "rus-mg", "MG nemica in gittata/LOS può fare opportunità")

	var mortar := _mk("rus-mortar", RUS, Domain.UnitType.WEAPON, Domain.UnitClass.MORTAR, 2, 1, 6, 7)
	s.units[mortar.id] = mortar
	_check(OpFire.eligible_shooters(s, mover, RUS).size() == 1, "il mortaio è escluso dall'opportunità")

	var rifle := _mk("rus-r", RUS, SQUAD, RIFLE, 1, 2, 7, 7)  # FP più alto, adiacente
	s.units[rifle.id] = rifle
	_check(OpFire.best_shooter(s, mover, RUS).id == "rus-r", "il miglior tiratore ha l'FP più alto")

	var far := _mk("rus-far", RUS, SQUAD, RIFLE, 0, 4, 5, 7)
	far.range = 1  # troppo lontano dal mover in (2,2)
	s.units[far.id] = far
	var has_far := false
	for u in OpFire.eligible_shooters(s, mover, RUS):
		if u.id == "rus-far":
			has_far = true
	_check(not has_far, "un tiratore fuori gittata non è idoneo all'opportunità")


func _act(name: String) -> Card:
	var c := Card.new()
	c.action_name = name
	return c


func _test_actions() -> void:
	print("· Azioni (carte A)")
	# Ferite leggere
	var s := _new_state()
	var u := _mk("ger", GER, SQUAD, RIFLE, 1, 1, 5, 7)
	u.break_unit()
	s.units[u.id] = u
	Actions.play(s, _act("FERITE LEGGERE"), GER)
	_check(u.efficient, "Ferite leggere recupera un'unità rotta")

	# Trincerarsi → buca + più copertura
	var s2 := _new_state()
	var u2 := _mk("ger", GER, SQUAD, RIFLE, 2, 2, 5, 7)
	s2.units[u2.id] = u2
	Actions.play(s2, _act("TRINCERARSI"), GER)
	_check(s2.hex_at(2, 2).has_foxhole, "Trincerarsi crea una buca sull'esagono dell'unità")

	# Mimetizzazione → concealed (sopravvive a un tiro al limite del morale)
	var s3 := _new_state()
	var atk := _mk("ger", GER, SQUAD, RIFLE, 0, 0, 5, 7)
	var def := _mk("rus", RUS, SQUAD, RIFLE, 0, 1, 5, 7)
	s3.units[atk.id] = atk
	s3.units[def.id] = def
	Actions.play(s3, _act("MIMETIZZAZIONE"), RUS)
	_check(def.concealed, "Mimetizzazione nasconde le unità")
	# attacco 5+2=7; difesa 7+1(mimetica)+6=14 → nessun effetto, ma rivelata
	var r := Combat.resolve_fire(atk, 0, 1, s3, Vector2i(1, 1), Vector2i(3, 3))
	_check(r.broken.is_empty(), "una unità mimetizzata resiste meglio")
	_check(not def.concealed, "il fuoco rivela la mimetizzazione")

	# Granate fumogene → fumo → hindrance lungo la LOS
	var s4 := _new_state()
	var c4 := _act("GRANATE FUMOGENE")
	c4.random_hex_label = "B1"  # (1,0)
	Actions.play(s4, c4, GER)
	_check(s4.hex_at(1, 0).has_smoke, "Granate fumogene posano fumo sull'esagono")


func _test_grenade() -> void:
	print("· Azione: Bombe a mano")
	var s := _new_state()
	var thrower := _mk("ger", GER, SQUAD, RIFLE, 1, 1, 5, 7)
	var foe := _mk("rus", RUS, SQUAD, RIFLE, 2, 1, 5, 7)  # adiacente a (1,1)
	s.units[thrower.id] = thrower
	s.units[foe.id] = foe
	var res := Actions.grenade_attack(s, thrower, 2, 1, Vector2i(6, 6))
	_check(res["broken"].has("rus"), "Bombe a mano rompono il nemico adiacente")


func _test_melee_tie() -> void:
	print("· Corpo a corpo: pareggio → entrambi eliminati")
	var s := _new_state()
	var a := _mk("ger", GER, SQUAD, RIFLE, 1, 1, 5, 7)
	var d := _mk("rus", RUS, SQUAD, RIFLE, 1, 1, 5, 7)
	s.units[a.id] = a
	s.units[d.id] = d
	var atkrs: Array[Unit] = [a]
	var defs: Array[Unit] = [d]
	var mr := Rules.resolve_melee(s, atkrs, defs, Vector2i(3, 3), Vector2i(3, 3))
	_check(mr.winner == -1, "pareggio: nessun vincitore")
	_check(not s.units.has("ger") and not s.units.has("rus"), "pareggio: entrambi i lati eliminati")


func _test_stacking() -> void:
	print("· Impilamento (7 soldier icons)")
	var s := _new_state()
	var sq := _mk("g1", GER, SQUAD, RIFLE, 1, 1, 5, 7)
	s.units[sq.id] = sq
	_check(s.soldier_icons_at(1, 1) == 4, "una squadra vale 4 figure")
	var ld := _mk("g2", GER, LEADER, ELITE, 1, 1, 1, 9, 6, 2)
	s.units[ld.id] = ld
	_check(s.soldier_icons_at(1, 1) == 5, "squadra + leader = 5 figure")
	var w := _mk("w", GER, Domain.UnitType.WEAPON, Domain.UnitClass.MG, 1, 1, 4, 7)
	s.units[w.id] = w
	_check(s.soldier_icons_at(1, 1) == 5, "le armi non contano come figure")


func _test_fire_suppress() -> void:
	print("· Fuoco: soppressione (pareggio, bersaglio fermo)")
	var s := _new_state()
	var atk := _mk("ger", GER, SQUAD, RIFLE, 0, 0, 5, 7)
	var def := _mk("rus", RUS, SQUAD, RIFLE, 0, 1, 5, 7)
	s.units[atk.id] = atk
	s.units[def.id] = def
	# attacco 5+12=17; difesa 7+0+10=17 → pareggio, fermo → soppressa
	var r := Combat.resolve_fire(atk, 0, 1, s, Vector2i(6, 6), Vector2i(5, 5))
	_check(r.suppressed.has("rus"), "pareggio su unità ferma → soppressa")
	_check(def.suppressed and def.efficient, "soppressa resta sul lato efficiente")
	_check(r.broken.is_empty(), "la soppressione non rompe")
	_check(not Combat.can_fire(def, 0, 0, s), "una unità soppressa non può sparare")


func _test_fire_moving_break() -> void:
	print("· Fuoco: pareggio su unità in movimento → rotta")
	var s := _new_state()
	var atk := _mk("ger", GER, SQUAD, RIFLE, 0, 0, 5, 7)
	var def := _mk("rus", RUS, SQUAD, RIFLE, 0, 1, 5, 7)
	s.units[atk.id] = atk
	s.units[def.id] = def
	s.moving_unit_id = "rus"  # il bersaglio si sta muovendo
	var r := Combat.resolve_fire(atk, 0, 1, s, Vector2i(6, 6), Vector2i(5, 5))
	_check(r.broken.has("rus"), "pareggio su unità in movimento → rotta")


func _test_maps_load() -> void:
	print("· Mappe: caricamento map1..map24")
	for n in range(1, 25):
		var st := GameState.new()
		var ok := MapLoader.load_into(st, "res://assets/maps/map%d.json" % n)
		_check(ok, "map%d caricata" % n)
		_check(st.map_cols == 15 and st.map_rows == 10, "map%d 15×10" % n)
		_check(st.objectives.size() == 5, "map%d ha 5 obiettivi" % n)
	# Sentiero (map7), ferrovia (map7), quota (map8) preservati dal loader.
	var m7 := GameState.new()
	MapLoader.load_into(m7, "res://assets/maps/map7.json")
	_check(m7.hex_at_label("D1").has_trail, "map7: sentiero D1 caricato")
	_check(m7.hex_at_label("O2").has_railway, "map7: ferrovia O2 caricata")
	var m8 := GameState.new()
	MapLoader.load_into(m8, "res://assets/maps/map8.json")
	_check(m8.hex_at_label("A9").elevation == 1, "map8: quota 1 in A9 caricata")


func _test_unit_chart() -> void:
	print("· UnitChart: categorie e statistiche esatte (carta ufficiale)")
	_check(UnitChart.category("Lt. Schrader") == UnitChart.Cat.LEADER, "Lt. → leader")
	_check(UnitChart.category("Heavy MG") == UnitChart.Cat.WEAPON, "Heavy MG → arma")
	_check(UnitChart.category("Weapon Team") == UnitChart.Cat.SQUAD, "Weapon Team → squadra")
	_check(UnitChart.category("Radio 105mm") == UnitChart.Cat.SKIP, "Radio → ignorata")
	# nation_code (incluse le nazioni minori)
	_check(UnitChart.nation_code("american") == "US", "american → US")
	_check(UnitChart.nation_code("canadian") == "GB", "canadian → GB")
	_check(UnitChart.nation_code("romanian") == "IT", "romanian → IT")
	# Statistiche ESATTE per (nazione, etichetta).
	var de_rifle := UnitChart.build_unit("a", GER, "Rifle", 0, 0, "DE")
	_check(de_rifle.fp == 5 and de_rifle.range == 5 and de_rifle.morale == 7, "Rifle tedesco: FP5/R5/Mor7")
	var ru_rifle := UnitChart.build_unit("b", RUS, "Rifle", 0, 0, "RU")
	_check(ru_rifle.fp == 5 and ru_rifle.range == 3 and ru_rifle.morale == 8, "Rifle russo: FP5/R3/Mor8")
	var us_line := UnitChart.build_unit("c", RUS, "Line", 0, 0, "US")
	_check(us_line.fp == 6 and us_line.morale == 6, "Line americano: FP6/Mor6")
	var cpt := UnitChart.build_unit("d", GER, "Cpt. Wehling", 0, 0, "DE")
	_check(cpt.command == 2 and cpt.morale == 10 and cpt.is_leader(), "Capitano: comando2/morale10")
	var lmg := UnitChart.build_unit("e", GER, "Light MG", 0, 0, "DE")
	_check(lmg.is_weapon() and lmg.fp == 4 and lmg.range == 8, "Light MG tedesca: FP4/R8")
	var hero := UnitChart.build_unit("h", RUS, "Smith, King's Hero", 0, 0, "GB")
	_check(hero.fp == 2 and hero.range == 4 and hero.morale == 9, "Eroe: FP2/R4/Mor9")


func _test_scenarios_load() -> void:
	print("· Scenari: caricamento catalogo 2..24")
	_check(ScenarioLoader.catalog().size() == 24, "catalogo ha 24 scenari")
	for n in range(2, 25):
		var st := GameState.new()
		st.human_faction = GER
		var ok := ScenarioLoader.setup(st, n)
		_check(ok, "scenario %d caricato" % n)
		_check(st.units.size() > 0, "scenario %d ha unità" % n)
		var ger := 0
		var rus := 0
		var in_bounds := true
		for u in st.units.values():
			if u.q < 0 or u.q >= st.map_cols or u.r < 0 or u.r >= st.map_rows:
				in_bounds = false
			if u.faction == GER: ger += 1
			else: rus += 1
		_check(in_bounds, "scenario %d: unità tutte dentro la mappa" % n)
		_check(ger > 0 and rus > 0, "scenario %d: entrambe le fazioni schierate" % n)


func _test_scenario_fidelity() -> void:
	print("· Fedeltà scenario: mano e soglie di resa dal catalogo")
	var st := GameState.new()
	st.human_faction = GER
	_check(ScenarioLoader.setup(st, 2), "scenario 2 caricato")
	# Catalogo scenario 2: mano_axis 4 / mano_allies 5, resa_axis 8 / resa_allies 9.
	_check(st.hand_size_of(GER) == 4, "mano Axis (scen.2) = 4")
	_check(st.hand_size_of(RUS) == 5, "mano Allies (scen.2) = 5")
	_check(int(st.surrender_threshold[GER]) == 8, "soglia resa Axis (scen.2) = 8")
	_check(int(st.surrender_threshold[RUS]) == 9, "soglia resa Allies (scen.2) = 9")


func _test_setup_depth() -> void:
	print("· Setup: profondità di schieramento per scenario (dalle schede)")
	var e := ScenarioLoader.entry(2)
	_check(int(e.get("setup_axis_depth", 0)) == 12 and int(e.get("setup_allies_depth", 0)) == 3,
		"scenario 2: profondità Axis 12 / Allies 3 dal catalogo")
	var st := GameState.new()
	st.human_faction = GER
	_check(ScenarioLoader.setup(st, 2), "scenario 2 caricato")
	# Il difensore (Axis, 12 prof.) ha una zona di schieramento più ampia
	# dell'attaccante (Allies, 3 prof.).
	var axis_zone := ScenarioLoader._setup_hexes(st, e, "axis")
	var allies_zone := ScenarioLoader._setup_hexes(st, e, "allies")
	_check(axis_zone.size() > allies_zone.size(),
		"zona Axis (difensore, prof. 12) più ampia della Allied (attaccante, prof. 3)")


func _test_surrender() -> void:
	print("· Resa: Casualty Track, soglie e tie-break iniziativa")
	var s := _new_state()
	s.surrender_threshold[RUS] = 2
	var r1 := _mk("RUS-0", RUS, SQUAD, RIFLE, 0, 0)
	var r2 := _mk("RUS-1", RUS, SQUAD, RIFLE, 1, 0)
	var w := _mk("RUS-2", RUS, Domain.UnitType.WEAPON, Domain.UnitClass.MG, 2, 0)
	var g := _mk("GER-0", GER, SQUAD, RIFLE, 4, 4)
	s.units[r1.id] = r1
	s.units[r2.id] = r2
	s.units[w.id] = w
	s.units[g.id] = g

	s.eliminate_unit(w.id)
	_check(int(s.casualties[RUS]) == 0, "l'arma eliminata non conta sul Casualty Track")
	s.eliminate_unit(r1.id)
	_check(int(s.casualties[RUS]) == 1, "uomo eliminato = 1 perdita")
	_check(not s.has_surrendered(RUS), "1 perdita < soglia 2 → nessuna resa")
	s.eliminate_unit(r2.id)
	_check(int(s.casualties[RUS]) == 2, "secondo uomo eliminato = 2 perdite")
	_check(s.has_surrendered(RUS), "perdite ≥ soglia → resa")

	# _check_end_conditions deve concludere con vittoria tedesca (RUS si arrende).
	var winner := { "f": -99 }
	var cb := func(w2: int) -> void: winner["f"] = w2
	Game.state = s
	Game.game_over.connect(cb)
	Game._check_end_conditions()
	_check(s.phase == Domain.Phase.GAME_OVER, "la resa termina la partita")
	_check(int(winner["f"]) == GER, "la resa russa fa vincere i Tedeschi")
	Game.game_over.disconnect(cb)

	# Doppia resa simultanea → vince chi detiene l'iniziativa (6.3.1).
	var s2 := _new_state()
	s2.surrender_threshold[GER] = 1
	s2.surrender_threshold[RUS] = 1
	s2.casualties[GER] = 1
	s2.casualties[RUS] = 1
	s2.initiative_holder = RUS
	var winner2 := { "f": -99 }
	var cb2 := func(w2: int) -> void: winner2["f"] = w2
	Game.state = s2
	Game.game_over.connect(cb2)
	Game._check_end_conditions()
	_check(int(winner2["f"]) == RUS, "doppia resa: vince chi ha l'iniziativa")
	Game.game_over.disconnect(cb2)
	Game.state = null


func _test_sudden_death_roll() -> void:
	print("· Morte Subitanea: tiro 2d6 vs casella Tempo (6.2.2)")
	# Tiro 2 < casella 8 → la partita finisce.
	var s := _new_state()
	s.time_marker = 8
	s.sudden_death_space = 7
	s.german_deck.append(_fate_card(1, 1))  # 2d6 = 2
	Game.state = s
	Game._check_sudden_death(GER)
	_check(s.phase == Domain.Phase.GAME_OVER, "tiro < casella Tempo → fine partita")

	# Tiro 12 ≥ casella 7 → la partita continua.
	var s2 := _new_state()
	s2.time_marker = 7
	s2.sudden_death_space = 7
	s2.german_deck.append(_fate_card(6, 6))  # 2d6 = 12
	Game.state = s2
	Game._check_sudden_death(GER)
	_check(s2.phase != Domain.Phase.GAME_OVER, "tiro ≥ casella Tempo → la partita continua")

	# tempo_iniziale: il loader parte dalla casella 0 (6.1.1, «di solito 0»).
	var s3 := GameState.new()
	s3.human_faction = GER
	_check(ScenarioLoader.setup(s3, 2), "scenario 2 caricato")
	_check(s3.time_marker == 0, "segnalino Tempo iniziale = 0 (default rulebook)")
	Game.state = null


func _test_ordnance() -> void:
	print("· Ordnance: Targeting Roll, gittata minima, fuori dal gruppo (O20.2)")
	var s := _new_state(8, 3)
	var mortar := _mk("m", GER, Domain.UnitType.WEAPON, Domain.UnitClass.MORTAR, 0, 0, 8, 0, 14, 0)
	mortar.ordnance = true
	mortar.min_range = 2
	var tgt := _mk("t", RUS, SQUAD, RIFLE, 5, 0, 5, 7)
	s.units[mortar.id] = mortar
	s.units[tgt.id] = tgt
	# Targeting MANCATO: 1×2 = 2 ≤ gittata → nessun effetto.
	var miss := Combat.resolve_fire(mortar, 5, 0, s, Vector2i(1, 2), Vector2i(3, 3))
	_check(miss.fp_total == 0 and s.units["t"].efficient, "targeting mancato (prodotto basso) → nessun effetto")
	# Targeting COLPITO: 6×6 = 36 > gittata → l'attacco procede e rompe il bersaglio.
	var hit := Combat.resolve_fire(mortar, 5, 0, s, Vector2i(6, 6), Vector2i(1, 1))
	_check(hit.fp_total > 0 and hit.broken.has("t"), "targeting colpito (prodotto alto) → l'attacco procede")
	# Gittata minima: non può sparare a un esagono adiacente.
	_check(not Combat.can_fire(mortar, 1, 0, s), "ordnance non spara sotto la gittata minima")
	# Ordnance spara da solo; e non entra nel gruppo di un'altra unità.
	var buddy := _mk("b", GER, SQUAD, RIFLE, 0, 0, 6, 7)
	s.units[buddy.id] = buddy
	var grp := Combat.fire_group(mortar, 5, 0, s)
	_check(grp.size() == 1 and grp[0].id == "m", "l'ordnance spara da solo (no gruppo)")
	var grp2 := Combat.fire_group(buddy, 5, 0, s)
	_check(not grp2.any(func(u: Unit) -> bool: return u.id == "m"), "il mortaio non entra nel gruppo altrui")


func _test_counter_art() -> void:
	print("· Counter: arte reale per nazione (art_map + cartelle)")
	var us := UnitChart.build_unit("a", RUS, "Line", 0, 0, "US")
	_check(us.nation_art == "Americani" and us.art_name == "Line Squad", "Line US → Americani/Line Squad")
	_check(ResourceLoader.exists("res://assets/counters/Americani/Line Squad.png"), "il counter US esiste")
	var it := UnitChart.build_unit("b", GER, "Fucilieri", 0, 0, "IT")
	_check(it.nation_art == "Italiani" and ResourceLoader.exists("res://assets/counters/Italiani/%s.png" % it.art_name), "Fucilieri IT ha il counter")
	var ldr := UnitChart.build_unit("c", GER, "Lt. Schrader", 0, 0, "DE")
	_check(ldr.art_name == "Lieutenant Y" and ResourceLoader.exists("res://assets/counters/Tedeschi/Lieutenant Y.png"), "leader DE → Tedeschi/Lieutenant Y")
	# Tutte le unità dei 24 scenari hanno un counter risolvibile.
	var unresolved := 0
	for n in range(2, 25):
		var st := GameState.new()
		st.human_faction = GER
		if not ScenarioLoader.setup(st, n):
			continue
		for u in st.units.values():
			if u.art_name == "":
				continue
			if not ResourceLoader.exists("res://assets/counters/%s/%s.png" % [u.nation_art, u.art_name]):
				unresolved += 1
	_check(unresolved == 0, "ogni unità dei 24 scenari ha un counter esistente")


func _test_decks() -> void:
	print("· Mazzi: tutte e 6 le nazioni (routing + validità)")
	for nat in ["german", "russian", "american", "british", "french", "italian"]:
		var deck := Cards.build_deck(nat)
		var nums := {}
		var dice_ok := true
		var ord_ok := true
		var valid := [Domain.OrderType.FIRE, Domain.OrderType.MOVE, Domain.OrderType.ADVANCE,
			Domain.OrderType.RECOVER, Domain.OrderType.ROUT, Domain.OrderType.PASS,
			Domain.OrderType.ARTY, Domain.OrderType.ARTY_DENIED]
		for c in deck:
			nums[c.number] = true
			if c.dice_white < 1 or c.dice_white > 6 or c.dice_red < 1 or c.dice_red > 6:
				dice_ok = false
			if not valid.has(c.order):
				ord_ok = false
		_check(deck.size() == 72 and nums.size() == 72, "%s: 72 carte con numeri unici" % nat)
		_check(dice_ok and ord_ok, "%s: dadi 1-6 e ordini validi" % nat)
	# Routing nazioni minori → capofila.
	_check(Cards.build_deck("canadian").size() == 72, "canadian → mazzo inglese")
	_check(Cards.build_deck("romanian").size() == 72, "romanian → mazzo italiano")
	# Routing per scenario: lo slot Alleati prende la nazione reale.
	var st := GameState.new()
	st.human_faction = GER
	if ScenarioLoader.setup(st, 2):
		_check(st.axis_nation == "german" and st.allied_nation == "american", "scenario 2: Asse tedesco / Alleati americani")


func _test_save_load() -> void:
	print("· Salvataggio: round-trip dello stato")
	var s := GameState.new()
	s.human_faction = GER
	if not ScenarioLoader.setup(s, 2):
		_check(false, "scenario 2 caricato per il test")
		return
	s.german_deck = Cards.build_deck(s.axis_nation)
	s.russian_deck = Cards.build_deck(s.allied_nation)
	# Muta dello stato da verificare al ritorno.
	s.vp_tracker = 5; s.time_marker = 3; s.turn_number = 4
	s.casualties[GER] = 2
	var any_id: String = s.units.keys()[0]
	s.units[any_id].efficient = false
	s.units[any_id].suppressed = true

	var path := "user://test_save.json"
	_check(SaveGame.save_state(s, path), "salvataggio scritto su file")
	var s2 := SaveGame.load_state(path)
	_check(s2 != null, "caricamento riuscito")
	if s2 == null:
		return
	_check(s2.units.size() == s.units.size(), "stesso numero di unità")
	_check(s2.vp_tracker == 5 and s2.time_marker == 3 and s2.turn_number == 4, "scalari (VP/tempo/turno) ripristinati")
	_check(int(s2.casualties[GER]) == 2, "perdite ripristinate")
	_check(s2.allied_nation == "american", "nazione alleata ripristinata")
	_check(s2.german_deck.size() == 72 and s2.russian_deck.size() == 72, "mazzi ripristinati (72+72)")
	_check(s2.objectives.size() == s.objectives.size(), "obiettivi ripristinati")
	_check(s2.hexes.size() == s.hexes.size(), "mappa (hex) ripristinata")
	var u2: Unit = s2.units.get(any_id)
	_check(u2 != null and not u2.efficient and u2.suppressed, "stato unità (rotta+soppressa) ripristinato")
	DirAccess.remove_absolute("user://test_save.json")


func _test_audio() -> void:
	print("· Audio: suoni presenti e autoload attivo")
	for f in ["RIFLE", "MACH_GUN", "Artillery", "time", "morse", "reload", "Deck Depleted"]:
		_check(ResourceLoader.exists("res://assets/sounds/%s.wav" % f), "suono '%s' presente e importato" % f)
	_check(Audio != null and Audio.has_method("play"), "autoload Audio attivo")


func _report() -> void:
	print("")
	if _checks == 0:
		# Nessun controllo eseguito = qualcosa è andato storto (es. errore di
		# script che interrompe i test): da trattare come fallimento.
		print("TEST_RESULT: FAIL (nessun controllo eseguito)")
		get_tree().quit(1)
	elif _failures.is_empty():
		print("TEST_RESULT: PASS (%d controlli)" % _checks)
		get_tree().quit(0)
	else:
		print("TEST_RESULT: FAIL (%d/%d falliti)" % [_failures.size(), _checks])
		for f in _failures:
			print("  - ", f)
		get_tree().quit(1)
