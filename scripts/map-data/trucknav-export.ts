import * as fs from 'node:fs';
import * as path from 'node:path';

import {
  readGraphData,
  readMapData,
  readRoundaboutsData,
} from '@truckermudgeon/io';
import {
  AtsDlc,
  AtsDlcGuards,
  ItemType,
} from '@truckermudgeon/map/constants';
import { getCommonItem } from '@truckermudgeon/map/get-common-item';
import { getLineString } from '@truckermudgeon/map/linestring';
import type { Position } from '@truckermudgeon/base/geom';
import { fromAtsCoordsToWgs84 } from '@truckermudgeon/map/projections';
import type {
  CompanyItem,
  Ferry,
  Node,
} from '@truckermudgeon/map/types';

const GRAPH_STRIDE = 12;
const DLC_MASK_FLAG = 1 << 20;

const [parserDirArg, graphDirArg, outDirArg] = process.argv.slice(2);
if (!parserDirArg || !graphDirArg || !outDirArg) {
  console.error(
    'usage: tsx trucknav-export.ts <parser-dir> <graph-dir> <output-dir>',
  );
  process.exit(2);
}

const parserDir = path.resolve(parserDirArg);
const graphDir = path.resolve(graphDirArg);
const outDir = path.resolve(outDirArg);
fs.mkdirSync(outDir, { recursive: true });

const truckNavDlcIds = new Map<number, number>([
  [AtsDlc.NewMexico, 1],
  [AtsDlc.Oregon, 2],
  [AtsDlc.Washington, 3],
  [AtsDlc.Utah, 4],
  [AtsDlc.Idaho, 5],
  [AtsDlc.Colorado, 6],
  [AtsDlc.Wyoming, 7],
  [AtsDlc.Montana, 8],
  [AtsDlc.Texas, 9],
  [AtsDlc.Oklahoma, 10],
  [AtsDlc.Kansas, 11],
  [AtsDlc.Nebraska, 12],
  [AtsDlc.Arkansas, 13],
  [AtsDlc.Missouri, 14],
  [AtsDlc.Iowa, 15],
  [AtsDlc.Louisiana, 16],
  [AtsDlc.Illinois, 17],
  [AtsDlc.SouthDakota, 18],
]);

function encodeDlcGuard(guard: number): {
  encoded: number;
  truckNavIds: number[];
} | null {
  const dlcs = AtsDlcGuards[guard as keyof typeof AtsDlcGuards];
  if (!dlcs) {
    return null;
  }

  const ids = [...dlcs]
    .map(dlc => truckNavDlcIds.get(dlc))
    .filter((id): id is number => id != null)
    .sort((a, b) => a - b);

  if (ids.length === 0) {
    return { encoded: 0, truckNavIds: [] };
  }
  if (ids.length === 1) {
    return { encoded: ids[0], truckNavIds: ids };
  }

  let mask = 0;
  for (const id of ids) {
    mask |= 1 << (id - 1);
  }
  return { encoded: DLC_MASK_FLAG + mask, truckNavIds: ids };
}

function heading(p0: [number, number], p1: [number, number]): number {
  const latRad = p0[1] * (Math.PI / 180);
  const xDiff = (p1[0] - p0[0]) * Math.cos(latRad);
  return Math.atan2(p1[1] - p0[1], xDiff);
}

function normalizeAngle(angle: number): number {
  while (angle > Math.PI) angle -= Math.PI * 2;
  while (angle < -Math.PI) angle += Math.PI * 2;
  return angle;
}

function classifyPrefabManeuver(
  startHeading: number,
  endHeading: number,
): number {
  const turn = normalizeAngle(endHeading - startHeading);
  const abs = Math.abs(turn);
  if (abs < 0.45) return 0;
  if (abs < 0.9) return turn > 0 ? 6 : 7;
  return turn > 0 ? 1 : 2;
}

function dedupeCoords(coords: [number, number][]): [number, number][] {
  const result: [number, number][] = [];
  for (const point of coords) {
    const prev = result.at(-1);
    if (!prev || prev[0] !== point[0] || prev[1] !== point[1]) {
      result.push(point);
    }
  }
  return result;
}

console.log('Reading parser and routing data...');
const tsMapData = readMapData(parserDir, 'usa', {
  mapDataKeys: [
    'nodes',
    'roads',
    'prefabs',
    'companies',
    'ferries',
    'roadLooks',
    'prefabDescriptions',
  ],
});
const graphData = readGraphData(graphDir, 'usa');
const roundaboutData = readRoundaboutsData(graphDir, 'usa');

