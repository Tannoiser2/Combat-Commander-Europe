## Dominio di gioco — Combat Commander: Europe
##
## Enum, costanti e dizionari di lookup che codificano le regole
## del regolamento in forma controllata. Autoload singleton: accessibile
## ovunque come Domain.XXX
extends Node


## Versione dell'applicazione (mostrata nella schermata iniziale, vedi
## res://assets/changelog.md per le modifiche).
const VERSION := "0.25.1"


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


# ─── Fortificazioni (F100-F106) ──────────────────────────────────────────────
# La buca (Foxhole) resta gestita a parte (HexData.has_foxhole). Qui i tipi
# aggiuntivi posati durante la partita.
enum Fort { NONE, TRENCH, PILLBOX, BUNKER, WIRE, MINES }

## Copertura alternativa (non cumulativa) di Trincea/Casamatta/Bunker; +1 contro
## ordnance. Filo/Mine non danno copertura.
const FORT_COVER := {
	Fort.TRENCH:  4,
	Fort.PILLBOX: 5,
	Fort.BUNKER:  6,
}

const FORT_NAMES := {
	Fort.NONE: "—",
	Fort.TRENCH: "Trincea",
	Fort.PILLBOX: "Casamatta",
	Fort.BUNKER: "Bunker",
	Fort.WIRE: "Filo spinato",
	Fort.MINES: "Mine",
}


# ─── Tipi di unità ───────────────────────────────────────────────────────────

# TEAM in coda per non alterare gli ordinali esistenti (compatibilità SaveGame).
enum UnitType { SQUAD, LEADER, WEAPON, TEAM }
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

## Terreni dell'esagono (CC Terrain Chart)
enum TerrainType {
	OPEN, BRUSH, WOODS, BUILDING, ORCHARD, FIELD,
	STREAM, MARSH, WATER_BARRIER, GULLY, BRIDGE,
	HILL1, HILL2, ROAD, RUBBLE,
}

## Nomi dei terreni (per il pannello info esagono)
const TERRAIN_NAMES := {
	TerrainType.OPEN: "Aperto", TerrainType.BRUSH: "Macchia", TerrainType.WOODS: "Bosco",
	TerrainType.BUILDING: "Edificio", TerrainType.ORCHARD: "Frutteto", TerrainType.FIELD: "Campo",
	TerrainType.STREAM: "Ruscello", TerrainType.MARSH: "Palude", TerrainType.WATER_BARRIER: "Acqua",
	TerrainType.GULLY: "Forra", TerrainType.BRIDGE: "Ponte", TerrainType.HILL1: "Collina 1",
	TerrainType.HILL2: "Collina 2", TerrainType.ROAD: "Strada", TerrainType.RUBBLE: "Macerie",
}

## Lati di esagono (CC Terrain Chart)
enum HexsideFeature { NONE, HEDGE, WALL, FENCE, BOCAGE, CLIFF, LOS_CLEAR, STREAM_SIDE }

## Feature lineari sovrapposte all'esagono
enum LinearFeature { NONE, ROAD, RAILWAY, TRAIL }

## Stringa del JSON mappe → TerrainType
const TERRAIN_FROM_STRING := {
	"open": TerrainType.OPEN, "brush": TerrainType.BRUSH, "woods": TerrainType.WOODS,
	"building": TerrainType.BUILDING, "orchard": TerrainType.ORCHARD, "field": TerrainType.FIELD,
	"stream": TerrainType.STREAM, "marsh": TerrainType.MARSH,
	"water_barrier": TerrainType.WATER_BARRIER, "gully": TerrainType.GULLY,
	"bridge": TerrainType.BRIDGE, "hill1": TerrainType.HILL1, "hill2": TerrainType.HILL2,
	"road": TerrainType.ROAD, "rubble": TerrainType.RUBBLE,
}

## Stringa del JSON → HexsideFeature
const HEXSIDE_FROM_STRING := {
	"hedge": HexsideFeature.HEDGE, "wall": HexsideFeature.WALL, "fence": HexsideFeature.FENCE,
	"bocage": HexsideFeature.BOCAGE, "cliff": HexsideFeature.CLIFF,
	"los_clear": HexsideFeature.LOS_CLEAR,
	"stream": HexsideFeature.STREAM_SIDE, "stream_side": HexsideFeature.STREAM_SIDE,
}

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
	TerrainType.FIELD:    1,
	TerrainType.ORCHARD:  1,
	TerrainType.MARSH:    3,
	TerrainType.WATER_BARRIER: 99,  # impraticabile
	TerrainType.GULLY:    2,
	TerrainType.BRIDGE:   1,
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
	TerrainType.FIELD:    1,
	TerrainType.ORCHARD:  1,
	TerrainType.MARSH:    0,
	TerrainType.WATER_BARRIER: 0,
	TerrainType.GULLY:    1,
	TerrainType.BRIDGE:   2,
}

