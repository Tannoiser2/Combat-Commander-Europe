## Schermata iniziale: titolo, scelta scenario e fazione.
extends Control

@onready var play_ger: Button = $Center/VBox/Factions/PlayGerman
@onready var play_rus: Button = $Center/VBox/Factions/PlayRussian
@onready var scenario_label: Label = $Center/VBox/ScenarioLabel


func _ready() -> void:
	scenario_label.text = "Scenario 1 — %s" % Scenario1.SCENARIO_NAME
	play_ger.pressed.connect(_start.bind(Domain.Faction.GERMAN))
	play_rus.pressed.connect(_start.bind(Domain.Faction.RUSSIAN))


func _start(faction: int) -> void:
	Game.start_new_game(faction)
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
