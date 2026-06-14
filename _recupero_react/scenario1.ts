// Scenario 1: "Fat Lipki" — Eastern Front, Russia 1941
// Germans (AXIS, bottom) vs Russians (ALLIES, top)
// Map A: cropped play area, 15 columns × 10 rows

import type { Hex, Unit, Objective } from './types';
import { buildHexGrid, type MapDefinition, type MapSideFeature } from './mapData';
import { attachCountryUnitChart, attachLeaderChart, attachWeaponChart } from './counterManifest';

export const SCENARIO_ID = 'fat_lipki';
export const SCENARIO_NAME = 'FAT LIPKI';
export const MAP_COLS = 15;
export const MAP_ROWS = 10;

const SIDE_FEATURES: MapSideFeature[] = [
  { from: 'A2', to: 'A3', feature: 'hedge' },
  { from: 'A3', to: 'B2', feature: 'hedge' },
  { from: 'A3', to: 'A4', feature: 'hedge' },
  { from: 'A4', to: 'B3', feature: 'hedge' },
  { from: 'A6', to: 'A7', feature: 'hedge' },
  { from: 'A6', to: 'B6', feature: 'hedge' },
  { from: 'A7', to: 'B7', feature: 'hedge' },
  { from: 'A8', to: 'B7', feature: 'hedge' },
  { from: 'A8', to: 'A9', feature: 'hedge' },
  { from: 'A9', to: 'B8', feature: 'hedge' },
  { from: 'B1', to: 'C2', feature: 'hedge' },
  { from: 'B1', to: 'B2', feature: 'hedge' },
  { from: 'B2', to: 'B3', feature: 'hedge' },
  { from: 'B3', to: 'C3', feature: 'hedge' },
  { from: 'B3', to: 'C4', feature: 'hedge' },
  { from: 'B3', to: 'B4', feature: 'hedge' },
  { from: 'B4', to: 'C5', feature: 'hedge' },
  { from: 'B5', to: 'B6', feature: 'hedge' },
  { from: 'B5', to: 'C6', feature: 'hedge' },
  { from: 'B5', to: 'C5', feature: 'hedge' },
  { from: 'B6', to: 'C6', feature: 'hedge' },
  { from: 'B6', to: 'B7', feature: 'hedge' },
  { from: 'B7', to: 'B8', feature: 'hedge' },
  { from: 'B8', to: 'C8', feature: 'hedge' },
  { from: 'B8', to: 'B9', feature: 'hedge' },
  { from: 'B9', to: 'C9', feature: 'hedge' },
  { from: 'C1', to: 'C2', feature: 'hedge' },
  { from: 'C1', to: 'D1', feature: 'hedge' },
  { from: 'C10', to: 'C9', feature: 'hedge' },
  { from: 'C10', to: 'D9', feature: 'hedge' },
  { from: 'C10', to: 'D10', feature: 'hedge' },
  { from: 'C2', to: 'D1', feature: 'hedge' },
  { from: 'C3', to: 'C4', feature: 'hedge' },
  { from: 'C3', to: 'D3', feature: 'hedge' },
  { from: 'C4', to: 'C5', feature: 'hedge' },
  { from: 'C5', to: 'D4', feature: 'hedge' },
  { from: 'C6', to: 'C7', feature: 'hedge' },
  { from: 'C7', to: 'D6', feature: 'hedge' },
  { from: 'C8', to: 'C9', feature: 'hedge' },
  { from: 'C8', to: 'D8', feature: 'hedge' },
  { from: 'C8', to: 'D7', feature: 'hedge' },
  { from: 'C9', to: 'D8', feature: 'hedge' },
  { from: 'D1', to: 'D2', feature: 'hedge' },
  { from: 'D1', to: 'E2', feature: 'hedge' },
  { from: 'D2', to: 'D3', feature: 'hedge' },
  { from: 'D2', to: 'E3', feature: 'hedge' },
  { from: 'D2', to: 'E2', feature: 'hedge' },
  { from: 'D3', to: 'E4', feature: 'hedge' },
  { from: 'D4', to: 'D5', feature: 'hedge' },
  { from: 'D4', to: 'E5', feature: 'hedge' },
  { from: 'D4', to: 'E4', feature: 'hedge' },
  { from: 'D5', to: 'E5', feature: 'hedge' },
  { from: 'D5', to: 'E6', feature: 'hedge' },
  { from: 'D6', to: 'D7', feature: 'hedge' },
  { from: 'D6', to: 'E7', feature: 'hedge' },
  { from: 'D6', to: 'E6', feature: 'hedge' },
  { from: 'D8', to: 'D9', feature: 'hedge' },
  { from: 'D8', to: 'E9', feature: 'hedge' },
  { from: 'D9', to: 'E10', feature: 'hedge' },
  { from: 'E1', to: 'E2', feature: 'hedge' },
  { from: 'E1', to: 'F1', feature: 'hedge' },
  { from: 'E10', to: 'E9', feature: 'hedge' },
  { from: 'E10', to: 'F9', feature: 'hedge' },
  { from: 'E2', to: 'E3', feature: 'hedge' },
  { from: 'E3', to: 'E4', feature: 'hedge' },
  { from: 'E3', to: 'F3', feature: 'hedge' },
  { from: 'E4', to: 'F4', feature: 'hedge' },
  { from: 'E5', to: 'F4', feature: 'hedge' },
  { from: 'E5', to: 'F5', feature: 'hedge' },
  { from: 'E5', to: 'E6', feature: 'hedge' },
  { from: 'E6', to: 'E7', feature: 'hedge' },
  { from: 'E6', to: 'F5', feature: 'hedge' },
  { from: 'E7', to: 'F7', feature: 'hedge' },
  { from: 'E7', to: 'F6', feature: 'hedge' },
  { from: 'E8', to: 'E9', feature: 'hedge' },
  { from: 'E8', to: 'F8', feature: 'hedge' },
  { from: 'E8', to: 'F7', feature: 'hedge' },
  { from: 'E9', to: 'F9', feature: 'hedge' },
  { from: 'F1', to: 'G2', feature: 'hedge' },
  { from: 'F1', to: 'G1', feature: 'hedge' },
  { from: 'F10', to: 'F9', feature: 'hedge' },
  { from: 'F10', to: 'G10', feature: 'hedge' },
  { from: 'F2', to: 'F3', feature: 'hedge' },
  { from: 'F2', to: 'G3', feature: 'hedge' },
  { from: 'F2', to: 'G2', feature: 'hedge' },
  { from: 'F3', to: 'G3', feature: 'hedge' },
  { from: 'F3', to: 'F4', feature: 'hedge' },
  { from: 'F4', to: 'G4', feature: 'hedge' },
  { from: 'F5', to: 'F6', feature: 'hedge' },
  { from: 'F5', to: 'G6', feature: 'hedge' },
  { from: 'F7', to: 'F8', feature: 'hedge' },
  { from: 'F7', to: 'G8', feature: 'hedge' },
  { from: 'F8', to: 'F9', feature: 'hedge' },
  { from: 'F8', to: 'G9', feature: 'hedge' },
  { from: 'G1', to: 'H1', feature: 'hedge' },
  { from: 'G10', to: 'H9', feature: 'hedge' },
  { from: 'G2', to: 'G3', feature: 'hedge' },
  { from: 'G2', to: 'H1', feature: 'hedge' },
  { from: 'G2', to: 'H2', feature: 'hedge' },
  { from: 'G3', to: 'G4', feature: 'hedge' },
  { from: 'G3', to: 'H3', feature: 'hedge' },
  { from: 'G4', to: 'G5', feature: 'hedge' },
  { from: 'G4', to: 'H3', feature: 'hedge' },
  { from: 'G4', to: 'H4', feature: 'hedge' },
  { from: 'G5', to: 'H4', feature: 'hedge' },
  { from: 'G5', to: 'H5', feature: 'hedge' },
  { from: 'G5', to: 'G6', feature: 'hedge' },
  { from: 'G7', to: 'G8', feature: 'hedge' },
  { from: 'G7', to: 'H7', feature: 'hedge' },
  { from: 'G8', to: 'G9', feature: 'hedge' },
  { from: 'G8', to: 'H8', feature: 'hedge' },
  { from: 'G9', to: 'H8', feature: 'hedge' },
  { from: 'G9', to: 'H9', feature: 'hedge' },
  { from: 'H1', to: 'I1', feature: 'hedge' },
  { from: 'H10', to: 'H9', feature: 'hedge' },
  { from: 'H10', to: 'I10', feature: 'hedge' },
  { from: 'H2', to: 'I3', feature: 'hedge' },
  { from: 'H2', to: 'H3', feature: 'hedge' },
  { from: 'H3', to: 'I3', feature: 'hedge' },
  { from: 'H4', to: 'H5', feature: 'hedge' },
  { from: 'H5', to: 'I6', feature: 'hedge' },
  { from: 'H6', to: 'H7', feature: 'hedge' },
  { from: 'H6', to: 'I7', feature: 'hedge' },
  { from: 'H6', to: 'I6', feature: 'hedge' },
  { from: 'H7', to: 'H8', feature: 'hedge' },
  { from: 'H7', to: 'I8', feature: 'hedge' },
  { from: 'H8', to: 'I9', feature: 'hedge' },
  { from: 'H9', to: 'I9', feature: 'hedge' },
  { from: 'I1', to: 'I2', feature: 'hedge' },
  { from: 'I10', to: 'I9', feature: 'hedge' },
  { from: 'I10', to: 'J10', feature: 'hedge' },
  { from: 'I2', to: 'J1', feature: 'hedge' },
  { from: 'I2', to: 'J2', feature: 'hedge' },
  { from: 'I2', to: 'I3', feature: 'hedge' },
  { from: 'I3', to: 'I4', feature: 'hedge' },
  { from: 'I3', to: 'J3', feature: 'hedge' },
  { from: 'I3', to: 'J2', feature: 'hedge' },
  { from: 'I5', to: 'J5', feature: 'hedge' },
  { from: 'I6', to: 'J6', feature: 'hedge' },
  { from: 'I6', to: 'J5', feature: 'hedge' },
  { from: 'I7', to: 'I8', feature: 'hedge' },
  { from: 'I7', to: 'J6', feature: 'hedge' },
  { from: 'I9', to: 'J9', feature: 'hedge' },
  { from: 'J10', to: 'J9', feature: 'hedge' },
  { from: 'J10', to: 'K10', feature: 'hedge' },
  { from: 'J2', to: 'K3', feature: 'hedge' },
  { from: 'J3', to: 'K3', feature: 'hedge' },
  { from: 'J4', to: 'J5', feature: 'hedge' },
  { from: 'J4', to: 'K5', feature: 'hedge' },
  { from: 'J5', to: 'J6', feature: 'hedge' },
  { from: 'J5', to: 'K6', feature: 'hedge' },
  { from: 'J6', to: 'J7', feature: 'hedge' },
  { from: 'J6', to: 'K7', feature: 'hedge' },
  { from: 'J6', to: 'K6', feature: 'hedge' },
  { from: 'J7', to: 'K7', feature: 'hedge' },
  { from: 'J7', to: 'K8', feature: 'hedge' },
  { from: 'J8', to: 'J9', feature: 'hedge' },
  { from: 'J8', to: 'K9', feature: 'hedge' },
  { from: 'J8', to: 'K8', feature: 'hedge' },
  { from: 'J9', to: 'K10', feature: 'hedge' },
  { from: 'K10', to: 'L10', feature: 'hedge' },
  { from: 'K2', to: 'L2', feature: 'hedge' },
  { from: 'K2', to: 'K3', feature: 'hedge' },
  { from: 'K2', to: 'L1', feature: 'hedge' },
  { from: 'K3', to: 'K4', feature: 'hedge' },
  { from: 'K3', to: 'L3', feature: 'hedge' },
  { from: 'K4', to: 'K5', feature: 'hedge' },
  { from: 'K4', to: 'L4', feature: 'hedge' },
  { from: 'K5', to: 'K6', feature: 'hedge' },
  { from: 'K5', to: 'L5', feature: 'hedge' },
  { from: 'K5', to: 'L4', feature: 'hedge' },
  { from: 'K6', to: 'L5', feature: 'hedge' },
  { from: 'K7', to: 'K8', feature: 'hedge' },
  { from: 'K8', to: 'L7', feature: 'hedge' },
  { from: 'L1', to: 'L2', feature: 'hedge' },
  { from: 'L10', to: 'L9', feature: 'hedge' },
  { from: 'L10', to: 'M10', feature: 'hedge' },
  { from: 'L2', to: 'M2', feature: 'hedge' },
  { from: 'L2', to: 'M3', feature: 'hedge' },
  { from: 'L2', to: 'L3', feature: 'hedge' },
  { from: 'L3', to: 'L4', feature: 'hedge' },
  { from: 'L4', to: 'M4', feature: 'hedge' },
  { from: 'L5', to: 'L6', feature: 'hedge' },
  { from: 'L6', to: 'M6', feature: 'hedge' },
  { from: 'L7', to: 'L8', feature: 'hedge' },
  { from: 'L8', to: 'M8', feature: 'hedge' },
  { from: 'L8', to: 'M9', feature: 'hedge' },
  { from: 'L9', to: 'M10', feature: 'hedge' },
  { from: 'L9', to: 'M9', feature: 'hedge' },
  { from: 'M1', to: 'N1', feature: 'hedge' },
  { from: 'M10', to: 'N10', feature: 'hedge' },
  { from: 'M10', to: 'N9', feature: 'hedge' },
  { from: 'M2', to: 'N2', feature: 'hedge' },
  { from: 'M2', to: 'N1', feature: 'hedge' },
  { from: 'M3', to: 'M4', feature: 'hedge' },
  { from: 'M3', to: 'N2', feature: 'hedge' },
  { from: 'M4', to: 'N3', feature: 'hedge' },
  { from: 'M4', to: 'M5', feature: 'hedge' },
  { from: 'M5', to: 'N5', feature: 'hedge' },
  { from: 'M5', to: 'N4', feature: 'hedge' },
  { from: 'M6', to: 'M7', feature: 'hedge' },
  { from: 'M6', to: 'N6', feature: 'hedge' },
  { from: 'M6', to: 'N5', feature: 'hedge' },
  { from: 'M7', to: 'N7', feature: 'hedge' },
  { from: 'M7', to: 'N6', feature: 'hedge' },
  { from: 'M8', to: 'M9', feature: 'hedge' },
  { from: 'M8', to: 'N8', feature: 'hedge' },
  { from: 'M8', to: 'N7', feature: 'hedge' },
  { from: 'M9', to: 'N9', feature: 'hedge' },
  { from: 'M9', to: 'N8', feature: 'hedge' },
  { from: 'N10', to: 'N9', feature: 'hedge' },
  { from: 'N10', to: 'O10', feature: 'hedge' },
  { from: 'N2', to: 'N3', feature: 'hedge' },
  { from: 'N2', to: 'O3', feature: 'hedge' },
  { from: 'N3', to: 'N4', feature: 'hedge' },
  { from: 'N4', to: 'O5', feature: 'hedge' },
  { from: 'N4', to: 'O4', feature: 'hedge' },
  { from: 'N5', to: 'O6', feature: 'hedge' },
  { from: 'N5', to: 'O5', feature: 'hedge' },
  { from: 'N6', to: 'O6', feature: 'hedge' },
  { from: 'N6', to: 'O7', feature: 'hedge' },
  { from: 'N7', to: 'O7', feature: 'hedge' },
  { from: 'N8', to: 'N9', feature: 'hedge' },
  { from: 'N8', to: 'O9', feature: 'hedge' },
  { from: 'O2', to: 'O3', feature: 'hedge' },
  { from: 'O7', to: 'O8', feature: 'hedge' },
  { from: 'O8', to: 'O9', feature: 'hedge' },
];

