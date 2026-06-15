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
| Mazzo del Fato (dadi) | ❌ | I tiri usano RNG 2d6, non i dadi della carta pescata. Blocca azioni/eventi/conseguenze. |
| Sequenza di gioco | 🟡 | Turni a blocchi (umano → IA). Manca alternanza carta-per-carta + finestra di reazione. |
| Mano e scarti | 🟡 | Pesca/scarto/rimescolo OK; mano **fissa a 4** (non per Postura: Att 6/Recon 5/Dif 4); nessun limite di scarto per nazione. |
| Ordine Mossa | 🟡 | Costo terreno + stacking. Manca bonus strada (ignorato in `move_cost`), lati esagono, malus PM armi, uscita mappa, attivazione multi-unità via leader. |
| Ordine Fuoco (O20) | ✅🟡 | Gruppo co-locato + Comando + copertura + 2d6 + rottura→eliminazione. Manca hindrance, elevazione, ordnance/Targeting Roll, gruppo multi-esagono. |
| Avanzata + Corpo a corpo (O21) | ✅ | Adiacenza, ΣFP+riquadri+Comando+2d6, pareggio al non-iniziativa, perdente perde tutto. |
| Recupero (O22) | ✅ | 2d6 ≤ Morale (+Comando nell'hex). |
| Rotta (O23) | ✅ | N = 2d6 − Morale verso il bordo amico; intrappolata+nemico adiacente → eliminata. |
| Passa | ✅ | Scarto + fine turno. |
| Artiglieria (O18/ARTY) | ❌ | Carte ARTY/ARTY_DENIED scartate: niente radio/spotter, Targeting Roll, scatter. |
| Azioni (carte A) | ❌ | `ActionType` definito ma inutilizzato. Niente Fuoco d'Assalto, Bombe a mano, Op Fire, Mimetizzazione, Trincerarsi, Fumogene… |
| Eventi (carte E) | ❌ | Nessuno (React: 35+). |
| Comando/Leadership | 🟡 | Bonus nello stesso esagono ✅; raggio di Comando multi-esagono ❌ (`Rules.has_command_at` esiste, non usato). |
| Linea di vista (LOS) | 🟡 | Blocco da terreno + interpolazione ✅. Manca hindrance cumulativo, lati (muro/siepe/dirupo), cresta/elevazione (T88.1), gully (T86), blind hex (T88.4), fumo. `side_features` caricato/disegnato ma non consultato dalla LOS. |
| Terreno & movimento | 🟡 | Tabella costi + acqua impassabile ✅; strada/trail/lati/elevazione/double-time/malus armi non applicati. |
| Armi | 🟡 | Sparano come unità. Manca trasporto/pairing 1↔1 (8.1.1), ordnance+minRange, FP radio, cattura/recupero, armi rotte/inceppate. |
| Impilamento (8.1) | 🟡 | Max **8 uomini**/hex; il regolamento è **7 figure** (squad 4/team 2/leader 1). |
| Traccia Tempo & Morte Subitanea | 🟡 | `time_marker` cresce ogni fine turno → fine a spazio fisso. Manca Time! pescato dal Fato e gli effetti della traccia (rimuovi fumo, dig-in, rinforzi, +1 VP difensore, auto-vittoria su 5 obiettivi). |
| Obiettivi / VP / Chit (7.3) | 🟡→❌ | Controllo = più uomini nell'hex; VP calcolati **solo alla Morte Subitanea**. Niente chit (segreti/aperti, 22), VP cumulativi, VP da eliminazione/uscita, auto-win. |
| Resa / Casualty Track | ❌ | Valori di resa inutilizzati; nessuna traccia perdite/resa/rinforzi. |
| Fortificazioni & marker | ❌ | Foxhole, trincea, filo, mine, pillbox, fumo, incendio: assenti. |
| Fuoco di Opportunità (A33) | ❌ | Fasi `REACTION_WINDOW`/`AI_OPP_FIRE` dichiarate ma vuote. |
| Fazioni & mazzi | 🟡 | Solo Germania+Russia (2/6); dati carta completi ma si usa solo l'ordine. No routing fazione→mazzo. |
| Iniziativa | 🟡 | Tracciata, usata per il pareggio in melee; nessuno scambio/re-roll. |
| IA | 🟡 | Gioca la mano (fuoco/avanzata/recupero/rotta/mossa) con euristiche semplici. Manca copertura, rischio reattivo, difesa obiettivi. |
| Scenari | 🟡 | Solo Scenario 1 giocabile in Godot (selettore lista 24; mappe in digitalizzazione). |
| Unità speciali (Eroe, Promozione…) | ❌ | Guidate da eventi → assenti. |
| Test & CI | ✅ | Test motore headless + gate CI (no `SCRIPT ERROR` + `TEST_RESULT: PASS`). |

## Prossime priorità (in ordine)

1. **Mazzo del Fato come motore di dadi + conseguenze** (jam/sniper/Time!/eventi) — prerequisito di quasi tutto.
2. **Aggiornamento continuo controllo obiettivi + VP** (oggi solo a fine partita).
3. **LOS/terreno completi** (lati esagono già caricati: siepe/muro/dirupo + hindrance + elevazione).
4. **Op Fire (A33)** durante il movimento.
5. **Azioni base (carte A)**, poi **Eventi (carte E)**.
