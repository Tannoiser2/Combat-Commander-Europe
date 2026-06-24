# Audit regole CC:E — Regolamento vs Motore Godot

Confronto **punto per punto** tra il *regolamento ufficiale* di **Combat Commander:
Europe** (20th Anniversary, v1.1, `CC-20thAnniv_Rulebook_ONLINE.pdf`, 24 pp.) e
ciò che il **motore Godot** (`godot/engine/`, `godot/scenes/`) fa **davvero nel
codice** (non in base ai commenti o a `STATO_REGOLE.md`).

Legenda: ✅ fedele · 🟡 parziale/semplificato · ❌ assente · 🐞 bug rispetto alla regola.

_Generato il 2026-06-24 leggendo regolamento + sorgente._

---

## 0. Risposta diretta: i Gruppi di Fuoco

Il **Gruppo di Fuoco non è assente**, ma è **invisibile e automatico**, e questo è
il motivo per cui sembra mancare.

- **C'è** (`Combat.fire_group` + `Combat.resolve_fire`): la potenza del gruppo è
  `FP_migliore + (numero di pezzi aggiuntivi)` — esattamente la regola **O20.3.1.2**
  (`X+Y`). ✅
- **Cosa manca rispetto a O20.3.1:**
  - 🟡 **Nessuna scelta del giocatore.** La regola dice che i gruppi *non sono mai
    obbligatori* (si può sparare separati, formare gruppi più piccoli, scegliere
    «tutti / alcuni / nessuno»). Nel motore il gruppo si forma da solo con tutte le
    unità idonee: il giocatore clicca **una** unità e il resto si aggrega da sé.
  - 🟡 **Catena multi-esagono semplificata.** O20.3.1 richiede che, se il gruppo
    occupa più esagoni, ciascuno sia adiacente ad almeno un altro («catena»). Il
    motore include qualsiasi unità entro il raggio di Comando del leader **che si
    trova nell'esagono dello sparatore**, senza verificare la catena di adiacenza,
    e solo se il leader è co-locato con l'unità che spara.
  - 🐞 **Comando in difesa mancante** (vedi §3): il leader nell'esagono bersaglio
    *non* aumenta la Morale dei difensori.
- **Op Fire** (`OpFire.best_shooter`): sceglie **automaticamente un solo** miglior
  tiratore, mai un gruppo, e senza far decidere il giocatore (A33). 🟡

In breve: la *matematica* del gruppo di fuoco è giusta, ma **l'interfaccia per
costruirlo a mano non esiste** — come era per il movimento prima di questa settimana.

---

## 1–13 · Regole base (Core)

