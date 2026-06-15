# Combat Commander Roadmap

## Legenda

| Stato | Significato |
| --- | --- |
| 🟢 Fatto | Implementato e verificato almeno con `npm run check`. |
| 🟡 Da fare | Necessario o utile, ma non bloccante per la vertical slice. |
| 🔴 Critico | Mancanza importante per fedeltà alle regole o stabilità del gioco. |

## Stato Attuale (aggiornato 2026-05-20)

| Stato | Area | Note |
| --- | --- | --- |
| 🟢 Fatto | App | App Vite/React in `app/`, build pulito, 89/89 test passano. |
| 🟢 Fatto | Regole | Regolamento, manifest carte, scenari, esempio di gioco e playbook letti dal PDF locale. |
| 🟢 Fatto | Carte | **Tutti i 6 mazzi Fato implementati** (72 carte ciascuno: German, Russian, American, British, Italian, French). Routing fazione→mazzo per Commonwealth/Minor. |
| 🟢 Fatto | Mappe immagini | **24 mappe ufficiali integrate** (mappa1.png…mappa24.png) per tutti gli scenari, calibrazione per scenario, auto-fit zoom alla viewport. |
| 🟡 In corso | Mappe terreno | Scenari 1-2 hanno dati terreno completi. Scenari 3-24 hanno scaffold pronti, da editare con l'editor mappa. |
| 🟢 Fatto | Setup automatico IA | `autoSetup.ts`: leader spread (≥2 hex apart, score su obiettivi per Defender / asse avanzata per Attacker), squad/team dentro raggio comando di un leader, weapon su hex con squad/team. Marker (Wire, Foxhole, Trench, Mines, Pillbox) saltati. |
| 🟢 Fatto | Setup anchor-based | Campi `axisSetupAnchors`/`alliedSetupAnchors` su ScenarioMeta: lista di hex label (es. ['A2','O1']) — unità piazzate IN o ADIACENTI a un anchor. Override su edge+depth quando presente. |
| 🟢 Fatto | Editor mappa | Editor con icone PNG esagonali (terreno, feature, hexside), nido d'ape, persistenza su file sorgente. |
| 🟢 Fatto | Splash scenari | Selettore con lista 24 scenari + banner verticale pittorico + pannello dettagli + ordine di battaglia. |
| 🟢 Fatto | Catalogo scenari | Tutti i 24 scenari con dati ufficiali estratti dal manuale (fazioni, ordini, hand size, sudden death, VP, posture, iniziativa, humanSide). |
| 🟢 Fatto | Ordini di battaglia | OB completo per tutti i 24 scenari in `scenarioOBs.ts` con resa, leader, squadre, weapon team, fortificazioni. |

## Port Godot 4.x — stato del motore (aggiornato 2026-06-15)

Il **prodotto attuale è il port in Godot** (`godot/`, vedi `README.md`). La ROADMAP
sopra descrive l'app **React** di riferimento (`_recupero_react/`), da cui si porta
la logica regola per regola. Stato del motore Godot:

