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
	_test_recover()
	_test_melee_winner_and_losses()
	_test_rout_retreat()
	_test_rout_trapped()
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

	var r1 := Combat.resolve_fire(atk, 0, 1, s, _rng)
	_check(r1.broken.has("rus"), "unità efficiente colpita si rompe")
	_check(s.units.has("rus"), "unità rotta resta in gioco")
	_check(s.units.has("rus") and not s.units["rus"].efficient, "unità marcata come rotta")

	var r2 := Combat.resolve_fire(atk, 0, 1, s, _rng)
	_check(r2.eliminated.has("rus"), "unità già rotta colpita viene eliminata")
	_check(not s.units.has("rus"), "unità eliminata rimossa dallo stato")


func _test_fire_no_effect() -> void:
	print("· Fuoco: nessun effetto sotto morale")
	var s := _new_state()
	var atk := _mk("ger", GER, SQUAD, RIFLE, 0, 0, 1, 7)
	var tgt := _mk("rus", RUS, SQUAD, RIFLE, 0, 1, 5, 99)  # morale irraggiungibile
	s.units[atk.id] = atk
	s.units[tgt.id] = tgt
	var r := Combat.resolve_fire(atk, 0, 1, s, _rng)
	_check(r.broken.is_empty() and r.eliminated.is_empty(), "punteggio < morale → nessun effetto")
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


func _test_recover() -> void:
	print("· Recupero (tiro di morale)")
	var s := _new_state()
	var u := _mk("rus", RUS, SQUAD, RIFLE, 2, 2, 5, 12)  # morale 12 → 2d6 sempre ≤ 12
	u.break_unit()
	s.units[u.id] = u
	var r := Rules.try_recover(s, u, _rng)
	_check(r["success"] and u.efficient, "morale 12 → recupero sempre riuscito")

	var u2 := _mk("rus2", RUS, SQUAD, RIFLE, 4, 4, 5, 1)  # morale 1 → 2d6 mai ≤ 1
	u2.break_unit()
	s.units[u2.id] = u2
	var r2 := Rules.try_recover(s, u2, _rng)
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
	var mr := Rules.resolve_melee(s, attackers, defenders, RUS, _rng)
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
	var r := Rules.rout_unit(s, u, _rng)
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
	var r := Rules.rout_unit(s, u, _rng)
	_check(r["eliminated"], "intrappolata + nemico adiacente → eliminata")
	_check(not s.units.has("ger"), "unità intrappolata rimossa")


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("TEST_RESULT: PASS (%d controlli)" % _checks)
		get_tree().quit(0)
	else:
		print("TEST_RESULT: FAIL (%d/%d falliti)" % [_failures.size(), _checks])
		for f in _failures:
			print("  - ", f)
		get_tree().quit(1)
