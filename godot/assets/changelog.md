[b]v0.43.1[/b]

[b]Fuoco: ora si vede chi cliccare (vista 3D)[/b]
- Dopo aver giocato la carta di [b]Fuoco[/b], nella vista 3D non si illuminava nulla: non si capiva cosa selezionare. Ora si accendono subito i [b]tiratori pronti[/b] (anello ciano) e i [b]leader che possono dirigere un gruppo[/b] di fuoco (anello oro), come già accadeva nella mappa 2D.
- Cliccando un leader-direttore si illuminano i tiratori che comanda; cliccando un tiratore si assembla il gruppo e si mostrano i bersagli. Il flusso «seleziona leader → si accendono le unità che possono sparare → scegli» ora è visibile.

[b]v0.43.0[/b]

[b]Vista 3D — pendii dei dislivelli più ripidi[/b]
- I fianchi dei rilievi ora sono [b]più ripidi e morbidi[/b]: il piede del pendio non invade più l'esagono sottostante (prima un rilievo di quota 2 sbordava di un intero raggio d'esagono). L'allargamento cresce con la radice della quota, così anche le colline alte restano ripide senza coprire gli esagoni vicini.

[b]Impilamento: il bot rispetta il limite (regola 8.2)[/b]
- Lo [b]schieramento[/b] non accatasta più le unità: ogni unità-uomo riceve un esagano distinto (2 squadre = 8 figure = oltre il limite di 7), e se la zona della scheda è troppo piccola per la forza viene [b]allargata[/b] quanto basta. Prima il bot poteva partire con torri di 7+ pedine in un solo esagono (es. scenari 3, 4, 12).
- Aggiunta la [b]risoluzione di fine turno[/b] (8.2): durante il turno si può sovrastare, ma a fine turno ogni esagono oltre le 7 figure perde le unità in eccesso (prima le rotte, poi le meno preziose), per entrambi gli schieramenti. È il punto in cui le regole d'impilamento valgono davvero.
- Lo schieramento [b]Auto[/b] del giocatore segue la stessa regola: nessun esagono oltre 7 figure.

[b]v0.42.1[/b]

[b]Correzione — Mossa/Avanzata di gruppo: concludere un membro[/b]
- In un gruppo, cliccare l'unità che si è mossa ora conclude [b]solo il suo[/b] movimento e passa al prossimo membro da muovere: l'ordine resta aperto finché ci sono unità da muovere. Prima cliccarla chiudeva l'intero ordine. Vale per Mossa e Avanzata.

[b]v0.42.0[/b]

[b]Colonna laterale separata + impilamento in movimento[/b]
- La colonna laterale ora è una [b]colonna a sé[/b] (come la barra di stato in alto): non si sovrappone più né alla mappa né alla mano di carte (la mano si ferma al bordo della colonna; chiudendo la colonna la mano torna a tutta larghezza).
- In [b]movimento[/b], cliccare un esagono occupato da un compagno ora [b]impila[/b] l'unità lì (se c'è spazio, max 7 figure) invece di selezionare l'unità presente e fermare il movimento. Durante Mossa/Avanzata cliccare muove l'unità attiva: non si selezionano più altre unità per sbaglio.

[b]v0.41.0[/b]

[b]Effetti visivi (vista 3D)[/b]
- [b]Bombe a mano[/b]: la granata arcua dal lanciatore al bersaglio e poi esplode.
- [b]Artiglieria[/b]: quando cade il bombardamento, esplosione grande sul centro e onda d'urto sui 6 esagoni adiacenti.
- [b]Rottura / eliminazione[/b]: le unità appena rotte lampeggiano di rosso; quelle eliminate sprofondano e svaniscono con un'esplosione.
- [b]Fuoco potenziato[/b]: sbuffo di fumo alla bocca dello sparo, oltre a tracciante e lampi già presenti.
- [b]Movimento[/b]: lo scivolamento ora ha un leggero dondolio (passo) per un effetto «camminata».

[b]v0.40.0[/b]