| Stato | Area | Note Godot (file) |
| --- | --- | --- |
| 🟢 Fatto | Scenario 1 | Mappa, obiettivi, mazzi German/Russian, turni, traccia Tempo, fine partita. |
| 🟢 Fatto | Modello rottura (break) | `Unit.efficient` = lato pedina. Fuoco ≥ Morale **rompe** un'unità efficiente; un secondo colpo la **elimina**. `effective_fp()` dimezza il lato rotto. (`Unit.gd`, `Combat.gd`) — sostituisce il vecchio «≥ morale+4 = morto». |
| 🟢 Fatto | Gruppo di fuoco + Comando | FP = Σ unità co-locate in gittata + Comando del miglior leader nell'esagono. (`Combat.fire_group`, `Rules.command_bonus_at`) |
| 🟢 Fatto | Recupero (O22) | Tiro 2d6 ≤ Morale (+Comando) **per unità**, non più azzeramento globale. (`Rules.try_recover`, `Game._execute_recover`) |
| 🟢 Fatto | Avanzata + Corpo a corpo (O21) | Avanzata di 1 esagono; in esagono nemico → melee: ΣFP + riquadri + Comando + 2d6; pareggio a chi **non** ha l'iniziativa; il perdente perde **tutte** le unità. (`Rules.resolve_melee`, `Game._execute_advance`) |
| 🟢 Fatto | Rotta (O23) | N = (2d6 − Morale) esagoni verso il bordo amico, lontano dai nemici; intrappolata + nemico adiacente → eliminata. (`Rules.rout_unit`, `Game._execute_rout`) |
| 🟢 Fatto | Ordini giocabili dalla mappa | MOVE/FIRE/ADVANCE con selezione bersaglio + evidenziazione; ROUT/RECOVER immediati. (`Game.play_card`, `HexMap._on_click`, `GameState.current_order`) |
| 🟢 Fatto | Test motore headless | `godot/tests/TestRunner.tscn` + workflow CI `tests.yml` (Godot 4.6.3): controlli su fuoco/comando/recupero/melee/rotta. |
| 🟡 Da fare | Conseguenze carta | jam/sniper/time/event non gestite alla pescata; il fuoco usa 2d6 RNG, non i dadi del Fato della carta. |
| 🟡 Da fare | Artiglieria | Ordini ARTY/ARTY_DENIED ancora scartati: mancano Targeting Roll, spotter/LOS, scatter. |
| 🟡 Da fare | Comando multi-esagono | Gruppo di fuoco solo co-locato; manca l'attivazione di unità nel raggio di Comando su esagoni diversi. |
| 🟢 Fatto | IA che gioca la mano | `AI.gd`: l'IA sceglie e risolve fino a `ai_max_orders` ordini dalla propria mano (Fuoco col bersaglio migliore, Avanzata in melee vantaggiosa, Recupero/Rotta delle unità rotte, Mossa verso l'obiettivo più vicino). (`AI.choose_play`, `Game._ai_execute`) |
| 🟡 Da fare | IA avanzata | Valutazioni più fini: copertura, rischio di fuoco reattivo, difesa degli obiettivi propri, scelta del gruppo di fuoco multi-esagono. |
| 🟡 Da fare | Scenari 2-24 (Godot) | In Godot esiste solo lo Scenario 1; dati scenario/OB e terreno mappe da portare (mappe in digitalizzazione). |

## Milestone 0: Base Tecnica

| Stato | Voce | Note |
| --- | --- | --- |
| 🟢 Fatto | Build e lint | `npm run build` e `npm run lint` verdi. |
| 🟢 Fatto | Test suite | **88 test passano** (3 file: cards, combat, los). |
| 🟢 Fatto | Git | Progetto versionato dalla root. |
| 🟡 Da fare | Documentazione tecnica | Documentare comandi, limiti, perimetro della vertical slice e architettura store. |

## Milestone 1: Mazzo Fato Come Motore

| Stato | Voce | Note |
| --- | --- | --- |
| 🟢 Fatto | Dadi da mazzo | Pescate dal mazzo per fuoco, difesa, recupero, rotta, morte improvvisa, targeting ordnance. |
| 🟢 Fatto | Conseguenze eventi | 35+ eventi del mazzo implementati. EROE ora spawna una vera unità Hero. |
| 🟢 Fatto | Conseguenza Time! completa | +1 VP difensore, rimozione smoke, reshuffle deck+discard di entrambe le fazioni, advance time. |
| 🟢 Fatto | Conseguenza Sniper corretta | Usa il `randomHexLabel` della carta (hex mappa), non più modulo random; ripara armi rotte; colpisce tutte le unità nemiche nell'hex. |
| 🟢 Fatto | Scarti e mano | Separazione tra mano, mazzo e scarti, refill a hand size per fazione. |
| 🟢 Fatto | Hand size per scenario | `axisHandSize`/`alliedHandSize` per ogni scenario (Green=4, Line=5, Elite=6) basato su Troop Quality del manuale. |
| 🟢 Fatto | Mazzi minori | British, Italian, French aggiunti (72 carte cad.). Routing: canadian/anzac→British, polish/yugoslav→French, romanian→Italian, brazilian→American. |
| 🟢 Fatto | Test mazzo | Validazione `buildDeck` (72 carte, no duplicati, dadi 1-6, ordini validi) su tutti e 6 i deck. |

