# Modelli 3D — crediti e licenza

Modelli low-poly usati nella vista 3D, presi dallo Starter Kit "City Builder"
di **Kenney** (account ufficiale `KenneyNL` su GitHub).

- Fonte: https://github.com/KenneyNL/Starter-Kit-City-Builder (licenza MIT)
- Asset grafici di **Kenney** — licenza **CC0 1.0** (https://kenney.nl) —
  uso libero anche commerciale, senza obbligo di attribuzione (citato per
  cortesia).

File inclusi: building-small-a/b/c (edifici), grass-trees (alberi),
grass (vegetazione bassa).

## Soldati 3D

Figure di soldato/ufficiale (WWII) usate come pedine 3D, con modelli dedicati per
fazione. Più figure per pedina secondo le "soldier icons": squadra 4, team 2,
leader 1, arma 1.

Asse (tedesco):
- `soldier_de.glb`, `soldier_de_a.glb`: due pose di soldato (squadre/team).
- `officer_de.glb`: ufficiale, usato per i leader.

Sovietici:
- `soldier_ru.glb`, `soldier_ru_a.glb`: due pose di soldato (squadre/team).
- `officer_ru.glb`: ufficiale, usato per i leader.

Americani:
- `soldier_us.glb`, `soldier_us_a.glb`: due pose di soldato (squadre/team).
- `officer_us.glb`: ufficiale, usato per i leader.

I modelli sono scelti per nazionalità dell'unità (`nation_art`: Tedeschi / Russi
/ Americani). Modelli forniti dall'utente (generati con Meshy AI), con la sola
geometria originale conservata (niente decimazione: evita crepe/buchi alle
cuciture) e le texture ridotte a 512×512 (ricodificate JPEG) per la build web. Se
una nazione non ha il modello, si ripiega su quello di un'altra con una tinta
verde-oliva come segnaposto.

## Armi 3D

Modelli delle armi di supporto (MG, mortai, cannoni) per le pedine WEAPON, scelti
per nazione e tipo (`wpn_<nazione>_<tipo>.glb`):

- Tedeschi: MG leggera (MG34), MG pesante (MG42), mortaio leggero, cannone (leIG18).
- Russi: MG leggera (DP), media (SG43), pesante (Maxim), mortaio, cannone (76mm).
- Americani: .50 (Browning M2), pesante (M1917A1), media (M1919A4), mortaio
  (81mm), obice (75mm Pack).

Stesso trattamento dei soldati (geometria originale, texture 512 JPEG). I tipi
senza modello dedicato (es. MG media tedesca) ripiegano sull'arma più simile
della stessa nazione.


## Alberi del bosco

`tree_collection.fbx` + `textures/color_1024x1024.jpg`: collezione di alberi
low-poly "Low-Poly Tree Collection 01" (fornita dall'utente). Usata per gli
esagoni di bosco/frutteto nella vista 3D. La licenza d'uso è quella della
collezione originale scaricata dall'utente.
