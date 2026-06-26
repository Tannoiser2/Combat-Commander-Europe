## Verifica headless della costruzione delle pedine 3D: per ogni unità il numero
## di figure (squadra 4, team 2, leader 1, arma 1), il badge numerico sopra la
## pila e l'orientamento (yaw) verso la direzione di marcia. Stampa
## PIECES_RESULT: PASS/FAIL. Va eseguito come scena (root Node), così gli
## autoload (Game, Domain) sono attivi.
extends Node

var _map: Node3D = null
var _frames := 0
var _ok := true


func _fail(msg: String) -> void:
	print("  [NO] ", msg)
	_ok = false


func _ready() -> void:
	Game.start_new_game(Domain.Faction.GERMAN, 1)
	_map = load("res://scenes/Map3D.tscn").instantiate()
	_map.active = true
	add_child(_map)


func _process(_dt: float) -> void:
	_frames += 1
	if _frames < 4:
		return
	_run_checks()
	print("PIECES_RESULT: ", "PASS" if _ok else "FAIL")
	get_tree().quit(0 if _ok else 1)


func _expected_figs(u) -> int:
	return maxi(1, u.soldier_icons())


func _run_checks() -> void:
	var s = Game.state
	if s == null:
		_fail("nessuno stato di gioco")
		return
	var pieces: Array = _map._pieces
	if pieces.is_empty():
		_fail("nessuna pedina costruita")
		return

	var by_id := {}
	for p in pieces:
		by_id[p["id"]] = p["node"]

	var checked_squad := false
	var checked_leader := false
	for u in s.units.values():
		if not by_id.has(u.id):
			continue  # arma trasportata o non in mappa: salta
		var node = by_id[u.id]
		# Conta le figure (Node3D interni) e il badge (Sprite3D).
		var figs := 0
		var badges := 0
		for c in node.get_children():
			if c is Sprite3D:
				badges += 1
			elif c is Node3D:
				figs += 1
		var want := _expected_figs(u)
		if node is Node3D and figs > 0:
			if figs != want:
				_fail("unità %s (tipo %d): %d figure invece di %d" % [u.id, u.type, figs, want])
			if badges < 1:
				_fail("unità %s: badge mancante sopra la pila" % u.id)
			if u.type == Domain.UnitType.SQUAD:
				checked_squad = true
			if u.type == Domain.UnitType.LEADER:
				checked_leader = true

	if not checked_squad:
		_fail("nessuna squadra verificata (figure 4)")
	if not checked_leader:
		print("  [..] nessun leader presente in scenario 1 (ok)")

	# Badge: i token sono coerenti col tipo (la texture è renderizzata in modo
	# asincrono via SubViewport e non è disponibile in headless; qui si verifica
	# la logica dei valori). Lo Sprite3D del badge è già contato sopra.
	var squad = _first_of_type(s, Domain.UnitType.SQUAD)
	if squad != null and _map._badge_tokens(squad).size() != 4:
		_fail("badge squadra: attesi 4 valori (PdF/Gittata/Mov/Morale)")
	var leader = _first_of_type(s, Domain.UnitType.LEADER)
	if leader != null and _map._badge_tokens(leader).is_empty():
		_fail("badge leader: nessun valore (manca il Comando)")

	# Orientamento: dopo uno spostamento, lo yaw verso il nuovo esagono è memorizzato.
	if squad != null:
		_map._last_unit_pos[squad.id] = Vector2i(squad.q, squad.r)
		_map._unit_heading.erase(squad.id)
		_map._on_unit_moved(squad.id, squad.q + 1, squad.r)
		if not _map._unit_heading.has(squad.id):
			_fail("yaw di marcia non memorizzato dopo lo spostamento")

	# Selezione del modello per nazionalità: ogni nazione usa i propri modelli
	# (senza tinta segnaposto). Verifica su squadre e leader sintetici.
	for nat in [["Tedeschi", "de"], ["Russi", "ru"], ["Americani", "us"]]:
		var sq := Unit.new("nat-sq-" + nat[0], Domain.Faction.RUSSIAN,
			Domain.UnitType.SQUAD, 0, "Test " + nat[0])
		sq.nation_art = nat[0]
		var pick = _map._figure_model(sq, 0)
		if pick["scene"] == null:
			_fail("nessun modello soldato per %s" % nat[0])
		elif pick["foreign"]:
			_fail("%s usa un modello di un'altra nazione (foreign)" % nat[0])
		elif not String(pick["scene"].resource_path).contains("soldier_" + nat[1]):
			_fail("%s: modello soldato sbagliato (%s)" % [nat[0], pick["scene"].resource_path])
		var ld := Unit.new("nat-ld-" + nat[0], Domain.Faction.RUSSIAN,
			Domain.UnitType.LEADER, 0, "Off " + nat[0])
		ld.nation_art = nat[0]
		var pick2 = _map._figure_model(ld, 0)
		if pick2["scene"] == null or not String(pick2["scene"].resource_path).contains("officer_" + nat[1]):
			_fail("%s: ufficiale sbagliato/mancante" % nat[0])

	# Modelli delle armi: ogni nazione+classe risolve a un modello esistente
	# (con i ripieghi). Verifica MG / mortaio / cannone per le 3 nazioni.
	for nat in ["Tedeschi", "Russi", "Americani"]:
		for kind in ["light_mg", "medium_mg", "heavy_mg", "fifty_mg", "mortar", "gun"]:
			var path: String = _map._weapon_model_path(nat, kind)
			if path == "" or not ResourceLoader.exists(path):
				_fail("arma non risolta: %s / %s -> '%s'" % [nat, kind, path])


func _first_of_type(s, t: int):
	for u in s.units.values():
		if u.type == t:
			return u
	return null
