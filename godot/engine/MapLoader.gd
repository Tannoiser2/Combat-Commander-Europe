## Carica una definizione di mappa (JSON) e popola GameState:
## terreno per esagono, sovrapposizione strade, lati (siepi/muri), obiettivi.
class_name MapLoader
extends RefCounted


## Carica il JSON e applica i dati allo stato. Restituisce true se riuscito.
static func load_into(state: GameState, path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Mappa non trovata: " + path)
		return false
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary):
		push_error("Formato mappa non valido: " + path)
		return false

	state.map_cols = int(data.get("cols", 15))
	state.map_rows = int(data.get("rows", 10))
	var default_t: int = Domain.TERRAIN_FROM_STRING.get(data.get("default", "open"), Domain.TerrainType.OPEN)

	# Crea tutti gli esagoni col terreno di default
	state.hexes.clear()
	for q in state.map_cols:
		for r in state.map_rows:
			state.hexes["%d,%d" % [q, r]] = GameState.HexData.new(default_t)

	# Gruppi di terreno (chiave = stringa terreno, valore = lista etichette)
	var tgroups: Dictionary = data.get("terrainGroups", {})
	for tname in tgroups:
		var tt: int = Domain.TERRAIN_FROM_STRING.get(tname, default_t)
		for lbl in tgroups[tname]:
			var qr := Domain.label_to_qr(String(lbl))
			var hd: GameState.HexData = state.hex_at(qr.x, qr.y)
			if hd:
				hd.terrain = tt

	# Sovrapposizioni (strade)
	var fgroups: Dictionary = data.get("featureGroups", {})
	for lbl in fgroups.get("road", []):
		var qr := Domain.label_to_qr(String(lbl))
		var hd: GameState.HexData = state.hex_at(qr.x, qr.y)
		if hd:
			hd.has_road = true

	# Lati di esagono (siepi, muri)
	state.side_features.clear()
	for sf in data.get("sideFeatures", []):
		if not (sf is Dictionary):
			continue
		var a := Domain.label_to_qr(String(sf.get("from", "")))
		var b := Domain.label_to_qr(String(sf.get("to", "")))
		var feat: int = Domain.HEXSIDE_FROM_STRING.get(sf.get("feature", "hedge"), Domain.HexsideFeature.HEDGE)
		if a.x >= 0 and b.x >= 0:
			state.side_features.append({ "a": a, "b": b, "feature": feat })

	# Obiettivi
	state.objectives.clear()
	var oid := 0
	for obj in data.get("objectives", []):
		oid += 1
		var qr := Domain.label_to_qr(String(obj.get("hex", "")))
		if qr.x < 0:
			continue
		var o := Objective.new(int(obj.get("id", oid)), qr.x, qr.y, int(obj.get("vp", 1)))
		state.objectives.append(o)
		var hd: GameState.HexData = state.hex_at(qr.x, qr.y)
		if hd:
			hd.objective_id = o.id

	return true
