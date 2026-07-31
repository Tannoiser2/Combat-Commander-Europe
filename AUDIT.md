# Audit completo — Regole, GUI e flusso di gioco (v0.44.2)

> **Stato al 31/07/2026** — Fasi **1, 2 e 3 completate** e su `main`; **Fase 4 in gran parte
> completata** (vedi in fondo il dettaglio di cosa resta). Questo documento resta la
> fotografia dell'audit iniziale: le voci corrette sono elencate come piano, non come
> difetti ancora presenti.


Audit condotto sul regolamento 20th Anniversary (`CC-20thAnniv_Rulebook_ONLINE.pdf`) +
Playbook, confrontati riga per riga col codice. Quattro aree: (1) VP/Obiettivi/Tempo,
(2) attivazione Ordini/Azioni, (3) movimento + Fuoco di Opportunità, (4) sweep generale
delle regole. Ogni voce ha il riferimento di regola e il punto nel codice.

Legenda gravità: 🔴 rompe il gioco · 🟠 grave (altera l'equilibrio) · 🟡 medio · ⚪ minore

---

## 1 · Punti Vittoria, Obiettivi, Tempo, Morte Subitanea

### 🔴 1.1 Controllo degli obiettivi: modello sbagliato
Regola 7.3.1: il controllo è "appiccicoso" — l'ultimo giocatore ad aver occupato **da solo**
l'esagono lo controlla, anche dopo averlo lasciato; mai neutro; conteso ≠ cambio di mano.
Le schede scenario assegnano il **controllo iniziale** (es. "AXIS — all").
Codice: `Game._update_objectives` (Game.gd:2906-2937) ricalcola a ogni azione per
maggioranza di presenti; vuoto/pareggio → neutro. Il controllo iniziale da scheda non è
mai letto. Sintomo: conquisti un obiettivo, ti sposti per attaccare e i VP spariscono;
il difensore che "controlla tutto" da scheda parte a 0.

### 🔴 1.2 Valori degli obiettivi inventati
Regola 7.3: senza chit un obiettivo vale **0 VP**; i valori veri li danno i chit
(aperti/segreti) elencati dalla scheda scenario. Codice: il **numero stampato** (1–5)
è usato come valore VP (`MapLoader.gd:90` legge il campo `"vp"` dei map*.json);
23/24 scenari non pescano alcun chit. Su map10 l'ordine del JSON scombina anche
l'abbinamento numero↔esagono. Sintomo: l'economia VP di quasi tutti gli scenari è
un'invenzione (l'obiettivo "5" vale sempre 5).

### 🔴 1.3 Sistema di chit aperti/segreti assente
Regola 7.3.2/7.3.3 + Playbook: ogni scenario elenca chit precisi (aperti e segreti per
lato); i segreti sono nascosti fino a fine partita (o E67 Ricognizione). Codice:
`ObjectiveChits.assign` applica tutto in chiaro, `Objective.secret` mai usato; lo
Scenario 1 (via `Scenario1.gd`) ha **3 obiettivi con VP fissi 2/2/3** e zero chit.
Sintomo: l'intero gioco delle condizioni di vittoria nascoste non esiste.

### 🔴 1.4 Vittoria automatica "tutti gli obiettivi" sempre attiva
Regola 7.3.2: esiste **solo col chit V**, e si controlla **solo subito prima di ogni
tiro di Morte Subitanea**. Codice: `Game.gd:2836-2840` chiude la partita appena una
fazione occupa tutti gli obiettivi, sempre e in continuo. Sintomo: rush di 3 esagoni
allo Scenario 1 = vittoria istantanea impossibile nel gioco reale.

### 🔴 1.5 Uscire con l'ultima unità = sconfitta (dovrebbe essere fine partita a punti)
Regola 6.3(3)/6.3.2: l'uscita volontaria dell'ultima unità termina la partita e **vince
chi ha più VP**. Codice: `_check_end_conditions` (Game.gd:2842-2846) tratta "0 unità"
sempre come annientamento → sconfitta automatica. Sintomo: sei a +8, esci per i VP
d'uscita e il gioco ti dichiara perdente.

