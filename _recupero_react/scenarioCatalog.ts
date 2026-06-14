import type { Faction } from './types';

export type MapId =
  | 'map1' | 'map2' | 'map3' | 'map4' | 'map5'
  | 'map6' | 'map7' | 'map8' | 'map9' | 'map10'
  | 'map11' | 'map12' | 'map13' | 'map14' | 'map15'
  | 'map16' | 'map17' | 'map18' | 'map19' | 'map20'
  | 'map21' | 'map22' | 'map23' | 'map24';

// Each side enters from a map edge. Default convention in this project:
// Axis on the East (right), Allied on the West (left). Some scenarios may
// reverse or use North/South edges depending on the official scenario card.
export type MapEdge = 'east' | 'west' | 'north' | 'south';

export interface ScenarioMeta {
  id: string;           // internal key, e.g. 'scenario_01'
  number: number;       // 1-24
  name: string;
  location: string;     // e.g. "Lipki, Russia"
  year: number;
  axisFaction: Faction;
  alliedFaction: Faction;
  mapId: MapId;
  axisOrders: number;
  alliedOrders: number;
  axisHandSize?: number;       // Troop Quality hand size (Green=4, Line=5, Elite=6); default 5
  alliedHandSize?: number;
  suddenDeath: number;
  vpStart: number;           // positive = axis side, negative = allied side
  axisPosture: 'attack' | 'defend' | 'recon';
  alliedPosture: 'attack' | 'defend' | 'recon';
  initiativeHolder: 'axis' | 'allies';
  humanSide: 'axis' | 'allies';   // which side the human player controls
  // Setup zones — per-scenario edge + depth (number of rows/cols from edge).
  // Defaults: axis=east depth 3, allied=west depth 3.
  axisEdge?: MapEdge;
  alliedEdge?: MapEdge;
  axisSetupDepth?: number;
  alliedSetupDepth?: number;
  // Anchor-based setup: lists of hex labels (e.g. ['A2','O1']) where the side
  // can set up in OR adjacent to. When provided, overrides edge+depth.
  axisSetupAnchors?: string[];
  alliedSetupAnchors?: string[];
}

