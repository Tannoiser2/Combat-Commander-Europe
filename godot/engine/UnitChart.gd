## Database statistiche unità per gli scenari.
##
## Gli ordini di battaglia (catalog.json) elencano le unità per ETICHETTA
## (es. "Rifle", "Heavy MG", "Lt. Schrader") e ogni scenario indica la nazione
## reale di ciascun lato (`fazione_axis/allies`). Qui ogni (nazione, etichetta)
## è tradotta nelle statistiche ESATTE della carta ufficiale "Unit & Weapon"
## (`assets/scenarios/unit_chart.json`, estratta dal manuale).
##
## L'ARTE dei counter resta "stand-in": le fazioni dell'Asse usano i Tedeschi e
## quelle Alleate i Russi finché non c'è l'artwork delle singole nazioni — ma le
## STATISTICHE sono ora quelle reali della nazione dell'unità.
class_name UnitChart
extends RefCounted


## Categoria di un'etichetta: come va trattata dal loader di scenario.
enum Cat { LEADER, SQUAD, WEAPON, FOXHOLE, FORT, SKIP }

## Equipaggiamenti non modellati come unità né fortificazioni (per ora ignorati).
const _SKIP := {
	"Flamethrower": true, "Satchel Charge": true, "Molotov Cocktail": true,
}

## Squadre d'élite (per il fallback euristico quando l'etichetta non è in carta).
const _ELITE := {
	"Elite": true, "Elite Rifle": true, "Guards": true, "Guards Rifle": true,
	"SS": true, "Parachute": true, "Paratroop": true, "Pionier": true,
	"Engineer": true, "Guastatori": true, "Airborne": true, "Legionnaire": true,
	"Assault": true, "Bersaglieri": true,
}
## Squadre mitra (alta potenza a corto raggio) — fallback.
const _SMG := { "SMG": true, "Guards SMG": true, "Sissi": true }
## Squadre di leva/scarse — fallback.
const _CONSCRIPT := {
	"Conscript": true, "Militia": true, "Green": true, "Blackshirt": true,
	"Garrison": true, "Reservist": true,
}

const CHART_PATH := "res://assets/scenarios/unit_chart.json"
static var _chart: Dictionary = {}

## Cartella dei counter (arte reale) per codice nazione.
const COUNTER_DIR := {
	"DE": "Tedeschi", "RU": "Russi", "US": "Americani",
	"GB": "Britannici", "FR": "Francesi", "IT": "Italiani",
}
## Mappa (cartella → etichetta → nome file counter) per squadre/armi/team,
## generata dai counter realmente disponibili (`assets/counters/art_map.json`).
const ART_MAP_PATH := "res://assets/counters/art_map.json"
static var _art_map: Dictionary = {}