## Ostacolo (hindrance): valori dalla Terrain Chart ufficiale (colonna LOS).
## NON cumulativo (10.3.3): lungo la LOS conta il modificatore singolo più grande.
const TERRAIN_HINDRANCE := {
	TerrainType.BRUSH:   3,
	TerrainType.ORCHARD: 2,
	TerrainType.FIELD:   1,
	TerrainType.MARSH:   1,
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
	TerrainType.FIELD:    false,
	TerrainType.ORCHARD:  false,
	TerrainType.MARSH:    false,
	TerrainType.WATER_BARRIER: false,
	TerrainType.GULLY:    false,
	TerrainType.BRIDGE:   false,
}

## Etichetta esagono "A1" ↔ coordinate (q,r). Colonna = lettera, riga = numero-1.
static func label_to_qr(lbl: String) -> Vector2i:
	if lbl.length() < 2:
		return Vector2i(-1, -1)
	var q := lbl.unicode_at(0) - 65
	var r := int(lbl.substr(1)) - 1
	return Vector2i(q, r)


## Inverso di label_to_qr: coordinata (q,r) → etichetta esagono (es. "C4").
static func qr_to_label(q: int, r: int) -> String:
	if q < 0 or r < 0:
		return "?"
	return "%s%d" % [char(65 + q), r + 1]


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
	PLAYER_SETUP,     ## Schieramento manuale delle proprie unità
}

const PHASE_LABELS := {
	Phase.PLAYER_TURN:     "Il tuo turno — seleziona carta e unità",
	Phase.PLAYER_MOVING:   "In movimento — clicca esagono adiacente",
	Phase.REACTION_WINDOW: "Finestra di reazione...",
	Phase.AI_OPP_FIRE:     "Fuoco di Opportunità IA!",
	Phase.AI_TURN:         "Turno IA in corso...",
	Phase.GAME_OVER:       "PARTITA TERMINATA",
	Phase.PLAYER_SETUP:    "Schieramento — disponi le tue unità nella zona",
}


# ─── Ordini e Azioni ─────────────────────────────────────────────────────────

enum OrderType { MOVE, FIRE, ADVANCE, RECOVER, ROUT, PASS, ARTY, ARTY_DENIED }
enum ActionType { ASSAULT_FIRE, OPPORTUNITY_FIRE, GRENADE, HERO, ENTRENCH }

## Disposizione del bot (FlipBot): Offensiva = avanza verso obiettivi/nemico,
## Difensiva = tiene gli obiettivi controllati. Decisa a inizio battaglia e a
## ogni avanzamento del segnalino Tempo (vedi FlipBot.compute_disposition).
enum Disposition { OFFENSIVE, DEFENSIVE }

const DISPOSITION_LABELS := {
	Disposition.OFFENSIVE: "Offensiva",
	Disposition.DEFENSIVE: "Difensiva",
}

## Livello di difficoltà del bot (FlipBot). Più alto = più carte, più ordini e
## resa più tenace per l'IA (vedi FlipBot.apply_difficulty).
enum BotDifficulty { GREEN, LINE, VETERAN }

const BOT_DIFFICULTY_LABELS := {
	BotDifficulty.GREEN:   "Recluta",
	BotDifficulty.LINE:    "Di linea",
	BotDifficulty.VETERAN: "Veterano",
}

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

## Badge grafici (res://assets/badges/): Ordine per tipo, Azione per nome.
## Mappature ricavate dalle immagini ufficiali (cartella BADGE del repo).
const ORDER_BADGE := {
	OrderType.ADVANCE:     "O_02",
	OrderType.ARTY_DENIED: "O_03",
	OrderType.ARTY:        "O_04",
	OrderType.PASS:        "O_05",  # "Command Confusion" (ORDINI CONTRADDITTORI)
	OrderType.FIRE:        "O_06",
	OrderType.MOVE:        "O_07",
	OrderType.RECOVER:     "O_08",
	OrderType.ROUT:        "O_09",
}
const ACTION_BADGE := {
	"IMBOSCATA": "A_25",
	"FUOCO D'ASSALTO": "A_26",
	"BUONA MIRA": "A_27",
	"ORDINI CONTRADDITTORI": "A_28",
	"MIMETIZZAZIONE": "A_29",
	"FUOCO INCROCIATO": "A_30",
	"DEMOLIZIONI": "A_31",
	"TRINCERARSI": "A_32",
	"BOMBE A MANO": "A_34",
	"TRINCERAMENTI NASCOSTI": "A_35_1",
	"MINE NASCOSTE": "A_35_2",
	"CASAMATTA NASCOSTA": "A_35_3",
	"UNITA' NASCOSTA": "A_35_4",
	"FILO SPINATO NASCOSTO": "A_35_5",
	"FERITE LEGGERE": "A_36",
	"FUOCO MIRATO": "A_37",
	"LOTTA SENZA QUARTIERE": "A_38",
	"GRANATE FUMOGENE": "A_39",
	"SVENTAGLIATA DI FUOCO": "A_40",
	"FUOCO SOSTENUTO": "A_41",
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