export const SCENARIO_CATALOG: ScenarioMeta[] = [
  {
    id: 'scenario_01', number: 1, name: 'Fat Lipki',
    location: 'Lipki, Russia', year: 1941,
    axisFaction: 'german', alliedFaction: 'russian',
    mapId: 'map1',
    axisOrders: 2, alliedOrders: 3,
    axisHandSize: 5, alliedHandSize: 5,
    suddenDeath: 7, vpStart: 0,
    axisPosture: 'recon', alliedPosture: 'recon',
    initiativeHolder: 'axis',
    humanSide: 'axis',
    // Scenario card: Allies set up in/adjacent to A2 and O1;
    // Axis sets up in/adjacent to G10 and/or N10.
    alliedSetupAnchors: ['A2', 'O1'],
    axisSetupAnchors: ['G10', 'N10'],
  },
  {
    id: 'scenario_02', number: 2, name: 'Hedgerows & Hand Grenades',
    location: 'Pont-Hebert, Normandia', year: 1944,
    axisFaction: 'german', alliedFaction: 'american',
    mapId: 'map2',
    axisOrders: 4, alliedOrders: 3,
    axisHandSize: 4, alliedHandSize: 5,
    suddenDeath: 8, vpStart: 10,
    axisPosture: 'defend', alliedPosture: 'attack',
    initiativeHolder: 'axis',
    humanSide: 'allies',
  },
  {
    id: 'scenario_03', number: 3, name: 'Bonfire of the NKVD',
    location: 'Brest-Litovsk, Russia', year: 1941,
    axisFaction: 'german', alliedFaction: 'russian',
    mapId: 'map3',
    axisOrders: 3, alliedOrders: 4,
    axisHandSize: 5, alliedHandSize: 4,
    suddenDeath: 7, vpStart: -20,
    axisPosture: 'attack', alliedPosture: 'defend',
    initiativeHolder: 'axis',
    humanSide: 'axis',
  },
  {
    id: 'scenario_04', number: 4, name: 'Closed for Renovation',
    location: 'Humain, Belgio', year: 1944,
    axisFaction: 'german', alliedFaction: 'american',
    mapId: 'map4',
    axisOrders: 3, alliedOrders: 4,
    axisHandSize: 6, alliedHandSize: 6,
    suddenDeath: 7, vpStart: 20,
    axisPosture: 'defend', alliedPosture: 'attack',
    initiativeHolder: 'axis',
    humanSide: 'axis',
  },
  {
    id: 'scenario_05', number: 5, name: 'Cold Front',
    location: 'Staritsa, Russia', year: 1941,
    axisFaction: 'german', alliedFaction: 'russian',
    mapId: 'map5',
    axisOrders: 3, alliedOrders: 5,
    axisHandSize: 5, alliedHandSize: 6,
    suddenDeath: 13, vpStart: 9,
    axisPosture: 'defend', alliedPosture: 'attack',
    initiativeHolder: 'allies',
    humanSide: 'axis',
  },
  {
    id: 'scenario_06', number: 6, name: 'Paralyzed from the West Down',
    location: 'St. Mere-Eglise, Francia', year: 1944,
    axisFaction: 'german', alliedFaction: 'american',
    mapId: 'map6',
    axisOrders: 1, alliedOrders: 4,
    axisHandSize: 5, alliedHandSize: 6,
    suddenDeath: 6, vpStart: 9,
    axisPosture: 'defend', alliedPosture: 'attack',
    initiativeHolder: 'allies',
    humanSide: 'axis',
  },
  {
    id: 'scenario_07', number: 7, name: 'Bessarabian Nights',
    location: 'Bessarabia', year: 1944,
    axisFaction: 'german', alliedFaction: 'russian',
    mapId: 'map7',
    axisOrders: 3, alliedOrders: 1,
    axisHandSize: 5, alliedHandSize: 5,
    suddenDeath: 5, vpStart: 0,
    axisPosture: 'recon', alliedPosture: 'defend',
    initiativeHolder: 'axis',
    humanSide: 'axis',
  },
  {
    id: 'scenario_08', number: 8, name: 'Breakout Dance',
    location: 'Velikiye-Luki, Russia', year: 1943,
    axisFaction: 'german', alliedFaction: 'russian',
    mapId: 'map8',
    axisOrders: 3, alliedOrders: 1,
    axisHandSize: 5, alliedHandSize: 5,
    suddenDeath: 5, vpStart: -2,
    axisPosture: 'recon', alliedPosture: 'recon',
    initiativeHolder: 'axis',
    humanSide: 'axis',
  },
  {
    id: 'scenario_09', number: 9, name: 'Rush to Contact',
    location: 'Hitdorf, Germania', year: 1945,
    axisFaction: 'german', alliedFaction: 'american',
    mapId: 'map9',
    axisOrders: 4, alliedOrders: 6,
    axisHandSize: 5, alliedHandSize: 6,
    suddenDeath: 12, vpStart: 14,
    axisPosture: 'defend', alliedPosture: 'attack',
    initiativeHolder: 'axis',
    humanSide: 'axis',
  },
  {
    id: 'scenario_10', number: 10, name: 'Commando School',
    location: 'Novorossiysk, Russia', year: 1943,
    axisFaction: 'german', alliedFaction: 'russian',
    mapId: 'map10',
    axisOrders: 4, alliedOrders: 3,
    axisHandSize: 5, alliedHandSize: 6,
    suddenDeath: 6, vpStart: -9,
    axisPosture: 'attack', alliedPosture: 'defend',
    initiativeHolder: 'axis',
    humanSide: 'axis',
  },
  {
    id: 'scenario_11', number: 11, name: 'Hold the Line',
    location: 'St. Jean de Daye, Francia', year: 1944,
    axisFaction: 'german', alliedFaction: 'american',
    mapId: 'map1',
    axisOrders: 2, alliedOrders: 2,
    axisHandSize: 6, alliedHandSize: 5,
    suddenDeath: 6, vpStart: -10,
    axisPosture: 'attack', alliedPosture: 'defend',
    initiativeHolder: 'axis',
    humanSide: 'axis',
  },
  {
    id: 'scenario_12', number: 12, name: 'Misty Mountain',
    location: 'Monte Castello, Italia', year: 1944,
    axisFaction: 'german', alliedFaction: 'brazilian',
    mapId: 'map1',
    axisOrders: 4, alliedOrders: 5,
    axisHandSize: 5, alliedHandSize: 5,
    suddenDeath: 12, vpStart: 16,
    axisPosture: 'defend', alliedPosture: 'attack',
    initiativeHolder: 'axis',
    humanSide: 'axis',
  },
  {
    id: 'scenario_13', number: 13, name: 'Tussle at Maleme',
    location: 'Maleme, Creta', year: 1941,
    axisFaction: 'german', alliedFaction: 'anzac',
    mapId: 'map1',
    axisOrders: 3, alliedOrders: 4,
    axisHandSize: 6, alliedHandSize: 6,
    suddenDeath: 6, vpStart: 3,
    axisPosture: 'defend', alliedPosture: 'attack',
    initiativeHolder: 'axis',
    humanSide: 'axis',
  },
  {
    id: 'scenario_14', number: 14, name: 'At the Crossroads',
    location: 'Sochaczew, Polonia', year: 1939,
    axisFaction: 'german', alliedFaction: 'polish',
    mapId: 'map2',
    axisOrders: 3, alliedOrders: 4,
    axisHandSize: 5, alliedHandSize: 5,
    suddenDeath: 6, vpStart: 3,
    axisPosture: 'defend', alliedPosture: 'attack',
    initiativeHolder: 'axis',
    humanSide: 'axis',
  },
  {
    id: 'scenario_15', number: 15, name: 'Armata Romana',
    location: 'Bessarabia', year: 1941,
    axisFaction: 'romanian', alliedFaction: 'russian',
    mapId: 'map2',
    axisOrders: 5, alliedOrders: 3,
    axisHandSize: 5, alliedHandSize: 5,
    suddenDeath: 7, vpStart: -12,
    axisPosture: 'attack', alliedPosture: 'defend',
    initiativeHolder: 'axis',
    humanSide: 'axis',
  },
  {
    id: 'scenario_16', number: 16, name: 'The Blitzkrieg Checked',
    location: 'Gembloux, Francia', year: 1940,
    axisFaction: 'german', alliedFaction: 'french',
    mapId: 'map1',
    axisOrders: 4, alliedOrders: 3,
    axisHandSize: 5, alliedHandSize: 6,
    suddenDeath: 7, vpStart: -30,
    axisPosture: 'attack', alliedPosture: 'defend',
    initiativeHolder: 'axis',
    humanSide: 'axis',
  },
  {
    id: 'scenario_17', number: 17, name: 'Little Stalingrad',
    location: 'Ortona, Italia', year: 1943,
    axisFaction: 'german', alliedFaction: 'canadian',
    mapId: 'map2',
    axisOrders: 4, alliedOrders: 4,
    axisHandSize: 6, alliedHandSize: 6,
    suddenDeath: 7, vpStart: 0,
    axisPosture: 'recon', alliedPosture: 'recon',
    initiativeHolder: 'allies',
    humanSide: 'axis',
  },
  {
    id: 'scenario_18', number: 18, name: 'Bridge Hunt',
    location: 'Nisava, Jugoslavia', year: 1941,
    axisFaction: 'german', alliedFaction: 'yugoslav',
    mapId: 'map1',
    axisOrders: 3, alliedOrders: 3,
    axisHandSize: 5, alliedHandSize: 4,
    suddenDeath: 6, vpStart: -16,
    axisPosture: 'attack', alliedPosture: 'defend',
    initiativeHolder: 'axis',
    humanSide: 'axis',
  },
  {
    id: 'scenario_19', number: 19, name: 'La Stagione di Metaxas',
    location: 'Kilkis, Grecia', year: 1941,
    axisFaction: 'german', alliedFaction: 'french',
    mapId: 'map1',
    axisOrders: 3, alliedOrders: 4,
    axisHandSize: 6, alliedHandSize: 5,
    suddenDeath: 7, vpStart: -12,
    axisPosture: 'attack', alliedPosture: 'defend',
    initiativeHolder: 'axis',
    humanSide: 'axis',
  },
  {
    id: 'scenario_20', number: 20, name: 'Marcia di Dicembre',
    location: 'Tolvajärvi, Finlandia', year: 1939,
    axisFaction: 'italian', alliedFaction: 'russian',
    mapId: 'map1',
    axisOrders: 3, alliedOrders: 4,
    axisHandSize: 6, alliedHandSize: 5,
    suddenDeath: 7, vpStart: -4,
    axisPosture: 'attack', alliedPosture: 'recon',
    initiativeHolder: 'axis',
    humanSide: 'axis',
  },
  {
    id: 'scenario_21', number: 21, name: "Sant'Agata",
    location: 'Sicilia settentrionale', year: 1943,
    axisFaction: 'italian', alliedFaction: 'american',
    mapId: 'map2',
    axisOrders: 3, alliedOrders: 3,
    axisHandSize: 5, alliedHandSize: 5,
    suddenDeath: 7, vpStart: 12,
    axisPosture: 'defend', alliedPosture: 'attack',
    initiativeHolder: 'allies',
    humanSide: 'allies',
  },
  {
    id: 'scenario_22', number: 22, name: 'Un Vero Bagno di Sangue',
    location: 'A sud di Goch, Olanda', year: 1945,
    axisFaction: 'german', alliedFaction: 'british',
    mapId: 'map2',
    axisOrders: 3, alliedOrders: 4,
    axisHandSize: 4, alliedHandSize: 5,
    suddenDeath: 6, vpStart: 16,
    axisPosture: 'defend', alliedPosture: 'recon',
    initiativeHolder: 'axis',
    humanSide: 'allies',
  },
  {
    id: 'scenario_23', number: 23, name: 'Terra di Nessuno',
    location: 'Deserto meridionale, Egitto', year: 1942,
    axisFaction: 'italian', alliedFaction: 'british',
    mapId: 'map1',
    axisOrders: 2, alliedOrders: 2,
    axisHandSize: 5, alliedHandSize: 5,
    suddenDeath: 12, vpStart: 0,
    axisPosture: 'recon', alliedPosture: 'recon',
    initiativeHolder: 'axis',
    humanSide: 'axis',
  },
  {
    id: 'scenario_24', number: 24, name: 'Sei Colline',
    location: 'Passo Tug Argan, Somaliland', year: 1940,
    axisFaction: 'italian', alliedFaction: 'british',
    mapId: 'map1',
    axisOrders: 4, alliedOrders: 3,
    axisHandSize: 5, alliedHandSize: 4,
    suddenDeath: 7, vpStart: -16,
    axisPosture: 'attack', alliedPosture: 'defend',
    initiativeHolder: 'axis',
    humanSide: 'axis',
  },
];

export const MAP_IMAGE: Record<MapId, string> = {
  map1: '/mappa1.png',
  map2: '/mappa2.png',
  map3: '/mappa3.png',
  map4: '/mappa4.png',
  map5: '/mappa5.png',
  map6: '/mappa6.png',
  map7: '/mappa7.png',
  map8: '/mappa8.png',
  map9: '/mappa9.png',
  map10: '/mappa10.png',
  map11: '/mappa11.png',
  map12: '/mappa12.png',
  map13: '/mappa13.png',
  map14: '/mappa14.png',
  map15: '/mappa15.png',
  map16: '/mappa16.png',
  map17: '/mappa17.png',
  map18: '/mappa18.png',
  map19: '/mappa19.png',
  map20: '/mappa20.png',
  map21: '/mappa21.png',
  map22: '/mappa22.png',
  map23: '/mappa23.png',
  map24: '/mappa24.png',
};

export function getScenario(id: string): ScenarioMeta | undefined {
  return SCENARIO_CATALOG.find(s => s.id === id);
}
