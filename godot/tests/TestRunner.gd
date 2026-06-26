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
	_test_recover_suppression()
	_test_can_be_ordered()
	_test_sudden_death_initiative()
	_test_team_vs_squad()
	_test_clone_preserves_hero()
	_test_ai_advance_no_command()
	_test_reachable_stops_at_wire()
	_test_reachable_costs()
	_test_fire_preview()
	_test_weapon_portage()
	_test_move_path_cost()
	_test_melee_winner_and_losses()
	_test_rout_retreat()
	_test_rout_trapped()
	_test_ai_best_fire()
	_test_ai_best_advance()
	_test_ai_choose_play()
	_test_fate_draw_and_reshuffle()
	_test_fate_time()
	_test_time_defender_vp()
	_test_fate_sniper()
	_test_fate_jam()
	_test_los_hexside()
	_test_los_hindrance()
	_test_los_kind()
	_test_min_fp_hindrance()
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
	_test_more_events()
	_test_more_events2()
	_test_radio_unit()
	_test_artillery()
	_test_click_hex()
	_test_stack_cycle()
	_test_artillery_available()
	_test_ai_artillery()
	_test_blaze()
	_test_melee_fortification_tie()
	_test_objective_chits()
	_test_assault_fire()
	_test_exit_vp()
	_test_spray_fire()
	_test_fortifications()
	_test_objectives_vp()
	_test_op_fire()
	_test_op_fire_card_cost()
	_test_pass_turn()
	_test_move_command_group()
	_test_initial_carriers_relocate()
	_test_scenario1_no_orphan_weapons()
	_test_loader_weapons_with_squads()
	_test_initial_fortifications()
	_test_fire_command_group()
	_test_fire_ready()
	_test_order_feasible()
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
	_test_scenario_rules()
	_test_setup_depth()
	_test_setup_zones()
	_test_smart_deploy()
	_test_manual_setup()
	_test_flipbot()
	_test_flipbot_move()
	_test_flipbot_fire()
	_test_flipbot_opfire()
	_test_flipbot_advance()
	_test_scenario_effects()
	_test_global_hindrance()
	_test_reinforcements()
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


func _card(order: int) -> Card:
	var c := Card.new()
	c.order = order
	c.faction = GER
	return c


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


func _test_recover_suppression() -> void:
	print("· Recupero: rimozione della soppressione (O22)")
	var s := _new_state()
	var sup := _mk("ger-s", GER, SQUAD, RIFLE, 1, 1, 5, 7)
	sup.suppress()                       # efficiente ma soppressa
	var brk := _mk("ger-b", GER, SQUAD, RIFLE, 2, 2, 5, 7)
	brk.break_unit()                     # rotta
	var ok := _mk("ger-ok", GER, SQUAD, RIFLE, 3, 3, 5, 7)  # nessuno stato
	s.units[sup.id] = sup
	s.units[brk.id] = brk
	s.units[ok.id] = ok
	# Query: solo l'unità efficiente soppressa.
	var sm := s.suppressed_men_of(GER)
	_check(sm.size() == 1 and sm[0].id == "ger-s", "suppressed_men_of trova solo le efficienti soppresse")
	# Il Recupero rimuove la soppressione automaticamente (senza tiro).
	var freed := Rules.clear_suppression(s, GER)
	_check(freed == 1 and not sup.suppressed, "il Recupero rimuove la soppressione (senza tiro)")
	_check(s.suppressed_men_of(GER).is_empty(), "nessuna unità soppressa dopo il Recupero")
	_check(not brk.efficient, "la rimozione della soppressione non ripristina le unità rotte")
	# Idempotente: senza unità soppresse non libera nulla.
	_check(Rules.clear_suppression(s, GER) == 0, "nessuna soppressione residua → 0 liberate")


func _test_team_vs_squad() -> void:
	print("· Squadra vs Team: VP (7.1) e figure soldato (8.2)")
	var squad := _mk("sq", GER, SQUAD, RIFLE, 0, 0)
	var team := _mk("tm", GER, Domain.UnitType.TEAM, RIFLE, 0, 0)
	_check(GameState.elimination_vp(squad) == 2, "una Squadra eliminata vale 2 VP")
	_check(GameState.elimination_vp(team) == 1, "un Team eliminato vale 1 VP")
	_check(squad.soldier_icons() == 4, "una Squadra conta 4 figure")
	_check(team.soldier_icons() == 2, "un Team conta 2 figure")
	# Stacking 8.2: Squadra(4)+Team(2)+Leader(1) = 7 (al limite, non overstack).
	var s := _new_state()
	var sq := _mk("s1", GER, SQUAD, RIFLE, 2, 2)
	var tm := _mk("t1", GER, Domain.UnitType.TEAM, RIFLE, 2, 2)
	var ld := _mk("l1", GER, Domain.UnitType.LEADER, RIFLE, 2, 2)
	s.units[sq.id] = sq
	s.units[tm.id] = tm
	s.units[ld.id] = ld
	_check(s.soldier_icons_at(2, 2) == 7, "Squadra+Team+Leader = 7 figure (limite di impilamento)")
	# UnitChart costruisce un "Weapon Team" come TEAM.
	var built := UnitChart.build_unit("wt", GER, "Weapon Team", 0, 0)
	_check(built.type == Domain.UnitType.TEAM, "UnitChart costruisce 'Weapon Team' come TEAM")
	_check(built.is_man() and not built.is_weapon(), "un Team è un uomo, non un'arma")


func _test_clone_preserves_hero() -> void:
	print("· Unit.clone preserva lo stato Eroe")
	var h := _mk("hero", GER, Domain.UnitType.LEADER, RIFLE, 0, 0)
	h.hero = true
	_check(h.clone().hero, "clone() copia il flag hero (immunità al Casualty Track)")


func _test_ai_advance_no_command() -> void:
	print("· IA: niente Comando nella stima della melee (O16.4)")
	var s := _new_state()
	# Attaccante con FP 1 ma Comando 5; difensore con FP 2 adiacente.
	var atk := _mk("rus", RUS, SQUAD, RIFLE, 1, 1, 1, 7, 6, 5)
	var foe := _mk("ger", GER, SQUAD, RIFLE, 2, 1, 2, 7)
	s.units[atk.id] = atk
	s.units[foe.id] = foe
	_check(AI.best_advance(s, RUS).is_empty(),
		"FP 1 vs 2: l'IA non avanza nonostante il Comando 5 (il Comando non conta in melee)")


func _test_reachable_stops_at_wire() -> void:
	print("· Anteprima movimento: Filo ferma l'espansione (F106)")
	var s := _new_state(5, 1)  # 1 riga = corridoio (ogni esagono solo sx/dx)
	var u := _mk("u", GER, SQUAD, RIFLE, 0, 0)
	u.move = 4
	s.units[u.id] = u
	_check(HexGrid.reachable(u, s).has(Vector2i(3, 0)), "corridoio libero: (3,0) raggiungibile")
	s.hex_at(1, 0).fortification = Domain.Fort.WIRE
	var r1 := HexGrid.reachable(u, s)
	_check(r1.has(Vector2i(1, 0)), "si può entrare nell'esagono con Filo")
	_check(not r1.has(Vector2i(2, 0)), "il Filo ferma il movimento: niente oltre (1,0)")


func _test_reachable_costs() -> void:
	print("· Anteprima movimento: costo in PM per esagono (HUD)")
	var s := _new_state(5, 1)  # corridoio: ogni esagono costa 1 PM (terreno aperto)
	var u := _mk("u", GER, SQUAD, RIFLE, 0, 0)
	u.move = 4
	s.units[u.id] = u
	var costs := HexGrid.reachable_costs(u, s)
	# Lungo il corridoio il costo cumulativo cresce di 1 per esagono.
	_check(int(costs.get("1,0", -1)) == 1, "(1,0) costa 1 PM")
	_check(int(costs.get("3,0", -1)) == 3, "(3,0) costa 3 PM")
	_check(not costs.has("0,0"), "l'esagono di partenza non è incluso nel costo")
	# Parità con reachable(): stesse chiavi (stesso insieme di esagoni).
	var reach := HexGrid.reachable(u, s)
	_check(reach.size() == costs.size(), "reachable e reachable_costs coprono gli stessi esagoni")
	# Budget ridotto: un esagono più costoso dei PM residui sparisce dalla mappa.
	var costs2 := HexGrid.reachable_costs(u, s, 2)
	_check(costs2.has("2,0") and not costs2.has("3,0"), "con 2 PM si arriva a (2,0) ma non a (3,0)")


func _test_fire_preview() -> void:
	print("· Anteprima fuoco: FP attacco vs difesa stimata (HUD)")
	var s := _new_state(6, 1)
	s.human_faction = GER
	var sh := _mk("sh", GER, SQUAD, RIFLE, 0, 0, 6, 7)
	var df := _mk("df", RUS, SQUAD, RIFLE, 2, 0, 5, 7)
	s.units[sh.id] = sh
	s.units[df.id] = df
	s.current_order = Domain.OrderType.FIRE
	s.selected_unit_id = sh.id
	s.fire_target_q = 2
	s.fire_target_r = 0
	s.fire_group_ids.clear()
	s.fire_group_ids.append("sh")
	Game.state = s
	var pv := Game.fire_preview()
	_check(int(pv["fp"]) == 6, "FP del singolo tiratore = 6")
	_check(int(pv["defense"]) == 7, "difesa = morale 7 + copertura 0 (terreno aperto)")
	_check(int(pv["margin"]) == -1 and pv["verdict"] == "incerto", "margine -1 → incerto")
	# Copertura: difensore nel bosco (cop 2) alza la difesa stimata.
	s.hex_at(2, 0).terrain = Domain.TerrainType.WOODS
	pv = Game.fire_preview()
	_check(int(pv["cover"]) == 2 and int(pv["defense"]) == 9, "bosco: copertura 2 → difesa 9")
	_check(pv["verdict"] == "sfavorevole", "FP6 vs DIF9 (margine -3) → sfavorevole")
	# Gruppo di fuoco: un secondo pezzo aggiunge +1 FP.
	var sh2 := _mk("sh2", GER, SQUAD, RIFLE, 1, 0, 6, 7)
	s.units[sh2.id] = sh2
	s.fire_group_ids.append("sh2")
	pv = Game.fire_preview()
	_check(int(pv["fp"]) == 7, "due pezzi nel gruppo: FP 6 + 1 = 7")


