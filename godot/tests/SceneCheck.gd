## Verifica headless che Main.tscn si istanzi senza errori (percorsi @onready,
## struttura della scena, costruzione sidebar). Stampa SCENE_RESULT: PASS/FAIL.
extends SceneTree


func _initialize() -> void:
	var ok := true
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
	# Un paio di nodi chiave devono esistere ai percorsi attesi.
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
			print("  [NO] nodo mancante: ", path)
			ok = false
	print("SCENE_RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
