# Combat Commander: Europe — Edizione Digitale

Reimplementazione digitale del gioco da tavolo tattico **Combat Commander: Europe**
(GMT Games), realizzata in **Godot 4.3**. Progetto a uso personale, non distribuito
a fini commerciali.

## ▶ Gioca online

Una volta attivato GitHub Pages, il gioco è eseguibile direttamente nel browser:
**https://tannoiser2.github.io/Combat-Commander-Europe/**

## 🎮 Stato attuale

- **Scenario 1 — Fat Lipki**: mappa 15×10, 7 unità tedesche e 13 sovietiche.
- Griglia esagonale *flat-top* sovrapposta alla mappa fotografica.
- Pedine fedeli al gioco fisico: potenza di fuoco / gittata / movimento, morale,
  comando dei leader, valori in riquadro per regole speciali.
- Impilamento (max 8 uomini + armi illimitate per esagono) con resa a «mazzo di carte».
- Motore di movimento passo-passo, risoluzione del fuoco (2d6 + FP vs Morale + copertura),
  linea di vista, obiettivi e punti vittoria.

## 📁 Struttura

| Cartella | Contenuto |
|----------|-----------|
| `godot/` | Il progetto Godot eseguibile (motore di gioco + scene). |
| `godot/engine/` | Logica pura: stato, regole, combattimento, mazzi, scenari. |
| `godot/scenes/` | Interfaccia e disegno della mappa. |
| `MAPPE/`, `SCENARI/`, `COUNTER/`, `BADGE/` | Materiali di riferimento per la conversione. |
| `Regolamento - Tabelle - Mappe/` | Regolamenti e tabelle (riferimento personale). |

## 🛠 Sviluppo

Aprire la cartella `godot/` in Godot 4.3 e premere F5.

## ⚖ Note legali

*Combat Commander: Europe* è © GMT Games. Questo è un progetto amatoriale a scopo
di studio e uso personale; tutti i materiali originali restano proprietà dei
rispettivi titolari.
