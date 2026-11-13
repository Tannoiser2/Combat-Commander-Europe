## Una carta del Fato a schermo. Usa l'illustrazione italiana quando esiste
## (Tedeschi, Sovietici, Americani); per gli altri mazzi la disegna con lo
## stesso impianto: Ordine in alto, Azione, Evento, esagono casuale e dadi.
class_name CardView
extends Control

signal tapped(view: CardView)

var card: Card = null
var index: int = -1
var playable: bool = false
var selected: bool = false
var marked: bool = false        ## scelta per lo scarto
var face_down: bool = false
var _tex: Texture2D = null

const ORDER_IT := {
	Domain.OrderType.MOVE: "MOSSA", Domain.OrderType.FIRE: "FUOCO",
	Domain.OrderType.ADVANCE: "AVANZATA", Domain.OrderType.RECOVER: "RECUPERO",
	Domain.OrderType.ROUT: "RITIRATA", Domain.OrderType.PASS: "ORDINI CONTRADDITTORI",
	Domain.OrderType.ARTY: "RICHIESTA D'ARTIGLIERIA", Domain.OrderType.ARTY_DENIED: "ARTIGLIERIA NEGATA",
}
const ORDER_COL := {
	Domain.OrderType.MOVE: Color(0.25, 0.42, 0.25), Domain.OrderType.FIRE: Color(0.55, 0.20, 0.15),
	Domain.OrderType.ADVANCE: Color(0.50, 0.36, 0.14), Domain.OrderType.RECOVER: Color(0.20, 0.36, 0.50),
	Domain.OrderType.ROUT: Color(0.40, 0.25, 0.42), Domain.OrderType.PASS: Color(0.30, 0.30, 0.30),
	Domain.OrderType.ARTY: Color(0.45, 0.30, 0.18), Domain.OrderType.ARTY_DENIED: Color(0.32, 0.32, 0.24),
}


static func art_path(c: Card) -> String:
	var nat := String(c.id).split("-")[0]
	return "res://assets/cards_it/%s/%02d.webp" % [nat, c.number]


func setup(c: Card, i: int) -> void:
	card = c
	index = i
	_tex = null
	if c != null:
		var p := art_path(c)
		if ResourceLoader.exists(p):
			_tex = load(p)
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped.emit(self)
		accept_event()


func _line(t: String, y: float, sz: int, col: Color, bold: bool = true) -> void:
	var f := Tema.bold_font() if bold else Tema.body_font()
	var w := size.x - 12.0
	var lines := _wrap(t, f, sz, w)
	for i in lines.size():
		var tw := f.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		draw_string(f, Vector2((size.x - tw) * 0.5, y + i * sz * 1.05), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _wrap(t: String, f: Font, sz: int, w: float) -> Array:
	var out: Array = []
	var cur := ""
	for word in t.split(" "):
		var test := word if cur == "" else cur + " " + word
		if f.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > w and cur != "":
			out.append(cur)
			cur = word
		else:
			cur = test
	if cur != "":
		out.append(cur)
	return out


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if face_down or card == null:
		draw_rect(r, Color(0.16, 0.19, 0.14))
		draw_rect(r.grow(-5), Tema.EDGE, false, 2.0)
		_line("COMBAT", size.y * 0.42, int(size.x * 0.17), Tema.BRASS)
		_line("COMMANDER", size.y * 0.42 + size.x * 0.19, int(size.x * 0.13), Tema.BRASS)
		return
	if _tex != null:
		draw_texture_rect(_tex, r, false)
	else:
		var u := size.y / 385.0
		draw_rect(r, Color(0.13, 0.14, 0.11))
		var oc: Color = ORDER_COL.get(card.order, Color(0.3, 0.3, 0.3))
		draw_rect(Rect2(4, 4, size.x - 8, 96 * u), oc)
		_line("ORDINE", 26 * u, int(15 * u), Color(1, 1, 1, 0.7), false)
		_line(String(ORDER_IT.get(card.order, "?")), 56 * u, int(26 * u), Color(1, 1, 1))
		draw_rect(Rect2(4, 104 * u, size.x - 8, 92 * u), Color(0.22, 0.25, 0.18))
		_line("AZIONE", 124 * u, int(15 * u), Color(1, 1, 1, 0.6), false)
		_line(card.action_name if card.action_name != "" else "nessuna", 152 * u, int(22 * u), Tema.PAPER)
		draw_rect(Rect2(4, 200 * u, size.x - 8, 92 * u), Color(0.19, 0.18, 0.15))
		_line("EVENTO", 220 * u, int(15 * u), Color(1, 1, 1, 0.6), false)
		_line(card.event_name.to_upper(), 248 * u, int(20 * u), Tema.PAPER)
		draw_rect(Rect2(4, 296 * u, size.x - 8, 85 * u), Color(0.26, 0.23, 0.16))
		_line("%s     %d  +  %d" % [card.random_hex_label, card.dice_white, card.dice_red], 345 * u, int(30 * u), Color(1, 1, 1))
		var cons := ""
		match String(card.consequence):
			"time": cons = "TEMPO!"
			"sniper": cons = "CECCHINO!"
			"event": cons = "EVENTO!"
			"jam": cons = "INCEPPAMENTO!"
		if cons != "":
			_line(cons, 372 * u, int(15 * u), Color(1.0, 0.5, 0.35))
	if marked:
		draw_rect(r, Color(0.7, 0.1, 0.1, 0.45))
		_line("SCARTA", size.y * 0.5, int(size.x * 0.2), Color(1, 1, 1))
	if selected:
		draw_rect(r.grow(-1), Color(0.3, 0.85, 1.0), false, 5.0)
	elif playable:
		var p := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 220.0)
		draw_rect(r.grow(-1), Color(1.0, 0.82, 0.25, p), false, 4.0)
	else:
		draw_rect(r, Color(0, 0, 0, 0.38))
		draw_rect(r.grow(-1), Color(0, 0, 0, 0.8), false, 2.0)


func _process(_d: float) -> void:
	if playable and not selected and is_visible_in_tree():
		queue_redraw()
