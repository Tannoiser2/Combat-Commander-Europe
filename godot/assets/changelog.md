[b]v0.17.0[/b]

[b]IA — FlipBot (6/n): Difficoltà[/b]
- Tre livelli di difficoltà del bot, scelti nella schermata iniziale: Recluta, Di linea, Veterano.
- Ai livelli superiori l'IA riceve i bonus del FlipBot: più carte in mano (fino a 7), più ordini per turno e una soglia di resa più alta (resiste più a lungo).

[b]v0.16.0[/b]

[b]IA — FlipBot (5/n): Avanzata[/b]
- L'Avanzata dell'IA ora dà la priorità alla conquista degli obiettivi liberi adiacenti, poi al corpo a corpo (prima su obiettivo, poi ovunque).
- Look-ahead della mischia: l'IA non avanza in un esagono nemico se vi resterebbe in deficit di mischia di 2 o più punti.

[b]v0.15.0[/b]

[b]IA — FlipBot (4/n): Fuoco di Opportunità[/b]
- La reazione difensiva dell'IA al tuo movimento ora attiva il gruppo di fuoco con la massima potenza totale contro l'unità in movimento (non il singolo tiratore con l'FP più alta), rispettando il requisito di FP minima: niente reazioni sprecate su tiri deboli.

[b]v0.14.0[/b]

[b]IA — FlipBot (3/n): Fuoco[/b]
- Il Fuoco dell'IA segue ora le priorità del FlipBot: attiva il gruppo con la massima potenza di fuoco totale che ha un bersaglio valido, e mira all'esagono nemico con il morale efficace più basso (morale + copertura + ostacolo + comando difensivo).
- Requisito di FP minima: se nessun gruppo arriva entro 5 punti dalla difesa del bersaglio, l'IA non spreca il Fuoco.

[b]v0.13.0[/b]

[b]IA — FlipBot (2/n): Mossa[/b]
- L'IA muove ora secondo le priorità di destinazione del FlipBot: conquista l'obiettivo libero più vicino (entro 5), tiene gli obiettivi amici in Disposizione Difensiva, altrimenti punta agli obiettivi/unità nemiche o al bordo mappa avversario.
- Muove più esagoni (fino ai suoi PM), non più uno solo, scegliendo i passi in copertura e verso il fronte nemico.
- Le unità rotte si ritirano verso il bordo amico; l'ultima unità su un obiettivo controllato non lo abbandona.

[b]v0.12.0[/b]

[b]IA — FlipBot (1/n)[/b]
- Adottato il motore di turno del bot "FlipBot" (di Russ Brown): l'IA gioca il Recupero per primo se ha unità rotte, poi il primo ordine giocabile da sinistra a destra della sua mano.
- Carte "dud" (inutili) riconosciute: Confusione d'Ordini (sempre), Artiglieria Negata se il nemico non ha radio, Richiesta d'Artiglieria se l'IA non ha radio. Con la mano per lo più inutile, l'IA passa e scarta.
- Disposizione (Offensiva/Difensiva) calcolata da VP e obiettivi controllati, ricalcolata a ogni avanzamento del Tempo (guiderà le mosse/avanzate nei prossimi aggiornamenti).

[b]v0.11.0[/b]

[b]Schieramento[/b]
- Schieramento manuale: a inizio partita disponi tu le tue unità nella zona di setup (evidenziata in azzurro). Clicca un'unità, poi l'esagono dove spostarla; l'impilamento (max 7 figure) e i confini della zona sono rispettati. «Schieramento pronto» avvia la partita.
- «Auto» intelligente: piazzamento automatico in gruppi comandati dai leader (entro il loro Comando), distanziati tra loro e su esagoni con copertura e altura. Le armi seguono il portatore.

[b]v0.10.0[/b]

[b]Interfaccia[/b]
- HUD a riquadri: i pannelli sono ora finestre opache che delimitano la mappa invece di coprirla. La mappa 2D vive nell'area libera e si riprende lo spazio quando chiudi colonna o mano.
- Colonna laterale come "cassetto" che scorre in orizzontale con una maniglia sul bordo. Raccoglie Vista 2D/3D, LOS, Comandi, Menu, Editor mappe, scheda unita/esagono e Registro.
- Barra in alto riorganizzata con il conteggio Ordini; tolta la scritta gialla sovrapposta alla mappa.
- Mappa 2D: zoom con la rotella e spostamento (pan) col mouse; "0" reinquadra.
- Schermata iniziale: mappa e Ordine di Battaglia piu grandi.

[b]Vista 3D[/b]
- Modelli 3D reali low-poly (Kenney, CC0) per case, alberi ed erba, auto-scalati negli esagoni.
- Pendii delle elevazioni smussati (scarpate inclinate invece di gradini).

[b]Regole e gioco[/b]
- Mossa: un ordine dato a una qualunque unita comandata attiva l'intero gruppo di Comando del leader (3.3.1.2).
- Fuoco leggibile: le unita che possono sparare hanno un anello ciano, linee verso i bersagli validi, gruppo di fuoco automatico ma modificabile; il leader dirige il gruppo dal suo esagono.
- I badge si illuminano solo per gli ordini/azioni davvero possibili in quel momento.
- "Passa" (O15): scegli quante carte scartare e ripescare.
- Setup: armi sempre possedute da una squadra (niente piu armi "a terra" al via).

[b]Scenari[/b]
- Regole speciali e di setup di tutti i 24 scenari, in italiano, visibili in gioco ("Regole scenario").
- Piazzamento per scenario: zone di schieramento fedeli alle schede, fortificazioni iniziali (trincee, filo, mine, bunker) sulla mappa.
- Effetti automatici: gettoni Obiettivo esclusi, carte garantite in mano a inizio partita, ostacolo globale di mappa (Nebbia).
- Rinforzi dalla Tabella del Tempo: le unita designate entrano dal bordo amico quando il segnalino Tempo raggiunge il loro spazio (scenari 4, 9, 11, 12, 13).

[b]v0.9.0[/b]

[b]Interfaccia[/b]
- Mano a "badge" grafici: Ordine sopra, Azione sotto, illuminati quando giocabili e spenti quando no.
- Modalita LOS (tasto V o pulsante "LOS"): verifica la linea di vista tra due esagoni, con estremita trascinabili. Verde = libera, gialla = ostacolata, rossa = bloccata. Funziona in 2D e in 3D (tiene conto dell'altezza degli esagoni).
- Movimento leggibile: costo in PM mostrato su ogni esagono, PM residui del mover, alone del raggio di Comando del leader.
- Fuoco leggibile: linea di mira dal tiratore al bersaglio, FP d'attacco vs difesa stimata, esito atteso.
- Registro spostato in una colonna a destra, collassabile (tasto R).
- Pannello "Comandi" (tasto H) con la guida ai comandi.
- Rimossi i caratteri non disegnabili dal font (quadratini) da tutta l'interfaccia e dal registro.
- Schermata iniziale riprogettata: elenco compatto dei 24 scenari, Mappa + Ordine di Battaglia (con la scelta della fazione) + Artwork grande. Numero di versione e changelog sempre visibili.

[b]Regole[/b]
- Movimento: ora si paga il costo dell'intero percorso (niente "salti" a prezzo di un passo); Mine, Filo e Fuoco di Opportunita scattano a ogni esagono attraversato.
- Fuoco di Opportunita (A33): e un'Azione, quindi costa una carta Fuoco dalla mano e attiva il tiratore. Niente reazioni gratuite o ripetute; l'avversario e vincolato dalla sua mano come un giocatore normale.
- Armi / Portage (regola 11): possesso dell'arma, trasporto col malus ai PM del portatore, trasferimento o raccolta (tasto G), l'arma segue il portatore ed e eliminata con lui.
- Mimetizzazione (A29) fedele: riduce di una volta il totale d'attacco subito del valore della Copertura, poi si consuma.

[b]Tecnica[/b]
- Suite di test del motore ampliata (oltre 500 controlli).
