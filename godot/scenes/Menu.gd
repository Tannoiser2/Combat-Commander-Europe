## Schermata iniziale: elenco dei 24 scenari + scelta della fazione.
extends Control

## Scenari giocabili. Lo scenario 1 è curato a mano; 2..24 usano il loader
## generico (catalogo + ordini di battaglia) con fazioni stand-in.
const IMPLEMENTED := {
	1: true, 2: true, 3: true, 4: true, 5: true, 6: true, 7: true, 8: true,
	9: true, 10: true, 11: true, 12: true, 13: true, 14: true, 15: true,
	16: true, 17: true, 18: true, 19: true, 20: true, 21: true, 22: true,
	23: true, 24: true,
}

@onready var list: VBoxContainer = $Scroll/List
@onready var faction_panel: Panel = $FactionPanel
@onready var scenario_label: Label = $FactionPanel/VBox/ScenarioLabel
@onready var play_ger: Button = $FactionPanel/VBox/Factions/PlayGerman
@onready var play_rus: Button = $FactionPanel/VBox/Factions/PlayRussian
@onready var back_btn: Button = $FactionPanel/VBox/BackBtn

var _selected_num: int = 0
var _scenarios: Array = []


func _ready() -> void:
	faction_panel.visible = false
	_scenarios = _load_scenarios()
	_build_list()
	play_ger.pressed.connect(_start.bind(Domain.Faction.GERMAN))
	play_rus.pressed.connect(_start.bind(Domain.Faction.RUSSIAN))
	back_btn.pressed.connect(_close_faction)
	# Pulsante editor mappe (in alto a destra)
	var ed := Button.new()
	ed.text = "✎ Editor mappe"
	ed.position = Vector2(-160, 12)
	ed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ed.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MapEditor.tscn"))
	add_child(ed)


func _load_scenarios() -> Array:
	var f := FileAccess.open("res://assets/scenari.json", FileAccess.READ)
	if f == null:
		return []
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return data if data is Array else []


func _build_list() -> void:
	for child in list.get_children():
		child.queue_free()
	for sc in _scenarios:
		var num := int(sc.get("numero", 0))
		var titolo: String = sc.get("titolo", "—")
		var luogo: String = sc.get("luogo", "")
		var data: String = sc.get("data", "")
		var playable: bool = IMPLEMENTED.get(num, false)

		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 46)
		var tag := "" if playable else "   [in arrivo]"
		btn.text = "%2d.  %s%s\n      %s — %s" % [num, titolo, tag, luogo, data]
		btn.disabled = not playable
		if playable:
			btn.pressed.connect(_select_scenario.bind(num, titolo))
		list.add_child(btn)


func _select_scenario(num: int, titolo: String) -> void:
	_selected_num = num
	scenario_label.text = "Scenario %d — %s" % [num, titolo]
	faction_panel.visible = true


func _close_faction() -> void:
	faction_panel.visible = false


func _start(faction: int) -> void:
	Game.start_new_game(faction, _selected_num)
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