const ferriesByUid = new Map<bigint, Ferry & { type: ItemType.Ferry }>(
  tsMapData.ferries
    .values()
    .map(f => [f.uid, { ...f, type: ItemType.Ferry }]),
);
const companiesByPrefab = new Map<bigint, CompanyItem>(
  tsMapData.companies.values().map(c => [c.prefabUid, c]),
);
const lookups = { ferriesByUid, companiesByPrefab };

const roundaboutNodes = new Set<bigint>();
for (const desc of roundaboutData.descs) {
  for (const uid of desc.cycleNodeUids) roundaboutNodes.add(uid);
  for (const [entryUid, exits] of desc.paths) {
    roundaboutNodes.add(entryUid);
    for (const exitUid of exits.keys()) roundaboutNodes.add(exitUid);
  }
}

const uniqueUids = new Set<bigint>();
for (const [u, neighbors] of graphData.graph) {
  uniqueUids.add(u);
  for (const edge of [...neighbors.forward, ...neighbors.backward]) {
    uniqueUids.add(edge.nodeUid);
  }
}

const nodeList = [...uniqueUids].sort((a, b) => {
  const ah = a.toString(16);
  const bh = b.toString(16);
  return ah < bh ? -1 : ah > bh ? 1 : 0;
});
const uidToInt = new Map<bigint, number>(
  nodeList.map((uid, index) => [uid, index]),
);

console.log(`Writing ${nodeList.length} compact TruckNav node ids...`);
const nodesBuffer = Buffer.alloc(nodeList.length * 16);
for (let i = 0; i < nodeList.length; i++) {
  nodesBuffer.write(
    nodeList[i].toString(16).padEnd(16, '\0'),
    i * 16,
    16,
    'ascii',
  );
}
fs.writeFileSync(path.join(outDir, 'nodes.bin'), nodesBuffer);

const graphFd = fs.openSync(path.join(outDir, 'graph.bin'), 'w');
const geometryFd = fs.openSync(path.join(outDir, 'geometry.bin'), 'w');

let edgeCount = 0;
let geometryFloatPointer = 0;
let geometryPointCount = 0;
let fallbackGeometryCount = 0;
let southDakotaEdgeCount = 0;
let compositeDlcEdgeCount = 0;
let roundaboutEdgeCount = 0;
const maneuverCounts = new Map<number, number>();
const guardCounts = new Map<number, number>();
const skippedUnknownGuardCounts = new Map<number, number>();

function fallbackLine(a: Node, b: Node): Position[] {
  return [
    [a.x, a.y],
    [b.x, b.y],
  ];
}

