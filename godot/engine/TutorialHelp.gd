## Contenuti della «Modalità tutorial». Per ogni ORDINE e AZIONE fornisce un
## riassunto della REGOLA (Combat Commander: Europe) e di COSA FARE nel programma
## (la GUI). Testo puro, nessuna dipendenza dalla scena: lo usa Main per la
## finestra di aiuto fluttuante.
class_name TutorialHelp
extends RefCounted


## Aiuto per un ordine (Domain.OrderType): { title, rule, todo }. {} se assente.
static func for_order(order: int) -> Dictionary:
	match order:
		Domain.OrderType.MOVE:
			return {
				"title": "Ordine: MOSSA",
				"rule": "Muovi le tue unità verso gli obiettivi. Ogni unità ha dei Punti Movimento; entrare in un esagono costa secondo il terreno (e l'altura). Un Leader può attivare e muovere insieme tutte le unità entro il suo raggio di Comando.",
				"todo": "Clicca l'unità (o il Leader) da muovere: gli esagoni raggiungibili si illuminano col costo in PM (verde = poco, rosso = molto). Clicca un esagono per spostarti, un passo alla volta. Clicca di nuovo l'unità attiva per concludere. Nei gruppi, clicca un membro arancione per passare a muovere lui.",
			}
		Domain.OrderType.FIRE:
			return {
				"title": "Ordine: FUOCO",
				"rule": "Spari a un'unità nemica in linea di vista e gittata. Potenza di Fuoco del gruppo − Copertura − ostacoli + dadi, contro il Morale del bersaglio: se pareggi o superi, il bersaglio si Rompe (o è eliminato se era già rotto).",
				"todo": "Clicca un tiratore (anello ciano), oppure un Leader per vederne i tiratori comandati. Il gruppo di fuoco si assembla subito: clicca un pezzo per includerlo/escluderlo. Le linee rosse mostrano i bersagli; passa il mouse su un bersaglio per le statistiche, poi cliccalo per sparare. Clicca il tiratore per annullare l'ordine.",
			}
		Domain.OrderType.ADVANCE:
			return {
				"title": "Ordine: AVANZATA",
				"rule": "Sposti un'unità di un esagono in uno adiacente. Se l'esagono contiene nemici scatta la Mischia (corpo a corpo): si confrontano le Potenze di Fuoco (senza Comando), chi perde si Rompe o viene eliminato.",
				"todo": "Clicca l'unità che avanza, poi un esagono adiacente evidenziato. Se contiene un nemico parte la mischia. Clicca l'unità per annullare.",
			}
		Domain.OrderType.RECOVER:
			return {
				"title": "Ordine: RECUPERO",
				"rule": "Rimette in efficienza le tue unità Rotte e toglie la Soppressione, con un tiro influenzato dal Morale e dal Comando di un Leader vicino.",
				"todo": "Premi l'ordine: il recupero è automatico su tutte le unità idonee. Conviene avere un Leader vicino alle unità rotte per migliorare il tiro.",
			}
		Domain.OrderType.ROUT:
			return {
				"title": "Ordine: FUGA",
				"rule": "Le unità Rotte sotto pressione (adiacenti a nemici o sotto tiro) fuggono verso un riparo. Se non hanno scampo, vengono eliminate.",
				"todo": "Premi l'ordine: la fuga è automatica per le unità rotte sotto pressione.",
			}
		Domain.OrderType.ARTY:
			return {
				"title": "Ordine: ARTIGLIERIA",
				"rule": "Con una Radio e un osservatore (Leader) che vede il bersaglio, chiami l'artiglieria: un tiro di puntamento, la granata può derivare, e l'impatto investe l'esagono colpito e i 6 adiacenti.",
				"todo": "Clicca un esagono nella linea di vista dell'osservatore (area evidenziata). Premi «S» per alternare colpo esplosivo/fumogeno. Clicca l'osservatore per annullare.",
			}
		Domain.OrderType.PASS:
			return {
				"title": "Ordine: PASSA",
				"rule": "Invece di dare un ordine, passi: puoi scartare alcune carte e ripescarne altrettante, poi tocca all'avversario. Utile per rinnovare una mano scarsa.",
				"todo": "Nella finestra «Passa» spunta le carte da scartare e conferma. Senza scartare nulla conservi la mano.",
			}
	return {}