func _test_weapon_portage() -> void:
	print("· Armi: possesso, trasporto, malus PM, trasferimento, eliminazione (11)")
	var s := _new_state(8, 1)
	s.human_faction = GER
	var squad := _mk("sq", GER, SQUAD, RIFLE, 0, 0, 6, 7)
	squad.move = 4
	var mg := _mk("mg", GER, Domain.UnitType.WEAPON, RIFLE, 0, 0, 8, 7)
	mg.move_penalty = -2
	s.units[squad.id] = squad
	s.units[mg.id] = mg
	# 11.2: l'arma co-locata è affidata alla squadra al setup.
	Game._assign_initial_carriers(s)
	_check(mg.carrier_id == "sq", "setup: l'arma è affidata alla squadra co-locata")
	_check(s.weapon_carried_by("sq") == mg, "weapon_carried_by trova l'arma del portatore")
	# 11.1: malus PM dell'arma sul portatore (4 - 2 = 2).
	_check(Rules.move_allowance(s, squad) == 2, "allowance = move 4 + malus -2 = 2")
	# 11.1: l'arma segue il portatore quando si sposta.
	s.set_unit_pos(squad, 3, 0)
	_check(mg.q == 3 and mg.r == 0, "l'arma si sposta col portatore")
	# 11.3: trasferimento a un compagno co-locato per 1 PM.
	var squad2 := _mk("sq2", GER, SQUAD, RIFLE, 3, 0, 6, 7)
	s.units[squad2.id] = squad2
	s.phase = Domain.Phase.PLAYER_MOVING
	s.current_order = Domain.OrderType.MOVE
	s.selected_unit_id = "sq"
	s.group_mp["sq"] = 2
	Game.state = s
	Game.transfer_weapon()
	_check(mg.carrier_id == "sq2", "trasferimento: l'arma passa al compagno")
	_check(int(s.group_mp["sq"]) == 1, "il trasferimento costa 1 PM")
	# 11.3: eliminato il portatore, l'arma è eliminata con lui.
	s.eliminate_unit("sq2")
	_check(s.unit_by_id("mg") == null, "eliminato il portatore, l'arma sparisce")


func _test_move_path_cost() -> void:
	print("· Movimento: passo-passo (un clic = un esagono) e percorso a costo minimo")
	var s := _new_state(9, 1)
	s.human_faction = GER
	var u := _mk("u", GER, SQUAD, RIFLE, 0, 0, 5, 7)
	u.move = 4
	s.units[u.id] = u
	# Corridoio aperto (costo 1/esagono): il percorso accumula il costo reale.
	_check(HexGrid.path_to(u, s, 3, 0, 4).size() == 3, "(3,0): percorso di 3 passi")
	_check(HexGrid.path_to(u, s, 4, 0, 4).size() == 4, "(4,0) costa 4: 4 passi entro 4 PM")
	_check(HexGrid.path_to(u, s, 5, 0, 4).is_empty(), "(5,0) costa 5: irraggiungibile con 4 PM")
	# Nemico lontano e soppresso: tiene viva la partita senza scatenare op-fire.
	var en := _mk("rus", RUS, SQUAD, RIFLE, 8, 0, 5, 7)
	en.suppressed = true
	s.units["rus"] = en
	s.phase = Domain.Phase.PLAYER_MOVING
	s.current_order = Domain.OrderType.MOVE
	s.group_mp["u"] = 4
	s.selected_unit_id = "u"
	s.moving_unit_id = "u"
	Game.state = s
	# Passo-passo: un clic (anche su un esagono lontano) muove UN solo esagono
	# verso il bersaglio, spendendo il costo di quell'unico passo.
	Game.click_hex_move(3, 0)
	_check(u.q == 1 and u.r == 0, "un clic muove di UN esagono verso il bersaglio")
	_check(int(s.group_mp["u"]) == 3, "ha speso 1 PM (un solo passo, non l'intero percorso)")
	# Un secondo clic avanza di un altro esagono.
	Game.click_hex_move(3, 0)
	_check(u.q == 2 and u.r == 0 and int(s.group_mp["u"]) == 2, "secondo clic: un altro passo")


func _test_sudden_death_initiative() -> void:
	print("· Morte Subitanea: pareggio all'Iniziativa (9.2) e Re-Roll (9.1)")
	# 9.2: in pareggio (bilancia VP 0) vince chi detiene la carta Iniziativa.
	_check(Rules.sd_winner(0, GER) == GER, "pareggio VP → vince chi ha l'Iniziativa (DE)")
	_check(Rules.sd_winner(0, RUS) == RUS, "pareggio VP → vince chi ha l'Iniziativa (RU)")
	_check(Rules.sd_winner(3, RUS) == GER, "bilancia +3 → vince la Germania a prescindere dall'Iniziativa")
	_check(Rules.sd_winner(-2, GER) == RUS, "bilancia -2 → vince la Russia")
	# 9.1: rifà il tiro (cedendo l'Iniziativa) solo chi perde E detiene l'Iniziativa.
	_check(Rules.sd_initiative_rerolls(3, RUS), "RU perde (DE avanti) e ha l'Iniziativa → Re-Roll")
	_check(not Rules.sd_initiative_rerolls(3, GER), "DE è in vantaggio: non rifà")
	_check(not Rules.sd_initiative_rerolls(0, GER), "in pareggio l'Iniziativa vince: non rifà")
	_check(Rules.sd_initiative_rerolls(-1, GER), "DE perde (RU avanti) e ha l'Iniziativa → Re-Roll")


func _test_can_be_ordered() -> void:
	print("· Idoneità agli ordini attivi (Mossa/Fuoco/Avanzata)")
	var healthy := _mk("h", GER, SQUAD, RIFLE, 1, 1, 5, 7)
	_check(Rules.can_be_ordered(healthy), "unità efficiente, non soppressa, non attivata → può ricevere ordini")
	var sup := _mk("s", GER, SQUAD, RIFLE, 1, 1, 5, 7)
	sup.suppress()
	_check(not Rules.can_be_ordered(sup), "unità soppressa → immobilizzata (no Mossa/Fuoco/Avanzata)")
	var brk := _mk("b", GER, SQUAD, RIFLE, 1, 1, 5, 7)
	brk.break_unit()
	_check(not Rules.can_be_ordered(brk), "unità rotta → no ordini attivi (solo Rotta/Recupero)")
	var act := _mk("a", GER, SQUAD, RIFLE, 1, 1, 5, 7)
	act.activated = true
	_check(not Rules.can_be_ordered(act), "unità già attivata → non rigiocabile")
	# Coerenza col fuoco: una soppressa non può sparare anche entro gittata/LOS.
	var s := _new_state()
	var shooter := _mk("sh", GER, SQUAD, RIFLE, 0, 0, 5, 7, 3)
	shooter.suppress()
	var tgt := _mk("tg", RUS, SQUAD, RIFLE, 1, 0, 5, 7)
	s.units[shooter.id] = shooter
	s.units[tgt.id] = tgt
	_check(not Combat.can_fire(shooter, 1, 0, s), "can_fire rifiuta la soppressa (coerente con can_be_ordered)")


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


func _test_time_defender_vp() -> void:
	print("· TEMPO!: +1 VP al Difensore dello scenario (6.1.2)")
	# Difensore Asse (GER) → +1 alla bilancia (positiva = Germania).
	var sg := _new_state()
	sg.defender_faction = GER
	sg.sudden_death_space = 7
	var b0 := sg.bonus_vp
	Fate.apply_consequence(sg, _fate_card(1, 1, "time"), RUS)
	_check(sg.bonus_vp == b0 + 1, "Difensore Asse → +1 alla bilancia VP")
	# Difensore Alleati (RUS) → -1.
	var sr := _new_state()
	sr.defender_faction = RUS
	sr.sudden_death_space = 7
	var r0 := sr.bonus_vp
	Fate.apply_consequence(sr, _fate_card(1, 1, "time"), GER)
	_check(sr.bonus_vp == r0 - 1, "Difensore Alleati → -1 alla bilancia VP")
	# Nessun difensore (scontro recon/recon) → il Tempo! non assegna VP.
	var sn := _new_state()
	sn.defender_faction = -1
	sn.sudden_death_space = 7
	var n0 := sn.bonus_vp
	Fate.apply_consequence(sn, _fate_card(1, 1, "time"), GER)
	_check(sn.bonus_vp == n0, "Senza difensore il Tempo! non dà VP")


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


func _test_min_fp_hindrance() -> void:
	print("· Fuoco: hindrance che azzera la FP annulla l'attacco (10.3.2.1)")
	var s := _new_state()
	var atk := _mk("ger", GER, SQUAD, RIFLE, 0, 0, 2, 7)  # FP 2, gittata 6
	var tgt := _mk("rus", RUS, SQUAD, RIFLE, 3, 0, 5, 7)
	s.units[atk.id] = atk
	s.units[tgt.id] = tgt
	# Brush (hindrance 3) intermedio: FP 2 − 3 ≤ 0 → attacco annullato.
	s.hexes["1,0"].terrain = Domain.TerrainType.BRUSH
	var r := Combat.resolve_fire(atk, 3, 0, s, Vector2i(6, 6), Vector2i(1, 1))
	_check(r.fp_total == 0 and r.broken.is_empty() and r.eliminated.is_empty() and r.suppressed.is_empty(),
		"FP 2 − hindrance 3 ≤ 0 → attacco annullato, nessun effetto")
	# Un'Azione che alza la FP la riporta a ≥1 e l'attacco si fa (2 +2 −3 = 1).
	var r2 := Combat.resolve_fire(atk, 3, 0, s, Vector2i(6, 6), Vector2i(1, 1), [], 2)
	_check(r2.fp_total == 1, "le Azioni che alzano la FP riportano l'attacco a ≥1 (10.3.2.1)")


func _test_los_hindrance() -> void:
	print("· LOS: hindrance NON cumulativo (10.3.3, valori Terrain Chart)")
	var s := _new_state()
	_check(HexGrid.los_hindrance(0, 0, 3, 0, s) == 0, "nessun hindrance su terreno aperto")
	# Valori ufficiali: Brush 3, Orchard 2, Field 1.
	var sb := _new_state()
	sb.hexes["1,0"].terrain = Domain.TerrainType.BRUSH
	_check(HexGrid.los_hindrance(0, 0, 3, 0, sb) == 3, "un Brush intermedio = hindrance 3")
	# Esempio del regolamento: DUE Brush intermedi = 3 (non 6) — non cumulativo.
	sb.hexes["2,0"].terrain = Domain.TerrainType.BRUSH
	_check(HexGrid.los_hindrance(0, 0, 3, 0, sb) == 3, "due Brush intermedi = 3, non 6 (non cumulativo)")
	# Il modificatore singolo più grande: Brush(3) + Orchard(2) → 3.
	var so := _new_state()
	so.hexes["1,0"].terrain = Domain.TerrainType.BRUSH
	so.hexes["2,0"].terrain = Domain.TerrainType.ORCHARD
	_check(HexGrid.los_hindrance(0, 0, 3, 0, so) == 3, "Brush+Orchard = max(3,2) = 3")
	# Fumo: ostacola anche sull'esagono del bersaglio (10.3.4).
	var ss := _new_state()
	ss.hexes["3,0"].has_smoke = true
	_check(HexGrid.los_hindrance(0, 0, 3, 0, ss) == HexGrid.SMOKE_HINDRANCE,
		"il fumo sul bersaglio ostacola (10.3.4)")


func _test_los_kind() -> void:
	print("· LOS: classificazione libera/ostacolata/bloccata (Modalità LOS)")
	_check(HexGrid.los_kind(0, 0, 3, 0, _new_state()) == HexGrid.LOS_CLEAR, "terreno aperto: libera")
	var sh := _new_state()
	sh.hexes["1,0"].terrain = Domain.TerrainType.BRUSH
	_check(HexGrid.los_kind(0, 0, 3, 0, sh) == HexGrid.LOS_HINDERED, "Brush intermedio: ostacolata")
	var sb := _new_state()
	sb.side_features.append(_side(Vector2i(1, 0), Vector2i(2, 0), Domain.HexsideFeature.WALL))
	_check(HexGrid.los_kind(0, 0, 3, 0, sb) == HexGrid.LOS_BLOCKED, "muro su lato intermedio: bloccata")


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


