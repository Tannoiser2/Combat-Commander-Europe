# Stato delle regole — Port Godot vs Regolamento CC:E

Mappa punto per punto tra il **motore Godot** (il prodotto, `godot/`) e il
regolamento di *Combat Commander: Europe* (20th Anniversary). Il riferimento
completo è l'app **React** (`_recupero_react/` + `ROADMAP.md`), da cui si porta.

Legenda: ✅ implementato e fedele · 🟡 parziale/semplificato · ❌ mancante.

_Aggiornato: 2026-06-15._

## Quadro sintetico

Il **ciclo di combattimento** gira sul **Mazzo del Fato** (dadi pescati dalle
carte + conseguenze Tempo!/Cecchino/Inceppamento/Evento): ordini completi
(mossa/fuoco/avanzata-melee/recupero/rotta), IA che gioca la mano, LOS e terreno
avanzati, obiettivi/VP live con auto-vittoria, Fuoco di Opportunità, azioni base
e **resa per Casualty Track** + **mano per qualità truppe** per scenario.
Restano soprattutto: **Artiglieria**, **chit obiettivo segreti**, i **marcatori
del Casualty Track** veri e propri (rinforzi/recupero armi), **modificatori di
fuoco/melee** e gli **eventi/azioni** che richiedono marker non ancora
modellati, **altre 4 fazioni/mazzi** e la fedeltà piena degli **scenari 2-24**.
Stima copertura motore: ~70%.

## Punto per punto