| Regola | Stato | Dettaglio sul codice |
|---|---|---|
| **1 Fate Cards** (mazzo del Fato) | ✅ | `Fate.gd`: i tiri pescano i dadi dalla carta; reshuffle su Tempo!. |
| 1.1 Dimensione mano | ✅ | per fazione (`hand_size`, scenario). |
| 1.2–1.3 Conoscenza/Rivelazione carte | 🟡 | la mano avversaria è nascosta; nessuna meccanica di rivelazione FP «boxed». |
| 1.9.1 Trigger dadi (Tempo/Cecchino/Inceppamento/Evento) | ✅🟡 | tutti e 4 presenti (`Fate.apply_consequence`); Cecchino rompe **una** unità. |
| **5 Sequence of Play** | ✅🟡 | Chiarimento: in CC:E i **turni** si alternano per **turno intero** (un giocatore gioca i suoi Ordini, poi l'altro) — ed è ciò che il motore già fa (umano → IA → umano). La **finestra di reazione** del giocatore inattivo (Op Fire) durante il turno IA è ora implementata (`_reactive_op_fire`, fase `REACTION_WINDOW`). Resta da rendere interattive anche le **Azioni reattive** dell'inattivo e il passaggio della carta Iniziativa. |
| 5.1 Order Capability (limite ordini) | ✅ | Tetto `max_orders` dello scenario ora applicato (MOVE/FIRE/ADVANCE/RECOVER/ROUT contano; PASS/Azioni no); conteggio mostrato e azzerato a fine turno. |
| 5.2 Action Capability | 🟡 | azioni via click destro, ma fuori dalla sequenza alternata. |
| 5.3–5.4 Scarto / Rifornimento mano | ✅ | scarto+ripesca 1↔1. |
| **6 Game Time** | ✅🟡 | il Tempo avanza **solo** con Tempo! (`Fate`); Morte Subitanea come tiro 2d6 (6.2.2). Mancano i **rinforzi** e i marker dal track. |
| **7 Victory** | 🟡 | Controllo obiettivi + bilancia VP live + auto-vittoria (`Game._update_objectives`). |
| 7.1 Elimination VP | ❌ | eliminare unità **non** dà VP (si contano solo per la **resa**, non per i VP). |
| 7.2 Exit VP (uscita dal bordo) | ❌ | nessuna uscita volontaria/involontaria dalla mappa. |
| 7.3.2–7.3.3 Objective Chits (segreti/aperti) | ❌ | gli obiettivi hanno VP fisso noto; niente chit pescati, niente bluff. |
| **8 Stacking** | ✅🟡 | max 7 figure/esagono (`soldier_icons_at`). Limiti per Radio/Fortificazioni/Smoke/Blaze non realmente applicati. |
| **9 Initiative** | 🟡 | tracciata, usata per il pareggio melee e la doppia resa. Niente passaggio della carta Iniziativa, niente re-roll (9.1). |
| **10 LOS** | ✅🟡 | linea di esagoni (cube_round), blocco da terreno opaco, lati muro/siepe/bocage, varco, hindrance cumulativo, elevazione base (`HexGrid`). Mancano: **cresta collina** (T88.3), **gully** (T86), **blind hex** (T88.4), grazing, fumo come ostacolo pieno. |
| **11 Weapons** | 🟡 | sparano con statistiche esatte + ordnance/gittata minima. |
| 11.2 Portage (trasporto 1↔1) | ❌ | le armi sono unità **indipendenti**: si muovono/sparano da sole, nessun legame uomo-arma, nessun trasferimento. |
| 11.4 Broken Weapons / riparazione | ❌ | nessun recupero di armi rotte/inceppate dal Casualty Track. |
| 11.6 Specialized Weapons | ❌ | nessuna arma speciale (lanciafiamme, ecc.). |
| **12 Radios** | ❌ | saltate dal loader: nessuna radio in gioco. |
| **13 Suppression** | ✅ | posa/effetti/rimozione; soppressa non spara, su pareggio in movimento si rompe. |

---

## O14–O23 · Ordini

| Ordine | Stato | Dettaglio |
|---|---|---|
| **O14 Attivazione** | 🟡 | un ordine attiva un'unità (o un leader + gruppo, ora per **Mossa** e **Fuoco**). Manca l'alternanza e il vincolo `orderCount`. |
| **O15 Pass** | ✅ | scarto + fine turno. |
| **O16 Advance + Melee** | ✅🟡 | adiacenza, ΣFP + riquadri (+1) + 2d6, lato più debole eliminato, **pareggio → entrambi eliminati**. Manca: avanzata **di gruppo** via leader; nessun bonus Comando in melee (corretto da regola); Bunker/Pillbox in pareggio. |
| **O17 Artillery Denied** | 🟡 | la carta viene semplicemente scartata. |
| **O18 Artillery Request** (radio/spotter/barrage) | ❌ | **intero sottosistema assente**: niente Spotting Round, accuracy, scatter, Fire For Effect, barrage fumogeno/HE. |
| **O19 Command Confusion** | ❌ | non implementato. |
| **O20 Fire** | ✅🟡🐞 | Attacco vs Fire Defense Roll; Targeting Roll per ordnance (O20.2.3); gruppo di fuoco (FP=X+Y). **Manca**: scelta del gruppo (vedi §0), Comando in difesa (🐞 §3), **colpi fumogeni** O20.2.1 (solo via azione Granate), bersagli «sospetti» O20.1. |
| **O21 Move** | ✅🟡 | passo-passo coi PM, costi terreno + lati + tariffa strada, impilamento, **Op Fire** durante il movimento, **mossa di gruppo del leader** (3.3.1.1). Manca: double-time, **malus PM delle armi**, uscita dalla mappa, sentiero/trail come tariffa. |
| **O22 Recover** | ✅ | 2d6 ≤ Morale (+Comando nell'esagono). |
| **O23 Rout** | ✅🟡 | N = 2d6 − Morale verso il bordo amico; intrappolata+nemico adiacente → eliminata. Manca: Wire/Mine durante la ritirata (O23.3.3/4). |

---

## A24–A41 · Azioni — **5 su 17**

| Azione (regola) | Stato | Note |
|---|---|---|
| A29 Concealment (Mimetizzazione) | ✅ | `+morale`, rivelata dal fuoco. |
| A32 Dig In (Trincerarsi) | ✅ | buca → +3 copertura. |
| A34 Hand Grenades (Bombe a mano) | ✅ | attacco ravvicinato auto-target. |
| A36 Light Wounds (Ferite leggere) | ✅ | recupero. |
| A39 Smoke Grenades (Granate fumogene) | ✅ | fumo → hindrance. |
| A25 Ambush | ❌ | melee. |
| **A26 Assault Fire** | ❌ | modificatore di fuoco (richiede il fuoco-in-movimento, da fare). |
| A27 Bore Sighting | ❌ | ordnance (difensore, +2). |
| A28 Command Confusion | ❌ | |
| **A30 Crossfire** | 🟡 | applicato come modificatore (+2) nell'assemblaggio del fuoco, con prerequisito «solo vs unità in movimento». |
| A31 Demolitions | ❌ | |
| **A33 Opportunity Fire** | ✅🟡 | **finestra di reazione interattiva**: quando l'IA muove in LOS/gittata, il giocatore sceglie il tiratore o rinuncia (`REACTION_WINDOW`). L'IA come difensore (durante il movimento del giocatore) resta automatica. |
| A35 Hidden | ❌ | unità nascoste. |
| **A37 Marksmanship** | ✅ | +2 FP nell'assemblaggio del fuoco, prereq: una squadra/team spara. |
| A38 No Quarter | ❌ | melee. |
| **A40 Spray Fire** | ❌ | modificatore di fuoco (richiede 2 esagoni bersaglio, da fare). |
| **A41 Sustained Fire** | ✅ | +2 FP nell'assemblaggio, prereq: MG/mortaio spara; su un doppio un'arma si inceppa. |

Dei cinque **modificatori di fuoco** ne sono ora attivi **3** (Mirato, Sostenuto,
Incrociato), applicabili durante l'assemblaggio interattivo del fuoco (tasto destro
su una carta). Restano **Sventagliata** (2 esagoni) e **Fuoco d'Assalto** (fuoco
durante il movimento), che richiedono cambi al targeting/flusso.