### 🔴 1.6 Il Tempo non avanza a fine mazzo
Regola 6.1.2: il Tempo avanza col "Time!" **e ogni volta che un mazzo si esaurisce**
(trattato come un Time!). Codice: `Fate.draw`/`Cards` rimescolano in silenzio
(Fate.gd:13-27). In più: al Time! vengono rimescolati **entrambi** i mazzi invece del
solo innescante (Fate.gd:71-72). Sintomo: l'orologio di gioco è quasi fermo, partite
eterne, Morte Subitanea rarissima.

### 🟠 1.7 Sequenza del Time! sbagliata
Regola 6.1.2: 1) rimescolo, 2) **tiro di Morte Subitanea**, e SOLO se la partita non è
finita: 3) +1 VP al difensore, 4) rimozione fumo (a scelta dell'innescante),
5) rinforzi, 6) Trincerarsi. Codice: +1 VP, fumo e rinforzi avvengono PRIMA del tiro SD
(`Fate._consequence_time` + `_apply_fate`). Il passo 6 manca. Sintomo: sul Time! che
chiude la partita il difensore incassa un +1 VP che non gli spetta (può ribaltare
l'esito con VP pari).

### 🟠 1.8 Unità uscite distrutte invece di tornare
Regola 7.2.1: l'unità uscita va sulla Traccia del Tempo e **rientra come rinforzo**
(integra, con la sua arma). Codice: `exit_unit_for_vp` la cancella per sempre
(GameState.gd:383-401). Inoltre: uscita permessa solo in Mossa (anche l'Avanzata può,
O16) e mai per l'IA (FlipBot non esce mai). Ritirata forzata fuori dal proprio bordo
(7.2.2, eliminazione + VP all'avversario) impossibile: il bordo è un muro
(`Rules._rout_passable`).

### 🟠 1.9 Carta Iniziativa senza re-roll volontario
Regola 9.1: chi la possiede può annullare e far ripetere **qualsiasi** tiro, cedendo la
carta. Codice: esiste solo il re-roll automatico e forzato sulla Morte Subitanea
(Game.gd:2881-2892), mai chiesto al giocatore; per fuoco/morale/mischia non esiste.
La carta non cambia mai di mano in partita.

### 🟡 1.10 Tempo iniziale ignorato negli scenari da catalogo
`tempo_iniziale` è supportato ma nessuna voce del catalog.json lo valorizza: tutti
partono da 0 (Playbook: scen. 4→1, 5→5, 9→2, 11→1, 12→4). Scenario 5 dura 5 passi di
troppo.

### ⚪ 1.11 Minori
"VP -12 (RUS)" si legge male (meglio "VP 12 (RUS)" come sul segnalino fisico); il
gettone obiettivo mostra il valore VP invece del numero (con i chit segreti sarebbe
un leak); edifici multi-esagono non modellati (7.3.1.1); `units_of` conta anche le armi
nel check di annientamento; `_count_objectives` è codice morto.

### ✅ Corretti (verificati)
Valori VP di eliminazione/uscita e direzione (7.1/7.2 + chit X/W), soglie di resa da
scheda e sconfitta immediata, matematica del tiro SD (< numero casella, pari
sopravvive), pareggi all'Iniziativa (6.3.2/9.2), convenzione di segno della traccia
unica, +1 al difensore in sé (Recon-vs-Recon escluso), Tempo che avanza SOLO col Time!.

---

## 2 · Attivazione Ordini e Azioni (badge)

### 🔴 2.1 ARTIGLIERIA NEGATA: badge acceso, effetto inesistente
Regola O17: rompe la Radio nemica (la elimina se già rotta); giocabile solo se il
nemico ha una Radio. Codice: unico `OrderType` senza ramo in `play_card` → scarto muto
(Game.gd:678-681), ma `order_feasible` di default dice `true`. Sintomo: "ricicla carta
gratis" illimitato, e l'effetto vero non esiste.

### 🔴 2.2 FUOCO INCROCIATO mai applicabile per l'umano
Regola A30: +2 contro unità **in movimento** — cioè in Fuoco d'Opportunità. Codice: i
modificatori si applicano solo durante un ordine di Fuoco umano (quando nessun nemico
si muove) e la finestra di Op Fire non li accetta. 8-9 copie per mazzo di carta morta,
col badge però sempre acceso durante l'assemblaggio.

### 🟠 2.3 GRANATE FUMOGENE: timing invertito e fumo nel posto sbagliato
Regola A39: giocabile SOLO mentre una propria unità con Movimento in scatola è attivata
a Muovere; fumo nel suo esagono o adiacente. Codice: accesa solo in PLAYER_TURN, spenta
durante la Mossa, e il fumo cade nell'**esagono casuale stampato sulla carta**
(Actions.gd:97-104), ovunque sia.

### 🟠 2.4 IMBOSCATA solo per l'IA
`_resolve_melee_ambushes` salta la fazione umana (Game.gd:2161-2196). 5-6 copie per
mazzo che il giocatore non può mai usare, nemmeno quando l'IA gli avanza addosso
(momento previsto da A25, con precedenza al giocatore inattivo).

### 🟠 2.5 Azioni nei mazzi senza alcuna implementazione
BUONA MIRA (A27, 6 copie GB), DEMOLIZIONI (A31), UNITÀ NASCOSTA (A35.4), LOTTA SENZA
QUARTIERE (A38, 3+3 copie). Giocarle = "non ancora simulata" + carta persa.
(ORDINI CONTRADDITTORI correttamente dud.)

### 🟠 2.6 ROTTA solo sui propri rotti / RECUPERO senza limiti
O23.1: la Rotta può attivare **anche l'avversario** (metà della sua utilità); O23.2:
pareggio→Soppressa; O23.3.5: eliminazione per ritirata su bordo amico. Tutto assente.
O22.1: massimo un Recupero per giocatore per turno — non applicato; pareggio→Soppressa
mancante anche qui (`try_recover` usa `<=`).

### 🟡 2.7 Modificatori di fuoco accesi senza prerequisiti
Mirato/Sostenuto/Sventagliata/Bombe a Mano si accendono appena esiste un gruppo di
fuoco, senza consultare `_fire_modifier_error` (Main.gd:284-285). Click che non fa
nulla o che "riesce" e poi svanisce allo sparo con "carta conservata".

### 🟡 2.8 Fattibilità imprecise
- AVANZATA: `order_feasible` è quasi-sempre-vero, non passa da `_can_advance_into`.
- FUOCO: `_any_fire_ready` ignora le **armi trasportate** (badge spento con MG che
  potrebbe legalmente sparare, O20.1).
- ARTIGLIERIA: non richiede leader non-attivato (O18.2) e ignora il Battery Access
  (radio rotta riparabile, O18.1) → una Radio rotta uccide l'artiglieria per sempre.
- `can_be_ordered` esclude in blocco soppressi (13.2: agiscono a −1, vietate solo le
  armi) e rotti (O21: possono Muovere).
- FUOCO D'ASSALTO: badge acceso per tutta la Mossa anche quando il motore rifiuterà
  (già usato / unità non idonea / niente bersaglio).

### 🟡 2.9 Azioni A35 "nascoste" e FERITE LEGGERE fuori regola
A35: solo il **Difensore** di scenario, in momenti reattivi — ora le giocano entrambi
nel proprio turno. A36 Ferite Leggere: dovrebbe scattare quando una squadra sta per
rompersi (diventa Team, −1 VP) — ora è un rally gratuito di un'unità già rotta.
TRINCERARSI: solo al passo 6 del Time! — ora sempre.

### 🟡 2.10 Op Fire: carta consumata mentre il tooltip dice "non giocabile"
Durante la finestra di reazione i badge sono tutti spenti, ma cliccare un tiratore
scarta di nascosto la prima carta Fuoco in mano (vedi 3.1/3.7).

---

## 3 · Movimento esagono-per-esagono + Fuoco di Opportunità

### ✅ Base corretta
Un click = un passo; l'op fire scatta per OGNI esagono entrato, in entrambe le
direzioni; niente op fire su Avanzata/Rotta; max un attacco per esagono (A33.3.3).

### 🔴 3.1 Economia dell'Op Fire rovesciata
Regola A33.2/.3: **una** carta Fuoco attiva il tiratore, che poi spara **gratis** a
ogni esagono entrato per tutta la durata di quell'ordine di Mossa. Codice: una carta
scartata per OGNI attacco, e il tiratore è marcato `activated` al primo (one-shot).
Sintomo: squadra IA che attraversa 5 esagoni davanti alla tua MG → da regola 5 attacchi
con 1 carta; nel port 1 attacco e basta (e con 5 carte ne faresti 5, spendendole tutte).

### 🔴 3.2 Chi fa Op Fire perde anche il proprio turno dopo
Le attivazioni si azzerano solo in `_end_player_turn` (fine turno UMANO): un tuo
tiratore che reagisce nel turno IA resta "attivato" per tutto il tuo turno successivo,
senza spiegazione. La regola limita solo a un op fire per turno avversario.

### 🔴 3.3 Mover IA rotto o ELIMINATO continua a muoversi
`_ai_move_toward` ignora l'esito dell'op fire (Game.gd:2809) e il ciclo non ricontrolla
lo stato: un'unità rotta prosegue, e una eliminata "cammina da fantasma" aprendo
finestre di reazione su esagoni vuoti (che ti bruciano comunque la carta Fuoco).

### 🟠 3.4 Mimetizzazione asimmetrica
Nell'op fire il mover IA gioca la Mimetizzazione automaticamente; al mover umano la
finestra non viene MAI offerta (`_maybe_react_concealment` early-return per l'umano).

### 🟠 3.5 L'IA muove tutta la fazione con un solo ordine (e ignora il Filo)
O14.1/O21: un ordine di Mossa attiva una unità o un gruppo di comando. `_ai_move_order`
muove TUTTE le unità ordinabili. `_wire_on_move` non è chiamato per l'IA.

### 🟡 3.6 Pareggio in difesa: "in movimento" troppo stretto
O20.3.4: il pareggio rompe tutte le unità **attivate a Muovere**, non solo quella che
sta facendo il passo (`t.id == moving_unit_id`). In più il codice rompe le soppresse
sul pareggio (estensione non da regolamento).

### 🔴 3.7 UI: il banner mente sul costo
"…nessuna carta da giocare" (Main.gd:1234) mentre il motore scarta la prima carta
Fuoco della mano, scelta da solo, senza chiedere QUALE. Se non hai carte Fuoco la
finestra non appare affatto, senza alcun messaggio: sembri "saltato" a caso.

### 🔴 3.8 UI: l'Op Fire è invisibile
`_resolve_op_fire` non emette `fire_resolved` → niente traccianti, lampi, suoni. La tua
unità "si rompe da sola" a schermo. (La linea `last_fire` c'è, ma è l'unico indizio.)

### 🟠 3.9 UI: click sbagliato = rinuncia definitiva
Nella finestra di reazione qualunque click non-esatto su un tiratore = `opfire_decline`
irreversibile (Game.gd:893-899). Cliccare il mover rosso per guardarlo chiude tutto.

### 🟡 3.10 UI: contesto assente
Niente preview FP/esito per scegliere il tiratore; il gruppo che spara insieme non è
mostrato; il mover IA "scivola" in linea retta senza mostrare il percorso esa-per-esa;
nessun focus camera sulla finestra (`opfire_offered` non è ascoltato da nessuno);
durante la TUA Mossa nessun avviso del rischio op fire; "si è mosso allo scoperto" è
regola sbagliata (vale ogni esagono in LOS/gittata); log op fire IA e tuo con lo
stesso colore.

---

## 4 · Sweep generale delle regole

### 🔴 4.1 Metagame del mazzo in gran parte no-op
Oltre a 1.6/2.1: **12 tipi di evento** presenti nei mazzi cadono nel ramo "non ancora
simulato" (~24 carte/mazzo nel tedesco): Crateri E73, Trappola Esplosiva E47, Dividersi
E52, Ricognizione E67, Spionaggio E61, Nebbia di Guerra E57, Rinforzi E68, Saccheggio
E71, Procedere Feriti E76, White Phosphorus E77, Zappatori E70 (stub), Scontro Senza
Perdite E45 (stub — darebbe VP!). Altri eventi implementati con effetti di un'altra
edizione: Interdizione, Infiltrazioni, Supporto Aereo (manca il fallback), Eroe (manca
il rally gratuito).

### 🔴 4.2 Deploy / squadre→team inesistente
E52 + 8.2: mai creati TEAM da SQUAD; il sovraccarico elimina senza offrire il Deploy
gratuito; Ferite Leggere non fa la sostituzione con Team.

### 🟠 4.3 Soppressione con effetti sbagliati
13.2: −1 FP/Gittata/Movimento/Morale e divieto di sparare **armi** — ma l'unità può
essere attivata. Codice: nessun −1 da nessuna parte, e attivazione bloccata del tutto
(paralisi totale, difesa a Morale pieno).

### 🟠 4.4 Fuoco: difesa condivisa e gruppi fuori regola
O20.3.4: un tiro di difesa **per unità** (una alla volta, ordine a scelta) — il codice
usa un solo tiro per l'intero esagono ("tutto o niente" sugli stack). O20.3.1: gli
esagoni di un gruppo di fuoco devono formare una **catena di adiacenza** — il codice
usa il raggio di Comando.

### 🟠 4.5 Terreno: blocco di modificatori mancanti
Ruscello: copertura **−1**, nel codice **+1** (Domain.gd:142 — segno invertito!);
Strada: −1 copertura e +1 PM entrando lungo strada; Muro/Siepe: copertura alternativa
2/1 attraverso quel lato; Height Advantage ±1 FP (T88.2); Airburst +2 di
mortai/artiglieria sul Bosco (T99); acqua/palude: vietato sparare armi e fortificare;
Forra invisibile da lontano; Recinzione (1 hindrance, +1 PM) del tutto assente.
LOS collinare parziale (mancano Blind Hex, Crest Line, ostacoli bassi ignorati
dall'alto). L'Incendio non blocca la LOS e non si propaga con la Brezza.

### 🟡 4.6 Fortificazioni incomplete
Mine: nessun attacco in Avanzata né in Ritirata (si aggira un campo minato avanzando).
Filo: mancano i divieti di fuoco (niente gruppo con fuori, niente armi dal filo).
Trincea: manca il movimento trincea↔trincea a 1 PM.

### 🟡 4.7 Armi rotte: mai riparabili, mai eliminate
11.4: confronto col Random Hex per Fix/Elim — assente. Un'arma rotta è persa per
sempre (ma mai rimossa). Battery Access (radio) idem, vedi 2.8.

### 🟡 4.8 Mischia
Il Comando non conta nella forza (3.3.1.2 vale sempre); melee non innescata da
co-occupazioni fuori-Avanzata (es. fuga da incendio in esagono nemico).

### ⚪ 4.9 Minori
Veterano: solo +1 Morale (mancano FP/Gittata/Movimento); statistiche lato rotto
approssimate; ordnance con un solo tiro per targeting+attacco; Smoke Rounds dei mortai
assenti; fumo binario invece dei marker 1-10; limite di scarto nazionale (5.3) non
applicato; refill continuo invece che a fine turno (5.4).

### ✅ Corretti (verificati)
Portage armi 11.1-11.3, mano/ordini/posture da scheda, Mimetizzazione A29 (nel Fuoco
ordinario), Targeting Roll moltiplicativo, gittata minima mortai, hindrance non
cumulativa, FP minima, fumo in/out, Group FP X+Y, deriva artiglieria, vulnerabilità
fortificazioni all'artiglieria, coperture alternative buca/trincea/casamatta/bunker
(+1 vs ordnance), −1 del Filo, impilamento a 7 figure con risoluzione a fine turno.

---

## Piano di intervento proposto

**Fase 1 — Economia di vittoria** (il "perché giochi"): controllo obiettivi sticky +
controllo iniziale da scheda; chit aperti/segreti con le composizioni degli scenari e
valore 0 di default; auto-win solo con chit V prima del tiro SD; uscita ultima unità =
fine partita a punti; Tempo a fine mazzo; sequenza Time! corretta (SD prima del +1);
rimescolo del solo innescante; tempo iniziale da scheda; unità uscite che rientrano.

**Fase 2 — Op Fire & movimento** (il cuore di ogni turno): una carta attiva il
tiratore per l'intera Mossa (attacchi gratuiti a ogni esagono); scelta della carta da
scartare; reset attivazioni a inizio del proprio turno; stop del mover IA
rotto/eliminato; `fire_resolved` dall'op fire (traccianti/suoni); banner onesto sul
costo; conferma prima di rinunciare; Mimetizzazione simmetrica; IA che muove per
gruppo di comando e rispetta il Filo.

**Fase 3 — Ordini/Azioni**: Artiglieria Negata + Battery Access; Imboscata umana;
Granate Fumogene col timing giusto; badge modificatori con prerequisiti; Rotta
sull'avversario + esiti O23; limite Recupero; fattibilità Avanzata/Fuoco;
soppressione a norma (−1, vietate le armi, attivabile).

**Fase 4 — Regole di contorno**: segno del Ruscello, strada, muri/siepi, height
advantage, airburst; mine in avanzata/ritirata; divieti del Filo; un tiro di difesa
per unità; catena di adiacenza dei gruppi; eventi mancanti; Deploy/team; Fix/Elim
delle armi rotte.


---

## Stato di avanzamento

**Fase 1 — Economia di vittoria** ✅ (v0.45.0): controllo obiettivi appiccicoso + controllo
iniziale da scheda, chit aperti/segreti col valore 0 di default, chit V, uscita dell'ultima
unità = fine ai punti, unità uscite che rientrano, Tempo a mazzo esaurito, sequenza del
Tempo! corretta, tempo iniziale da scheda.

**Fase 2 — Op Fire & movimento** ✅ (v0.46.0): una carta attiva il tiratore per l'intero
ordine di Mossa (tiri successivi gratuiti), attivazioni azzerate a inizio del proprio turno,
mover colpito che si ferma, `fire_resolved` (traccianti/suono) anche per op fire e fuoco IA,
banner col costo reale, niente rinuncia per click accidentale.

**Fase 3 — Ordini/Azioni** ✅ (v0.47.0): soppressione a norma (13.2), Artiglieria Negata
(O17), Recupero (O22) e Rotta (O23) coi tre esiti e l'attivazione per turno, Rotta
sull'avversario, Granate Fumogene (A39) col timing giusto, badge con prerequisiti reali.

**Fase 4 — Regole di contorno** 🟨 (v0.48.0), fatto:
- Terrain Chart: Ruscello copertura **−1** (era +1), Campo **0** (era 1), Recinzione (+1 PM
  e ostacolo 1 con la regola dei lati), Airburst T99 (+2 di mortai/artiglieria sul Bosco),
  esagoni d'acqua (niente fortificazioni, niente armi che sparano).
- Filo spinato: nessun'arma spara dal filo (F106.3).
- Mine: attaccano anche in **Avanzata** e in **Ritirata** (F103.1).
- Fuoco: **un tiro di difesa per ogni unità** (O20.3.4) — niente più esiti "tutto o niente"
  sugli stack.

**Fase 5 — LOS colline, eventi, Imboscata, strada** ✅ (v0.49.0):
- T88 LOS avanzata: ostacoli più bassi non bloccano da una collina, esagono cieco (T88.4.1),
  ostacoli a quota inferiore che non disturbano (T88.5), incendio che blocca sempre.
- T88.2 vantaggio d'altura (±1 FP); T93 Strada (copertura −1, +1 Movimento per l'ordine).
- A25 Imboscata giocabile dall'umano.
- Otto eventi implementati: Crateri, Trappola esplosiva, Nebbia di guerra, Spionaggio,
  Saccheggio, Procedere feriti, Zappatori, Scontro senza perdite.

**Resta aperto** (non ancora affrontato):
- Terreno: copertura alternativa di Muro/Siepe attraversati dal tiro; Forra visibile solo da
  adiacente/più in alto; Crest Line vera (T88.3.1); incendio che si propaga con la Brezza.
- Gruppi di fuoco per catena di adiacenza (O20.3.1) invece del raggio di Comando.
- Trincea: movimento trincea↔trincea a 1 PM (F105.2).
- Armi rotte: riparazione/eliminazione col Random Hex (11.4); Battery Access (O18.1).
- Deploy/split in team (E52) e i pochi eventi che richiedono marcatori assenti.
- Mimetizzazione offerta al mover umano sotto op fire dell'IA (A29).