| Area regolamento | Stato | Dettaglio |
|---|---|---|
| Mazzo del Fato (dadi) | ✅ | I tiri (fuoco/melee/recupero/rotta) pescano i dadi dalla carta in cima al mazzo (`Fate.gd`); fallback RNG solo se mazzo+scarti vuoti. |
| Conseguenze carta | ✅🟡 | Tempo! (avanza tempo + rimuove un fumo + reshuffle + 1 VP difensore), Cecchino (rompe **una** unità in/adiacente all'hex), Inceppamento (arma fuori uso nel fuoco) ed **Evento** (dispatcher `Events.gd`). |
| Sequenza di gioco | 🟡 | Turni a blocchi (umano → IA). Manca alternanza carta-per-carta + finestra di reazione. |
| Mano e scarti | ✅🟡 | Pesca/scarto/rimescolo OK; **dimensione mano per fazione** dallo scenario (qualità truppe `mano_axis/allies`, scartata e ripescata 1↔1 a mantenere la mano). Resta il limite di scarto per nazione. |
| Ordine Mossa | 🟡 | Costo terreno + stacking. Manca bonus strada (ignorato in `move_cost`), lati esagono, malus PM armi, uscita mappa, attivazione multi-unità via leader. |
| Ordine Fuoco (O20) | ✅🟡 | Gruppo (FP pezzo migliore **+1/aggiuntivo**) + Comando − hindrance, **Attacco vs Fire Defense Roll** (Morale+copertura+dadi del difensore): difesa< → rotta/eliminata; pareggio → rotta se in movimento, altrimenti **soppressa**; difesa> → nessun effetto. Suppress e Break sono ora stati distinti. Manca ordnance/Targeting Roll, tiro di difesa per-unità (ora per-esagono), gruppo multi-esagono. |
| Corpo a corpo (O16.4) | ✅ | Adiacenza, ΣFP (no Comando) + riquadri + 2d6; lato più debole eliminato, **pareggio → entrambi eliminati** (salvo Bunker/Pillbox). |
| Recupero (O22) | ✅ | 2d6 ≤ Morale (+Comando nell'hex). |
| Rotta (O23) | ✅ | N = 2d6 − Morale verso il bordo amico; intrappolata+nemico adiacente → eliminata. |
| Passa | ✅ | Scarto + fine turno. |
| Ordnance / mortai (O20.2) | ✅🟡 | Mortai e cannoni (`Unit.ordnance`/`min_range`): **Targeting Roll** (d1×d2 > gittata+hindrance) prima del Fire Attack, gittata minima, niente Comando/hindrance sull'FP, esclusi da gruppo di fuoco e Op Fire (11.5). Restano i colpi fumogeni (O20.2.1). |
| Artiglieria via Radio (O18) | ❌ | Le radio (artiglieria fuori mappa) sono saltate dal loader: niente spotter/Spotting Round, scatter. (I mortai in mappa funzionano, vedi Ordnance.) |
| Azioni (carte A) | 🟡 | `Actions.gd` + `Game.play_action` (click destro su una carta). Implementate: Ferite leggere (recupero), Trincerarsi (buca→+copertura), Mimetizzazione (nascondimento→+morale), Granate fumogene (fumo→hindrance), Bombe a mano (attacco ravvicinato). I modificatori di fuoco (Fuoco Incrociato/Sostenuto/Sventagliata/Mirato/Assalto) e i marker nascosti (mine/filo/casamatta/unità nascoste) sono loggati come non simulati. |
| Eventi (carte E) | 🟡 | Dispatcher `Events.gd` + eventi realizzabili coi sistemi attuali: Supporto aereo, Macerie, Shock da combattimento, Ucciso in azione, Infiltrazione, Fuoco di soppressione, Acquattarsi, Temprati, Zappatori (no-op). Quelli che richiedono marker/Casualty Track/chit obiettivo sono loggati come «non simulato». |
| Comando/Leadership | 🟡 | Bonus nello stesso esagono ✅; raggio di Comando multi-esagono ❌ (`Rules.has_command_at` esiste, non usato). |
| Linea di vista (LOS) | ✅🟡 | Linea di esagoni corretta (cube_round) + blocco da terreno opaco, **lati muro/siepe (intermedi) e bocage**, **varco LOS_CLEAR**, **hindrance cumulativo** (frutteto/campo/macchia) ed **elevazione** base. Restano cresta collina (T88.1), gully (T86), blind hex (T88.4), grazing, fumo. |
| Terreno & movimento | ✅🟡 | Costi terreno + acqua impassabile ✅; **attraversamento lati** (muro/siepe/bocage/torrente +1, dirupo impassabile) e **tariffa strada** (1 PM lungo strada) ✅. Restano trail, double-time, malus PM armi. |
| Armi | ✅🟡 | Sparano come unità con **statistiche esatte per nazione** (carta ufficiale) e **ordnance+gittata minima** per mortai/cannoni. Manca trasporto/pairing 1↔1 (8.1.1), FP radio, cattura/recupero, armi rotte/inceppate. |
| Impilamento (8.1) | ✅ | Max **7 soldier icons**/hex (squad 4, leader 1, armi 0); applicato a movimento/avanzata/IA. (`Unit.soldier_icons`, `GameState.soldier_icons_at`) |
| Traccia Tempo & Morte Subitanea | ✅🟡 | Il tempo avanza **solo** con un Tempo! (corretto); Tempo! dà +1 VP al difensore, rimuove un fumo e rimescola i mazzi. **Morte Subitanea come tiro (6.2.2)**: quando il segnalino Tempo entra in/oltre la casella di Morte Subitanea, il giocatore che ha innescato il Tempo pesca 2d6; se il risultato è < numero della casella Tempo la partita finisce (vincitore ai VP, 6.3.2), altrimenti prosegue. Segnalino Tempo iniziale = casella `tempo_iniziale` (default 0). Restano dig-in e rinforzi della traccia. |
| Obiettivi / VP / Chit (7.3) | ✅🟡 | Controllo (più uomini nell'hex) e bilancia VP **aggiornati a ogni azione**; **vittoria automatica** controllando tutti gli obiettivi (`Game._update_objectives`/`_check_end_conditions`). Restano i chit (segreti/aperti, 22), VP da eliminazione/uscita. |
| Resa / Casualty Track | ✅🟡 | **Resa implementata** (6.3/6.3.1): ogni uomo eliminato (no armi) conta come perdita della sua fazione; al raggiungimento della soglia di resa dello scenario (`resa_axis/allies`) la fazione perde, a prescindere dai VP; doppia resa simultanea → vince chi ha l'iniziativa. Restano i **marcatori** del track per rinforzi/recupero armi. |
| Fortificazioni & marker | 🟡 | Buca/trincea (Trincerarsi → `HexData.has_foxhole`, +2 copertura) e fumo (Granate fumogene → `HexData.has_smoke`, hindrance) implementati. Restano mine, filo spinato, casamatta, incendio. |
| Fuoco di Opportunità (A33) | ✅🟡 | Durante il movimento, il difensore reagisce col miglior tiratore idoneo (efficiente, in gittata/LOS, no mortai/cannoni); può interrompere il movimento se rompe il mover (`OpFire.gd`, `Game._op_fire`). Per ora il tiratore è scelto automaticamente (manca la scelta interattiva del giocatore). |
| Fazioni & mazzi | ✅🟡 | **Counter reali per tutte e 6 le nazioni** (fronte+rovescio, `assets/counters/`, mappa `(nazione,etichetta)→file`). Statistiche esatte per nazione. Restano i **mazzi** delle 4 nazioni mancanti (dati non disponibili nel repo): si usa il routing stand-in (Asse→tedesco, Alleati→russo). |
| Iniziativa | 🟡 | Tracciata, usata per il pareggio in melee; nessuno scambio/re-roll. |
| IA | 🟡 | Gioca la mano (fuoco/avanzata/recupero/rotta/mossa) con euristiche semplici. Manca copertura, rischio reattivo, difesa obiettivi. |
| Scenari | 🟡 | Solo Scenario 1 giocabile in Godot (selettore lista 24; mappe in digitalizzazione). |
| Unità speciali (Eroe, Promozione…) | ❌ | Guidate da eventi → assenti. |
| Test & CI | ✅ | Test motore headless + gate CI (no `SCRIPT ERROR` + `TEST_RESULT: PASS`). |

## Prossime priorità (in ordine)

1. ~~Mazzo del Fato come motore di dadi + conseguenze~~ ✅ **fatto** (resta da implementare gli handler dei singoli **Eventi**).
2. ~~Aggiornamento continuo controllo obiettivi + VP~~ ✅ **fatto** (+ auto-vittoria; restano i chit obiettivo).
3. ~~LOS/terreno: lati esagono + hindrance + elevazione~~ ✅ **fatto** (restano cresta/gully/blind hex/grazing/fumo).
4. ~~Op Fire (A33) durante il movimento~~ ✅ **fatto** (resta la scelta interattiva del tiratore).
5. ~~Azioni base (carte A)~~ ✅ **fatto** (restano i modificatori di fuoco e i marker nascosti); **Eventi (carte E)** completi ancora da fare.
6. **Chit obiettivo** (segreti/aperti, VP cumulativi).
