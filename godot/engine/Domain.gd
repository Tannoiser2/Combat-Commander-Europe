## Dominio di gioco — Combat Commander: Europe
##
## Enum, costanti e dizionari di lookup che codificano le regole
## del regolamento in forma controllata. Autoload singleton: accessibile
## ovunque come Domain.XXX
extends Node


# ─── Fazioni ─────────────────────────────────────────────────────────────────

enum Faction { GERMAN, RUSSIAN }

const FACTION_NAMES := {
	Faction.GERMAN:  "Germania",
	Faction.RUSSIAN: "Russia",
}

## Cartella dei segnalini (arte) per fazione, sotto res://assets/counters/
const FACTION_ART_DIR := {
	Faction.GERMAN:  "Tedeschi",
	Faction.RUSSIAN: "Russi",
}

const FACTION_SHORT := {
	Faction.GERMAN:  "GER",
	Faction.RUSSIAN: "RUS",
}


# ─── Tipi di unità ───────────────────────────────────────────────────────────

enum UnitType { SQUAD, LEADER, WEAPON }
enum UnitClass { RIFLE, ELITE, CONSCRIPT, MG, MORTAR, AT }

const UNIT_CLASS_LABEL := {
	UnitClass.RIFLE:     "Rifle",
	UnitClass.ELITE:     "Elite",
	UnitClass.CONSCRIPT: "Rifle",
	UnitClass.MG:        "MG",
	UnitClass.MORTAR:    "Mortar",
	UnitClass.AT:        "AT",
}


# ─── Terreno ─────────────────────────────────────────────────────────────────

enum TerrainType { OPEN, ROAD, BRUSH, WOODS, BUILDING, STREAM, HILL1, HILL2, RUBBLE }

## Costo in Punti Movimento per entrare nell'esagono.
const TERRAIN_MOVE_COST := {
	TerrainType.OPEN:     1,
	TerrainType.ROAD:     1,
	TerrainType.BRUSH:    2,
	TerrainType.WOODS:    2,
	TerrainType.BUILDING: 2,
	TerrainType.STREAM:   3,
	TerrainType.HILL1:    2,
	TerrainType.HILL2:    3,
	TerrainType.RUBBLE:   2,
}

## Copertura aggiunta al tiro di morale del difensore.
const TERRAIN_COVER := {
	TerrainType.OPEN:     0,
	TerrainType.ROAD:     0,
	TerrainType.BRUSH:    1,
	TerrainType.WOODS:    2,
	TerrainType.BUILDING: 3,
	TerrainType.STREAM:   1,
	TerrainType.HILL1:    1,
	TerrainType.HILL2:    2,
	TerrainType.RUBBLE:   2,
}

## Blocco della LOS: true = questo terreno interrompe la linea di vista.
const TERRAIN_BLOCKS_LOS := {
	TerrainType.OPEN:     false,
	TerrainType.ROAD:     false,
	TerrainType.BRUSH:    false,
	TerrainType.WOODS:    true,
	TerrainType.BUILDING: true,
	TerrainType.STREAM:   false,
	TerrainType.HILL1:    false,
	TerrainType.HILL2:    true,
	TerrainType.RUBBLE:   false,
}


# ─── Griglia hex flat-top, offset colonne ────────────────────────────────────
# Colonne pari: lo spostamento verticale è 0; colonne dispari: +1 riga.

const HEX_DIRS_EVEN := [
	Vector2i( 1,  0), Vector2i( 1, -1), Vector2i( 0, -1),
	Vector2i(-1, -1), Vector2i(-1,  0), Vector2i( 0,  1),
]
const HEX_DIRS_ODD := [
	Vector2i( 1,  1), Vector2i( 1,  0), Vector2i( 0, -1),
	Vector2i(-1,  0), Vector2i(-1,  1), Vector2i( 0,  1),
]


# ─── Fasi di gioco ───────────────────────────────────────────────────────────

enum Phase {
	PLAYER_TURN,      ## Selezione carta + unità
	PLAYER_MOVING,    ## Movimento passo per passo
	REACTION_WINDOW,  ## Finestra reazione IA dopo ogni passo
	AI_OPP_FIRE,      ## IA risolve fuoco di opportunità
	AI_TURN,          ## Turno dell'IA
	GAME_OVER,
}

const PHASE_LABELS := {
	Phase.PLAYER_TURN:     "Il tuo turno — seleziona carta e unità",
	Phase.PLAYER_MOVING:   "In movimento — clicca esagono adiacente",
	Phase.REACTION_WINDOW: "⏳ Finestra di reazione...",
	Phase.AI_OPP_FIRE:     "⚡ Fuoco di Opportunità IA!",
	Phase.AI_TURN:         "Turno IA in corso...",
	Phase.GAME_OVER:       "PARTITA TERMINATA",
}


# ─── Ordini e Azioni ─────────────────────────────────────────────────────────

enum OrderType { MOVE, FIRE, ADVANCE, RECOVER, ROUT, PASS, ARTY, ARTY_DENIED }
enum ActionType { ASSAULT_FIRE, OPPORTUNITY_FIRE, GRENADE, HERO, ENTRENCH }

const ORDER_LABELS := {
	OrderType.MOVE:        "Mossa",
	OrderType.FIRE:        "Fuoco",
	OrderType.ADVANCE:     "Avanzata",
	OrderType.RECOVER:     "Recupero",
	OrderType.ROUT:        "Ritirata",
	OrderType.PASS:        "Passa",
	OrderType.ARTY:        "Artiglieria",
	OrderType.ARTY_DENIED: "Artiglieria negata",
}

## Mappa la stringa orderType del JSON dei mazzi all'enum OrderType.
const ORDER_TYPE_FROM_STRING := {
	"move":        OrderType.MOVE,
	"fire":        OrderType.FIRE,
	"advance":     OrderType.ADVANCE,
	"recover":     OrderType.RECOVER,
	"rout":        OrderType.ROUT,
	"pass":        OrderType.PASS,
	"arty":        OrderType.ARTY,
	"arty_denied": OrderType.ARTY_DENIED,
}