## Milestone 2: Ordini Principali

| Stato | Voce | Note |
| --- | --- | --- |
| 🟢 Fatto | Limite ordini | Per fazione da scenario. |
| 🟢 Fatto | Comando | Leader attiva unità non-Comandante nel raggio per lo stesso Ordine; bonus FP nello stesso esagono. |
| 🟡 Da fare | Movimento | Costi terreno, road, hexside features OK. Mancano: uscita mappa con VP, interdizione completa, dig-in da Time!. |
| 🟢 Fatto | Fuoco | LOS, copertura, hindrance, elevazione, gruppo di fuoco (O20.3), armi come supporto, mortai/radio esclusi. |
| 🟢 Fatto | Fuoco multi-esagono | Unità attivate da leader formano gruppo da esagoni diversi con catena di adiacenza. |
| 🟢 Fatto | Avanzata | Adiacenza, melee con vera resoluzione CC:E O21 (Melee Total = ΣFP+2d6, loser perde unità con morale più basso). |
| 🟢 Fatto | Recupero | Tie-break corretto `roll ≤ morale` = success. |
| 🟢 Fatto | Rotta | Morale Roll vs target: success → retreat fino a 2 hex; fail → nessun effetto; elimina solo se senza via di fuga. |
| 🟢 Fatto | Artiglieria | LOS spotter→target, Targeting Roll (d1×d2 ≥ range), scatter su miss, FP reale della radio. |
| 🟡 Da fare | Passare | Scarto mano implementato. Da raffinare con selezione parziale. |
| 🟢 Fatto | Armi (trasporto) | CC:E 8.1.1: pairing 1 weapon ↔ 1 carrier, weapon eccedenti restano nell'esagono di origine; `carriedWeaponId` tracciato durante l'ordine e azzerato a fine ordine. Applicato sia a Move sia ad Advance. |

## Milestone 2b: Azioni Giocabili

| Stato | Voce | Note |
| --- | --- | --- |
| 🟢 Fatto | UI azioni | Azioni cliccabili dalla banda della carta. |
| 🟢 Fatto | Azioni di fuoco | Buona Mira, Fuoco Mirato, Fuoco Incrociato, Fuoco Sostenuto, Sventagliata, Fuoco d'Assalto, Bombe a Mano, Imboscata, Lotta Senza Quartiere. |
| 🟢 Fatto | Azioni utility | Ferite Leggere, Trincerarsi, Trinceramenti Nascosti, Mimetizzazione, Unità Nascosta, Granate Fumogene. |
| 🟢 Fatto | Marker mappa | Mine, filo spinato, casamatta, demolizioni, smoke (rimosso da Time!), foxholes/trench. |
| 🟢 Fatto | Azioni reattive | OP Fire con scelta sparatore umano, fuoco OP annullabile, finestra di reazione. |
| 🟡 Da fare | IA azioni | Agganciare azioni più sofisticate all'IA (oltre alle azioni di base già supportate). |

## Milestone 2c: Fuoco di Opportunità (A33)

| Stato | Voce | Note |
| --- | --- | --- |
| 🟢 Fatto | A33.3 ex.1 — Artiglieria esclusa | Mortai e radio esclusi da OP fire. |
| 🟢 Fatto | A33.3 ex.2 — Attivazione persistente | `opFireActivatedIds` tracciato; svuotato a fine Movimento. |
| 🟢 Fatto | A33.3 ex.3 — Max 1 fuoco per passo | `opFireUsedThisStep` con reset. |
| 🟢 Fatto | Scelta sparatore AI | IA sceglie sparatore con FP più alto. |
| 🟢 Fatto | Scelta sparatore umano | Pannello UI con conferma/annulla. |
| 🟡 Da fare | OP Fire a gruppo | Solo 1 unità spara OP per passo; verificare se le regole ammettono gruppo. |