static func _art_data() -> Dictionary:
	if _art_map.is_empty():
		var f := FileAccess.open(ART_MAP_PATH, FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if d is Dictionary:
				_art_map = d
	return _art_map


## Cartella arte della nazione (default Tedeschi per lo stand-in se non mappata).
static func counter_folder(nat: String) -> String:
	return String(COUNTER_DIR.get(nat, "Tedeschi"))


## Nome file counter per (cartella, etichetta non-leader); fallback all'etichetta.
static func _art_for(folder: String, label: String) -> String:
	var byfolder: Dictionary = _art_data().get(folder, {})
	return String(byfolder.get(label, label))


## File counter del leader per grado (gli stessi nomi esistono in ogni nazione).
static func _leader_art_file(label: String) -> String:
	if label.contains("Hero"):
		return "Hero"
	if label.begins_with("Cpt."):
		return "Captain"
	if label.begins_with("Lt."):
		return "Lieutenant Y"
	if label.begins_with("Sgt."):
		return "Sergeant X"
	return "Corporal Y"


## Carica (una volta) la carta unità/armi.
static func _data() -> Dictionary:
	if _chart.is_empty():
		var f := FileAccess.open(CHART_PATH, FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if d is Dictionary:
				_chart = d
	return _chart


## Codice nazione della carta (DE/RU/US/GB/FR/IT) dal nome fazione dello
## scenario. Le nazioni minori usano il profilo della loro "capofila" (come il
## routing dei mazzi): Commonwealth→GB, brasiliani→US, polacchi/jugoslavi→FR,
## rumeni→IT.
static func nation_code(faz: String) -> String:
	match faz:
		"german": return "DE"
		"italian", "romanian": return "IT"
		"american", "brazilian": return "US"
		"british", "canadian", "anzac": return "GB"
		"french", "polish", "yugoslav": return "FR"
		"russian": return "RU"
	return ""


## Determina la categoria dell'etichetta.
static func category(label: String) -> int:
	if _SKIP.has(label):
		return Cat.SKIP
	if label == "Foxholes":
		return Cat.FOXHOLE
	if fort_type(label) != Domain.Fort.NONE:
		return Cat.FORT
	if _is_leader(label):
		return Cat.LEADER
	if _is_weapon(label):
		return Cat.WEAPON
	return Cat.SQUAD


## Tipo di fortificazione (Domain.Fort) per un'etichetta di setup, o Fort.NONE.
static func fort_type(label: String) -> int:
	match label:
		"Trench", "Trenches", "Trincea":
			return Domain.Fort.TRENCH
		"Bunker", "Bunker Complex", "Bunkers":
			return Domain.Fort.BUNKER
		"Pillbox", "Casemate", "Casamatta":
			return Domain.Fort.PILLBOX
		"Wire", "Barbed Wire", "Filo":
			return Domain.Fort.WIRE
		"Mines", "Minefield", "Mine":
			return Domain.Fort.MINES
	return Domain.Fort.NONE


static func _is_leader(label: String) -> bool:
	return label.begins_with("Lt.") or label.begins_with("Sgt.") \
		or label.begins_with("Cpl.") or label.begins_with("Cpt.") \
		or label.contains("Hero")


static func _is_weapon(label: String) -> bool:
	if label == "Weapon Team":
		return false
	if label.begins_with("Radio"):
		return true  # le Radio sono unità WEAPON benigne (abilitano l'artiglieria O18)
	return label.ends_with("MG") or label.contains("Mortar") \
		or label.contains("Gun") or label.contains("Howitzer") or label.contains("'75")


## Costruisce una Unit per l'etichetta. `nat` = codice nazione reale (DE/RU/…);
## se vuoto, si deduce dall'enum fazione (GERMAN→DE, RUSSIAN→RU).
static func build_unit(id: String, faction: int, label: String, q: int, r: int, nat: String = "") -> Unit:
	if nat == "":
		nat = "DE" if faction == Domain.Faction.GERMAN else "RU"
	var folder := counter_folder(nat)
	var cat := category(label)
	var u: Unit
	if cat == Cat.LEADER:
		u = _leader(id, faction, label)
		u.art_name = _leader_art_file(label)
	elif cat == Cat.WEAPON:
		u = _weapon(id, faction, label, nat)
		# La Radio non ha un counter proprio: usa l'arte stand-in di una MG pesante
		# (presente in tutte le nazioni).
		u.art_name = "Heavy MG" if label.begins_with("Radio") else _art_for(folder, label)
	else:
		u = _squad(id, faction, label, nat)
		u.art_name = _art_for(folder, label)
	u.nation_art = folder
	u.q = q
	u.r = r
	return u


static func _mk(id: String, faction: int, type: int, cls: int, name: String) -> Unit:
	return Unit.new(id, faction, type, cls, name)


# ─── Leader ──────────────────────────────────────────────────────────────────

## I leader sono uguali per tutte le nazioni (un'unica tabella). L'etichetta
## narrativa dà solo il grado: scegliamo un profilo rappresentativo per grado
## (i valori esatti del singolo ufficiale sono sul counter, non nel catalogo).
static func _leader(id: String, faction: int, label: String) -> Unit:
	var key := "Corporal Y"
	if label.contains("Hero"):
		key = "Hero"
	elif label.begins_with("Cpt."):
		key = "Captain"
	elif label.begins_with("Lt."):
		key = "Lieutenant Y"
	elif label.begins_with("Sgt."):
		key = "Sergeant X"
	elif label.begins_with("Cpl."):
		key = "Corporal Y"
	var s: Dictionary = _data().get("leaders", {}).get(key, {})
	var cls := Domain.UnitClass.ELITE if (key == "Captain" or key == "Lieutenant Y" or key == "Hero") else Domain.UnitClass.RIFLE
	var u := _mk(id, faction, Domain.UnitType.LEADER, cls, label)
	u.fp = int(s.get("fp", 1)); u.fp_boxed = bool(s.get("fp_boxed", false))
	u.range = int(s.get("range", 1)); u.range_boxed = bool(s.get("range_boxed", false))
	u.move = int(s.get("move", 6)); u.morale = int(s.get("morale", 8))
	u.command = int(s.get("command", 1)); u.move_penalty = 0
	u.art_name = _leader_art(faction, label)
	return u


static func _leader_art(faction: int, label: String) -> String:
	var senior := label.begins_with("Lt.") or label.begins_with("Cpt.") \
		or label.begins_with("Sgt.") or label.contains("Hero")
	if faction == Domain.Faction.GERMAN:
		return "Lieutenant Y" if senior else "Corporal X"
	return "Sergeant Y" if senior else "Corporal Y"


# ─── Squadre / Team ──────────────────────────────────────────────────────────

static func _is_team(label: String) -> bool:
	return label.ends_with("Team")  # "Weapon Team", "Elite Team", ...


static func _squad(id: String, faction: int, label: String, nat: String) -> Unit:
	var s := _squad_stats(nat, label)
	var utype := Domain.UnitType.TEAM if _is_team(label) else Domain.UnitType.SQUAD
	var u := _mk(id, faction, utype, _squad_class(label), label)
	u.fp = int(s.get("fp", 5)); u.fp_boxed = bool(s.get("fp_boxed", false))
	u.range = int(s.get("range", 5)); u.range_boxed = bool(s.get("range_boxed", true))
	u.move = int(s.get("move", 4)); u.morale = int(s.get("morale", 7))
	u.command = 0; u.move_penalty = 0
	u.art_name = "Rifle"
	return u


static func _squad_class(label: String) -> int:
	if _ELITE.has(label) or _SMG.has(label):
		return Domain.UnitClass.ELITE
	if _CONSCRIPT.has(label):
		return Domain.UnitClass.CONSCRIPT
	return Domain.UnitClass.RIFLE


## Statistiche di una squadra/team: cerca (nazione, etichetta) nella carta;
## "Weapon Team" → la voce Team della nazione; se assente prova la stessa
## etichetta in un'altra nazione; in ultima istanza un fallback euristico.
static func _squad_stats(nat: String, label: String) -> Dictionary:
	var units: Dictionary = _data().get("units", {})
	var key := "Team Weapon" if label == "Weapon Team" else label
	var tbl: Dictionary = units.get(nat, {})
	if tbl.has(key):
		return tbl[key]
	for n in units:
		if (units[n] as Dictionary).has(key):
			return units[n][key]
	return _squad_fallback(label)


static func _squad_fallback(label: String) -> Dictionary:
	if label == "Weapon Team":
		return { "fp": 2, "range": 3, "range_boxed": false, "move": 4, "morale": 7 }
	if _SMG.has(label):
		return { "fp": 6, "range": 3, "range_boxed": false, "move": 5, "morale": 8 }
	if _ELITE.has(label):
		return { "fp": 6, "fp_boxed": true, "range": 5, "range_boxed": true, "move": 5, "morale": 8 }
	if _CONSCRIPT.has(label):
		return { "fp": 4, "range": 3, "range_boxed": false, "move": 3, "morale": 6 }
	return { "fp": 5, "range": 4, "range_boxed": true, "move": 4, "morale": 7 }


# ─── Armi ────────────────────────────────────────────────────────────────────

static func _weapon(id: String, faction: int, label: String, nat: String) -> Unit:
	# Radio: non è un'arma da fuoco. È un'unità benigna (FP/gittata 0, immobile)
	# che serve solo ad abilitare la Richiesta d'Artiglieria (O18).
	if label.begins_with("Radio"):
		var ru := _mk(id, faction, Domain.UnitType.WEAPON, Domain.UnitClass.MG, label)
		ru.fp = 0
		ru.range = 0
		ru.move = 0
		ru.morale = 0
		ru.command = 0
		ru.ordnance = false
		ru.move_penalty = 0
		return ru
	var s := _weapon_stats(nat, label)
	var cls := _weapon_class(label)
	var u := _mk(id, faction, Domain.UnitType.WEAPON, cls, label)
	u.fp = int(s.get("fp", 4)); u.fp_boxed = bool(s.get("fp_boxed", true))
	u.range = int(s.get("range", 8)); u.range_boxed = bool(s.get("range_boxed", false))
	u.move = 0; u.morale = 0; u.command = 0
	u.move_penalty = int(s.get("move_penalty", -1))
	# Ordnance (barra bianca): Targeting Roll + gittata minima. I mortai sono
	# sempre ordnance; per i cannoni la carta lo segna esplicitamente.
	u.ordnance = bool(s.get("ordnance", false)) or cls == Domain.UnitClass.MORTAR or cls == Domain.UnitClass.AT
	u.min_range = int(s.get("min_range", 0))
	# Arte stand-in: i Tedeschi hanno solo "Light MG"; i Russi anche "Medium MG".
	var heavy := not label.begins_with("Light")
	if faction == Domain.Faction.RUSSIAN and heavy:
		u.art_name = "Medium MG"
	else:
		u.art_name = "Light MG"
	return u


static func _weapon_class(label: String) -> int:
	if label.contains("Mortar"):
		return Domain.UnitClass.MORTAR
	if label.contains("Gun") or label.contains("Howitzer") or label.contains("'75"):
		return Domain.UnitClass.AT
	return Domain.UnitClass.MG


## Statistiche arma: (nazione, etichetta) con normalizzazione dei nomi e, in
## mancanza, un profilo generico per tipo (le MG .30cal americane, ad es., non
## sono nella carta base).
static func _weapon_stats(nat: String, label: String) -> Dictionary:
	var weapons: Dictionary = _data().get("weapons", {})
	var tbl: Dictionary = weapons.get(nat, {})
	for key in _weapon_aliases(label):
		if tbl.has(key):
			return tbl[key]
	# stessa etichetta in un'altra nazione (per nomi specifici come Brixia/IG 18)
	for n in weapons:
		var t: Dictionary = weapons[n]
		for key in _weapon_aliases(label):
			if t.has(key):
				return t[key]
	return _weapon_fallback(label)


## Possibili nomi della carta per un'etichetta di catalogo, in ordine di
## preferenza (es. "60mm Mortar" → "60mm Mortar" oppure "Light Mortar").
static func _weapon_aliases(label: String) -> Array:
	match label:
		"60mm Mortar", "50mm Mortar":
			return [label, "Light Mortar"]
		"81mm Mortar", "82mm Mortar":
			return [label, "Medium Mortar"]
		"French '75", "Pack Howitzer", "Infantry Gun":
			return [label, "Pack Howitzer", "IG 18 Gun"]
		_:
			return [label]


static func _weapon_fallback(label: String) -> Dictionary:
	if label.begins_with("Light MG"):
		return { "fp": 4, "fp_boxed": true, "range": 8, "move_penalty": 0 }
	if label.begins_with("Medium MG"):
		return { "fp": 6, "range": 10, "move_penalty": -2 }
	if label.begins_with("Heavy MG") or label == ".50cal MG":
		return { "fp": 8, "range": 14, "move_penalty": -2 }
	if label.contains("Mortar"):
		return { "fp": 7, "range": 14, "move_penalty": -2 }
	# cannoni/obici
	return { "fp": 10, "range": 16, "move_penalty": -3 }
