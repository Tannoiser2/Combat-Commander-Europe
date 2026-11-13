extends Node
## Giro automatico dell'interfaccia: gioca una partita pilotando il lato umano
## con un Bot e salva una schermata per ogni TIPO di decisione incontrata (e
## una dell'avversario in azione). Serve a controllare a occhio menu e pannelli
## a varie risoluzioni.
## Uso: godot --path godot --resolution 1280x800 res://tests/UiTour.tscn -- <cartella> [scenario] [max_decisioni] [3d]

var out_dir := "user://tour"
var seen := {}
var helper: Bot
var steps := 0
var max_steps := 400
var want_3d := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var scen := int(args[1]) if args.size() > 1 else 1
	if args.size() > 2:
		max_steps = int(args[2])
	want_3d = args.size() > 3
	DirAccess.make_dir_recursive_absolute(out_dir)
	Game.speed = 30.0
	Game.start_new_game(Flow.AX, scen, 2, Game.Mode.VS_AI, 4242)
	helper = Bot.new(Game.flow, 2, 99)
	var scene: PackedScene = load("res://scenes/Partita.tscn")
	var p := scene.instantiate()
	add_child(p)
	await get_tree().create_timer(0.6).timeout
	if want_3d:
		p._toggle_3d()
		await get_tree().create_timer(2.5).timeout
	await _shot("00_inizio")
	_loop()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])


func _loop() -> void:
	var foe_shot := false
	while steps < max_steps and not Game.flow.over:
		await get_tree().create_timer(0.05).timeout
		var p := Game.pending()
		if p.is_empty():
			if not foe_shot and not Game.flow.pending.is_empty() and steps > 3:
				foe_shot = true
				await _shot("01_avversario")
			continue
		var kind := String(p["kind"])
		if not seen.has(kind):
			seen[kind] = true
			await get_tree().create_timer(0.25).timeout
			await _shot("%02d_%s" % [seen.size() + 1, kind])
		Game.choose(helper.pick())
		steps += 1
	if Game.flow.over:
		await get_tree().create_timer(1.0).timeout
		await _shot("99_fine")
	print("TOUR_RESULT: PASS (%d decisioni, tipi visti: %s)" % [steps, ", ".join(seen.keys())])
	get_tree().quit()