---

## E42–E77 · Eventi — **~8 su ~35**

Implementati (`Events.gd`): Air Support (E43), Battle Harden (E44), Cower (E51),
Infiltration (E59), KIA (E62), Rubble (E69), Suppressing Fire (E75), Shell Shock
(E72); Zappatori/Scontro-senza-perdite come no-op.

Assenti (~27), tra cui i più impattanti: **Hero (E58)**, **Field Promotion (E56)**,
**Deploy (E52)**, **Reinforcements (E68)**, **Medic! (E64)**, **Mission/Strategic
Objective (E65/E74)**, **Interdiction (E60)**, **Prisoners of War (E66)**, Commissar
(E50), Élan (E54), Booby Trap (E47), Malfunction (E63), White Phosphorus (E77), ecc.

---

## T78–T99 · Terreno e F100–F105 · Fortificazioni

| Area | Stato | Note |
|---|---|---|
| Costi movimento / copertura / hindrance | ✅🟡 | Woods/Building/Field/Orchard/Brush/Road/Stream + lati (muro/siepe/bocage/torrente). |
| T88 Hills / elevazione | 🟡 | elevazione base nella LOS; mancano cresta (T88.3), downhill +1FP, blind hex. |
| T83 Cliff, T86 Gully, T89 Marsh, T80 Bridge, T92 Railway | ❌/🟡 | per lo più non modellati o solo come costo. |
| T79/T94 Blaze & Smoke (incendio/fumo) | 🟡 | fumo come hindrance via azione/evento; nessuna propagazione incendio. |
| F100–F105 Fortificazioni | 🟡 | **solo Buca** (Dig In) e **Fumo**. Mancano: Bunker, Pillbox, Trincea (distinta), Filo spinato (Wire), Mine, Booby trap. |