// Objectives (approximate hex positions from Mappa_1)
const OBJECTIVE_DEFS = [
  { id: 1, q: 5,  r: 1,  vp: 2, initController: null  as 'german'|'russian'|null },  // top building
  { id: 2, q: 5,  r: 7,  vp: 2, initController: null  },  // bottom building
  { id: 3, q: 7,  r: 4,  vp: 3, initController: null  },  // crossroads center
];

const FAT_LIPKI_MAP: MapDefinition = {
  id: 'map-a-fat-lipki',
  name: 'Map A / Fat Lipki',
  cols: MAP_COLS,
  rows: MAP_ROWS,
  defaultTerrain: 'open',
  terrainGroups: {
    building: ['F6', 'G7', 'H6', 'J8', 'N3'],
    field: ['A9', 'B9', 'B10', 'C10', 'E2', 'F1', 'F2', 'F4', 'F5', 'G5', 'I3', 'J6', 'K8', 'K9', 'K10', 'L4', 'L5', 'L8', 'L9', 'M5', 'M6', 'M9', 'M10', 'O3', 'O4', 'O5', 'O6', 'O7'],
    orchard: ['C5', 'C6', 'D5', 'D6', 'F9', 'G9', 'G10', 'H10', 'I8', 'I9', 'K3', 'K6', 'K7', 'L2', 'L6', 'L7', 'M7', 'M8', 'N1', 'N2'],
    woods: ['A1', 'A2', 'B7', 'C8', 'F10', 'H3', 'H4', 'J4', 'J10', 'K2', 'L10', 'N8', 'N10'],
  },
  featureGroups: {
    road: ['A5', 'A8', 'B4', 'B8', 'C4', 'C9', 'D9', 'E9', 'F8', 'G6', 'G8', 'H5', 'H7', 'I4', 'I5', 'I6', 'I7', 'J1', 'J2', 'J3', 'J7', 'J8', 'K4', 'L3', 'M3', 'M4', 'N4', 'N5', 'N6', 'N7', 'O8'],
  },
  sideFeatures: SIDE_FEATURES,
};

