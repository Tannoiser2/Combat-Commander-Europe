// Scenario 2: "Hedgerows & Hand Grenades" — Normandy, France 1944
// Germans (AXIS, defends, right side) vs Americans (ALLIES, attacks, left side)
// Map B: 15 columns × 10 rows

import type { Hex, Unit, Objective } from './types';
import { buildHexGrid, type MapDefinition } from './mapData';
import { attachCountryUnitChart, attachLeaderChart, attachWeaponChart } from './counterManifest';

export const SCENARIO_ID = 'scenario_02';
export const SCENARIO_NAME = 'HEDGEROWS & HAND GRENADES';
export const MAP2_COLS = 15;
export const MAP2_ROWS = 10;

// Objectives: approximate positions on Map B based on playbook thumbnail
// Objective T is open (random placement by players) — we place it centrally
const OBJECTIVE_DEFS = [
  { id: 1, q: 7, r: 4, vp: 3, initController: null as 'german' | 'american' | null },
];

const MAP2_DEF: MapDefinition = {
  id: 'map-b-hedgerows',
  name: 'Map B / Hedgerows',
  cols: MAP2_COLS,
  rows: MAP2_ROWS,
  defaultTerrain: 'open',
  terrainGroups: {},
  featureGroups: {},
  sideFeatures: [],
};

export function buildMap2(): Hex[][] {
  const objectiveByHex = Object.fromEntries(
    OBJECTIVE_DEFS.map(o => [`${String.fromCharCode(65 + o.q)}${o.r + 1}`, o.id]),
  );
  return buildHexGrid(MAP2_DEF, objectiveByHex);
}

export function buildObjectives2(): Objective[] {
  return OBJECTIVE_DEFS.map(o => ({
    ...o,
    secret: false,
    controller: o.initController,
  })) as Objective[];
}

// ─── Units ────────────────────────────────────────────────────────────────────
// AXIS (German) — defends, sets up last, 12 hexes deep (cols q=3..14)
// ALLIES (American) — attacks, sets up first, 3 hexes deep (cols q=0..2)
//
// German Forces (from scenario card):
//   Lt. Schrader  — ldr morale 9, cmd 1, fp 1/1/6
//   Sgt. Esser    — ldr morale 8, cmd 2, fp 2/1/6
//   Sgt. Biermann — ldr morale 8, cmd 1, fp 1/1/6
//   Cpl. Reiterhaus — ldr morale 7, cmd 1, fp 1/1/6
//   Volksgrenadier ×3 — morale 7, fp 5/4/4
//   Conscript ×5  — morale 6, fp 5/3/3
//   Heavy MG ×2   — fp 8/range 16, movePenalty -1
//   Light MG ×2   — fp 4/range 8
//
// American Forces (from scenario card):
//   Lt. Blankenship — ldr morale 9, cmd 1, fp 1/1/6
//   Sgt. Smith      — ldr morale 8, cmd 2, fp 2/1/6
//   Cpl. Hubbard    — ldr morale 7, cmd 1, fp 1/1/6
//   Elite ×2        — morale 7, fp 6/6/5 (fpBoxed)
//   Line ×6         — morale 6, fp 6/6/4
//   Weapon team ×1  — morale 7, fp 2/2/4
//   Medium MG ×1    — fp 6/range 10
//   Light Mortar ×1 — fp 7/range 2-16, movePenalty -2
//   Radio: 105mm ×1