func _test_more_events() -> void:
	print("· Eventi: Interdizione/Trinceramento/Promozione/C&C/Impeto")
	# E60 Interdizione: ogni mano perde una carta.
	var s := _new_state()
	for _i in 3:
		s.german_hand.append(Card.new())
	for _j in 2:
		s.russian_hand.append(Card.new())
	Events.fire(s, _ev("INTERDIZIONE"), GER)
	_check(s.german_hand.size() == 2 and s.russian_hand.size() == 1,
		"Interdizione scarta una carta per mano")

	# E55 Trinceramento: buca sull'esagono dell'unità.
	var s2 := _new_state()
	var g := _mk("g", GER, SQUAD, RIFLE, 1, 1, 5, 7)
	s2.units[g.id] = g
	Events.fire(s2, _ev("TRINCERAMENTO"), GER)
	_check(s2.hex_at(1, 1).has_foxhole, "Trinceramento crea una buca sull'unità")

	# E56 Promozione sul campo: Soldato (Comando 2) su un'unità rotta.
	var s3 := _new_state()
	var br := _mk("b", GER, SQUAD, RIFLE, 2, 2, 5, 7)
	br.break_unit()
	s3.units[br.id] = br
	Events.fire(s3, _ev("PROMOZIONE SUL CAMPO"), GER)
	_check(s3.units.has("PRIVATE-GER") and s3.units["PRIVATE-GER"].command == 2,
		"Promozione crea un Soldato (Comando 2) sull'unità rotta")

	# E49 Comando e Controllo: +1 VP per obiettivo controllato.
	var s4 := _new_state()
	for i in 3:
		s4.objectives.append(Objective.new(i + 1, i, 0, 3))
	s4.objectives[0].controller = GER
	s4.objectives[1].controller = GER
	s4.objectives[2].controller = RUS
	Events.fire(s4, _ev("COMANDO E CONTROLLO"), GER)
	_check(s4.bonus_vp == 2, "Comando e Controllo: +1 VP per obiettivo controllato")

	# E54 Impeto: la soglia di resa sale di 1.
	var s5 := _new_state()
	s5.surrender_threshold[GER] = 5
	Events.fire(s5, _ev("IMPETO"), GER)
	_check(int(s5.surrender_threshold[GER]) == 6, "Impeto alza la soglia di resa di 1")


func _test_radio_unit() -> void:
	print("· Radio: entra in gioco come unità benigna (abilita O18)")
	_check(UnitChart.category("Radio 105mm") == UnitChart.Cat.WEAPON,
		"La Radio è categoria WEAPON (non più SKIP)")
	var r := UnitChart.build_unit("R1", GER, "Radio 105mm", 1, 1)
	_check(r != null and r.unit_name.contains("Radio"), "La Radio ha un nome che la identifica")
	_check(r.fp == 0 and r.range == 0 and r.move == 0, "La Radio non spara e non si muove")
	_check(not r.is_man() and not r.is_leader(), "La Radio è un'arma, non un uomo/leader")

	# Integrazione: in uno scenario con Radio, essa entra in gioco.
	var s := GameState.new()
	if ScenarioLoader.setup(s, 4):  # Closed for Renovation: Radio 75mm alleata
		var has_radio := false
		for u in s.units.values():
			if u.unit_name.contains("Radio"):
				has_radio = true
				break
		_check(has_radio, "Scenario 4: la Radio entra in gioco")


func _test_artillery() -> void:
	print("· Artiglieria (O18): deriva e impatto a 7 esagoni")
	var s := _new_state()
	var sr := Rules.artillery_drift(s, 2, 2, true, 1, 1)
	_check(sr.x >= 0 and sr.x < s.map_cols and sr.y >= 0 and sr.y < s.map_rows,
		"Deriva (colpito) resta in mappa")
	var off := Rules.artillery_drift(s, 0, 0, false, 5, 2)
	_check(off.x < 0, "Deriva oltre il bordo → nessun effetto")

	# Impatto: chi è nel raggio (centro+adiacenti) è colpito, chi è fuori no.
	var s2 := _new_state()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var inblast := _mk("in", GER, SQUAD, RIFLE, 2, 2, 5, 2)
	var outside := _mk("out", RUS, SQUAD, RIFLE, 0, 0, 5, 2)
	s2.units[inblast.id] = inblast
	s2.units[outside.id] = outside
	var res := Combat.resolve_artillery(s2, 30, 2, 2, rng)
	_check(not s2.units.has("in") or not s2.units["in"].efficient,
		"Impatto colpisce chi è nel raggio")
	_check(s2.units["out"].efficient, "Impatto non tocca chi è fuori dal raggio")
	_check(int(res["hexes"]) >= 5, "Impatto copre il centro e gli adiacenti in mappa")

	# Radio FP dal Manifest (75-76→8 … 183-203→13).
	_check(Rules.radio_fp_for("75-76mm") == 8, "Radio 75-76mm → FP 8")
	_check(Rules.radio_fp_for("Radio 81-88mm") == 9, "Radio 81-88mm → FP 9")
	_check(Rules.radio_fp_for("105-114mm") == 10, "Radio 105-114mm → FP 10")
	_check(Rules.radio_fp_for("183-203mm") == 13, "Radio 183-203mm → FP 13")
	# Vulnerabilità delle fortificazioni (O18.2.3.3): 20 − FP, match ESATTO.
	_check(Rules.artillery_fort_vulnerability(8) == 12, "Vulnerabilità: Radio FP 8 → 12")
	_check(Rules.artillery_fort_vulnerability(13) == 7, "Vulnerabilità: Radio FP 13 → 7")
	var sf := _new_state()
	sf.hex_at(2, 2).fortification = Domain.Fort.BUNKER
	Combat.resolve_artillery(sf, 8, 2, 2, rng, 12)  # impact 12 == vulnerabilità (FP 8)
	_check(sf.hex_at(2, 2).fortification == Domain.Fort.NONE,
		"Impact Roll esatto (12 con Radio FP 8) distrugge il Bunker")
	var sf2 := _new_state()
	sf2.hex_at(2, 2).fortification = Domain.Fort.BUNKER
	Combat.resolve_artillery(sf2, 8, 2, 2, rng, 11)  # impact 11 ≠ 12
	_check(sf2.hex_at(2, 2).fortification == Domain.Fort.BUNKER,
		"Impact Roll diverso dalla vulnerabilità non spiana il Bunker")

	# Barrage fumogeno (O18.2.3.1): posa fumo sui 7 esagoni, salta le fiamme.
	var sm := _new_state(6, 6)
	var ns := Combat.resolve_smoke_barrage(sm, 2, 2)
	_check(ns >= 5 and sm.hex_at(2, 2).has_smoke, "Barrage fumogeno copre centro e adiacenti")
	var sm2 := _new_state(6, 6)
	sm2.hex_at(2, 2).has_blaze = true
	Combat.resolve_smoke_barrage(sm2, 2, 2)
	_check(not sm2.hex_at(2, 2).has_smoke, "Barrage fumogeno salta l'esagono in fiamme")

	# Integrazione: l'ordine ARTI con Radio+Leader conta come ordine.
	var s3 := _new_state(6, 6)
	s3.human_faction = GER
	s3.phase = Domain.Phase.PLAYER_TURN
	s3.max_orders = 5
	s3.sudden_death_space = 20
	var radio := _mk("R", GER, Domain.UnitType.WEAPON, RIFLE, 1, 1, 0, 7)
	radio.unit_name = "Radio 75mm"
	var ldr := _mk("L", GER, LEADER, ELITE, 1, 1, 1, 8)
	s3.units[radio.id] = radio
	s3.units[ldr.id] = ldr
	s3.units["en"] = _mk("en", RUS, SQUAD, RIFLE, 3, 1, 5, 2)
	var card := Card.new()
	card.order = Domain.OrderType.ARTY
	s3.german_hand.append(card)
	Game.state = s3
	Game.play_card(0)
	_check(s3.order_count == 1, "Artiglieria con Radio+Leader conta come ordine")
	_check(s3.current_order == Domain.OrderType.ARTY and not s3.highlighted_hexes.is_empty(),
		"Artiglieria: fase di scelta bersaglio con esagoni nella LOS")
	Game.toggle_artillery_smoke()
	_check(s3.artillery_smoke, "Toggle «S»: attiva il barrage fumogeno")
	Game.toggle_artillery_smoke()
	_check(not s3.artillery_smoke, "Toggle «S»: torna a esplosivo")
	Game.click_hex_artillery(3, 1)
	_check(s3.phase == Domain.Phase.PLAYER_TURN and s3.current_order == -1,
		"Artiglieria: scelto il bersaglio, si torna al turno")

	# Senza Radio non si consuma un ordine.
	var s4 := _new_state(6, 6)
	s4.human_faction = GER
	s4.phase = Domain.Phase.PLAYER_TURN
	s4.max_orders = 5
	s4.sudden_death_space = 20
	s4.units["L2"] = _mk("L2", GER, LEADER, ELITE, 1, 1, 1, 8)
	var card2 := Card.new()
	card2.order = Domain.OrderType.ARTY
	s4.german_hand.append(card2)
	Game.state = s4
	Game.play_card(0)
	_check(s4.order_count == 0, "Artiglieria senza Radio non consuma un ordine")


func _test_ai_artillery() -> void:
	print("· IA artiglieria (O18): scelta del bombardamento")
	var s := _new_state(6, 6)
	var radio := _mk("R", RUS, Domain.UnitType.WEAPON, RIFLE, 1, 1, 0, 7)
	radio.unit_name = "Radio 105mm"
	s.units[radio.id] = radio
	s.units["L"] = _mk("L", RUS, LEADER, ELITE, 1, 1, 1, 8)
	s.units["g1"] = _mk("g1", GER, SQUAD, RIFLE, 3, 1, 5, 7)
	s.units["g2"] = _mk("g2", GER, SQUAD, RIFLE, 3, 1, 5, 7)  # due nemici nello stesso esagono
	var art := AI.best_artillery(s, RUS)
	_check(not art.is_empty() and int(art["score"]) == 2, "IA mira al cluster nemico (2 unità)")
	_check(art.get("spotter_id") == "L" and art.get("radio_id") == "R",
		"IA usa Radio e Leader corretti")

	var s2 := _new_state(6, 6)
	s2.units["L2"] = _mk("L2", RUS, LEADER, ELITE, 1, 1, 1, 8)
	s2.units["g3"] = _mk("g3", GER, SQUAD, RIFLE, 3, 1, 5, 7)
	_check(AI.best_artillery(s2, RUS).is_empty(), "Senza Radio l'IA non richiede artiglieria")