try {
  for (const [u, neighbors] of graphData.graph) {
    const startNode = tsMapData.nodes.get(u);
    if (!startNode) {
      throw new Error(`graph start node missing from parser data: ${u.toString(16)}`);
    }

    for (const edge of [...neighbors.forward, ...neighbors.backward]) {
      const v = edge.nodeUid;
      const endNode = tsMapData.nodes.get(v);
      if (!endNode) {
        throw new Error(`graph end node missing from parser data: ${v.toString(16)}`);
      }

      const uInt = uidToInt.get(u);
      const vInt = uidToInt.get(v);
      if (uInt == null || vInt == null) {
        throw new Error('internal compact node mapping error');
      }

      const dlcEncoding = encodeDlcGuard(edge.dlcGuard);
      if (dlcEncoding == null) {
        skippedUnknownGuardCounts.set(
          edge.dlcGuard,
          (skippedUnknownGuardCounts.get(edge.dlcGuard) ?? 0) + 1,
        );
        continue;
      }

      let gameGeometry: Position[];
      let itemType: ItemType | undefined;
      let prefabToken: string | undefined;
      try {
        const item = getCommonItem(u, v, tsMapData, lookups);
        itemType = item.type;
        if (item.type === ItemType.Prefab) prefabToken = item.token;
        gameGeometry = getLineString([u, v], tsMapData, lookups);
      } catch {
        // The upstream graph intentionally creates a small number of synthetic
        // company/dead-end edges. They have no physical shared map item.
        gameGeometry = fallbackLine(startNode, endNode);
        fallbackGeometryCount++;
      }

      let coords = dedupeCoords(
        gameGeometry.map(p => fromAtsCoordsToWgs84(p) as [number, number]),
      );
      if (coords.length < 2) {
        coords = [
          fromAtsCoordsToWgs84([startNode.x, startNode.y]) as [number, number],
          fromAtsCoordsToWgs84([endNode.x, endNode.y]) as [number, number],
        ];
        fallbackGeometryCount++;
      }

      const hOut = heading(coords[0], coords[1]);
      const hIn = heading(coords.at(-2)!, coords.at(-1)!);

      const { encoded: requiredDlc, truckNavIds } = dlcEncoding;
      guardCounts.set(edge.dlcGuard, (guardCounts.get(edge.dlcGuard) ?? 0) + 1);
      if (truckNavIds.includes(18)) southDakotaEdgeCount++;
      if (truckNavIds.length > 1) compositeDlcEdgeCount++;

      const isRoundabout =
        roundaboutNodes.has(u) ||
        roundaboutNodes.has(v) ||
        (prefabToken != null && roundaboutData.prefabTokens.has(prefabToken));

      let maneuverType = 0;
      let exitNumber = 0;
      if (isRoundabout) {
        maneuverType = 3;
        // Exit ordinal reconstruction can be added later. Zero deliberately
        // yields TruckNav's generic "Take the exit at the roundabout" prompt.
        exitNumber = 0;
        roundaboutEdgeCount++;
      } else if (itemType === ItemType.Prefab) {
        maneuverType = classifyPrefabManeuver(hOut, hIn);
      }
      maneuverCounts.set(
        maneuverType,
        (maneuverCounts.get(maneuverType) ?? 0) + 1,
      );

      const startIndex = geometryFloatPointer;
      const geometry = new Float32Array(coords.length * 2);
      for (let i = 0; i < coords.length; i++) {
        geometry[i * 2] = coords[i][0];
        geometry[i * 2 + 1] = coords[i][1];
      }
      fs.writeSync(
        geometryFd,
        Buffer.from(geometry.buffer, geometry.byteOffset, geometry.byteLength),
      );
      geometryFloatPointer += geometry.length;
      geometryPointCount += coords.length;

      const graphRow = new Float32Array(GRAPH_STRIDE);
      graphRow[0] = uInt;
      graphRow[1] = vInt;
      graphRow[2] = edge.distance || 1;
      graphRow[3] = hIn;
      graphRow[4] = hOut;
      graphRow[5] = edge.isFerry ? 1 : 0;
      graphRow[6] = requiredDlc;
      graphRow[7] = 0;
      graphRow[8] = startIndex;
      graphRow[9] = coords.length;
      graphRow[10] = maneuverType;
      graphRow[11] = exitNumber;
      fs.writeSync(
        graphFd,
        Buffer.from(graphRow.buffer, graphRow.byteOffset, graphRow.byteLength),
      );

      edgeCount++;
      if (edgeCount % 25000 === 0) {
        console.log(`  exported ${edgeCount} edges...`);
      }
    }
  }
} finally {
  fs.closeSync(graphFd);
  fs.closeSync(geometryFd);
}

const manifest = {
  schemaVersion: 2,
  source: {
    game: 'ats',
    parserVersionFile: 'usa-version.txt',
  },
  graph: {
    stride: GRAPH_STRIDE,
    edges: edgeCount,
    nodes: nodeList.length,
    geometryPoints: geometryPointCount,
    fallbackGeometryEdges: fallbackGeometryCount,
  },
  dlcEncoding: {
    legacySingleId: true,
    compositeMaskFlag: DLC_MASK_FLAG,
    southDakotaTruckNavId: 18,
    southDakotaEdges: southDakotaEdgeCount,
    compositeEdges: compositeDlcEdgeCount,
  },
  navigation: {
    roundaboutEdges: roundaboutEdgeCount,
    roundaboutExitOrdinals: false,
    maneuverCounts: Object.fromEntries(
      [...maneuverCounts.entries()].sort((a, b) => a[0] - b[0]),
    ),
  },
  sourceDlcGuardCounts: Object.fromEntries(
    [...guardCounts.entries()].sort((a, b) => a[0] - b[0]),
  ),
  skippedUnknownDlcGuards: Object.fromEntries(
    [...skippedUnknownGuardCounts.entries()].sort((a, b) => a[0] - b[0]),
  ),
};
fs.writeFileSync(
  path.join(outDir, 'trucknav-graph-manifest.json'),
  JSON.stringify(manifest, null, 2),
);

if (skippedUnknownGuardCounts.size > 0) {
  console.warn(
    'Skipped edges with unknown/unreleased ATS DLC guards:',
    Object.fromEntries(
      [...skippedUnknownGuardCounts.entries()].sort((a, b) => a[0] - b[0]),
    ),
  );
}

console.log('');
console.log('TruckNav graph export complete.');
console.log(JSON.stringify(manifest, null, 2));
