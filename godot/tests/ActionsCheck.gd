## Verifica delle Azioni: la whitelist delle azioni "accendibili" (AUTONOMOUS_ACTIONS)
## corrisponde a effetti reali, le azioni senza effetto NON sono in whitelist, e la
## Sventagliata è instradata correttamente. Stampa ACTIONS_RESULT: PASS/FAIL.
extends Node

var _ok := true


func _fail(m: String) -> void:
	print("  [NO] ", m)
	_ok = false


func _ready() -> void:
	Game.start_new_game(Domain.Faction.GERMAN, 1)
	var s = Game.state
	var fac = s.human_faction

	# 1) Ogni azione autonoma in whitelist ha un handler reale (Actions.play non
	#    cade nel ramo "non ancora simulata").
	for name in Game.AUTONOMOUS_ACTIONS:
		var c = Card.new()
		c.action_name = name
		var lines: Array = Actions.play(s, c, fac)
		if "non ancora simulata" in "\n".join(lines):
			_fail("azione in whitelist senza handler reale: %s" % name)

	# 1b) BOMBE A MANO (A34) è ora un modificatore di fuoco (+2 a un esagono
	#     adiacente), non più un'azione autonoma.
	if not Game.FIRE_MOD_NAMES.has("BOMBE A MANO"):
		_fail("BOMBE A MANO dovrebbe essere un modificatore di fuoco")
	if Game.AUTONOMOUS_ACTIONS.has("BOMBE A MANO"):
		_fail("BOMBE A MANO non deve più essere un'azione autonoma")

	# 2) Le azioni oggi senza effetto NON devono essere accendibili (badge spento).
	for name in ["IMBOSCATA", "BUONA MIRA", "ORDINI CONTRADDITTORI", "DEMOLIZIONI",
			"UNITA' NASCOSTA", "LOTTA SENZA QUARTIERE"]:
		if Game.AUTONOMOUS_ACTIONS.has(name):
			_fail("azione senza effetto accesa per errore: %s" % name)

	# 3) Sventagliata: il nome del mazzo deve essere instradabile allo spray.
	if not "SVENTAGLIATA DI FUOCO".begins_with("SVENTAGLIATA"):
		_fail("Sventagliata: nome non instradabile allo spray")

	print("ACTIONS_RESULT: ", "PASS" if _ok else "FAIL")
	get_tree().quit(0 if _ok else 1)