func _test_click_hex() -> void:
	print("· Dispatch click esagono (condiviso 2D/3D)")
	var s := _new_state()
	s.human_faction = GER
	s.phase = Domain.Phase.PLAYER_TURN
	var u := _mk("g", GER, SQUAD, RIFLE, 2, 2, 5, 7)
	s.units[u.id] = u
	Game.state = s
	Game.click_hex(2, 2)
	_check(s.selected_unit_id == "g", "click_hex su unità amica la seleziona")
	Game.click_hex(0, 0)
	_check(s.selected_unit_id == "", "click_hex su esagono vuoto deseleziona")


func _test_stack_cycle() -> void:
	print("· Impilamento: ciclo di selezione a clic ripetuti")
	var s := _new_state()
	s.human_faction = GER
	s.phase = Domain.Phase.PLAYER_TURN
	s.units["a"] = _mk("a", GER, SQUAD, RIFLE, 2, 2, 5, 7)
	s.units["b"] = _mk("b", GER, SQUAD, RIFLE, 2, 2, 5, 7)
	s.units["c"] = _mk("c", GER, LEADER, ELITE, 2, 2, 1, 8)
	Game.state = s
	Game.click_hex(2, 2)
	_check(s.selected_unit_id == "a", "1° clic: prima pedina")
	Game.click_hex(2, 2)
	_check(s.selected_unit_id == "b", "2° clic: seconda pedina")
	Game.click_hex(2, 2)
	_check(s.selected_unit_id == "c", "3° clic: terza pedina")
	Game.click_hex(2, 2)
	_check(s.selected_unit_id == "", "4° clic: deseleziona dopo l'ultima")
	Game.click_hex(2, 2)
	_check(s.selected_unit_id == "a", "5° clic: riparte dalla prima")


func _test_artillery_available() -> void:
	print("· HUD: disponibilità artiglieria (Radio + Leader)")
	var s := _new_state()
	s.human_faction = GER
	Game.state = s
	_check(not Game.has_artillery_available(), "Senza unità: niente artiglieria")
	s.units["L"] = _mk("L", GER, LEADER, ELITE, 1, 1, 1, 8)
	_check(not Game.has_artillery_available(), "Solo leader: niente artiglieria")
	var r := _mk("R", GER, Domain.UnitType.WEAPON, RIFLE, 1, 1, 0, 7)
	r.unit_name = "Radio 75mm"
	s.units["R"] = r
	_check(Game.has_artillery_available(), "Radio + Leader: artiglieria disponibile")
	r.break_unit()
	_check(not Game.has_artillery_available(), "Radio rotta: niente artiglieria")


func _test_blaze() -> void:
	print("· Incendio (E46): esagono impassabile + sgombero")
	var s := _new_state()
	var u := _mk("u", GER, SQUAD, RIFLE, 1, 1, 5, 7)
	s.units[u.id] = u
	s.hex_at(1, 1).has_smoke = true
	s.hex_at(1, 1).fortification = Domain.Fort.TRENCH
	var c := _ev("INCENDIO")
	c.random_hex_label = "B2"  # → (1,1)
	Events.fire(s, c, GER)
	_check(s.hex_at(1, 1).has_blaze, "Incendio accende l'esagono")
	_check(not s.hex_at(1, 1).has_smoke and s.hex_at(1, 1).fortification == Domain.Fort.NONE,
		"Incendio rimuove fumo e fortificazione")
	_check(s.units.has("u") and (s.units["u"].q != 1 or s.units["u"].r != 1),
		"Incendio sgombera l'unità in un esagono adiacente")
	_check(HexGrid.step_cost(s, 2, 1, 1, 1) == -1, "Esagono in fiamme impassabile")


func _test_melee_fortification_tie() -> void:
	print("· Corpo a corpo: pareggio in Bunker/Casamatta (F101/F104)")
	# Pareggio in Bunker → vince il difensore (ultimo occupante solitario).
	var s := _new_state()
	s.hex_at(2, 2).fortification = Domain.Fort.BUNKER
	var atk := _mk("a", GER, SQUAD, RIFLE, 2, 2, 5, 7)
	var dfn := _mk("d", RUS, SQUAD, RIFLE, 2, 2, 5, 7)
	s.units[atk.id] = atk
	s.units[dfn.id] = dfn
	var r := Rules.resolve_melee(s, [atk], [dfn], Vector2i(3, 3), Vector2i(3, 3))
	_check(r.winner == RUS, "Pareggio in Bunker: vince il difensore")
	_check(not s.units.has("a") and s.units.has("d"),
		"Pareggio in Bunker: eliminato solo l'attaccante")

	# Pareggio in aperto → entrambi eliminati (comportamento standard).
	var s2 := _new_state()
	var a2 := _mk("a2", GER, SQUAD, RIFLE, 2, 2, 5, 7)
	var d2 := _mk("d2", RUS, SQUAD, RIFLE, 2, 2, 5, 7)
	s2.units[a2.id] = a2
	s2.units[d2.id] = d2
	var r2 := Rules.resolve_melee(s2, [a2], [d2], Vector2i(3, 3), Vector2i(3, 3))
	_check(r2.winner == -1 and not s2.units.has("a2") and not s2.units.has("d2"),
		"Pareggio in aperto: entrambi eliminati")


func _test_more_events2() -> void:
	print("· Eventi: Prigionieri/Polvere/Obiettivo-missione/strategico")
	# E66 Prigionieri di guerra: rotta a contatto col nemico → eliminata.
	var s := _new_state()
	var br := _mk("b", GER, SQUAD, RIFLE, 2, 2, 5, 7)
	br.break_unit()
	s.units[br.id] = br
	s.units["e"] = _mk("e", RUS, SQUAD, RIFLE, 2, 2, 5, 7)  # stesso esagono = a contatto
	Events.fire(s, _ev("PRIGIONIERI DI GUERRA"), GER)
	_check(not s.units.has("b"), "Prigionieri elimina la rotta a contatto col nemico")
	# Senza nemico vicino non elimina nulla.
	var s2 := _new_state()
	var lone := _mk("b2", GER, SQUAD, RIFLE, 0, 0, 5, 7)
	lone.break_unit()
	s2.units[lone.id] = lone
	Events.fire(s2, _ev("PRIGIONIERI DI GUERRA"), GER)
	_check(s2.units.has("b2"), "Prigionieri: nessuna eliminazione senza nemico vicino")

	# E53 Polvere: fumo sull'esagono della carta (B2 → 1,1).
	var s3 := _new_state()
	var dust := _ev("POLVERE")
	dust.random_hex_label = "B2"
	Events.fire(s3, dust, GER)
	_check(s3.hex_at(1, 1).has_smoke, "Polvere posa il fumo sull'esagono indicato")

	# E65 Obiettivo della missione: estrae UN chit reale e lo applica.
	var s4 := _new_state()
	for i in 5:
		s4.objectives.append(Objective.new(i + 1, i, 0, 0))
	var ev_lines := Events.fire(s4, _ev("OBIETTIVO DELLA MISSIONE"), GER)
	var mentions_chit := false
	for l in ev_lines:
		if "chit" in String(l).to_lower():
			mentions_chit = true
	_check(mentions_chit, "Obiettivo della missione estrae un chit obiettivo")
	var total := 0
	for o in s4.objectives:
		total += o.vp
	# Tutti gli obiettivi 1-5 sono presenti: un chit di valore dà VP, uno globale 0.
	_check(total >= 0, "il chit estratto applica VP validi (≥ 0)")


func _obj_vp(s: GameState, oid: int) -> int:
	for o in s.objectives:
		if o.id == oid:
			return o.vp
	return -1


func _test_objective_chits() -> void:
	print("· Chit Obiettivo (7.3.2): mix reale dei 22 chit")
	var s := _new_state()
	for i in 5:
		s.objectives.append(Objective.new(i + 1, 0, i, 0))
	var lines: Array = []
	# Esempio del regolamento: C+G+K sull'Obiettivo #3 = 1+2+3 = 6 VP.
	ObjectiveChits.apply(s, "C", lines)
	ObjectiveChits.apply(s, "G", lines)
	ObjectiveChits.apply(s, "K", lines)
	_check(_obj_vp(s, 3) == 6, "C+G+K sull'Obiettivo #3 = 6 VP (cumulativo, esempio del regolamento)")
	ObjectiveChits.apply(s, "Q", lines)
	_check(_obj_vp(s, 5) == 5, "Chit Q: Obiettivo #5 +5 VP")
	ObjectiveChits.apply(s, "S", lines)  # ogni obiettivo +1
	_check(_obj_vp(s, 1) == 1 and _obj_vp(s, 3) == 7 and _obj_vp(s, 5) == 6, "Chit S: ogni Obiettivo +1 VP")
	# Chit "[open]" globali: attivano le regole sui VP raddoppiati.
	ObjectiveChits.apply(s, "W", lines)
	ObjectiveChits.apply(s, "X", lines)
	_check(s.chit_double_exit, "Chit W: VP d'uscita raddoppiati")
	_check(s.chit_double_elim, "Chit X: VP da eliminazione raddoppiati")
	# Chit per un obiettivo non sulla mappa → nessun effetto, nessun crash.
	var s_small := _new_state()
	s_small.objectives.append(Objective.new(1, 0, 0, 0))
	_check(ObjectiveChits.apply(s_small, "Q", []) and _obj_vp(s_small, 1) == 0,
		"Chit per un obiettivo assente non produce VP")

	# assign(): estrae `count` chit DISTINTI dal sacchetto da 22 (senza rimpiazzo).
	var s2 := _new_state()
	for i in 5:
		s2.objectives.append(Objective.new(i + 1, 0, i, 9))
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var res := ObjectiveChits.assign(s2, 4, rng)
	_check(res["drawn"].size() == 4, "assign estrae 4 chit")
	var uniq := {}
	for d in res["drawn"]:
		uniq[d] = true
	_check(uniq.size() == 4, "i chit estratti sono distinti (senza rimpiazzo)")

	# count<=0 → nessun cambiamento ai VP stampati.
	var s3 := _new_state()
	s3.objectives.append(Objective.new(1, 0, 0, 7))
	ObjectiveChits.assign(s3, 0, rng)
	_check(s3.objectives[0].vp == 7, "Senza chit i VP stampati restano")

	# Nessun obiettivo → nessun crash, nessun chit.
	var s4 := _new_state()
	var r4 := ObjectiveChits.assign(s4, 5, rng)
	_check(r4["drawn"].is_empty(), "Nessun obiettivo: nessun chit assegnato")

	# Doppia eliminazione (Chit X): i VP da eliminazione sono raddoppiati.
	var s5 := _new_state()
	s5.chit_double_elim = true
	var victim := _mk("rus-v", RUS, SQUAD, RIFLE, 0, 0, 5, 7)  # squadra = 2 VP
	s5.units[victim.id] = victim
	var before := s5.bonus_vp
	s5.eliminate_unit(victim.id)
	_check(s5.bonus_vp - before == 4, "Chit X: una squadra eliminata vale 4 VP (2×2) invece di 2")


