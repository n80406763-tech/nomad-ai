import { readFile, writeFile } from "node:fs/promises";

const [inputPath, outputPath] = process.argv.slice(2);

if (!inputPath || !outputPath) {
  throw new Error(
    "Usage: node convert-geofabrik-poly.mjs INPUT.poly OUTPUT.geojson",
  );
}

const lines = (await readFile(inputPath, "utf8")).split(/\r?\n/);
const polygons = [];
let currentPolygon = null;
let currentRing = null;

for (const rawLine of lines.slice(1)) {
  const line = rawLine.trim();
  if (!line) continue;
  if (line === "END") {
    if (currentRing) {
      currentPolygon.rings.push({
        hole: currentRing.hole,
        coordinates: currentRing.coordinates,
      });
      currentRing = null;
    } else if (currentPolygon) {
      polygons.push(currentPolygon);
      currentPolygon = null;
    } else {
      break;
    }
    continue;
  }

  const pair = line.split(/\s+/).map(Number);
  if (pair.length === 2 && pair.every(Number.isFinite)) {
    if (!currentRing)
      throw new Error(`Coordinate without ring header: ${line}`);
    currentRing.coordinates.push(pair);
    continue;
  }

  if (currentRing) throw new Error(`Unexpected ring header: ${line}`);
  if (!currentPolygon) currentPolygon = { rings: [] };
  currentRing = { hole: line.startsWith("!"), coordinates: [] };
}

const geometries = polygons.map(({ rings }) => {
  const outer = rings
    .filter((ring) => !ring.hole)
    .map((ring) => ring.coordinates);
  const holes = rings
    .filter((ring) => ring.hole)
    .map((ring) => ring.coordinates);
  return holes.length === 0 && outer.length === 1
    ? { type: "Polygon", coordinates: outer }
    : {
        type: "MultiPolygon",
        coordinates: outer.map((ring) => [ring, ...holes]),
      };
});

const geometry =
  geometries.length === 1
    ? geometries[0]
    : { type: "GeometryCollection", geometries };

await writeFile(
  outputPath,
  JSON.stringify({ type: "Feature", properties: { name: "Russia" }, geometry }),
);
