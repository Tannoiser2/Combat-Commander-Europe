## Effetti sonori della partita (autoload).
##
## Si collega ai segnali di Game e riproduce i suoni del modulo VASSAL
## (`assets/sounds/`): fuoco (fucile/mitragliatrice secondo la potenza), Tempo!/
## Morte Subitanea, cecchino e fine partita. Un piccolo pool di player permette
## suoni sovrapposti. In headless il driver audio è fittizio: nessun suono ma
## nessun errore.
extends Node

const SOUNDS := {
	"rifle": "res://assets/sounds/RIFLE.wav",
	"mg": "res://assets/sounds/MACH_GUN.wav",
	"artillery": "res://assets/sounds/Artillery.wav",
	"time": "res://assets/sounds/time.wav",
	"morse": "res://assets/sounds/morse.wav",
	"reload": "res://assets/sounds/reload.wav",
	"deck": "res://assets/sounds/Deck Depleted.wav",
}

var enabled := true
var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for key in SOUNDS:
		var path: String = SOUNDS[key]
		if ResourceLoader.exists(path):
			_streams[key] = load(path)
	for _i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	# Eventi di gioco → suoni.
	Game.chronicle.connect(_on_event)
	Game.game_over.connect(_on_game_over)


## Riproduce il suono `key` su un player libero del pool (round-robin).
func play(key: String) -> void:
	if not enabled or not _streams.has(key) or _players.is_empty():
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[key]
	p.play()


func toggle_mute() -> bool:
	enabled = not enabled
	return enabled


# ─── Handler ──────────────────────────────────────────────────────────────────

func _on_event(ev: Dictionary) -> void:
	match String(ev.get("kind", "")):
		"fire":
			if String(ev.get("fx", "")) == "arty":
				play("artillery")
			elif String(ev.get("fx", "")) == "fire":
				var mg := false
				for id in ev.get("pieces", []):
					var u: Unit = Game.state.unit_by_id(String(id)) if Game.state != null else null
					if u != null and u.is_weapon():
						mg = true
						if u.ordnance:
							play("artillery")
							return
				play("mg" if mg else "rifle")
		"time":
			play("time")
		"fate":
			if String(ev.get("text", "")).contains("Cecchino"):
				play("rifle")


func _on_game_over(_winner: int) -> void:
	play("deck")