func _test_assault_fire() -> void:
	print("· Fuoco d'Assalto (A26): attacco di fuoco durante la Mossa")
	var s := _new_state(6, 6)
	s.sudden_death_space = 20
	s.human_faction = GER
	s.phase = Domain.Phase.PLAYER_MOVING
	s.current_order = Domain.OrderType.MOVE
	var atk := _mk("g", GER, SQUAD, RIFLE, 2, 2, 12, 7, 6)
	s.units[atk.id] = atk
	s.selected_unit_id = atk.id
	var d := _mk("r", RUS, SQUAD, RIFLE, 2, 4, 5, -50)  # in gittata/LOS, difesa sempre persa
	s.units[d.id] = d
	var card := Card.new()
	card.action_name = "FUOCO D'ASSALTO"
	s.german_hand.append(card)
	Game.state = s
	Game.assault_fire(0)
	_check(s.assault_fired, "Fuoco d'Assalto: segnato come usato")
	_check(not s.units.has("r") or not s.units["r"].efficient,
		"Fuoco d'Assalto: il bersaglio in gittata è colpito")

	# Un secondo Fuoco d'Assalto nello stesso ordine è rifiutato.
	s.assault_fired = true
	var d2 := _mk("r2", RUS, SQUAD, RIFLE, 3, 2, 5, 7)
	s.units[d2.id] = d2
	Game.assault_fire(0)
	_check(s.units["r2"].efficient, "Fuoco d'Assalto: non si ripete nello stesso ordine")

	# Un leader non può fare Fuoco d'Assalto (no FP «in scatola»).
	var s2 := _new_state(6, 6)
	s2.sudden_death_space = 20
	s2.human_faction = GER
	s2.phase = Domain.Phase.PLAYER_MOVING
	s2.current_order = Domain.OrderType.MOVE
	var ldr := _mk("L", GER, LEADER, RIFLE, 2, 2, 0, 8, 6)
	s2.units[ldr.id] = ldr
	s2.selected_unit_id = ldr.id
	s2.units["re"] = _mk("re", RUS, SQUAD, RIFLE, 2, 3, 5, 7)
	var c2 := Card.new()
	c2.action_name = "FUOCO D'ASSALTO"
	s2.german_hand.append(c2)
	Game.state = s2
	Game.assault_fire(0)
	_check(not s2.assault_fired, "Fuoco d'Assalto: un leader non può eseguirlo")


func _test_exit_vp() -> void:
	print("· VP di uscita (7.2): uscita dal bordo avversario")
	# Tedesco sul bordo Ovest (q=0) → +2 VP ai Tedeschi.
	var s := _new_state(6, 6)
	s.sudden_death_space = 20
	s.human_faction = GER
	s.phase = Domain.Phase.PLAYER_MOVING
	s.current_order = Domain.OrderType.MOVE
	var g := _mk("g", GER, SQUAD, RIFLE, 0, 2, 5, 7)
	s.units[g.id] = g
	s.selected_unit_id = g.id
	s.group_mp[g.id] = 2
	Game.state = s
	_check(Game.can_exit_selected(), "Tedesco sul bordo Ovest può uscire")
	Game.exit_selected_unit()
	_check(not s.units.has("g"), "L'unità uscita lascia la mappa")
	_check(s.bonus_vp == 2, "Uscita di una squadra tedesca: +2 VP ai Tedeschi")

	# Russo sul bordo Est (q=cols-1) → +2 VP ai Russi (bonus negativo).
	var s2 := _new_state(6, 6)
	s2.sudden_death_space = 20
	s2.human_faction = RUS
	s2.phase = Domain.Phase.PLAYER_MOVING
	s2.current_order = Domain.OrderType.MOVE
	var r := _mk("r", RUS, SQUAD, RIFLE, 5, 2, 5, 7)
	s2.units[r.id] = r
	s2.selected_unit_id = r.id
	s2.group_mp[r.id] = 1
	Game.state = s2
	_check(Game.can_exit_selected(), "Russo sul bordo Est può uscire")
	Game.exit_selected_unit()
	_check(s2.bonus_vp == -2, "Uscita di una squadra russa: +2 VP ai Russi")

	# Lontano dal bordo: niente uscita.
	var s3 := _new_state(6, 6)
	s3.sudden_death_space = 20
	s3.human_faction = GER
	s3.phase = Domain.Phase.PLAYER_MOVING
	s3.current_order = Domain.OrderType.MOVE
	var g3 := _mk("g3", GER, SQUAD, RIFLE, 3, 2, 5, 7)
	s3.units[g3.id] = g3
	s3.selected_unit_id = g3.id
	s3.group_mp[g3.id] = 2
	Game.state = s3
	_check(not Game.can_exit_selected(), "Lontano dal bordo non si può uscire")


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

	# Buca (F102): copertura ALTERNATIVA 3 (4 vs ordnance/artiglieria), non cumulativa.
	var sfx := _new_state()
	sfx.hex_at(0, 0).has_foxhole = true
	_check(Rules.cover_at(sfx, 0, 0, false) == 3, "Buca → copertura 3")
	_check(Rules.cover_at(sfx, 0, 0, true) == 4, "Buca vs ordnance/artiglieria → 4 (F102)")
	sfx.hex_at(1, 1).terrain = Domain.TerrainType.WOODS  # copertura 2
	sfx.hex_at(1, 1).has_foxhole = true
	_check(Rules.cover_at(sfx, 1, 1, false) == 3, "Buca nel bosco → 3 (alternativa, NON cumulativa)")

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


func _test_op_fire_card_cost() -> void:
	print("· Op Fire: serve una carta Fuoco, la consuma e attiva il tiratore (A24.1/.3)")
	var s := _new_state(6, 3)
	s.human_faction = GER          # difensore IA = RUS
	var mover := _mk("ger", GER, SQUAD, RIFLE, 2, 2, 5, 7)
	var sh := _mk("rus", RUS, SQUAD, RIFLE, 2, 1, 9, 7)  # adiacente, FP alto: tiro conveniente
	s.units[mover.id] = mover
	s.units[sh.id] = sh
	# Mazzi minimi (carte PASS) per il rifornimento e i dadi del Fato.
	for i in 5:
		var rc := Card.new(); rc.order = Domain.OrderType.PASS; s.russian_deck.append(rc)
		var gc := Card.new(); gc.order = Domain.OrderType.PASS; s.german_deck.append(gc)
	Game.state = s
	# Senza carta Fuoco: l'IA non reagisce e non attiva nessuno.
	s.russian_hand.clear()
	_check(Game._op_fire(mover, RUS) == false, "senza carta Fuoco l'IA non reagisce")
	_check(not sh.activated, "nessun tiratore attivato senza reazione")
	# A24.3: un'unità già attivata non è idonea all'op-fire.
	sh.activated = true
	_check(OpFire.eligible_shooters(s, mover, RUS).is_empty(), "un'unità attivata non fa op-fire")
	sh.activated = false
	# Con una carta Fuoco: reagisce, consuma la carta e attiva il tiratore.
	var fcard := Card.new()
	fcard.order = Domain.OrderType.FIRE
	s.russian_hand.append(fcard)
	Game._op_fire(mover, RUS)
	_check(Game._fire_card_index(RUS) < 0, "la carta Fuoco è stata consumata (A24.1)")
	_check(sh.activated, "il tiratore è stato attivato dall'op-fire (A24.3)")


func _test_pass_turn() -> void:
	print("· Passa (O15): scarta le carte scelte, ne ripesca altrettante, cede il turno")
	var s := _new_state(4, 3)
	s.human_faction = GER
	s.phase = Domain.Phase.PLAYER_TURN
	s.order_count = 2
	s.turn_number = 5
	# Mano di 4 carte distinguibili per ordine.
	for o in [Domain.OrderType.MOVE, Domain.OrderType.FIRE,
			Domain.OrderType.ADVANCE, Domain.OrderType.RECOVER]:
		var c := Card.new(); c.order = o; s.german_hand.append(c)
	# Mazzo per il rifornimento (più carte di quelle che si scartano: niente reshuffle).
	for i in 4:
		var d := Card.new(); d.order = Domain.OrderType.ROUT; s.german_deck.append(d)
	Game.state = s
	var move_card: Card = s.german_hand[0]
	var adv_card: Card = s.german_hand[2]
	var hand_size := s.german_hand.size()
	Game.pass_turn([0, 2])  # scarta MOSSA e AVANZATA
	_check(s.german_hand.size() == hand_size, "la mano resta piena (ripesca quante ne scarta)")
	_check(s.german_hand.find(move_card) < 0 and s.german_hand.find(adv_card) < 0,
		"le carte scelte sono uscite dalla mano")
	_check(s.german_discard.has(move_card) and s.german_discard.has(adv_card),
		"le carte scelte sono finite negli scarti")
	_check(s.order_count == 0 and s.turn_number == 6,
		"passare cede il turno (azzera gli ordini, avanza il numero di turno)")
	# Passare senza scartare conserva la mano e cede comunque il turno.
	var s2 := _new_state(4, 3)
	s2.human_faction = GER
	s2.phase = Domain.Phase.PLAYER_TURN
	s2.turn_number = 1
	for o in [Domain.OrderType.MOVE, Domain.OrderType.FIRE]:
		var c2 := Card.new(); c2.order = o; s2.german_hand.append(c2)
	Game.state = s2
	Game.pass_turn([])
	_check(s2.german_hand.size() == 2 and s2.german_discard.is_empty(),
		"passare senza scartare conserva la mano")
	_check(s2.turn_number == 2, "passare senza scartare cede comunque il turno")


func _test_move_command_group() -> void:
	print("· Comando (3.3.1.2): ordinare una qualunque unità comandata attiva tutto il gruppo")
	var s := _new_state(8, 4)
	s.human_faction = GER
	s.phase = Domain.Phase.PLAYER_MOVING
	s.current_order = Domain.OrderType.MOVE
	var L := _mk("L", GER, LEADER, ELITE, 2, 1, 1, 8, 6, 3)  # comando 3
	var A := _mk("A", GER, SQUAD, RIFLE, 3, 1, 5, 7)
	var B := _mk("B", GER, SQUAD, RIFLE, 1, 1, 5, 7)
	s.units["L"] = L; s.units["A"] = A; s.units["B"] = B
	Game.state = s
	# Clicco la squadra A (NON il leader): si attiva l'intero raggio di comando.
	Game.select_unit("A")
	_check(s.ordered_group.has("A") and s.ordered_group.has("B") and s.ordered_group.has("L"),
		"ordinare una squadra comandata attiva leader + tutte le unità in raggio")
	# Una squadra fuori dal comando di qualsiasi leader si muove da sola.
	var s2 := _new_state(14, 5)
	s2.human_faction = GER
	s2.phase = Domain.Phase.PLAYER_MOVING
	s2.current_order = Domain.OrderType.MOVE
	s2.units["L2"] = _mk("L2", GER, LEADER, ELITE, 0, 0, 1, 8, 6, 2)
	s2.units["C"] = _mk("C", GER, SQUAD, RIFLE, 12, 4, 5, 7)  # lontanissima
	Game.state = s2
	Game.select_unit("C")
	_check(s2.ordered_group.size() == 1 and s2.ordered_group.has("C"),
		"una squadra fuori comando si muove da sola")