## Aiuto per un'azione (carta, banda inferiore): { title, rule, todo }.
static func for_action(action_name: String) -> Dictionary:
	var nm := action_name.to_upper()
	if nm.begins_with("SVENTAGLIATA"):
		return _entry("Azione: SVENTAGLIATA DI FUOCO",
			"L'attacco di Fuoco colpisce anche un secondo esagono nemico adiacente al bersaglio.",
			"Si gioca DURANTE l'assemblaggio del Fuoco, col bersaglio scelto: premi il badge AZIONE per estendere il colpo.")
	match nm:
		"MIMETIZZAZIONE":
			return _entry("Azione: MIMETIZZAZIONE",
				"Mimetizza un'unità in Copertura: il prossimo attacco di fuoco che subisce è ridotto del valore della Copertura dell'esagono (una volta sola).",
				"Premi il badge AZIONE: arma l'unità selezionata (o la prima idonea). Funziona anche come reazione quando l'IA ti spara: clicca l'unità ciano nel banner.")
		"TRINCERARSI":
			return _entry("Azione: TRINCERARSI",
				"Scava una buca (foxhole) sull'esagono di una tua unità: aggiunge Copertura. Vietato su acqua, incendio o dove c'è già una fortificazione o una buca.",
				"Premi il badge AZIONE: la buca viene posata su una tua unità idonea.")
		"FERITE LEGGERE":
			return _entry("Azione: FERITE LEGGERE",
				"Cura sul posto: recupera immediatamente una tua unità Rotta.",
				"Premi il badge AZIONE: un'unità rotta torna efficiente.")
		"GRANATE FUMOGENE":
			return _entry("Azione: GRANATE FUMOGENE",
				"Posa fumo su un esagono: ostacola (riduce) la linea di vista che lo attraversa, proteggendo chi è dietro.",
				"Premi il badge AZIONE: il fumo va sull'esagono indicato dalla carta.")
		"FILO SPINATO NASCOSTO", "MINE NASCOSTE", "CASAMATTA NASCOSTA", "TRINCERAMENTI NASCOSTI":
			return _entry("Azione: FORTIFICAZIONE NASCOSTA",
				"Posa una fortificazione (filo spinato, mine, casamatta o trincea) sull'esagono di una tua unità: ostacola il nemico o protegge l'unità.",
				"Premi il badge AZIONE: la fortificazione va su un esagono idoneo di una tua unità.")
		"FUOCO MIRATO", "FUOCO SOSTENUTO", "FUOCO INCROCIATO":
			return _entry("Azione: MODIFICATORE DI FUOCO",
				"Aggiunge +2 Potenza di Fuoco all'attacco di Fuoco in corso (ognuno con i propri prerequisiti, es. Fuoco Mirato richiede una squadra/team).",
				"Si gioca DURANTE l'assemblaggio del Fuoco, col bersaglio scelto: premi il badge AZIONE per applicarlo all'attacco.")
		"BOMBE A MANO":
			return _entry("Azione: BOMBE A MANO",
				"+2 Potenza di Fuoco se almeno un pezzo del gruppo spara a distanza 1 (esagono adiacente).",
				"Durante un Fuoco verso un esagono adiacente, premi il badge AZIONE per aggiungere il bonus.")
		"FUOCO D'ASSALTO":
			return _entry("Azione: FUOCO D'ASSALTO",
				"Un'unità che ha appena mosso può sparare una volta, a Potenza dimezzata (valori «in box»), durante l'ordine di Mossa.",
				"Durante una Mossa, dopo aver mosso l'unità, premi il badge AZIONE per spararle.")
		"IMBOSCATA":
			return _entry("Azione: IMBOSCATA",
				"In Mischia, prima dei dadi, rompe un'unità nemica partecipante: indebolisce il nemico nel corpo a corpo.",
				"Per ora la gioca l'IA; la versione per il giocatore arriverà presto.")
	# Azione non ancora dettagliata: aiuto generico.
	return _entry("Azione: %s" % action_name,
		"Azione di Combat Commander (banda inferiore della carta).",
		"Premi il badge AZIONE quando è illuminato per giocarla.")


static func _entry(title: String, rule: String, todo: String) -> Dictionary:
	return {"title": title, "rule": rule, "todo": todo}
