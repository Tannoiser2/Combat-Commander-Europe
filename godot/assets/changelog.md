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
