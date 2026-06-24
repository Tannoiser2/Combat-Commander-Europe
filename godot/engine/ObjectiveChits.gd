## Chit Obiettivo (7.3.2): all'inizio dello scenario si estraggono dei "chit" che
## assegnano valori in VP agli obiettivi sulla mappa. Più chit possono cadere sullo
## stesso obiettivo: i valori si SOMMANO (l'esempio del regolamento: i chit C+G+K
## sull'Obiettivo #3 lo rendono da 1+2+3 = 6 VP).
##
## Modello semplificato: un sacchetto con valori 1/2/3 (il mix reale dei 22 chit non
## è riprodotto). Opt-in per scenario tramite il campo catalogo `objective_chits`.
class_name ObjectiveChits
extends RefCounted

## Valori dei chit nel sacchetto (estratti senza rimpiazzo finché disponibili).
const CHIT_POOL := [1, 1, 1, 2, 2, 2, 3, 3, 3]


## Estrae `count` chit e li assegna ad obiettivi casuali (cumulativo, 7.3.2),
## azzerando prima i VP stampati. No-op se non ci sono obiettivi o `count` <= 0.
## Restituisce { "drawn": Array[int], "lines": Array[String] }.
static func assign(state: GameState, count: int, rng: RandomNumberGenerator) -> Dictionary:
	var out := { "drawn": [], "lines": [] }
	if count <= 0 or state.objectives.is_empty():
		return out
	for o in state.objectives:
		o.vp = 0
	# Estrazione dei chit dal sacchetto (si ricarica se si esaurisce).
	var bag: Array = CHIT_POOL.duplicate()
	var drawn: Array = []
	for _i in count:
		if bag.is_empty():
			bag = CHIT_POOL.duplicate()
		var bi := rng.randi_range(0, bag.size() - 1)
		drawn.append(int(bag[bi]))
		bag.remove_at(bi)
	# Assegnazione cumulativa ad obiettivi casuali.
	for v in drawn:
		var oi := rng.randi_range(0, state.objectives.size() - 1)
		state.objectives[oi].vp += int(v)
	out["drawn"] = drawn
	var lines: Array = []
	for o in state.objectives:
		lines.append("Obiettivo #%d → %d VP" % [o.id, o.vp])
	out["lines"] = lines
	return out
