## Tema grafico «carta da campo» (anni '40): verde oliva scuro, kaki e ottone,
## titoli a stencil e testi in un condensato ben leggibile.
class_name Tema
extends RefCounted

const BG := Color(0.086, 0.098, 0.078)
const PANEL := Color(0.145, 0.160, 0.125)
const PANEL_HI := Color(0.205, 0.225, 0.170)
const EDGE := Color(0.42, 0.40, 0.27)
const BRASS := Color(0.86, 0.72, 0.36)
const PAPER := Color(0.90, 0.87, 0.76)
const INK := Color(0.93, 0.91, 0.82)
const DIM := Color(0.66, 0.66, 0.56)
const RED := Color(0.80, 0.22, 0.16)
const AXIS := Color(0.55, 0.63, 0.66)
const ALLIES := Color(0.80, 0.60, 0.36)

static var _theme: Theme = null


static func title_font() -> Font:
	return load("res://assets/fonts/BlackOpsOne-Regular.ttf")

static func body_font() -> Font:
	return load("res://assets/fonts/BarlowCondensed-Medium.ttf")

static func bold_font() -> Font:
	return load("res://assets/fonts/BarlowCondensed-SemiBold.ttf")


static func box(bg: Color, border: Color, bw: int = 2, radius: int = 4, pad: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	return sb


static func side_color(f: int) -> Color:
	return AXIS if f == Flow.AX else ALLIES


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 18
	# Pulsanti
	t.set_stylebox("normal", "Button", box(PANEL_HI, EDGE, 2, 4, 8))
	t.set_stylebox("hover", "Button", box(PANEL_HI.lightened(0.12), BRASS, 2, 4, 8))
	t.set_stylebox("pressed", "Button", box(PANEL.darkened(0.2), BRASS, 2, 4, 8))
	t.set_stylebox("disabled", "Button", box(PANEL.darkened(0.1), EDGE.darkened(0.4), 2, 4, 8))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), BRASS, 2, 4, 8))
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_color("font_pressed_color", "Button", BRASS)
	t.set_color("font_disabled_color", "Button", DIM.darkened(0.3))
	t.set_font("font", "Button", bold_font())
	t.set_font_size("font_size", "Button", 18)
	for cls in ["OptionButton", "CheckButton", "CheckBox"]:
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			t.set_stylebox(st, cls, t.get_stylebox(st, "Button"))
		t.set_color("font_color", cls, INK)
		t.set_font("font", cls, bold_font())
	# Pannelli
	t.set_stylebox("panel", "PanelContainer", box(PANEL, EDGE, 2, 4, 8))
	t.set_stylebox("panel", "Panel", box(PANEL, EDGE, 2, 4, 8))
	t.set_stylebox("panel", "PopupPanel", box(PANEL, BRASS, 2, 4, 10))
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.05, 0.05, 0.04, 0.96), BRASS, 1, 3, 6))
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_font_size("font_size", "TooltipLabel", 16)
	# Testi
	t.set_color("font_color", "Label", INK)
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_font("normal_font", "RichTextLabel", body_font())
	t.set_font("bold_font", "RichTextLabel", bold_font())
	t.set_font_size("normal_font_size", "RichTextLabel", 17)
	t.set_font_size("bold_font_size", "RichTextLabel", 17)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	# Barre di scorrimento
	var grab := box(EDGE, EDGE, 0, 4, 0)
	var track := box(PANEL.darkened(0.3), EDGE.darkened(0.5), 0, 4, 0)
	for cls in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("grabber", cls, grab)
		t.set_stylebox("grabber_highlight", cls, box(BRASS, BRASS, 0, 4, 0))
		t.set_stylebox("grabber_pressed", cls, box(BRASS, BRASS, 0, 4, 0))
		t.set_stylebox("scroll", cls, track)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	# Liste del menu
	t.set_stylebox("panel", "ItemList", box(PANEL.darkened(0.15), EDGE, 2, 4, 6))
	t.set_stylebox("selected", "ItemList", box(BRASS.darkened(0.45), BRASS, 1, 3, 2))
	t.set_stylebox("selected_focus", "ItemList", box(BRASS.darkened(0.45), BRASS, 1, 3, 2))
	t.set_stylebox("hovered", "ItemList", box(PANEL_HI, EDGE, 1, 3, 2))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_color("font_color", "ItemList", INK)
	t.set_color("font_selected_color", "ItemList", Color(1, 1, 1))
	t.set_font_size("font_size", "ItemList", 18)
	t.set_constant("v_separation", "ItemList", 6)
	t.set_stylebox("panel", "PopupMenu", box(PANEL, BRASS, 2, 4, 6))
	t.set_stylebox("hover", "PopupMenu", box(PANEL_HI, BRASS, 1, 3, 4))
	t.set_color("font_color", "PopupMenu", INK)
	_theme = t
	return t


## Etichetta-titolo a stencil.
static func title(text: String, size: int = 22, col: Color = BRASS) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", title_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l