[b]Selettore di stack (scegli una pedina impilata)[/b]
- Cliccando un esagono con più unità tue compare un piccolo pannello che le elenca: clicca quella che vuoi per selezionarla. Così è facile prendere anche un [b]leader «sotto» lo stack[/b], che prima in 3D era scomodo da centrare. I leader sono elencati per primi. (In 2D resta anche lo scorrimento a clic ripetuti.)

[b]v0.39.0[/b]

[b]Avanzata di gruppo (ordine dato al leader)[/b]
- Come la Mossa, ora anche l'[b]Avanzata[/b] data «tramite» un leader attiva il leader [b]e[/b] tutte le squadre/team entro il suo raggio di Comando: ciascun membro avanza di un esagono (con eventuale corpo a corpo), poi si passa al successivo (membro arancio) e l'ordine si conclude da solo. Prima l'Avanzata muoveva una sola unità. (Regole O7/O14.1 + 3.3.1.1, confermate sul regolamento ufficiale.)
- Nota: Recupero e Rotta restano correttamente «a livello di giocatore» (agiscono su tutte le unità rotte, non sul gruppo di un leader), come da regolamento (O22/O23).

[b]v0.38.0[/b]

[b]Correzioni — badge azioni/ordini e movimento dell'IA[/b]
- [b]Azioni[/b]: i badge azione ora si accendono solo quando l'azione ha davvero un effetto (es. Ferite Leggere solo se hai un'unità rotta, Mimetizzazione solo se hai un'unità idonea, Trincerarsi/fortificazioni solo se c'è un esagono valido). Prima si accendevano sempre e poi la carta si scartava a vuoto.
- [b]Modificatori di fuoco[/b]: con la selezione «gruppo-prima» i modificatori (Fuoco Mirato/Sostenuto/Incrociato, Bombe a Mano, Sventagliata) erano diventati ingiocabili. Ora si accendono e si applicano durante l'assemblaggio del gruppo: premi il badge per accodarli (ri-premi per toglierli), e allo sparo vengono validati sul bersaglio — quelli non applicabili restano in mano, non si sprecano.
- [b]Movimento dell'IA[/b]: l'avversario ignorava i costi di movimento del terreno e si muoveva un numero di esagoni pari al suo Movimento (ogni esagono come 1 PM), spostandosi 2-3 volte troppo in bosco/macchia/ruscello. Ora l'IA spende i Punti Movimento secondo il terreno, esattamente come il giocatore. (Nota di regola: il bonus di Comando ai Punti Movimento del giocatore è corretto, 3.3.1.2 del regolamento.)
- [b]Colline[/b]: ora la collina in piano costa come il terreno sottostante e la salita di quota costa +1 PM (T88.1), invece di un costo fisso 2/3. La copertura della collina resta invariata.
- [b]Comando cumulativo[/b]: due o più leader nello stesso esagono sommano il bonus di Comando (3.3.1.2), invece di contare solo il migliore.
- [b]Eroe[/b]: Movimento corretto a 4 (come la tabella unità), prima era 6.

[b]v0.37.0[/b]

[b]Registro più ricco e leggibile[/b]
- Il registro ora distingue le situazioni: [b]inizio/fine turno[/b] su banda colorata, l'[b]ordine giocato[/b] in rosso, il [b]fuoco[/b] e la [b]mischia[/b] in arancio, le mosse dell'[b]IA[/b] in azzurro; le parole chiave (ROTTE, ELIMINATE, SOPPRESSE…) sono in neretto.
- Per le risoluzioni con un calcolo (fuoco, corpo a corpo) compare un dettaglio [b]«formula» collassabile[/b] (chiuso di default): cliccaci sopra per vedere la formula e i numeri usati (FP, ostacolo, copertura, dadi, totali). Richiudibile con un clic.

[b]v0.36.0[/b]

[b]Modalità tutorial (aiuto guidato)[/b]
- Nuova opzione nella schermata iniziale: «Modalità tutorial». Quando è attiva, ogni volta che premi un ordine o un'azione compare una finestra fluttuante con due sezioni: [b]Regola[/b] (sunto del regolamento CC:E) e [b]Cosa fare[/b] (come funziona il programma in quel momento). Coperti tutti gli ordini (Mossa, Fuoco, Avanzata, Recupero, Fuga, Artiglieria, Passa) e le azioni principali. La finestra si chiude col tasto «✕» o «Disattiva tutorial», e l'impostazione viene ricordata.