---

## 3 · Comando & Leadership (3.3) — focus

| Regola | Stato | Codice |
|---|---|---|
| 3.3.1.1 Raggio di Comando: attiva unità non-leader entro il raggio per lo **stesso** ordine | 🟡 | fatto per **Fuoco** (`Combat.fire_group`) e **Mossa** (`Game._form_move_group`). Manca per **Avanzata/Recupero/Rotta** e la scelta «alcuni/nessuno». |
| 3.3.1.2 Comando → **FP** di squadre/team co-locati | ✅ | `Rules.command_bonus_at` in attacco. |
| 3.3.1.2 Comando → **Morale** in **difesa** | 🐞 **bug** | `Combat.resolve_fire` calcola la difesa come `morale + copertura + dadi`: **non** aggiunge il Comando del leader nell'esagono bersaglio. |
| 3.3.1.2 Comando → **Gittata** | ❌ | mai applicato. |
| 3.3.1.2 Comando → **Movimento** | ❌ | mai applicato. |
| 3.3.1.2 Comando → **Morale** per Recupero | ✅ | `Rules.try_recover`. |
| 3.3.1.3 **Weapon Command** (Comando → FP/Gittata delle armi co-locate) | ❌ | mai applicato. |

---

## Stima onesta della copertura

- **Ciclo di combattimento di base** (pesca dadi, fuoco diretto, melee, movimento,
  recupero, rotta, LOS/terreno core, obiettivi/VP, resa): **buona**, ~70–80%.
- **Sistema completo del regolamento** (azioni, eventi, radio/artiglieria, chit,
  fortificazioni, armi/portage, unità speciali, sequenza alternata): **molto
  parziale**, ~35–45% per numero di regole.

La sensazione dell'utente — «mancano tantissime cose» — è **corretta** per il
regolamento nel suo insieme: il motore è una buona base del *cuore* del gioco, non
ancora il gioco completo.

---

## Priorità consigliate (impatto sul "sembra vero")

1. 🐞 **Comando in difesa** (fix piccolo, alto impatto sulla correttezza del fuoco).
2. **Gruppo di Fuoco interattivo**: selezione manuale dei pezzi e del bersaglio
   (come è stato fatto per il movimento di gruppo).
3. **Modificatori di fuoco** (Assault/Crossfire/Sustained/Spray/Marksmanship): 5
   azioni che cambiano davvero le sparatorie.
4. **Comando → Gittata/Movimento** e **Weapon Command** (completare 3.3.1.2/.3).
5. **Op Fire interattivo** (scelta del tiratore, finestra di reazione).
6. **Limite ordini per turno** (5.1) per dare struttura al turno.
7. Sottosistemi grandi (Artiglieria/Radio O18, Chit obiettivo, Fortificazioni,
   Eventi mancanti) come tracce successive.