func _test_reinforcements() -> void:
	print("· Rinforzi: sottratti dal setup, entrano quando il Tempo raggiunge il loro spazio")
	Game.start_new_game(GER, 9)  # «Rush to Contact»: molti rinforzi su entrambi i lati
	var s := Game.state
	_check(not s.reinforcements.is_empty(), "lo scenario 9 ha rinforzi in attesa nel pool")
	var before := s.units.size()
	var pending := 0
	for grp in s.reinforcements:
		for f in grp.get("forces", []):
			pending += int(f.get("n", 0))
	_check(pending > 0, "ci sono unità di rinforzo in attesa")
	# Il segnalino Tempo raggiunge tutti gli spazi usati (max 6): entrano tutti.
	s.time_marker = 6
	Game._check_reinforcements()
	_check(s.units.size() == before + pending, "tutti i rinforzi entrano in campo (+%d)" % pending)
	_check(s.reinforcements.is_empty(), "il pool dei rinforzi si svuota")
	# Le unità entrate sono sul bordo amico (Asse a destra / Alleati a sinistra).
	var on_edges := true
	for u in s.units.values():
		if String(u.id).begins_with("R-"):
			var edge := s.map_cols - 1 if u.faction == GER else 0
			if u.q != edge:
				on_edges = false
	_check(on_edges, "i rinforzi entrano dal bordo amico")
	# Scenario 24: i rinforzi (ricavati dall'OB della scheda) entrano allo spazio 1.
	Game.start_new_game(GER, 24)
	var s2 := Game.state
	var has_space1 := false
	for grp in s2.reinforcements:
		if int(grp.get("space", 0)) == 1:
			has_space1 = true
	_check(has_space1, "lo scenario 24 ha rinforzi allo spazio 1")
	var before2 := s2.units.size()
	s2.time_marker = 1
	Game._check_reinforcements()
	_check(s2.units.size() > before2, "i rinforzi dello scenario 24 entrano allo spazio 1")


func _test_global_hindrance() -> void:
	print("· SSR Nebbia: ostacolo globale (scenario 12) riduce la FP nel fuoco")
	var sc := GameState.new()
	ScenarioLoader.setup(sc, 12)
	_check(sc.global_hindrance == 3, "lo scenario 12 (Nebbia) ha ostacolo globale 3")
	# A parità di tutto, l'ostacolo globale taglia la FP dell'attacco.
	var st := _new_state(8, 3)
	var atk := _mk("a", GER, SQUAD, RIFLE, 0, 1, 8, 7, 9)
	st.units["a"] = atk
	st.units["d"] = _mk("d", RUS, SQUAD, RIFLE, 4, 1, 5, 7)
	var d33 := Vector2i(3, 3)
	var r0 := Combat.resolve_fire(atk, 4, 1, st, d33, d33)
	st.global_hindrance = 3
	var r1 := Combat.resolve_fire(atk, 4, 1, st, d33, d33)
	_check(r1.fp_total == r0.fp_total - 3, "l'ostacolo globale riduce la FP dell'attacco di 3")