[b]v0.35.2[/b]

[b]Correzione — finestra di reazione più chiara (niente «blocco»)[/b]
- Durante il turno dell'IA il gioco può chiederti una reazione (Fuoco di Opportunità su un'unità che si muove, o Mimetizzazione): è una fase «non tua», quindi ordini, azioni e «Fine Turno» sono spenti. Prima l'unico avviso era una riga nella colonna laterale (facile da non vedere, specie a colonna chiusa), così sembrava che il gioco si fermasse. Ora compare un banner centrale ben visibile che spiega cosa fare, con un pulsante «Non sparare / Non mimetizzarmi» (anche col tasto SPAZIO) per proseguire.

[b]v0.35.1[/b]

[b]Correzione — Fuoco: l'ordine si poteva «bloccare»[/b]
- Risolto un blocco introdotto con la selezione gruppo-prima: una volta dato l'ordine di Fuoco non c'era più modo di annullarlo cliccando, e con i badge spenti (sei «in ordine») sembrava che il gioco si fermasse. Ora cliccare il tiratore selezionato annulla l'ordine di Fuoco e riporta alla scelta della carta, esattamente come per Mossa e Avanzata.

[b]v0.35.0[/b]

[b]Fuoco — selezione «gruppo-prima-del-bersaglio»[/b]
- Il Fuoco ora si imposta nell'ordine naturale: selezioni un tiratore (o un leader per vederne i tiratori comandati) e il [color=#ffae5a]gruppo di fuoco[/color] si assembla SUBITO, prima di scegliere il bersaglio.
- I pezzi del gruppo sono modificabili al volo: clic su un pezzo = aggiungilo/toglilo. A ogni modifica si ricalcolano i bersagli validi.
- Si illuminano tutti i bersagli possibili, con linee di mira da ogni tiratore verso ogni bersaglio (2D e 3D).
- In 3D, passando il mouse su un bersaglio compare un flyover con le statistiche del tiro: FP d'attacco vs Difesa, copertura, numero di difensori e tiratori, ed esito stimato.
- Un clic sul bersaglio apre il fuoco e conclude l'ordine in un colpo solo.

[b]v0.34.0[/b]

[b]Azioni — Trincerarsi: vincoli di posa[/b]
- Trincerarsi (A32) e le fortificazioni «nascoste» (A35) ora rispettano i vincoli del regolamento: non si può scavare/fortificare su acqua, su un incendio, né dove c'è già una fortificazione o una buca.

[b]v0.33.0[/b]

[b]Azioni — tempistica reattiva (3/n): Imboscata dell'IA[/b]
- L'IA ora gioca l'Imboscata (A25) in Mischia, prima dei dadi: se è coinvolta in un corpo a corpo e ha la carta, rompe l'unità avversaria partecipante più debole (riducendone la potenza prima del calcolo), come prevede la regola. Prima non la usava mai. (L'Imboscata giocata dal giocatore umano arriverà in una prossima fase.)

[b]v0.32.0[/b]

[b]Azioni — tempistica reattiva (2/n): Mimetizzazione, reazione umana[/b]
- Quando l'IA ti spara a un'unità in copertura e hai la carta Mimetizzazione, si apre ora una finestra di reazione: clicca l'unità (evidenziata in ciano) per mimetizzarti, oppure premi SPAZIO / clicca altrove per rinunciare. Vale in 2D e 3D. Così la Mimetizzazione si gioca nel momento giusto (al tiro di Difesa), come da regola — oltre al gioco "in anticipo" che resta disponibile.

[b]v0.31.0[/b]

[b]Azioni — tempistica reattiva (1/n): Mimetizzazione dell'IA[/b]
- L'IA ora usa la Mimetizzazione (A29) come reazione, nell'istante in cui una sua unità in copertura viene presa di mira: se ha la carta in mano si mimetizza e la Copertura riduce una volta l'attacco subìto. Prima l'IA non la giocava mai. (Lato umano resta per ora il gioco "in anticipo" nel proprio turno; la finestra di reazione umana arriverà in una prossima fase.)

