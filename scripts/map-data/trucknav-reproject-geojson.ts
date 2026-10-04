import * as fs from 'node:fs';
import * as path from 'node:path';

import type { Position } from '@truckermudgeon/base/geom';
import { fromWgs84ToAtsCoords } from '@truckermudgeon/map/projections';

const TRUCKNAV_MERCATOR_R = 300000.0;

function toTruckNavCoords([gameX, gameY]: Position): [number, number] {
  const lon = (gameX / TRUCKNAV_MERCATOR_R) * (180.0 / Math.PI);
  const yMerc = -gameY / TRUCKNAV_MERCATOR_R;
  const latRad = 2.0 * Math.atan(Math.exp(yMerc)) - Math.PI / 2.0;
  const lat = latRad * (180.0 / Math.PI);
  return [lon, lat];
}

function reprojectPoint(value: unknown): unknown {
  if (
    Array.isArray(value) &&
    value.length >= 2 &&
    typeof value[0] === 'number' &&
    typeof value[1] === 'number'
  ) {
    const game = fromWgs84ToAtsCoords([value[0], value[1]]);
    return toTruckNavCoords(game);
  }

  if (Array.isArray(value)) {
    return value.map(reprojectPoint);
  }

  return value;
}

const [inputArg, outputArg] = process.argv.slice(2);
if (!inputArg || !outputArg) {
  console.error(
    'usage: tsx trucknav-reproject-geojson.ts <input.geojson> <output.geojson>',
  );
  process.exit(2);
}

const input = path.resolve(inputArg);
const output = path.resolve(outputArg);

const data = JSON.parse(fs.readFileSync(input, 'utf8'));
if (data?.type !== 'FeatureCollection' || !Array.isArray(data.features)) {
  throw new Error('expected a GeoJSON FeatureCollection');
}

let minX = Infinity;
let minY = Infinity;
let maxX = -Infinity;
let maxY = -Infinity;

function track(value: unknown): void {
  if (
    Array.isArray(value) &&
    value.length >= 2 &&
    typeof value[0] === 'number' &&
    typeof value[1] === 'number'
  ) {
    minX = Math.min(minX, value[0]);
    maxX = Math.max(maxX, value[0]);
    minY = Math.min(minY, value[1]);
    maxY = Math.max(maxY, value[1]);
    return;
  }
  if (Array.isArray(value)) {
    for (const item of value) track(item);
  }
}

for (const feature of data.features) {
  if (!feature?.geometry || feature.geometry.coordinates == null) continue;
  feature.geometry.coordinates = reprojectPoint(feature.geometry.coordinates);
  track(feature.geometry.coordinates);
}

if (
  !Number.isFinite(minX) ||
  !Number.isFinite(minY) ||
  Math.max(Math.abs(minX), Math.abs(maxX), Math.abs(minY), Math.abs(maxY)) > 40
) {
  throw new Error(
    `unexpected TruckNav map bounds: ${JSON.stringify({
      minX,
      minY,
      maxX,
      maxY,
    })}`,
  );
}

fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, JSON.stringify(data));

const visualManifest = {
  schemaVersion: 1,
  projection: 'trucknav-flat-mercator-r300000',
  features: data.features.length,
  bounds: { minX, minY, maxX, maxY },
};
fs.writeFileSync(
  path.join(path.dirname(output), 'trucknav-visual-manifest.json'),
  JSON.stringify(visualManifest, null, 2),
);

console.log('TruckNav visual reprojection complete.');
console.log(JSON.stringify(visualManifest, null, 2));