## Milestone 3: Dati Scenario e Mappa

| Stato | Voce | Note |
| --- | --- | --- |
| 🟢 Fatto | Scenario 1 e 2 | Dati completi (mappa, OB, obiettivi, posture, hand size). |
| 🟡 In corso | Scenari 3-24 dati mappa | **Tutte le 24 immagini PNG integrate** (mappa1.png…mappa24.png), scaffold `scenarioN.ts` creati, registry in `gameStore`, save-map-plugin esteso. Mancano i dati terreno/hexside per scenari 3-24 (da disegnare con l'editor). |
| 🟢 Fatto | Setup unità scenari 3-24 | autoPlaceScenario pesca dall'OB e piazza unità nelle zone (edge default: Axis=east, Allied=west; depth default=3). Leader narrative → chart per prefisso (Lt/Sgt/Cpl/Cpt/Private). |
| 🟢 Fatto | Terreni | Catalogo terreno centralizzato; road, railway, trail; side features (fence/hedge/wall/cliff/bridge/gap). |
| 🟢 Fatto | LOS base | Hindrance, ostacoli, Gully (T86), Blind Hex (T88.4.1). |
| 🟢 Fatto | LOS avanzata | Wall/hedge/cliff agli estremi, cresta collina (T88.1), grazing pair OR-blocking, gap esplicito per LOS libera tra hex obstacle. |
| 🟢 Fatto | Smoke/Concealment hindrance | Spostati da cover a hindrance (corretto per CC:E). |
| 🟡 Da fare | Coerenza log | Correggere incongruenze residue tra commenti, costanti e log. |

## Milestone 3b: Chart e Counter Data

| Stato | Voce | Note |
| --- | --- | --- |
| 🟢 Fatto | Unit Chart | Catalogo centrale leader/squad/team con retro-dimezzati. |
| 🟢 Fatto | Weapon Chart | Catalogo armi/radio con FP, range, minRange, movePenalty, ordnance, smoke. |
| 🟢 Fatto | Propagazione stat | `attachWeaponChart` passa ordnance/minRange a `Unit.stats`. |
| 🟢 Fatto | Enforcement ordnance | `canUnitFireAt` e `getFireTargets` rispettano minRange; Targeting Roll automatico per mortai/cannoni. |
| 🟡 Da fare | Integrazione completa | Manifest agganciati, ma alcuni dati (es. radio FP per artiglieria) potrebbero non essere ancora del tutto consistenti. |

## Milestone 4: Carte Complete

| Stato | Voce | Note |
| --- | --- | --- |
| 🟢 Fatto | Mazzi Asse | German + Italian (Axis Minors: Romanian) implementati. |
| 🟢 Fatto | Mazzi Alleati | Russian + American + British (Commonwealth: Canadian, ANZAC) + French (Allied Minors: Polish, Yugoslav). |
| 🟢 Fatto | Dati carta | Ordini, azioni, eventi, esagono casuale, dadi reali, trigger Jam/Sniper/Event/Time. |
| 🟢 Fatto | Routing fazione→mazzo | `deckForFaction` mappa correttamente fazioni minori al deck condiviso. |
| 🟢 Fatto | Bug INFILTRAZIONI→INFILTRAZIONE | Uniformato evento orfano nel mazzo russo (cards.ts + handler). |
| 🟡 Da fare | Diff completo manifest | Audit riga-per-riga per i 3 mazzi nuovi (British/Italian/French) per allineare azioni/eventi rari con la traduzione italiana ufficiale. |

## Milestone 4b: Conformità Regolamento Ufficiale (CC-20thAnniv)

Cross-check con il rulebook ufficiale (24 pagine) ha rivelato e corretto:

| Categoria | Voce | Stato |
| --- | --- | --- |
| Eventi | E43 Air Support (era +2 VP) → rompi tutte unità in hex random | 🟢 Fix |
| Eventi | E44 Battle Harden — sceglie unità non-veterana, no "prima nell'hex" | 🟢 Fix |
| Eventi | E46 Blaze — Blaze marker, evacuazione, no smoke surrogate | 🟢 Fix |
| Eventi | E48 Breeze — rimuovi tutto smoke + sposta Blaze adiacente | 🟢 Fix |
| Eventi | E51 Cower — sopprime squadre fuori Command Radius | 🟢 Fix |
| Eventi | E52 Deploy — divide squad in 2 team (era suppress su dado) | 🟢 Fix |
| Eventi | E54 Élan — sposta Surrender marker (era +1 VP) | 🟢 Fix |
| Eventi | E55 Entrench — Foxholes su hex amico (no Water/Fortification) | 🟢 Fix |
| Eventi | E56 Field Promotion — spawn Private leader (era Veteran) | 🟢 Fix |
| Eventi | E57 Fog of War — scambia carta random dalle mani (era unconceal) | 🟢 Fix |
| Eventi | E59 Infiltration — suppress unità con Cover <1 (era +1 VP) | 🟢 Fix |
| Eventi | E62 KIA — sceglie qualsiasi unità broken (era leader amico) | 🟢 Fix |
| Eventi | E65 Mission Objective — nuovo Objective segreto (era +VP) | 🟢 Fix |
| Eventi | E66 Prisoners of War — elimina broken amico adiacente nemico (era enemy weakest) | 🟢 Fix |
| Eventi | E67 Reconnaissance — rivela 1 obiettivo segreto del difensore | 🟢 Fix |
| Eventi | E68 Reinforcements — recupera unità da Casualty Track | 🟢 Fix |
| Eventi | E69 Rubble — converte hex in terreno Rubble | 🟢 Fix |
| Eventi | E70 Sappers — rimuove Mine/Wire (era piazza!) | 🟢 Fix |
| Eventi | E71 Scrounge — recupera Weapon da Casualty (era Veteran) | 🟢 Fix |
| Eventi | E72 Shell Shock — rompi unità più vicina (era suppress) | 🟢 Fix |
| Eventi | E73 Shellholes — Foxholes (era bunker marker) | 🟢 Fix |
| Eventi | E74 Strategic Objective — nuovo Objective aperto (era perdi VP) | 🟢 Fix |
| Eventi | E75 Suppressing Fire — sopprime nemico in range/LOS di MG amica | 🟢 Fix |
| Eventi | E76 Walking Wounded — recupera Weapon broken (era unsuppress) | 🟢 Fix |
| Azioni | A27 Bore Sighting — +2 FP per arma FP≥5 (era +1 FP) | 🟢 Fix |
| Azioni | A35.4 Hidden Unit — spawn Light MG nascosta sotto unità | 🟢 Fix |
| Azioni | A38 No Quarter — etnicità (German vs Russian / Russian vs any) | 🟢 Fix |
| Ordini | O18 Battery Access — repair Radio rotta se non ne hai operative | 🟢 Fix |
| Ordini | O23.2 Rout retreat N = roll − morale (era 2 hex fissi) | 🟢 Fix |
| Azioni | A35.2 Mine Attack già invocato in `triggerMinefield` | 🟢 OK |
| Azioni | A28 Command Confusion (dud as Action) | 🟢 OK |

### Modificatori chart (foglio riepilogo ufficiale)

| Categoria | Voce | Stato |
| --- | --- | --- |
| Stacking | Max **7 soldier figures/hex** (Squad=4, Team=2, Leader=1) | 🟢 Fix (rulebook 8.1: 10-uomini squad = 4 figures) |
| Discard | Limite di scarto per nazione (Germany 6 / Italy 2 / France 1, ecc.) | 🟢 Fix (era intera mano) |
| Hand size | Determinata dalla **Posture** (Attacker 6, Recon 5, Defender 4) | 🟢 Fix (era Troop Quality) |
| Time Marker | Step 4: rimuovi **UN** smoke marker (non tutti) | 🟢 Fix |
| Time Marker | Auto-win check: chi controlla tutti i 5 obiettivi vince automaticamente | 🟢 Aggiunto |
| Sniper | Colpisce 1 unità IN o ADIACENTE all'hex random, non tutte | 🟢 Fix |
| Melee | +1 FP per unità con **boxed FP** | 🟢 Fix |
| Melee | Inactive player roll FIRST (per Initiative re-roll) | 🟢 Fix |
| Melee | Bunker/Pillbox: in pareggio, attaccanti eliminati invece di entrambi | 🟢 Fix |
| Melee | Loser side: **TUTTE** le unità partecipanti eliminate (non solo una) | 🟢 Fix |
| VP unità | Leader = 1 + Command, Hero = 0, Squad = 2, Team = 1 | 🟢 OK già corretto |

### Sistema Obiettivi & Chit (7.3 Objective Victory Points)

| Categoria | Voce | Stato |
| --- | --- | --- |
| Chit | **22 chit obiettivo** modellati in `objectiveChits.ts` | 🟢 Nuovo |
| Chit | Setup automatico: 1 chit "open" + 2 segreti (uno per fazione) | 🟢 Nuovo |
| Chit | Tipi: `specific` (Obj 1-5), `all` (x5), `sd-win`, `elim-x2`, `exit-x2` | 🟢 Nuovo |
| Chit | **Cumulatività**: VP di un Obj = somma di tutti i chit (revealed) che lo riferiscono | 🟢 Nuovo |
| VP | `updateObjectiveControl` usa `objectiveVPValue` invece di `obj.vp` fisso | 🟢 Nuovo |
| VP | `eliminationVPDoubled` raddoppia VP da eliminazione se chit "elim-x2" attivo | 🟢 Nuovo |
| VP | `exitVPDoubled` flag esposto (la logica exit-from-map è semplificata) | 🟡 Parziale |
| Eventi | E67 Reconnaissance → rivela uno dei chit segreti del difensore | 🟢 Fix (ora rivela una chit segreta dal cup del difensore, attiva elim/exit ×2, dà VP retroattivi al controllore) |
| Carte | Badge image set (O/A/E + dadi + consequence + hex compass) | 🟢 Nuovo (CardHand riscritta con badge PNG, illuminazione per slot giocabile, popup chit obiettivi) |
| Carte | Cross-check numerazione vs Card Manifest + Rulebook | 🟢 Fix (ordini O1-O9 corretti; azioni A25-A41; eventi E43-E77; INTEGRITA DEL CAMPO unificata; PROMOZIONE↔TEMPRATI scambiate; TARATURA→FUOCO MIRATO) |
| Carte | Playability per slot (canPlayOrder/canPlayAction) | 🟢 Nuovo (badge spenti se non giocabili: postura defender, fase player_moving/ai_reaction/time_advance, modificatori fire/melee con prerequisiti) |

## Milestone 5: IA/Playbook

| Stato | Voce | Note |
| --- | --- | --- |
| 🟡 Da fare | Priorità IA | Usa tutti gli ordini base. Serve playbook leggibile / priorità per scenario. |
| 🟡 In corso | Valutazione bersagli | `aiObjectiveScore` pesa VP cumulativi dei chit + distanza per Move/Advance; `aiFireTargetScore` priorità su nemici su nostri obiettivi (+15 base), poi obiettivi nemici, poi prossimità; bonus per eliminare leader nemici. Recover prioritizza unità rotte sugli obiettivi. Mancano: copertura, rischio reattivo, distanza supporto. |
| 🟢 Nuovo | AI Move tactics | Squad/team mosse PRIMA (sacrificabili davanti), leader per ULTIMO da posizione retrostante. Bonus forte per atterrare su obiettivi non controllati (+6×VP per step). Weapon segue il carrier (CC:E 8.1.1). Ogni passo apre finestra ai_reaction per Op Fire. |
| 🟡 Da fare | Reazioni IA | OP migliorato; da integrare azioni difensive complesse e recupero opportuno. |
| 🟡 Da fare | IA difesa obiettivi propri | L'IA preferisce capture (controller≠ai), ma "difendere" un proprio obj segnato da chit segreti propri non è ancora considerato (chit segreti non visibili all'IA per design). |