[b]v0.30.0[/b]

[b]Azioni — conformità degli effetti[/b]
- Fuoco d'Assalto (A26): ora richiede una FP «in scatola», come da regola (solo le unità con potenza di fuoco riquadrata possono sparare mentre si muovono).
- Bombe a Mano (A34): non è più un attacco a sé, ma un modificatore di Fuoco (+2 FP, cumulabile) giocabile quando almeno un pezzo spara a un esagono adiacente — come prevede il regolamento.

[b]v0.29.0[/b]

[b]Azioni — correzioni e chiarezza[/b]
- I badge Azione si accendono ora solo quando l'azione ha davvero un effetto: le azioni non ancora simulate (Imboscata, Buona Mira, Ordini Contraddittori, Demolizioni, Unità Nascosta, Lotta Senza Quartiere) restano spente invece di sembrare giocabili e poi scartarsi senza fare nulla.
- Corretta la «Sventagliata di Fuoco»: per un errore di nome non partiva mai; ora aggiunge davvero il secondo esagono bersaglio durante un Fuoco.

[b]v0.28.0[/b]

[b]Interfaccia — flusso "prima la carta"[/b]
- Ora si dà sempre prima l'ordine (la carta) e poi si scelgono le unità sulla mappa: la selezione fatta prima della carta non viene più "ereditata" dall'ordine. Giocando Mossa o Avanzata si illuminano le unità ordinabili (chi puoi cliccare); col Fuoco resta l'anello su chi può sparare.

[b]v0.27.0[/b]

[b]Interfaccia — selezione e gruppo di comando[/b]
- Selezionando un leader (prima di dare un ordine) si illuminano ora tutte le unità che potrebbe attivare nel turno, cioè il suo gruppo di comando (uomini idonei entro il raggio di Comando). Vale sia nella vista 2D sia nella 3D.
- Resta valido il flusso "prima la carta, poi le unità": giochi l'ordine e poi scegli sulla mappa l'unità/gruppo a cui applicarlo.

[b]v0.26.0[/b]

[b]Vista 3D[/b]
- Rimosse le decorazioni 3D del terreno (edifici, alberi, vegetazione): non convincevano e ne arriveranno di nuove. Per ora gli esagoni sono "puliti" e il terreno resta leggibile dalla skin del tabellone.
- Armi ancora un po' più piccole rispetto ai soldati.

[b]v0.25.1[/b]