func _test_scenario_effects() -> void:
	print("· SSR: gettoni Obiettivo esclusi dal sacchetto e carte garantite in mano")
	# Esclusione: con exclude i gettoni V/W/X non vengono mai pescati (22 = tutti).
	var s := _new_state(6, 6)
	s.objectives.append(Objective.new(1, 2, 2, 0))
	s.objectives.append(Objective.new(2, 3, 3, 0))
	s.objectives.append(Objective.new(3, 4, 4, 0))
	s.objectives.append(Objective.new(4, 1, 4, 0))
	s.objectives.append(Objective.new(5, 4, 1, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var res := ObjectiveChits.assign(s, 22, rng, ["V", "W", "X"])
	var drawn: Array = res["drawn"]
	_check(not drawn.has("V") and not drawn.has("W") and not drawn.has("X"),
		"i gettoni esclusi non vengono pescati")
	_check(drawn.size() == 19, "restano 19 gettoni nel sacchetto (22 − 3 esclusi)")
	# Carte iniziali: lo scenario 3 mette G-65 in mano all'Asse (mazzo tedesco).
	Game.start_new_game(GER, 3)
	var has65 := false
	for c in Game.state.german_hand:
		if int(c.number) == 65:
			has65 = true
	_check(has65, "lo scenario 3 garantisce G-65 in mano all'Asse")


func _test_smart_deploy() -> void:
	print("· Schieramento Auto intelligente: squadre raggruppate attorno ai leader")
	var s := GameState.new()
	if not ScenarioLoader.setup(s, 1):
		_check(false, "setup scenario 1 riuscito")
		return
	for fac in [GER, RUS]:
		var leaders: Array = []
		var squads: Array = []
		for u in s.units.values():
			if u.faction != fac or not u.is_man():
				continue
			if u.is_leader() and u.command > 0:
				leaders.append(u)
			elif not u.is_leader():
				squads.append(u)
		if leaders.is_empty() or squads.is_empty():
			continue
		var commanded := 0
		for sq in squads:
			for L in leaders:
				if HexGrid.distance(L.q, L.r, sq.q, sq.r) <= L.command:
					commanded += 1
					break
		_check(float(commanded) / float(squads.size()) >= 0.6,
			"≥60%% delle squadre è nel raggio di Comando di un leader (%d/%d)" % [commanded, squads.size()])


func _test_flipbot() -> void:
	print("· FlipBot: disposizione, carte dud, passa-e-scarta, scelta ordine")
	# Disposizione: il bot è il Tedesco. VP +7 a favore → Difensiva.
	var s := _new_state(6, 6)
	s.human_faction = RUS
	s.vp_tracker = 7
	_check(FlipBot.compute_disposition(s, GER) == Domain.Disposition.DEFENSIVE,
		"VP +7 a favore del bot → Difensiva")
	s.vp_tracker = 2
	_check(FlipBot.compute_disposition(s, GER) == Domain.Disposition.OFFENSIVE,
		"VP +2 (sotto soglia) → Offensiva")
	# Obiettivi controllati spingono verso la Difensiva (peso 2 ciascuno).
	s.vp_tracker = 3
	s.objectives = [Objective.new(1, 0, 0, 1), Objective.new(2, 1, 0, 1)]
	s.objectives[0].controller = GER
	s.objectives[1].controller = GER
	_check(FlipBot.compute_disposition(s, GER) == Domain.Disposition.DEFENSIVE,
		"VP +3 + 2 obiettivi controllati (×2) = 7 → Difensiva")

	# Carte dud: Confusione d'Ordini (PASS) sempre; Artiglieria senza radio.
	var pass_card := _card(Domain.OrderType.PASS)
	var arty_card := _card(Domain.OrderType.ARTY)
	var move_card := _card(Domain.OrderType.MOVE)
	var s2 := _new_state(6, 6)
	s2.human_faction = RUS
	_check(FlipBot.is_dud(s2, pass_card, GER), "Confusione d'Ordini è sempre dud")
	_check(FlipBot.is_dud(s2, arty_card, GER), "Richiesta d'Artiglieria senza radio è dud")
	_check(not FlipBot.is_dud(s2, move_card, GER), "una Mossa non è mai dud")

	# Mano per lo più dud → passa e scarta.
	s2.german_hand = [pass_card, _card(Domain.OrderType.PASS), move_card]
	_check(FlipBot.should_pass_and_discard(s2, GER), "2 dud su 3 → passa e scarta")
	_check(FlipBot.dud_indices(s2, GER).size() == 2, "trova 2 carte dud nella mano")

	# Scelta ordine: Recupero per primo se c'è un'unità rotta (anche non a sinistra).
	var s3 := _new_state(6, 6)
	s3.human_faction = RUS
	var sq := _mk("g1", GER, SQUAD, RIFLE, 0, 0)
	sq.efficient = false
	s3.units[sq.id] = sq
	s3.german_hand = [_card(Domain.OrderType.MOVE), _card(Domain.OrderType.RECOVER)]
	var play := FlipBot.choose_turn_order(s3, GER)
	_check(int(play.get("order", -1)) == Domain.OrderType.RECOVER,
		"con un'unità rotta gioca prima il Recupero")

	# Senza rotti: primo ordine giocabile da sinistra (PASS saltata, MOVE giocata).
	var s4 := _new_state(6, 6)
	s4.human_faction = RUS
	var sq2 := _mk("g2", GER, SQUAD, RIFLE, 0, 0)
	s4.units[sq2.id] = sq2
	s4.german_hand = [_card(Domain.OrderType.PASS), _card(Domain.OrderType.MOVE)]
	var play2 := FlipBot.choose_turn_order(s4, GER)
	_check(int(play2.get("order", -1)) == Domain.OrderType.MOVE,
		"salta la dud a sinistra e gioca la prima Mossa giocabile")


func _test_flipbot_move() -> void:
	print("· FlipBot: destinazioni di Mossa (obiettivi, Disposizione, ritirata)")
	# Mappa 10×3; il bot è il Tedesco (bordo nemico = colonna 0).
	var s := _new_state(10, 3)
	s.human_faction = RUS
	s.disposition = Domain.Disposition.OFFENSIVE
	_check(FlipBot.enemy_edge_col(s, GER) == 0, "bordo nemico del Tedesco = colonna 0")
	_check(FlipBot.friendly_edge_col(s, GER) == 9, "bordo amico del Tedesco = colonna 9")
	var u := _mk("g1", GER, SQUAD, RIFLE, 6, 1)
	s.units[u.id] = u
	# Nessun obiettivo né nemico → destinazione = bordo mappa nemico (colonna 0).
	var d0 := FlipBot.move_destination(s, GER, u)
	_check(d0.x == 0, "senza obiettivi/nemici punta al bordo nemico (col 0)")
	# Obiettivo non controllato entro 5 → lo conquista (priorità 1).
	var obj := Objective.new(1, 4, 1, 2)
	s.objectives = [obj]
	var d1 := FlipBot.move_destination(s, GER, u)
	_check(d1 == Vector2i(4, 1), "punta all'obiettivo conquistabile entro 5")
	# Obiettivo già controllato dal bot: in Offensiva NON è una destinazione...
	obj.controller = GER
	var d2 := FlipBot.move_destination(s, GER, u)
	_check(d2.x == 0, "obiettivo amico ignorato in Offensiva → bordo nemico")
	# ...ma in Difensiva sì (priorità 2): lo tiene.
	s.disposition = Domain.Disposition.DEFENSIVE
	var d3 := FlipBot.move_destination(s, GER, u)
	_check(d3 == Vector2i(4, 1), "in Difensiva tiene l'obiettivo amico entro 5")
	# Unità rotta → ritirata verso il bordo amico (colonna 9).
	u.efficient = false
	var d4 := FlipBot.move_destination(s, GER, u)
	_check(d4.x == 9, "un'unità rotta si ritira verso il bordo amico (col 9)")
	# "Ultima sull'obiettivo non lo lascia": unità sola su un obiettivo controllato.
	var u2 := _mk("g2", GER, SQUAD, RIFLE, 4, 1)
	u2.efficient = true
	var s5 := _new_state(10, 3)
	s5.human_faction = RUS
	var o2 := Objective.new(1, 4, 1, 2)
	o2.controller = GER
	s5.objectives = [o2]
	s5.units[u2.id] = u2
	_check(FlipBot.should_hold_objective(s5, GER, u2),
		"l'unica unità su un obiettivo controllato non lo abbandona")


func _test_flipbot_fire() -> void:
	print("· FlipBot: scelta del Fuoco (massima FP, bersaglio a morale minimo)")
	var s := _new_state(8, 3)
	s.human_faction = RUS  # bot = Tedesco
	var sh := _mk("g1", GER, SQUAD, RIFLE, 0, 1, 6, 7, 6)
	s.units[sh.id] = sh
	# Due bersagli russi in gittata e LOS: uno a morale basso, uno alto.
	var lo := _mk("r1", RUS, SQUAD, RIFLE, 3, 1, 5, 5, 6)   # morale 5
	var hi := _mk("r2", RUS, SQUAD, RIFLE, 2, 1, 5, 9, 6)   # morale 9
	s.units[lo.id] = lo
	s.units[hi.id] = hi
	var f := FlipBot.best_fire(s, GER)
	_check(not f.is_empty(), "il bot trova un fuoco utile")
	_check(String(f.get("attacker_id", "")) == "g1", "attiva il tiratore disponibile")
	_check(int(f.get("q", -1)) == 3 and int(f.get("r", -1)) == 1,
		"bersaglia l'esagono col morale efficace più basso (r1, mor 5)")

	# Minimum Firepower: tiratore troppo debole per un bersaglio coriaceo → niente.
	var s2 := _new_state(8, 3)
	s2.human_faction = RUS
	var weak := _mk("g9", GER, SQUAD, RIFLE, 0, 1, 2, 7, 6)  # FP 2
	s2.units[weak.id] = weak
	var tough := _mk("r9", RUS, SQUAD, RIFLE, 3, 1, 5, 9, 6)  # morale 9
	s2.units[tough.id] = tough
	_check(FlipBot.best_fire(s2, GER).is_empty(),
		"FP 2 contro difesa 9: sotto il minimo → nessun fuoco")


func _test_flipbot_opfire() -> void:
	print("· FlipBot: Fuoco di Opportunità (gruppo a massima FP, non individuale)")
	var s := _new_state(8, 3)
	s.human_faction = RUS  # il bot tedesco difende; il russo (umano) muove
	var mv := _mk("mv", RUS, SQUAD, RIFLE, 4, 0, 5, 5, 6)  # mover, morale 5
	s.units[mv.id] = mv
	# Tiratore solitario con FP individuale alta (gruppo = 6).
	var solo := _mk("g1", GER, SQUAD, RIFLE, 0, 0, 6, 7, 6)
	s.units[solo.id] = solo
	# Tre squadre co-locate a FP individuale minore ma totale maggiore (5 + 2 = 7).
	var a := _mk("g2", GER, SQUAD, RIFLE, 2, 0, 5, 7, 6)
	var b := _mk("g3", GER, SQUAD, RIFLE, 2, 0, 5, 7, 6)
	var c := _mk("g4", GER, SQUAD, RIFLE, 2, 0, 5, 7, 6)
	s.units[a.id] = a
	s.units[b.id] = b
	s.units[c.id] = c
	var sh := FlipBot.best_op_fire(s, mv, GER)
	_check(sh != null, "il bot reagisce al movimento")
	_check(sh != null and sh.q == 2,
		"sceglie il gruppo a FP totale massima (7), non il tiratore solitario (6)")

	# FP minima: un mover ad alto morale e un tiratore debole → niente reazione.
	var s2 := _new_state(8, 3)
	s2.human_faction = RUS
	var mv2 := _mk("mv", RUS, SQUAD, RIFLE, 4, 0, 5, 10, 6)  # morale 10
	s2.units[mv2.id] = mv2
	var weak := _mk("g9", GER, SQUAD, RIFLE, 3, 0, 2, 7, 6)  # gruppo FP 2
	s2.units[weak.id] = weak
	_check(FlipBot.best_op_fire(s2, mv2, GER) == null,
		"FP 2 contro difesa 10: sotto il minimo → nessuna reazione")


func _test_flipbot_advance() -> void:
	print("· FlipBot: Avanzata (conquista obiettivo, mischia con look-ahead)")
	# Obiettivo libero adiacente + nemico debole adiacente: conquista (priorità).
	var s := _new_state(6, 3)
	s.human_faction = RUS
	var u := _mk("g1", GER, SQUAD, RIFLE, 1, 1, 6, 7, 6)
	s.units[u.id] = u
	s.objectives = [Objective.new(1, 2, 1, 2)]  # neutro a (2,1)
	var weak := _mk("r1", RUS, SQUAD, RIFLE, 0, 1, 2, 5, 6)  # nemico debole a (0,1)
	s.units[weak.id] = weak
	var a := FlipBot.best_advance(s, GER)
	_check(int(a.get("q", -9)) == 2 and int(a.get("r", -9)) == 1,
		"conquista l'obiettivo libero adiacente (priorità massima)")
	_check(String(a.get("kind", "")) == "capture", "tipo avanzata = conquista")

	# Solo un nemico FORTE adiacente (deficit ≥2): niente avanzata.
	var s2 := _new_state(6, 3)
	s2.human_faction = RUS
	var u2 := _mk("g2", GER, SQUAD, RIFLE, 1, 1, 4, 7, 6)  # FP 4
	s2.units[u2.id] = u2
	var strong := _mk("r2", RUS, SQUAD, RIFLE, 2, 1, 8, 7, 6)  # FP 8 → margine -4
	s2.units[strong.id] = strong
	_check(FlipBot.best_advance(s2, GER).is_empty(),
		"non avanza in una mischia in deficit di 2+ (look-ahead)")

	# Nemico debole adiacente, nessun obiettivo: avanza in mischia favorevole.
	var s3 := _new_state(6, 3)
	s3.human_faction = RUS
	var u3 := _mk("g3", GER, SQUAD, RIFLE, 1, 1, 7, 7, 6)
	s3.units[u3.id] = u3
	var w3 := _mk("r3", RUS, SQUAD, RIFLE, 2, 1, 3, 7, 6)  # FP 3 → margine +4
	s3.units[w3.id] = w3
	var a3 := FlipBot.best_advance(s3, GER)
	_check(int(a3.get("q", -9)) == 2 and int(a3.get("r", -9)) == 1 \
			and String(a3.get("kind", "")) == "melee",
		"avanza nella mischia favorevole quando non ci sono obiettivi")


func _test_manual_setup() -> void:
	print("· Schieramento manuale: zona di setup, spostamento, «Auto» e «pronto»")
	var s := GameState.new()
	s.human_faction = GER
	if not ScenarioLoader.setup(s, 2):
		_check(false, "setup scenario 2 riuscito")
		return
	_check(not s.setup_zone.is_empty(), "la zona di schieramento del giocatore è popolata")
	var zone_keys := {}
	for h in s.setup_zone:
		zone_keys["%d,%d" % [h.x, h.y]] = true
	var all_in := true
	for u in s.units_of(GER):
		if u.is_man() and not zone_keys.has("%d,%d" % [u.q, u.r]):
			all_in = false
	_check(all_in, "le unità umane partono dentro la zona di schieramento")

	# Game in fase di setup: sposta una squadra in un esagono libero della zona.
	Game.state = s
	s.phase = Domain.Phase.PLAYER_SETUP
	var sq: Unit = null
	for u in s.units_of(GER):
		if u.type == Domain.UnitType.SQUAD:
			sq = u
			break
	_check(sq != null, "c'è una squadra umana da schierare")
	if sq != null:
		var dest := Vector2i(-1, -1)
		for h in s.setup_zone:
			if (h.x != sq.q or h.y != sq.r) \
					and s.soldier_icons_at(h.x, h.y) + sq.soldier_icons() <= 7:
				dest = h
				break
		_check(dest.x >= 0, "esiste un esagono di destinazione nella zona")
		if dest.x >= 0:
			Game.select_unit(sq.id)
			Game.click_hex(dest.x, dest.y)
			_check(sq.q == dest.x and sq.r == dest.y,
				"la squadra selezionata si sposta nell'esagono cliccato")
		# Spostamento fuori zona: rifiutato (la posizione non cambia).
		var outside := Vector2i(-1, -1)
		for q in s.map_cols:
			for r in s.map_rows:
				if not zone_keys.has("%d,%d" % [q, r]):
					outside = Vector2i(q, r)
					break
			if outside.x >= 0:
				break
		if outside.x >= 0:
			var pq := sq.q
			var pr := sq.r
			Game.select_unit(sq.id)
			Game.click_hex(outside.x, outside.y)
			_check(sq.q == pq and sq.r == pr, "uno spostamento fuori dalla zona è rifiutato")

	# «Auto»: ripiazza le unità, tutte ancora nella zona.
	Game.auto_setup()
	var still_in := true
	for u in s.units_of(GER):
		if u.is_man() and not zone_keys.has("%d,%d" % [u.q, u.r]):
			still_in = false
	_check(still_in, "dopo «Auto» le unità restano nella zona di schieramento")

	# «Schieramento pronto»: passa al turno del giocatore e svuota la zona.
	Game.finish_setup()
	_check(s.phase == Domain.Phase.PLAYER_TURN,
		"«Schieramento pronto» avvia il turno del giocatore")
	_check(s.setup_zone.is_empty(), "la zona di setup viene svuotata all'avvio del gioco")


func _test_setup_zones() -> void:
	print("· Setup: zone fedeli dalle schede (setup_zones.json) hanno priorità")
	# Scenario 3: gli Alleati sono ancorati a N5 (assente nel catalogo, presente in
	# setup_zones) → tutte le loro unità devono stare in/adiacenti a N5.
	var s := GameState.new()
	if not ScenarioLoader.setup(s, 3):
		_check(false, "setup scenario 3 riuscito")
		return
	var anchor := Domain.label_to_qr("N5")
	var n := 0
	var all_near := true
	for u in s.units.values():
		if u.faction == RUS and u.is_man():
			n += 1
			if HexGrid.distance(u.q, u.r, anchor.x, anchor.y) > 1:
				all_near = false
	_check(n > 0, "lo scenario 3 ha unità alleate da verificare")
	_check(all_near, "le unità alleate sono in/adiacenti all'ancora N5")


func _test_initial_fortifications() -> void:
	print("· Setup: fortificazioni iniziali del difensore (trincee/filo/mine/bunker)")
	# Categoria FORT: prima Wire/Mines/Bunker erano ignorate, Trench era una buca.
	_check(UnitChart.category("Wire") == UnitChart.Cat.FORT, "Wire è una fortificazione")
	_check(UnitChart.fort_type("Trench") == Domain.Fort.TRENCH, "Trench → Trincea")
	_check(UnitChart.fort_type("Mines") == Domain.Fort.MINES, "Mines → Mine")
	_check(UnitChart.fort_type("Bunker Complex") == Domain.Fort.BUNKER, "Bunker Complex → Bunker")
	_check(UnitChart.category("Foxholes") == UnitChart.Cat.FOXHOLE, "Foxholes resta una buca")
	# Scenario 11 «Hold the Line»: Filo + Mine (Asse) + Bunker (Alleati).
	var s := GameState.new()
	if not ScenarioLoader.setup(s, 11):
		_check(false, "setup scenario 11 riuscito")
		return
	var kinds := {}
	for hd in s.hexes.values():
		if hd.fortification != Domain.Fort.NONE:
			kinds[hd.fortification] = int(kinds.get(hd.fortification, 0)) + 1
	_check(int(kinds.get(Domain.Fort.WIRE, 0)) > 0, "ci sono esagoni con Filo spinato")
	_check(int(kinds.get(Domain.Fort.MINES, 0)) > 0, "ci sono esagoni con Mine")
	_check(int(kinds.get(Domain.Fort.BUNKER, 0)) > 0, "c'è almeno un Bunker")


func _test_fire_command_group() -> void:
	print("· Fuoco: il leader estende il gruppo al suo raggio di comando (3.3.1.2)")
	var s := _new_state(8, 3)
	s.human_faction = GER
	# Comando e gittate enormi: l'inclusione dipende solo da co-locazione/comando.
	s.units["L"] = _mk("L", GER, LEADER, ELITE, 1, 1, 1, 8, 99, 99)
	s.units["A"] = _mk("A", GER, SQUAD, RIFLE, 0, 1, 6, 7, 99)
	s.units["B"] = _mk("B", GER, SQUAD, RIFLE, 2, 1, 6, 7, 99)  # non co-locata con A
	s.units["e"] = _mk("e", RUS, SQUAD, RIFLE, 6, 1, 5, 7)
	var ids: Array = []
	for g in Combat.fire_group(s.units["A"], 6, 1, s):
		ids.append(g.id)
	_check(ids.has("A"), "il pezzo che spara fa parte del gruppo")
	_check(ids.has("B"), "il leader aggiunge una squadra non co-locata ma in comando")


func _test_fire_ready() -> void:
	print("· Fuoco: fire_ready elenca solo le unità con un bersaglio valido")
	var s := _new_state(8, 3)
	s.human_faction = GER
	s.units["A"] = _mk("A", GER, SQUAD, RIFLE, 0, 1, 6, 7, 99)  # gittata 99 → colpisce
	s.units["F"] = _mk("F", GER, SQUAD, RIFLE, 0, 0, 6, 7, 1)   # gittata 1 → non arriva
	s.units["e"] = _mk("e", RUS, SQUAD, RIFLE, 6, 1, 5, 7)
	Game.state = s
	Game._compute_fire_ready()
	_check(s.fire_ready_ids.has("A"), "una squadra con bersaglio è pronta a sparare")
	_check(not s.fire_ready_ids.has("F"), "una squadra senza bersaglio non è pronta")


func _test_scenario_rules() -> void:
	print("· Regole scenario: special_rules.json caricato e mostrabile (24 scenari)")
	_check(not ScenarioRules.title(1).is_empty(), "lo scenario 1 ha un titolo")
	_check(not ScenarioRules.rules(1).is_empty(), "lo scenario 1 ha regole speciali")
	_check(not ScenarioRules.setup_note(1).is_empty(), "lo scenario 1 ha la nota di setup")
	var bb := ScenarioRules.as_bbcode(1)
	_check(bb.contains("Schieramento") and bb.contains("Regole speciali"),
		"as_bbcode produce le sezioni Schieramento e Regole speciali")
	var missing := 0
	for n in range(1, 25):
		if ScenarioRules.entry(n).is_empty():
			missing += 1
	_check(missing == 0, "tutti e 24 gli scenari hanno una voce di regole")


func _test_order_feasible() -> void:
	print("· Badge: order_feasible riflette ciò che è davvero possibile ora")
	var s := _new_state(8, 3)
	s.human_faction = GER
	Game.state = s
	# Mappa vuota: solo Passa è possibile.
	_check(Game.order_feasible(Domain.OrderType.PASS), "Passa è sempre possibile")
	_check(not Game.order_feasible(Domain.OrderType.MOVE), "senza unità la Mossa non è possibile")
	_check(not Game.order_feasible(Domain.OrderType.FIRE), "senza bersagli il Fuoco non è possibile")
	_check(not Game.order_feasible(Domain.OrderType.ROUT), "senza unità rotte la Rotta non è possibile")
	# Una squadra mobile → Mossa e Avanzata possibili.
	var sq := _mk("sq", GER, SQUAD, RIFLE, 1, 1, 5, 7, 9)  # gittata 9
	s.units["sq"] = sq
	_check(Game.order_feasible(Domain.OrderType.MOVE), "con una squadra mobile la Mossa è possibile")
	_check(Game.order_feasible(Domain.OrderType.ADVANCE), "con una squadra l'Avanzata è possibile")
	_check(not Game.order_feasible(Domain.OrderType.FIRE), "ancora nessun nemico → Fuoco no")
	# Nemico in gittata e LOS → Fuoco possibile.
	s.units["e"] = _mk("e", RUS, SQUAD, RIFLE, 4, 1, 5, 7)
	_check(Game.order_feasible(Domain.OrderType.FIRE), "con un nemico in gittata il Fuoco è possibile")
	# Unità rotta → Recupero e Rotta possibili (e niente Mossa/Fuoco con quella sola).
	sq.break_unit()
	_check(Game.order_feasible(Domain.OrderType.RECOVER), "con un'unità rotta il Recupero è possibile")
	_check(Game.order_feasible(Domain.OrderType.ROUT), "con un'unità rotta la Rotta è possibile")
	_check(not Game.order_feasible(Domain.OrderType.MOVE), "un'unità rotta non può muovere")


func _weapon(id: String, faction: int, q: int, r: int) -> Unit:
	var u := Unit.new(id, faction, Domain.UnitType.WEAPON, Domain.UnitClass.MG, "Light MG")
	u.q = q
	u.r = r
	return u


func _test_initial_carriers_relocate() -> void:
	print("· Setup armi (11.2): l'arma orfana viene spostata sull'uomo libero e affidata")
	# Arma schierata in un esagono vuoto, squadra lontana: deve essere ricollocata.
	var s := _new_state(8, 3)
	s.units["sq"] = _mk("sq", GER, SQUAD, RIFLE, 1, 1, 5, 7)
	var w := _weapon("w", GER, 5, 1)
	s.units["w"] = w
	Game._assign_initial_carriers(s)
	_check(w.carrier_id == "sq", "l'arma orfana è affidata alla squadra")
	_check(w.q == 1 and w.r == 1, "l'arma orfana è spostata sull'esagono della squadra")
	# Arma già co-locata con un uomo: resta dov'è.
	var s2 := _new_state(8, 3)
	s2.units["sq2"] = _mk("sq2", GER, SQUAD, RIFLE, 2, 1, 5, 7)
	var w2 := _weapon("w2", GER, 2, 1)
	s2.units["w2"] = w2
	Game._assign_initial_carriers(s2)
	_check(w2.carrier_id == "sq2" and w2.q == 2 and w2.r == 1,
		"l'arma co-locata resta col suo portatore")
	# Si preferisce una squadra a un leader (il leader resta libero di comandare).
	var s3 := _new_state(8, 3)
	s3.units["ld"] = _mk("ld", GER, LEADER, ELITE, 3, 1, 1, 8)
	s3.units["sq3"] = _mk("sq3", GER, SQUAD, RIFLE, 3, 1, 5, 7)
	var w3 := _weapon("w3", GER, 3, 1)
	s3.units["w3"] = w3
	Game._assign_initial_carriers(s3)
	_check(w3.carrier_id == "sq3", "a parità di esagono l'arma va alla squadra, non al leader")


func _test_scenario1_no_orphan_weapons() -> void:
	print("· Scenario 1: dopo il setup nessun'arma resta «a terra»")
	var s := GameState.new()
	Scenario1.setup(s)
	Game._assign_initial_carriers(s)
	var orphans := 0
	var weapons := 0
	for u in s.units.values():
		if not u.is_weapon():
			continue
		weapons += 1
		if u.carrier_id == "":
			orphans += 1
		else:
			var c := s.unit_by_id(u.carrier_id)
			_check(c != null and c.q == u.q and c.r == u.r,
				"%s è co-locata col portatore" % u.unit_name)
	_check(weapons > 0, "lo scenario 1 ha delle armi da verificare")
	_check(orphans == 0, "nessun'arma senza portatore (niente anelli gialli al via)")


func _test_loader_weapons_with_squads() -> void:
	print("· Loader generico: le armi sono schierate negli esagoni delle squadre")
	var s := GameState.new()
	if not ScenarioLoader.setup(s, 2):
		_check(false, "ScenarioLoader.setup(2) riuscito")
		return
	var weapons := 0
	for u in s.units.values():
		if not u.is_weapon():
			continue
		weapons += 1
		var has_man := false
		for m in s.men_at(u.q, u.r):
			if m.faction == u.faction:
				has_man = true
				break
		_check(has_man, "%s schierata in un esagono con una squadra amica" % u.unit_name)
	_check(weapons > 0, "lo scenario 2 ha delle armi da verificare")


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

	# Mimetizzazione (A29): la carta arma UNA sola unità (one-shot), non tutte.
	var sc := _new_state()
	var cu1 := _mk("cu1", RUS, SQUAD, RIFLE, 0, 0, 5, 7)
	var cu2 := _mk("cu2", RUS, SQUAD, RIFLE, 1, 0, 5, 7)
	sc.units[cu1.id] = cu1
	sc.units[cu2.id] = cu2
	sc.selected_unit_id = ""
	Actions.play(sc, _act("MIMETIZZAZIONE"), RUS)
	_check((1 if cu1.concealed else 0) + (1 if cu2.concealed else 0) == 1,
		"MIMETIZZAZIONE arma UNA sola unità (one-shot), non tutte")

	# A29 effetto: riduce il totale d'attacco del valore della Copertura.
	# Bersaglio nel bosco (cover 2), morale 7. Attacco FP6 + dadi(5+5=10) = 16.
	# Senza A29: difesa 7+2+ (3+3=6) = 15 → 16>15 colpisce. Con A29: 15+2 = 17 → no.
	var sn := _new_state()
	sn.hex_at(0, 1).terrain = Domain.TerrainType.WOODS
	var an := _mk("g", GER, SQUAD, RIFLE, 0, 0, 6, 7)
	var dn := _mk("r", RUS, SQUAD, RIFLE, 0, 1, 5, 7)
	sn.units[an.id] = an
	sn.units[dn.id] = dn
	var r0 := Combat.resolve_fire(an, 0, 1, sn, Vector2i(5, 5), Vector2i(3, 3))
	_check(r0.broken.has("r"), "senza Mimetizzazione (att 16 vs dif 15) il difensore si rompe")
	# Con A29 armata: stesso attacco, nessun effetto, e mimetizzazione consumata.
	var sm := _new_state()
	sm.hex_at(0, 1).terrain = Domain.TerrainType.WOODS
	var am := _mk("g2", GER, SQUAD, RIFLE, 0, 0, 6, 7)
	var dm := _mk("r2", RUS, SQUAD, RIFLE, 0, 1, 5, 7)
	sm.units[am.id] = am
	sm.units[dm.id] = dm
	dm.concealed = true
	var r1 := Combat.resolve_fire(am, 0, 1, sm, Vector2i(5, 5), Vector2i(3, 3))
	_check(r1.broken.is_empty(), "con A29 (+Copertura) lo stesso attacco non ha effetto")
	_check(not dm.concealed, "la Mimetizzazione A29 è consumata (one-shot)")

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
	_check(UnitChart.category("Radio 105mm") == UnitChart.Cat.WEAPON, "Radio → arma (abilita O18)")
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
