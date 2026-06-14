import type { Hex, HexDirection, HexsideFeatureType, TerrainFeatureType, TerrainType } from './types';
import { adjacentHexCoords, hexDirectionBetween } from './los';

export interface HexLabelCoord {
  q: number;
  r: number;
}

export interface MapHexOverride {
  terrain?: TerrainType;
  terrainFeature?: TerrainFeatureType | null;
  elevation?: number;
  featureDirs?: HexDirection[];
  objectiveId?: number;
}

export interface MapSideFeature {
  from: string;
  to: string;
  feature: HexsideFeatureType;
}

export interface ElevationGroup {
  elevation: number;
  hexes: string[];
}

export interface MapDefinition {
  id: string;
  name: string;
  cols: number;
  rows: number;
  defaultTerrain?: TerrainType;
  terrainGroups?: Partial<Record<TerrainType, string[]>>;
  featureGroups?: Partial<Record<TerrainFeatureType, string[]>>;
  elevationGroups?: ElevationGroup[];
  hexOverrides?: Record<string, MapHexOverride>;
  sideFeatures?: MapSideFeature[];
}

export function hexLabel(q: number, r: number): string {
  return `${String.fromCharCode(65 + q)}${r + 1}`;
}

export function parseHexLabel(label: string): HexLabelCoord {
  const normalized = label.trim().toUpperCase();
  return {
    q: normalized.charCodeAt(0) - 65,
    r: Number(normalized.slice(1)) - 1,
  };
}

function applyHexOverride(hex: Hex, override?: MapHexOverride): Hex {
  if (!override) return hex;
  return {
    ...hex,
    terrain: override.terrain ?? hex.terrain,
    terrainFeature: override.terrainFeature === undefined ? hex.terrainFeature : override.terrainFeature,
    elevation: override.elevation ?? hex.elevation,
    objectiveId: override.objectiveId ?? hex.objectiveId,
    featureDirs: override.featureDirs ?? hex.featureDirs,
  };
}

function buildFeatureDirMap(
  labels: Set<string>,
  cols: number,
  rows: number,
): Partial<Record<string, HexDirection[]>> {
  const featureDirMap: Partial<Record<string, HexDirection[]>> = {};
  for (const label of labels) {
    const origin = parseHexLabel(label);
    const dirs = adjacentHexCoords(origin, cols, rows)
      .filter(({ q, r }) => labels.has(hexLabel(q, r)))
      .map(neighbor => hexDirectionBetween(origin, neighbor))
      .filter((dir): dir is HexDirection => !!dir);
    if (dirs.length > 0) featureDirMap[label] = dirs;
  }
  return featureDirMap;
}

export function buildHexGrid(
  definition: MapDefinition,
  objectiveByHex: Record<string, number> = {},
): Hex[][] {
  const defaultTerrain = definition.defaultTerrain ?? 'open';
  const hexes: Hex[][] = [];

  const terrainByHex: Partial<Record<string, TerrainType>> = {};
  for (const [terrain, labels] of Object.entries(definition.terrainGroups ?? {})) {
    for (const label of labels ?? []) {
      terrainByHex[label] = terrain as TerrainType;
    }
  }

  const featureByHex: Partial<Record<string, TerrainFeatureType>> = {};
  const featureDirByHex: Partial<Record<string, HexDirection[]>> = {};
  for (const [feature, labels] of Object.entries(definition.featureGroups ?? {})) {
    const labelSet = new Set(labels ?? []);
    const dirMap = buildFeatureDirMap(labelSet, definition.cols, definition.rows);
    for (const label of labels ?? []) {
      featureByHex[label] = feature as TerrainFeatureType;
      if (dirMap[label]) featureDirByHex[label] = dirMap[label];
    }
  }

  const elevationByHex: Partial<Record<string, number>> = {};
  for (const group of definition.elevationGroups ?? []) {
    for (const label of group.hexes) elevationByHex[label] = group.elevation;
  }

  for (let q = 0; q < definition.cols; q++) {
    hexes[q] = [];
    for (let r = 0; r < definition.rows; r++) {
      const label = hexLabel(q, r);
      const baseHex: Hex = {
        q,
        r,
        terrain: terrainByHex[label] ?? defaultTerrain,
        terrainFeature: featureByHex[label] ?? null,
        featureDirs: featureDirByHex[label],
        elevation: elevationByHex[label] ?? 0,
        objectiveId: objectiveByHex[label],
      };
      hexes[q][r] = applyHexOverride(baseHex, definition.hexOverrides?.[label]);
    }
  }

  for (const side of definition.sideFeatures ?? []) {
    const from = parseHexLabel(side.from);
    const to = parseHexLabel(side.to);
    const dir = hexDirectionBetween(from, to);
    const reverse = hexDirectionBetween(to, from);
    if (!dir || !reverse) continue;

    hexes[from.q][from.r].sideFeatures = {
      ...(hexes[from.q][from.r].sideFeatures ?? {}),
      [dir]: side.feature,
    };
    hexes[to.q][to.r].sideFeatures = {
      ...(hexes[to.q][to.r].sideFeatures ?? {}),
      [reverse]: side.feature,
    };
  }

  return hexes;
}

export function refreshFeatureDirs(hexes: Hex[][], cols: number, rows: number): void {
  for (let q = 0; q < cols; q++) {
    for (let r = 0; r < rows; r++) {
      const hex = hexes[q]?.[r];
      if (!hex?.terrainFeature) {
        if (hex) hex.featureDirs = undefined;
        continue;
      }

      const dirs = adjacentHexCoords({ q, r }, cols, rows)
        .filter(({ q: nq, r: nr }) => hexes[nq]?.[nr]?.terrainFeature === hex.terrainFeature)
        .map(neighbor => hexDirectionBetween({ q, r }, neighbor))
        .filter((dir): dir is HexDirection => !!dir);

      hex.featureDirs = dirs.length > 0 ? dirs : undefined;
    }
  }
}
