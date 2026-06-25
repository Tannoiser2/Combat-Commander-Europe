## Regole di setup e regole speciali (SSR) di ogni scenario, lette dalle schede
## ufficiali (Scenari.pdf) e tradotte in italiano. Sono DATI di sola lettura: la
## visualizzazione le mostra al giocatore; le meccaniche vengono applicate
## altrove man mano che sono implementate.
class_name ScenarioRules
extends RefCounted

const PATH := "res://assets/scenarios/special_rules.json"

static var _data: Dictionary = {}
static var _loaded := false


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if d is Dictionary:
		_data = d


## Voce completa dello scenario ({titolo, setup, regole}) o {} se assente.
static func entry(num: int) -> Dictionary:
	_ensure()
	var e: Variant = _data.get(str(num), {})
	return e if e is Dictionary else {}


static func title(num: int) -> String:
	return String(entry(num).get("titolo", ""))


static func setup_note(num: int) -> String:
	return String(entry(num).get("setup", ""))


## Elenco delle regole speciali (stringhe). Vuoto se non disponibili.
static func rules(num: int) -> Array:
	var r: Variant = entry(num).get("regole", [])
	return r if r is Array else []


## Testo bbcode pronto per un RichTextLabel: setup + regole numerate.
static func as_bbcode(num: int) -> String:
	var e := entry(num)
	if e.is_empty():
		return "[i]Regole dello scenario non disponibili.[/i]"
	var out := ""
	var su := String(e.get("setup", ""))
	if su != "":
		out += "[b]Schieramento[/b]\n%s\n\n" % su
	var rs: Array = rules(num)
	if not rs.is_empty():
		out += "[b]Regole speciali[/b]\n"
		for i in rs.size():
			out += "%d. %s\n" % [i + 1, String(rs[i])]
	return out if out != "" else "[i]Nessuna regola speciale.[/i]"