export function buildMap(): Hex[][] {
  const objectiveByHex = Object.fromEntries(
    OBJECTIVE_DEFS.map(objective => [`${String.fromCharCode(65 + objective.q)}${objective.r + 1}`, objective.id]),
  );
  return buildHexGrid(FAT_LIPKI_MAP, objectiveByHex);
}

export function buildObjectives(): Objective[] {
  return OBJECTIVE_DEFS.map(o => ({
    ...o,
    secret: false,
    controller: o.initController,
  })) as Objective[];
}

// ─── Units — from scenario card ───────────────────────────────────────────────
// Stats format: FP - Range - Move, Morale in top-right of counter
// AXIS (German) starts at right columns (q=12..14), ALLIES (Russian) at left (q=0..2)
// Units from scenario card (scenario1.png):
//   German: Lt. v. Karstens (ldr 9/②), Cpl. Winkler (ldr 6/①), Rifle×4 (5/[5]/4 mor7), Light MG ([4]/8/-)
//   Russian: Sgt. Kovalev (ldr 8/②), Cpl. Koylov (ldr 7/①), Rifle×8 (5/3/4 mor7), Med MG×2 ([6]/10/-2), Light MG ([3]/6/-)

export function buildUnits(): Record<string, Unit> {
  const units: Record<string, Unit> = {};

  const german: Omit<Unit, 'id'>[] = [
    attachLeaderChart({
      faction: 'german', type: 'leader', unitClass: 'elite', name: 'Lt. v. Karstens',
      stats: { fp: 2, fpBoxed: false, range: 1, rangeBoxed: false, move: 6, morale: 9, command: 2 },
      q: 13, r: 4, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'german', 'Lieutenant Y'),
    attachLeaderChart({
      faction: 'german', type: 'leader', unitClass: 'rifle', name: 'Cpl. Winkler',
      stats: { fp: 1, fpBoxed: false, range: 1, rangeBoxed: false, move: 6, morale: 6, command: 1 },
      q: 13, r: 6, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'german', 'Corporal X'),
    attachCountryUnitChart({
      faction: 'german', type: 'squad', unitClass: 'rifle', name: 'Rifle 1',
      stats: { fp: 5, fpBoxed: false, range: 5, rangeBoxed: true, move: 4, moveBoxed: true, morale: 7 },
      q: 12, r: 3, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'german', 'squad', 'Rifle'),
    attachCountryUnitChart({
      faction: 'german', type: 'squad', unitClass: 'rifle', name: 'Rifle 2',
      stats: { fp: 5, fpBoxed: false, range: 5, rangeBoxed: true, move: 4, moveBoxed: true, morale: 7 },
      q: 14, r: 3, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'german', 'squad', 'Rifle'),
    attachCountryUnitChart({
      faction: 'german', type: 'squad', unitClass: 'rifle', name: 'Rifle 3',
      stats: { fp: 5, fpBoxed: false, range: 5, rangeBoxed: true, move: 4, moveBoxed: true, morale: 7 },
      q: 12, r: 5, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'german', 'squad', 'Rifle'),
    attachCountryUnitChart({
      faction: 'german', type: 'squad', unitClass: 'rifle', name: 'Rifle 4',
      stats: { fp: 5, fpBoxed: false, range: 5, rangeBoxed: true, move: 4, moveBoxed: true, morale: 7 },
      q: 14, r: 5, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'german', 'squad', 'Rifle'),
    attachWeaponChart({
      faction: 'german', type: 'weapon', unitClass: 'mg', name: 'Light MG',
      stats: { fp: 4, fpBoxed: true, range: 8, rangeBoxed: true, move: 0, morale: 0 },
      q: 12, r: 5, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'german', 'Light MG'),
  ];

  const russian: Omit<Unit, 'id'>[] = [
    attachLeaderChart({
      faction: 'russian', type: 'leader', unitClass: 'elite', name: 'Sgt. Kovalev',
      stats: { fp: 2, fpBoxed: false, range: 1, rangeBoxed: false, move: 6, morale: 8, command: 2 },
      q: 1, r: 4, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'russian', 'Sergeant Y'),
    attachLeaderChart({
      faction: 'russian', type: 'leader', unitClass: 'rifle', name: 'Cpl. Koylov',
      stats: { fp: 1, fpBoxed: false, range: 1, rangeBoxed: false, move: 6, morale: 7, command: 1 },
      q: 1, r: 6, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'russian', 'Corporal Y'),
    attachCountryUnitChart({
      faction: 'russian', type: 'squad', unitClass: 'rifle', name: 'Rifle 1',
      stats: { fp: 5, fpBoxed: false, range: 3, rangeBoxed: false, move: 4, morale: 7 },
      q: 0, r: 2, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'russian', 'squad', 'Rifle'),
    attachCountryUnitChart({
      faction: 'russian', type: 'squad', unitClass: 'rifle', name: 'Rifle 2',
      stats: { fp: 5, fpBoxed: false, range: 3, rangeBoxed: false, move: 4, morale: 7 },
      q: 0, r: 3, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'russian', 'squad', 'Rifle'),
    attachCountryUnitChart({
      faction: 'russian', type: 'squad', unitClass: 'rifle', name: 'Rifle 3',
      stats: { fp: 5, fpBoxed: false, range: 3, rangeBoxed: false, move: 4, morale: 7 },
      q: 0, r: 5, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'russian', 'squad', 'Rifle'),
    attachCountryUnitChart({
      faction: 'russian', type: 'squad', unitClass: 'rifle', name: 'Rifle 4',
      stats: { fp: 5, fpBoxed: false, range: 3, rangeBoxed: false, move: 4, morale: 7 },
      q: 0, r: 6, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'russian', 'squad', 'Rifle'),
    attachCountryUnitChart({
      faction: 'russian', type: 'squad', unitClass: 'rifle', name: 'Rifle 5',
      stats: { fp: 5, fpBoxed: false, range: 3, rangeBoxed: false, move: 4, morale: 7 },
      q: 1, r: 2, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'russian', 'squad', 'Rifle'),
    attachCountryUnitChart({
      faction: 'russian', type: 'squad', unitClass: 'rifle', name: 'Rifle 6',
      stats: { fp: 5, fpBoxed: false, range: 3, rangeBoxed: false, move: 4, morale: 7 },
      q: 1, r: 3, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'russian', 'squad', 'Rifle'),
    attachCountryUnitChart({
      faction: 'russian', type: 'squad', unitClass: 'rifle', name: 'Rifle 7',
      stats: { fp: 5, fpBoxed: false, range: 3, rangeBoxed: false, move: 4, morale: 7 },
      q: 2, r: 3, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'russian', 'squad', 'Rifle'),
    attachCountryUnitChart({
      faction: 'russian', type: 'squad', unitClass: 'rifle', name: 'Rifle 8',
      stats: { fp: 5, fpBoxed: false, range: 3, rangeBoxed: false, move: 4, morale: 7 },
      q: 2, r: 5, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'russian', 'squad', 'Rifle'),
    attachWeaponChart({
      faction: 'russian', type: 'weapon', unitClass: 'mg', name: 'Medium MG 1',
      stats: { fp: 6, fpBoxed: true, range: 10, rangeBoxed: false, move: 0, morale: 0 },
      q: 0, r: 5, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'russian', 'Medium MG'),
    attachWeaponChart({
      faction: 'russian', type: 'weapon', unitClass: 'mg', name: 'Medium MG 2',
      stats: { fp: 6, fpBoxed: true, range: 10, rangeBoxed: false, move: 0, morale: 0 },
      q: 2, r: 3, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'russian', 'Medium MG'),
    attachWeaponChart({
      faction: 'russian', type: 'weapon', unitClass: 'mg', name: 'Light MG',
      stats: { fp: 3, fpBoxed: true, range: 6, rangeBoxed: true, move: 0, morale: 0 },
      q: 0, r: 3, efficient: true, suppressed: false, activated: false, veteran: false,
    }, 'russian', 'Light MG'),
  ];

  [...german, ...russian].forEach((u, i) => {
    const id = `${u.faction}-${i}`;
    units[id] = { ...u, id } as Unit;
  });

  return units;
}

// Scenario setup data
export const SCENARIO_SETUP = {
  timeStart: 2,       // '1941' space
  suddenDeath: 7,
  germanSurrender: 5,
  russianSurrender: 7,
  vpStart: 0,
  initiativeHolder: 'german' as 'german' | 'russian',
  germanOrders: 2,
  russianOrders: 3,
};
