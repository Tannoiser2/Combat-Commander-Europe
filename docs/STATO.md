# Stato del gioco — v0.50.0 «Rifondazione»

## Fatto e verificato con partite automatiche su tutti i 24 scenari

- Sequenza di gioco: Ordini uno alla volta fino al limite, oppure scarto col limite della nazione; pesca a fine turno; sovraccarico a fine turno.
- Attivazione: unità singola o comandante con gli uomini nel raggio di Comando, scelti uno per uno.
- Ordini: Mossa, Fuoco, Avanzata (con corpo a corpo), Recupero, Ritirata (su di sé o sull'avversario), Richiesta d'Artiglieria (accesso alla batteria, tiro esplosivo o fumogeno, deviazione), Artiglieria Negata, Ordini Contraddittori.
- Azioni: Fuoco di Opportunità, Fuoco d'Assalto, Fuoco Sostenuto, Fuoco Mirato, Bombe a Mano, Fuoco Incrociato, Buona Mira, Sventagliata, Mimetizzazione, Trinceramenti/Mine/Filo/Casamatta Nascosti, Granate Fumogene, Ferite Leggere, Imboscata, Lotta senza Quartiere, Trincerarsi, Demolizioni.
- Inneschi: Tempo! (sequenza completa con Morte Subitanea, PV al Difensore, fumo, rinforzi, Trincerarsi), Cecchino con scelta, Evento, Inceppamento; mazzo esaurito = Tempo.
- Carta Iniziativa: ripetizione di un tiro sfavorevole.
- Unità rotte con le statistiche del retro della pedina; soppressione; armi portate e guaste.
- Vittoria: obiettivi con chit aperti e segreti, PV da eliminazione e da uscita, resa, annientamento, Morte Subitanea.
- Bordi amici per scenario (alto/basso o sinistra/destra).

## Semplificazioni e cose ancora da fare

1. **Schieramento**: per ora automatico per entrambi i lati (manca la fase in cui il giocatore dispone le sue unità).
2. **Salvataggio** della partita: non ancora collegato al nuovo motore.
3. **Unità Nascosta (A35.4)** ed evento **Rinforzi**: la Tabella di Supporto della nazione non è modellata (Rinforzi dà una Squadra base; Unità Nascosta non è giocabile).
4. **Eventi** Saccheggio, Procedere Feriti e Fosforo Bianco: senza effetto.
5. **Armi guaste**: non si riparano/eliminano con l'Esagono Casuale (11.4); trasferimento arma (O21.1.1) e muovere in gruppo (O21.2) non ci sono: ogni unità muove da sola.
6. **Terreno**: copertura −1 lungo strada, vantaggio d'altura, esagoni ciechi e creste, obiettivi su edifici di più esagoni, fumo a valore variabile (ora vale sempre 3).
7. **Regole speciali di scenario**: valgono quelle già presenti nei dati (carte iniziali, rinforzi, chit esclusi, modifiche al terreno, ostacolo globale); le altre sono solo descritte in «Come si gioca».
8. **Carte illustrate** per Britannici, Italiani e Francesi: per ora disegnate dal gioco con lo stesso impianto.
9. **Vista 3D**: funziona col nuovo motore (evidenziazioni, tocco), ma le targhette delle pedine sono ancora quelle vecchie.
10. **Online su Firebase**: da fare; il motore a decisioni è già adatto (basta trasmettere l'indice dell'opzione scelta).
