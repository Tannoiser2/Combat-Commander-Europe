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

	# Sparare rivela il TIRATORE: una unità mimetizzata che fa fuoco si scopre.
	var s3b := _new_state()
	var hidden_shooter := _mk("ger-h", GER, SQUAD, RIFLE, 0, 0, 5, 7)
	var foe := _mk("rus-f", RUS, SQUAD, RIFLE, 0, 1, 5, 7)
	s3b.units[hidden_shooter.id] = hidden_shooter
	s3b.units[foe.id] = foe
	Actions.play(s3b, _act("MIMETIZZAZIONE"), GER)
	_check(hidden_shooter.concealed, "la pedina è mimetizzata prima di sparare")
	Combat.resolve_fire(hidden_shooter, 0, 1, s3b, Vector2i(3, 3), Vector2i(2, 2))
	_check(not hidden_shooter.concealed, "sparare rivela il tiratore (perde la mimetizzazione)")

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