## Milestone 6: UI e Grafica

| Stato | Voce | Note |
| --- | --- | --- |
| 🟢 Fatto | Vista mappa | Zoom, Adatta, Vista ampia, auto-fit, pannelli collassabili, risoluzione root 100vw. |
| 🟢 Fatto | Debug LOS | Modalità test LOS con linea verde/gialla/rossa + pannello esito. |
| 🟢 Fatto | Counter art | Pedine PNG per German, Russian, American (squad/team/leader/weapons); proxy art per fazioni minori. |
| 🟢 Fatto | UI fuoco preview | Pannello pre-fuoco con FP base, hindrance, elevazione, copertura, morale bersaglio. |
| 🟢 Fatto | Splash scenari | Lista 24 scenari + banner verticale + dettagli + OB. |
| 🟢 Fatto | Editor icone | Tutte le icone PNG ufficiali (terreno esagonale, hexside rettangolare). |
| 🟡 Da fare | Counter art fazioni minori | Generare/disegnare PNG dedicati per Italian, French, British, Polish, Yugoslav, Brazilian, ANZAC (ora usano proxy). |
| 🟡 Da fare | UI combattimento | Mostrare meglio risultati di combattimento sul terreno; UI conseguenze (Event card draw). |
| 🟡 Da fare | UI iniziativa | Bottone "Scambia Iniziativa" già esposto via store; manca pulsante UI. |

