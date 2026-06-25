## Verifica headless che Main.tscn si istanzi senza errori (percorsi @onready,
## struttura della HUD) e che la logica di zoom/pan della mappa 2D sia corretta.
## Stampa SCENE_RESULT: PASS/FAIL.
extends SceneTree

var _ok := true


func _fail(msg: String) -> void:
	print("  [NO] ", msg)
	_ok = false


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/Main.tscn")
	if scene == null:
		print("SCENE_RESULT: FAIL (Main.tscn non caricata)")
		quit(1)
		return
	var inst: Node = scene.instantiate()
	if inst == null:
		print("SCENE_RESULT: FAIL (instantiate ha restituito null)")
		quit(1)
		return
	get_root().add_child(inst)

	# 1) Nodi chiave della HUD ai percorsi attesi.
	for path in [
		"Sidebar/SideVBox/LogList",
		"Sidebar/SideVBox/SideHeader/SideToggleBtn",
		"Sidebar/SideVBox/Tools/View3DBtn",
		"Sidebar/SideVBox/Tools/LosBtn",
		"Sidebar/SideVBox/Tools/HelpBtn",
		"Sidebar/SideVBox/InfoPanel/InfoMargin/InfoLabel",
		"TopBar/Bar/HBox/PhaseLabel",
		"TopBar/Bar/Hint",
	]:
		if inst.get_node_or_null(path) == null:
			_fail("nodo mancante: " + path)

	# 2) Zoom & pan della mappa 2D.
	_check_view(inst.get_node_or_null("HexMap"))

	print("SCENE_RESULT: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _check_view(map: Node) -> void:
	if map == null:
		_fail("HexMap assente")
		return
	# Le texture compresse (.ctex) non si caricano sotto il renderer "dummy"
	# headless; iniettiamo una texture semplice per esercitare la matematica di
	# inquadratura/zoom in modo deterministico (in gioco la mappa reale si carica).
	var img := Image.create(200, 150, false, Image.FORMAT_RGB8)
	map._map_texture = ImageTexture.create_from_image(img)
	map._view_custom = false
	map._update_view()
	var fit_scale: float = map._fit_scale
	if fit_scale <= 0.0:
		_fail("scala di auto-fit non valida")
		return
	if absf(map.view_scale - fit_scale) > 0.01:
		_fail("dopo l'auto-fit view_scale != scala di fit")

	# Lo zoom centrato mantiene fermo il punto-immagine sotto il cursore.
	var cursor := Vector2(120, 90)
	var img_before: Vector2 = (cursor - map.view_origin) / map.view_scale
	map._zoom_at(cursor, 1.15)
	var img_after: Vector2 = (cursor - map.view_origin) / map.view_scale
	if img_before.distance_to(img_after) > 0.01:
		_fail("lo zoom non mantiene fermo il punto sotto il cursore")
	if map.view_scale <= fit_scale:
		_fail("lo zoom-in non ha aumentato la scala")
	if not map._view_custom:
		_fail("lo zoom non ha marcato la vista come personalizzata")

	# Limiti di zoom rispetto all'auto-fit.
	for i in 40:
		map._zoom_at(cursor, 2.0)
	if map.view_scale > fit_scale * 6.0 + 0.001:
		_fail("lo zoom-in supera il limite massimo")
	for i in 40:
		map._zoom_at(cursor, 0.5)
	if map.view_scale < fit_scale * 0.5 - 0.001:
		_fail("lo zoom-out supera il limite minimo")

	# Pan: spostare l'origine sposta la mappa di pari quantità.
	var o0: Vector2 = map.view_origin
	map.view_origin += Vector2(50, -30)
	if map.view_origin.distance_to(o0 + Vector2(50, -30)) > 0.01:
		_fail("il pan non sposta l'origine come atteso")

	# reset_view reinquadra (torna all'auto-fit, vista non più personalizzata).
	map.reset_view()
	if map._view_custom:
		_fail("reset_view non ha azzerato la personalizzazione")
	if absf(map.view_scale - fit_scale) > 0.01:
		_fail("reset_view non ha ripristinato la scala di auto-fit")