[b]Correzioni[/b]
- Vista 3D: le armi erano enormi (venivano scalate sull'altezza, ma sono basse e larghe). Ora si scalano sull'ingombro massimo e restano più piccole dei soldati.

[b]v0.25.0[/b]

[b]Vista 3D — armi e qualità delle miniature[/b]
- Le pedine arma (mitragliatrici, mortai, cannoni) mostrano ora il loro modello 3D, scelto per nazione e tipo (MG leggera/media/pesante/.50, mortaio, cannone/obice). I tipi senza modello dedicato ripiegano sull'arma più simile della stessa nazione.
- Migliorata la resa dei soldati: si conserva la geometria originale (niente più decimazione) così la texture non si "spezzetta" più lungo le cuciture — via le superfici mottled/strane viste prima. Texture sempre a 512 per il web.
- Coerenza fra pose: i soldati accucciati/in fuoco non sono più alti come quelli in piedi (l'altezza si adatta all'ingombro della posa).

[b]v0.24.1[/b]

[b]Correzioni[/b]
- Vista 3D: corretti i "buchi" nelle miniature dei soldati. La riduzione dei poligoni apriva delle crepe lungo le cuciture della texture; ora si conserva la geometria originale, quindi le mesh restano integre.

[b]v0.24.0[/b]

[b]Vista 3D — soldati più grandi e badge migliore[/b]
- Le figure dei soldati sono un po' più grandi e leggibili.
- Il badge dei valori sopra la pedina è ora più piccolo e curato: pannello con angoli stondati e un font vero (non più "a quadretti"). I valori "in box" e il Comando dei leader hanno un riquadro stondato del loro colore; il pannello diventa rosso se l'unità è rotta.
- La pedina selezionata non si solleva più: la selezione è indicata colorando il fondo del badge (azzurro con bordo acceso). Più chiaro e meno invasivo.

[b]v0.23.0[/b]

[b]Vista 3D — soldati americani[/b]
- Modelli 3D dedicati anche per gli Americani (soldati in 2 pose + ufficiale). I modelli sono ora scelti per nazionalità dell'unità (Tedeschi / Russi / Americani), non più solo per fazione: ogni nazione mostra i propri soldati, con ripiego tinto solo se un modello manca.

[b]v0.22.0[/b]

[b]Vista 3D — squadre, badge numerico e direzione[/b]
- Ogni pedina mostra ora il giusto numero di figure: squadra 4, team 2, leader 1 (arma 1). I leader usano un modello di ufficiale dedicato; le squadre/team alternano due pose per varietà. Geometria dei modelli alleggerita (~5000 triangoli, texture 512) per la build web.
- Modelli dedicati per fazione: soldati e ufficiali tedeschi per l'Asse, sovietici per i Russi (niente più tinta verde "segnaposto" quando il modello della fazione esiste).
- Le figure sono orientate nella direzione di marcia: quando un'unità si muove, il gruppo ruota verso il nuovo esagono (di riposo guardano verso il fronte nemico).
- Al posto del segnalino "fotografico" ora c'è un piccolo badge numerico sopra la pila: striscia di valori (PdF, Gittata, Movimento, Morale in box), con il valore Comando per i leader e il riquadro sui valori "in box". Si tinge di rosso se l'unità è rotta.

[b]v0.21.0[/b]

[b]Vista 3D — soldati[/b]
- Le pedine in 3D sono ora una figura di soldato (una per pedina), con il segnalino di gioco sopra la testa per identità e valori. L'Asse usa il modello tedesco; gli Alleati lo stesso modello con tinta verde-oliva come segnaposto (in attesa di un modello dedicato). Texture ridotte per la build web; ripiego al segnalino se il modello manca.

[b]v0.20.0[/b]

[b]Vista 3D — alberi[/b]
- Nuovi alberi low-poly variati (collezione dedicata) al posto dei coni negli esagoni di bosco e frutteto: più forme, più verde, più "foresta". Restano leggeri per il web.
- Correzione: gli alberi ora sono dritti e di dimensione corretta (prima un errore di orientamento li coricava e li ingrandiva).

[b]v0.19.0[/b]

[b]Vista 3D — spostamento[/b]
- Ora la mappa 3D si può spostare (pan) trascinando col tasto destro (o centrale) del mouse, come la 2D. Il tasto «0» reinquadra la vista. La rotazione resta sul tasto sinistro e lo zoom sulla rotella.

[b]v0.18.2[/b]

[b]Correzioni[/b]
- Scenario 1 «Fat Lipki»: corrette le posizioni di schieramento, che erano sui lati sbagliati. Ora rispettano la scheda: Alleati negli angoli in alto (in/adiacente ad A2 e O1), Asse sul bordo basso (in/adiacente a G10 e N10).
- Vista 3D: i modelli (edifici, alberi, erba) non sono più bianchi — ripristinata la texture dei colori mancante.

[b]v0.18.1[/b]

[b]Correzioni[/b]
- Scenario 1: ripristinato il piazzamento storico esatto. Gli scenari con piazzamento fisso (curato a mano) non passano più dalla fase di Schieramento manuale — partono direttamente con le forze ai loro esagoni precisi. Lo Schieramento manuale con «Auto» resta per gli scenari che hanno una zona di schieramento dalle schede.

[b]v0.18.0[/b]

[b]IA — FlipBot (7/n): istruzioni per scenario[/b]
- Implementato il sottoinsieme automatizzabile delle regole speciali del FlipBot: negli scenari di "sortita/ritirata" (No Quarter, Breakout, Ritirata, Raid — scenari 7/8/13/20) l'IA ignora il bordo mappa nemico come obiettivo e punta invece al nemico più vicino.
- Le altre istruzioni per scenario riguardano meccaniche non modellate nel nostro motore (marcatori Obiettivo "generici", unità nascoste, segretezza della mano) e non sono applicabili.

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
