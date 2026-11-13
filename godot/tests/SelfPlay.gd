extends Node
## Partite automatiche IA contro IA sul nuovo motore: verifica che ogni scenario
## arrivi a fine partita senza errori, blocchi o mosse impossibili.
## Uso: godot --headless --path godot res://tests/SelfPlay.tscn -- [scenari] [partite] [verbose]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var scen: Array = []
	if args.size() > 0 and args[0] != "all":
		for x in String(args[0]).split(","):
			scen.append(int(x))
	else:
		for i in range(1, 25):
			scen.append(i)
	var games := int(args[1]) if args.size() > 1 else 1
	var verbose := args.size() > 2
	var fails := 0
	var total := 0
	for n in scen:
		for g in games:
			total += 1
			var res := _play(n, 1000 + n * 17 + g, verbose)
			print("Scenario %2d partita %d: %s" % [n, g + 1, res["line"]])
			if not res["ok"]:
				fails += 1
	print("SELFPLAY_RESULT: %s (%d partite, %d fallite)" % ["PASS" if fails == 0 else "FAIL", total, fails])
	get_tree().quit(0 if fails == 0 else 1)


func _play(n: int, sd: int, verbose: bool) -> Dictionary:
	var flow := Flow.new_game(n, Flow.AX, sd)
	var bots := { Flow.AX: Bot.new(flow, 2, sd + 1), Flow.AL: Bot.new(flow, 2, sd + 2) }
	flow.start()
	var steps := 0
	var kinds := {}
	var last_turn := 0
	while not flow.over and steps < 60000:
		if flow.pending.is_empty():
			return { "ok": false, "line": "BLOCCO: nessuna decisione in sospeso al passo %d (turno %d)" % [steps, flow.turn_count] }
		var p := flow.pending
		kinds[p["kind"]] = int(kinds.get(p["kind"], 0)) + 1
		var i: int = bots[p["who"]].pick()
		if i < 0 or i >= (p["options"] as Array).size():
			return { "ok": false, "line": "SCELTA NON VALIDA %d per %s" % [i, p["kind"]] }
		flow.answer(i)
		steps += 1
		if verbose:
			for ev in flow.events:
				print("   ", String(ev["text"]))
		flow.events.clear()
		if flow.turn_count != last_turn:
			last_turn = flow.turn_count
	if not flow.over:
		return { "ok": false, "line": "NON FINITA dopo %d decisioni (turno %d, tempo %d)" % [steps, flow.turn_count, flow.s.time_marker] }
	return { "ok": true, "line": "vincono i %s in %d turni, tempo %d, PV %+d, perdite %d/%d, %d decisioni — %s" % [
		flow.side_name(flow.winner), flow.turn_count, flow.s.time_marker, flow.s.vp_tracker,
		int(flow.s.casualties[Flow.AX]), int(flow.s.casualties[Flow.AL]), steps, flow.end_reason] }
