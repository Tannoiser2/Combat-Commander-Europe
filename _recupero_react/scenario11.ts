// Scenario 11: scaffold map data. Terrain, objectives and units to be filled in
// by the map editor. Background map image is mappa11.png.

import type { Hex, Unit, Objective } from './types';
import { buildHexGrid, type MapDefinition, type MapSideFeature } from './mapData';

export const SCENARIO_ID = 'scenario_11';
export const MAP11_COLS = 15;
export const MAP11_ROWS = 10;

const SIDE_FEATURES: MapSideFeature[] = [
];

const MAP11_DEF: MapDefinition = {
  id: 'map-11',
  name: 'Map 11',
  cols: MAP11_COLS,
  rows: MAP11_ROWS,
  defaultTerrain: 'open',
  terrainGroups: {
  },
  featureGroups: {
  },
  elevationGroups: [
  ],
  sideFeatures: SIDE_FEATURES,
};

export function buildMap11(): Hex[][] {
  return buildHexGrid(MAP11_DEF, {});
}

export function buildObjectives11(): Objective[] {
  return [];
}

export function buildUnits11(): Record<string, Unit> {
  return {};
}
