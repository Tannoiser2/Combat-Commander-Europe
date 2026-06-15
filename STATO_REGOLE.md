# Stato delle regole — Port Godot vs Regolamento CC:E

Mappa punto per punto tra il **motore Godot** (il prodotto, `godot/`) e il
regolamento di *Combat Commander: Europe* (20th Anniversary). Il riferimento
completo è l'app **React** (`_recupero_react/` + `ROADMAP.md`), da cui si porta.

Legenda: ✅ implementato e fedele · 🟡 parziale/semplificato · ❌ mancante.

_Aggiornato: 2026-06-15._

## Quadro sintetico

Il **ciclo di combattimento base** è completo (muovi → fuoco/avanzata/melee →
recupero/rotta) con IA che gioca la propria mano. Manca il **cuore di CC:E**: il
**Mazzo del Fato come motore di dadi + conseguenze** (oggi i dadi sono RNG 2d6,
quindi azioni/eventi/conseguenze non scattano). Stima copertura motore: ~35-40%.

## Punto per punto

| Area regolamento | Stato | Dettaglio |
|---|---|---|
| Mazzo del Fato (dadi) | ✅ | I tiri (fuoco/melee/recupero/rotta) pescano i dadi dalla carta in cima al mazzo (`Fate.gd`); fallback RNG solo se mazzo+scarti vuoti. |
| Conseguenze carta | ✅🟡 | Tempo!, Cecchino (colpisce l'hex + ripara armi), Inceppamento (arma fuori uso nel fuoco) ed **Evento** (dispatcher `Events.gd`) implementate. |
| Sequenza di gioco | 🟡 | Turni a blocchi (umano → IA). Manca alternanza carta-per-carta + finestra di reazione. |
| Mano e scarti | 🟡 | Pesca/scarto/rimescolo OK; mano **fissa a 4** (non per Postura: Att 6/Recon 5/Dif 4); nessun limite di scarto per nazione. |
| Ordine Mossa | 🟡 | Costo terreno + stacking. Manca bonus strada (ignorato in `move_cost`), lati esagono, malus PM armi, uscita mappa, attivazione multi-unità via leader. |
| Ordine Fuoco (O20) | ✅🟡 | Gruppo co-locato + Comando + copertura + 2d6 + rottura→eliminazione. Manca hindrance, elevazione, ordnance/Targeting Roll, gruppo multi-esagono. |
| Avanzata + Corpo a corpo (O21) | ✅ | Adiacenza, ΣFP+riquadri+Comando+2d6, pareggio al non-iniziativa, perdente perde tutto. |
| Recupero (O22) | ✅ | 2d6 ≤ Morale (+Comando nell'hex). |
| Rotta (O23) | ✅ | N = 2d6 − Morale verso il bordo amico; intrappolata+nemico adiacente → eliminata. |
| Passa | ✅ | Scarto + fine turno. |
| Artiglieria (O18/ARTY) | ❌ | Carte ARTY/ARTY_DENIED scartate: niente radio/spotter, Targeting Roll, scatter. |
| Azioni (carte A) | 🟡 | `Actions.gd` + `Game.play_action` (click destro su una carta). Implementate: Ferite leggere (recupero), Trincerarsi (buca→+copertura), Mimetizzazione (nascondimento→+morale), Granate fumogene (fumo→hindrance), Bombe a mano (attacco ravvicinato). I modificatori di fuoco (Fuoco Incrociato/Sostenuto/Sventagliata/Mirato/Assalto) e i marker nascosti (mine/filo/casamatta/unità nascoste) sono loggati come non simulati. |
| Eventi (carte E) | 🟡 | Dispatcher `Events.gd` + eventi realizzabili coi sistemi attuali: Supporto aereo, Macerie, Shock da combattimento, Ucciso in azione, Infiltrazione, Fuoco di soppressione, Acquattarsi, Temprati, Zappatori (no-op). Quelli che richiedono marker/Casualty Track/chit obiettivo sono loggati come «non simulato». |
| Comando/Leadership | 🟡 | Bonus nello stesso esagono ✅; raggio di Comando multi-esagono ❌ (`Rules.has_command_at` esiste, non usato). |
| Linea di vista (LOS) | ✅🟡 | Linea di esagoni corretta (cube_round) + blocco da terreno opaco, **lati muro/siepe (intermedi) e bocage**, **varco LOS_CLEAR**, **hindrance cumulativo** (frutteto/campo/macchia) ed **elevazione** base. Restano cresta collina (T88.1), gully (T86), blind hex (T88.4), grazing, fumo. |
| Terreno & movimento | ✅🟡 | Costi terreno + acqua impassabile ✅; **attraversamento lati** (muro/siepe/bocage/torrente +1, dirupo impassabile) e **tariffa strada** (1 PM lungo strada) ✅. Restano trail, double-time, malus PM armi. |
| Armi | 🟡 | Sparano come unità. Manca trasporto/pairing 1↔1 (8.1.1), ordnance+minRange, FP radio, cattura/recupero, armi rotte/inceppate. |
| Impilamento (8.1) | 🟡 | Max **8 uomini**/hex; il regolamento è **7 figure** (squad 4/team 2/leader 1). |
| Traccia Tempo & Morte Subitanea | ✅🟡 | Il tempo ora avanza **solo** con un Tempo! pescato dal Fato (corretto); Tempo! dà +1 VP al difensore e rimescola i mazzi. Restano gli altri effetti della traccia (dig-in, rinforzi, rimozione fumo, auto-vittoria su 5 obiettivi). |
| Obiettivi / VP / Chit (7.3) | ✅🟡 | Controllo (più uomini nell'hex) e bilancia VP **aggiornati a ogni azione**; **vittoria automatica** controllando tutti gli obiettivi (`Game._update_objectives`/`_check_end_conditions`). Restano i chit (segreti/aperti, 22), VP da eliminazione/uscita. |
| Resa / Casualty Track | ❌ | Valori di resa inutilizzati; nessuna traccia perdite/resa/rinforzi. |
| Fortificazioni & marker | 🟡 | Buca/trincea (Trincerarsi → `HexData.has_foxhole`, +2 copertura) e fumo (Granate fumogene → `HexData.has_smoke`, hindrance) implementati. Restano mine, filo spinato, casamatta, incendio. |
| Fuoco di Opportunità (A33) | ✅🟡 | Durante il movimento, il difensore reagisce col miglior tiratore idoneo (efficiente, in gittata/LOS, no mortai/cannoni); può interrompere il movimento se rompe il mover (`OpFire.gd`, `Game._op_fire`). Per ora il tiratore è scelto automaticamente (manca la scelta interattiva del giocatore). |
| Fazioni & mazzi | 🟡 | Solo Germania+Russia (2/6); dati carta completi ma si usa solo l'ordine. No routing fazione→mazzo. |
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
