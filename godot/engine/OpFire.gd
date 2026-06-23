## Fuoco di Opportunità (CC:E A33).
## Mentre un'unità si muove, le unità nemiche efficienti che la vedono e la
## raggiungono possono spararle (una per passo). Mortai e cannoni (ordnance)
## sono esclusi (A33.3 es.1). Le funzioni qui selezionano i tiratori; la
## risoluzione del fuoco avviene in Game (pesca del Fato + conseguenza).
class_name OpFire
extends RefCounted


## Unità di `defender` che possono reagire al movimento di `mover`:
## efficienti, con FP, non mortai/cannoni, in gittata e con linea di vista.
static func eligible_shooters(state: GameState, mover: Unit, defender: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for u in state.units_of(defender):
		if not u.efficient or u.suppressed or u.fp <= 0:
			continue
		if u.ordnance or u.unit_class == Domain.UnitClass.MORTAR or u.unit_class == Domain.UnitClass.AT:
			continue  # ordnance escluso dal Fuoco di Opportunità (11.5/A33.3)
		var dist := HexGrid.distance(u.q, u.r, mover.q, mover.r)
		if dist < 1 or dist > u.range:
			continue
		if not HexGrid.has_los(u.q, u.r, mover.q, mover.r, state):
			continue
		result.append(u)
	return result


## Miglior tiratore di opportunità (FP più alto), o null se nessuno è idoneo.
static func best_shooter(state: GameState, mover: Unit, defender: int) -> Unit:
	var best: Unit = null
	for u in eligible_shooters(state, mover, defender):
		if best == null or u.fp > best.fp:
			best = u
	return best