## Milestone 7: Regole CC:E avanzate

| Stato | Voce | Note |
| --- | --- | --- |
| 🟢 Fatto | Melee CC:E O21 | Vera resoluzione: Melee Total = ΣFP + comando + 2d6; loser perde unità con morale più basso; ties → non-initiative wins; iterativa. |
| 🟢 Fatto | Ordnance Targeting Roll | d1×d2 vs range; miss → no fire; minRange enforcement. |
| 🟢 Fatto | Smoke/Concealment hindrance | Trattati correttamente come hindrance, non cover. |
| 🟢 Fatto | Rotta CC:E | Morale roll + retreat 2 hex. |
| 🟢 Fatto | Time! consequence | +1 VP difensore, smoke removal, reshuffle. |
| 🟢 Fatto | Hero spawn | Evento EROE crea unità Hero (FP 2, range 6, morale 9, command 1); non va in Casualty Track. |
| 🟢 Fatto | Sniper corretto | Hex-based victim + repair armi rotte. |
| 🟢 Fatto | Initiative trade | Azione `tradeInitiative()` esposta (manca UI). |
| 🟡 Da fare | Dig-In da Time! | Il PDF richiede opportunità Dig-In per il giocatore attivo dopo Time!; non implementato. |
| 🟡 Da fare | Reinforcements | Carry-over di rinforzi dalle caselle Time Track; non implementato. |
| 🟡 Da fare | Initiative re-roll force | `tradeInitiative` esiste ma non è ancora legata al meccanismo di re-roll durante una risoluzione di tiro. |
| 🟡 Da fare | Hidden Unit reveal | La carta UNITÀ NASCOSTA esiste ma non spawna unità da chart di rinforzo. |

## Rischi Aperti

| Stato | Rischio | Note |
| --- | --- | --- |
| 🟡 Risolto parzialmente | Fedeltà regolamento | Tutti i 5 bug critici dall'audit dell'Esempio di Gioco corretti. Restano dig-in, reinforcements, initiative re-roll. |
| 🟢 Risolto | Armi (trasporto) | Pairing 1↔1 enforced in Move/Advance; weapon orfane restano nell'esagono. |
| 🟢 Risolto | LOS e terreni | Base + Gully + Blind Hex + crest + grazing + gap esplicito. |
| 🟡 In corso | Mappa dati scenari 3-24 | Scenari 1-2 hanno dati terreno completi. Tutti gli scenari 3-24 hanno immagine PNG + scaffold pronti. Le **unità** sono ora piazzate automaticamente da OB; il **terreno** dettagliato resta da disegnare con l'editor. |
| 🟢 Fatto | Test motore | 89 test verdi su cards, combat, los. |
