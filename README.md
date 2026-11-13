# Combat Commander: Europe — Edizione digitale

Versione digitale del gioco da tavolo tattico **Combat Commander: Europe** (GMT Games),
in **Godot 4.6**, con esportazione web. Progetto amatoriale a uso personale.

Gioca online: https://tannoiser2.github.io/Combat-Commander-Europe/

## Com'è fatto (dalla v0.50 «Rifondazione»)

| Parte | File | Che cosa fa |
|---|---|---|
| Motore a decisioni | `godot/engine/Flow.gd` | Tutta la partita come sequenza di decisioni: a ogni passo elenca **solo le mosse legali** e aspetta una scelta. |
| IA | `godot/engine/Bot.gd` | Sceglie fra le stesse opzioni del giocatore, dando un punteggio a ciascuna. |
| Regista | `godot/engine/Game.gd` | Fa girare il motore, dà il ritmo alla cronaca, traduce i tocchi in scelte. |
| Regole pure | `Rules.gd`, `HexGrid.gd`, `Combat.gd`, `Events.gd`, `ObjectiveChits.gd` | Calcoli riusati dal motore (linea di vista, costi, copertura, eventi, chit). |
| Dati | `godot/assets/` | 24 mappe, 6 mazzi da 72 carte, tabella unità (fronte e retro), scenari. |
| Interfaccia | `godot/scenes/Partita.gd`, `Board2D.gd`, `CardView.gd`, `Map3D.gd`, `Menu.gd` | Guida passo passo, mappa 2D e 3D, mano di carte, cronaca. |
| Tema | `godot/engine/Tema.gd`, `godot/assets/fonts/` | Colori e font (Black Ops One, Barlow Condensed — licenza OFL). |

## Verifiche

```
godot --headless --path godot --import
godot --headless --path godot res://tests/SelfPlay.tscn -- all 1     # partite IA contro IA su tutti gli scenari
godot --path godot --resolution 1024x768 res://tests/UiTour.tscn -- /tmp/giro 2 160   # schermate di ogni tipo di decisione
python3 tools/controlla_glifi.py                                    # nessun carattere senza glifo
```

## Pubblicazione

Solo su richiesta: pulsante «Run workflow» di `deploy.yml`, oppure un commit su `main`
con `[pubblica]` nel messaggio.

## Stato e cose da fare

Vedi `docs/STATO.md`. I vecchi audit e il codice della v0.48 sono in `docs/archivio/`.

## Note legali

*Combat Commander: Europe* è © GMT Games. Tutti i materiali originali restano dei rispettivi titolari.