export function buildUnits2(): Record<string, Unit> {
  const units: Record<string, Unit> = {};

  const german: Omit<Unit, 'id'>[] = [
    attachLeaderChart({
      faction: 'german', type: 'leader', unitClass: 'elite', name: 'Lt. Schrader',
      stats: { fp: 1, fpBoxed: false, range: 1, rangeBoxed: false, move: 6, morale: 9, command: 1 },
      q: 13, r: 4, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'german', 'Lieutenant X'),
    attachLeaderChart({
      faction: 'german', type: 'leader', unitClass: 'elite', name: 'Sgt. Esser',
      stats: { fp: 2, fpBoxed: false, range: 1, rangeBoxed: false, move: 6, morale: 8, command: 2 },
      q: 12, r: 3, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'german', 'Sergeant Y'),
    attachLeaderChart({
      faction: 'german', type: 'leader', unitClass: 'rifle', name: 'Sgt. Biermann',
      stats: { fp: 1, fpBoxed: false, range: 1, rangeBoxed: false, move: 6, morale: 8, command: 1 },
      q: 12, r: 6, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'german', 'Sergeant X'),
    attachLeaderChart({
      faction: 'german', type: 'leader', unitClass: 'rifle', name: 'Cpl. Reiterhaus',
      stats: { fp: 1, fpBoxed: false, range: 1, rangeBoxed: false, move: 6, morale: 7, command: 1 },
      q: 13, r: 7, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'german', 'Corporal X'),
    // Volksgrenadier ×3
    attachCountryUnitChart({
      faction: 'german', type: 'squad', unitClass: 'volksgrenadier', name: 'Volksgrenadier 1',
      stats: { fp: 5, fpBoxed: false, range: 4, rangeBoxed: true, move: 4, morale: 7 },
      q: 11, r: 3, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'german', 'squad', 'Volksgrenadier'),
    attachCountryUnitChart({
      faction: 'german', type: 'squad', unitClass: 'volksgrenadier', name: 'Volksgrenadier 2',
      stats: { fp: 5, fpBoxed: false, range: 4, rangeBoxed: true, move: 4, morale: 7 },
      q: 12, r: 5, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'german', 'squad', 'Volksgrenadier'),
    attachCountryUnitChart({
      faction: 'german', type: 'squad', unitClass: 'volksgrenadier', name: 'Volksgrenadier 3',
      stats: { fp: 5, fpBoxed: false, range: 4, rangeBoxed: true, move: 4, morale: 7 },
      q: 13, r: 6, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'german', 'squad', 'Volksgrenadier'),
    // Conscript ×5
    attachCountryUnitChart({
      faction: 'german', type: 'squad', unitClass: 'conscript', name: 'Conscript 1',
      stats: { fp: 5, fpBoxed: false, range: 3, rangeBoxed: true, move: 3, morale: 6 },
      q: 10, r: 2, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'german', 'squad', 'Conscript'),
    attachCountryUnitChart({
      faction: 'german', type: 'squad', unitClass: 'conscript', name: 'Conscript 2',
      stats: { fp: 5, fpBoxed: false, range: 3, rangeBoxed: true, move: 3, morale: 6 },
      q: 10, r: 4, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'german', 'squad', 'Conscript'),
    attachCountryUnitChart({
      faction: 'german', type: 'squad', unitClass: 'conscript', name: 'Conscript 3',
      stats: { fp: 5, fpBoxed: false, range: 3, rangeBoxed: true, move: 3, morale: 6 },
      q: 10, r: 6, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'german', 'squad', 'Conscript'),
    attachCountryUnitChart({
      faction: 'german', type: 'squad', unitClass: 'conscript', name: 'Conscript 4',
      stats: { fp: 5, fpBoxed: false, range: 3, rangeBoxed: true, move: 3, morale: 6 },
      q: 11, r: 7, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'german', 'squad', 'Conscript'),
    attachCountryUnitChart({
      faction: 'german', type: 'squad', unitClass: 'conscript', name: 'Conscript 5',
      stats: { fp: 5, fpBoxed: false, range: 3, rangeBoxed: true, move: 3, morale: 6 },
      q: 14, r: 5, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'german', 'squad', 'Conscript'),
    // Heavy MG ×2
    attachWeaponChart({
      faction: 'german', type: 'weapon', unitClass: 'mg', name: 'Heavy MG 1',
      stats: { fp: 8, fpBoxed: false, range: 16, rangeBoxed: true, move: 0, morale: 0 },
      q: 11, r: 3, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'german', 'Heavy MG'),
    attachWeaponChart({
      faction: 'german', type: 'weapon', unitClass: 'mg', name: 'Heavy MG 2',
      stats: { fp: 8, fpBoxed: false, range: 16, rangeBoxed: true, move: 0, morale: 0 },
      q: 13, r: 7, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'german', 'Heavy MG'),
    // Light MG ×2
    attachWeaponChart({
      faction: 'german', type: 'weapon', unitClass: 'mg', name: 'Light MG 1',
      stats: { fp: 4, fpBoxed: true, range: 8, rangeBoxed: true, move: 0, morale: 0 },
      q: 12, r: 5, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'german', 'Light MG'),
    attachWeaponChart({
      faction: 'german', type: 'weapon', unitClass: 'mg', name: 'Light MG 2',
      stats: { fp: 4, fpBoxed: true, range: 8, rangeBoxed: true, move: 0, morale: 0 },
      q: 14, r: 5, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'german', 'Light MG'),
  ];

  const american: Omit<Unit, 'id'>[] = [
    attachLeaderChart({
      faction: 'american', type: 'leader', unitClass: 'elite', name: 'Lt. Blankenship',
      stats: { fp: 1, fpBoxed: false, range: 1, rangeBoxed: false, move: 6, morale: 9, command: 1 },
      q: 1, r: 4, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'american', 'Lieutenant X'),
    attachLeaderChart({
      faction: 'american', type: 'leader', unitClass: 'elite', name: 'Sgt. Smith',
      stats: { fp: 2, fpBoxed: false, range: 1, rangeBoxed: false, move: 6, morale: 8, command: 2 },
      q: 1, r: 3, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'american', 'Sergeant Y'),
    attachLeaderChart({
      faction: 'american', type: 'leader', unitClass: 'rifle', name: 'Cpl. Hubbard',
      stats: { fp: 1, fpBoxed: false, range: 1, rangeBoxed: false, move: 6, morale: 7, command: 1 },
      q: 1, r: 6, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'american', 'Corporal X'),
    // Elite ×2
    attachCountryUnitChart({
      faction: 'american', type: 'squad', unitClass: 'elite', name: 'Elite 1',
      stats: { fp: 6, fpBoxed: true, range: 6, rangeBoxed: false, move: 5, morale: 7 },
      q: 0, r: 3, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'american', 'squad', 'Elite'),
    attachCountryUnitChart({
      faction: 'american', type: 'squad', unitClass: 'elite', name: 'Elite 2',
      stats: { fp: 6, fpBoxed: true, range: 6, rangeBoxed: false, move: 5, morale: 7 },
      q: 0, r: 6, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'american', 'squad', 'Elite'),
    // Line ×6
    attachCountryUnitChart({
      faction: 'american', type: 'squad', unitClass: 'line', name: 'Line 1',
      stats: { fp: 6, fpBoxed: false, range: 6, rangeBoxed: false, move: 4, morale: 6 },
      q: 0, r: 2, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'american', 'squad', 'Line'),
    attachCountryUnitChart({
      faction: 'american', type: 'squad', unitClass: 'line', name: 'Line 2',
      stats: { fp: 6, fpBoxed: false, range: 6, rangeBoxed: false, move: 4, morale: 6 },
      q: 0, r: 4, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'american', 'squad', 'Line'),
    attachCountryUnitChart({
      faction: 'american', type: 'squad', unitClass: 'line', name: 'Line 3',
      stats: { fp: 6, fpBoxed: false, range: 6, rangeBoxed: false, move: 4, morale: 6 },
      q: 0, r: 5, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'american', 'squad', 'Line'),
    attachCountryUnitChart({
      faction: 'american', type: 'squad', unitClass: 'line', name: 'Line 4',
      stats: { fp: 6, fpBoxed: false, range: 6, rangeBoxed: false, move: 4, morale: 6 },
      q: 0, r: 7, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'american', 'squad', 'Line'),
    attachCountryUnitChart({
      faction: 'american', type: 'squad', unitClass: 'line', name: 'Line 5',
      stats: { fp: 6, fpBoxed: false, range: 6, rangeBoxed: false, move: 4, morale: 6 },
      q: 1, r: 2, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'american', 'squad', 'Line'),
    attachCountryUnitChart({
      faction: 'american', type: 'squad', unitClass: 'line', name: 'Line 6',
      stats: { fp: 6, fpBoxed: false, range: 6, rangeBoxed: false, move: 4, morale: 6 },
      q: 1, r: 7, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'american', 'squad', 'Line'),
    // Weapon team ×1
    attachCountryUnitChart({
      faction: 'american', type: 'team', unitClass: 'weapon', name: 'Weapon Team',
      stats: { fp: 2, fpBoxed: false, range: 2, rangeBoxed: false, move: 4, morale: 7 },
      q: 2, r: 4, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'american', 'team', 'Weapon'),
    // Medium MG ×1
    attachWeaponChart({
      faction: 'american', type: 'weapon', unitClass: 'mg', name: 'Medium MG',
      stats: { fp: 6, fpBoxed: false, range: 10, rangeBoxed: true, move: 0, morale: 0 },
      q: 2, r: 4, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'american', 'Medium MG'),
    // Light Mortar ×1
    attachWeaponChart({
      faction: 'american', type: 'weapon', unitClass: 'mortar', name: 'Light Mortar',
      stats: { fp: 7, fpBoxed: false, range: 16, rangeBoxed: false, move: 0, morale: 0 },
      q: 2, r: 5, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'american', 'Light Mortar'),
    // Radio: 105mm ×1
    {
      faction: 'american', type: 'weapon', unitClass: 'radio', name: 'Radio: 105mm',
      stats: { fp: 10, fpBoxed: true, range: 16, rangeBoxed: false, move: 0, morale: 0 },
      q: 1, r: 5, efficient: true, suppressed: false, activated: false, veteran: false,
      manifestId: 'radio-105-114mm',
    } as Omit<Unit, 'id'>,
  ];

  [...german, ...american].forEach((u, i) => {
    const id = `${u.faction}-${i}`;
    units[id] = { ...u, id } as Unit;
  });

  return units;
}

export const SCENARIO2_SETUP = {
  timeStart: 0,
  suddenDeath: 8,
  vpStart: 10,
  initiativeHolder: 'german' as 'german' | 'american',
  axisOrders: 4,
  alliedOrders: 3,
};
