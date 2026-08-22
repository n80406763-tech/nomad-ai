import { createWriteStream } from "node:fs";
import { mkdir, mkdtemp, readFile, rename, rm } from "node:fs/promises";
import { dirname, join } from "node:path";
import { tmpdir } from "node:os";
import { spawn } from "node:child_process";

// Строит компактный офлайн-граф федеральных трасс России (магистрали, трассы,
// дороги первого класса) для маршрутизации по дорогам без сети — вместо
// прямой линии между точками. Запускается один раз на CI перед сборкой.
//
// Осознанно ограничен "скелетом" сети (motorway/trunk/primary + съезды):
// полный граф со всеми дорогами вплоть до местных улиц для страны размера
// России — это уже задача уровня OSRM/Valhalla с отдельным пайплайном
// (extract/partition/customize) и десятками ГБ исходных данных, что не
// умещается в разумный CI-шаг. Этот граф покрывает дальние межгородские
// поездки; последняя миля до точки (в городе/посёлке) достраивается прямой
// линией на стороне приложения — см. Sources/OfflineRoadGraph.swift.
//
// Usage: node build-offline-road-graph.mjs OUTPUT.json [overpass-endpoint]

const [outputPath, endpointArg] = process.argv.slice(2);
if (!outputPath) {
  throw new Error("Usage: node build-offline-road-graph.mjs OUTPUT.json [overpass-endpoint]");
}
const endpoint = endpointArg || "https://overpass-api.de/api/interpreter";

const HIGHWAY_CLASSES = ["motorway", "trunk", "primary", "motorway_link", "trunk_link", "primary_link"];

const SPEED_KMH = {
  motorway: 110,
  trunk: 90,
  primary: 70,
  motorway_link: 60,
  trunk_link: 50,
  primary_link: 40,
};

// curl вместо fetch(): надёжнее для очень больших ответов (потоковая запись
// на диск, не в память) и не зависит от особенностей HTTP-стека Node/undici
// за прокси, которые могут обрезать длинные chunked-ответы.
async function fetchOverpass(query) {
  const dir = await mkdtemp(join(tmpdir(), "nomad-overpass-"));
  const destPath = join(dir, "response.json");
  try {
    await new Promise((resolve, reject) => {
      const child = spawn("curl", [
        "--fail",
        "--silent",
        "--show-error",
        "--location",
        "--max-time",
        "1800",
        "-X",
        "POST",
        "-H",
        "User-Agent: NomadAI-OfflineBuild/1.0",
        "--data-urlencode",
        `data=${query}`,
        "-o",
        destPath,
        endpoint,
      ]);
      child.stderr.pipe(process.stderr);
      child.on("error", reject);
      child.on("close", (code) => (code === 0 ? resolve() : reject(new Error(`curl завершился с кодом ${code}`))));
    });
    const raw = await readFile(destPath, "utf8");
    return JSON.parse(raw);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

// Ключ узла — округлённые координаты (~0.1 м), чтобы совпадающие точки
// пересечения дорог в разных ways схлопывались в один узел графа.
const nodeKey = (lat, lon) => `${lat.toFixed(6)},${lon.toFixed(6)}`;

function haversine(lat1, lon1, lat2, lon2) {
  const R = 6_371_000;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

async function main() {
  const areaFilter = process.env.OFFLINE_ROADS_BBOX
    ? `(${process.env.OFFLINE_ROADS_BBOX})`
    : "(area.ru)";
  const areaSetup = process.env.OFFLINE_ROADS_BBOX ? "" : 'area["ISO3166-1"="RU"][admin_level=2]->.ru;\n';
  const highwayRegex = HIGHWAY_CLASSES.join("|");

  const query = `[out:json][timeout:900];\n${areaSetup}(\n  way["highway"~"^(${highwayRegex})$"]${areaFilter};\n);\nout geom;`;

  console.log("Запрашиваю Overpass (это может занять несколько минут для всей страны)...");
  const data = await fetchOverpass(query);
  const ways = (data.elements || []).filter((el) => el.type === "way" && Array.isArray(el.geometry));
  console.log(`Получено ways: ${ways.length}`);

  const nodeIndex = new Map(); // key -> index
  const nodes = []; // [lat, lon]

  const indexForPoint = (lat, lon) => {
    const key = nodeKey(lat, lon);
    let idx = nodeIndex.get(key);
    if (idx === undefined) {
      idx = nodes.length;
      nodes.push([lat, lon]);
      nodeIndex.set(key, idx);
    }
    return idx;
  };

  // edges: [fromIdx, toIdx, meters, speedKmh]
  const edges = [];

  for (const way of ways) {
    const tags = way.tags || {};
    const highway = tags.highway;
    const speed = SPEED_KMH[highway] ?? 60;
    const geometry = way.geometry.filter((p) => typeof p.lat === "number" && typeof p.lon === "number");
    if (geometry.length < 2) continue;

    const isMotorwayDefault = highway === "motorway" || highway === "motorway_link";
    const oneway = tags.oneway === "yes" || tags.oneway === "true" || tags.oneway === "1" || (tags.oneway === undefined && isMotorwayDefault);
    const reverseOnly = tags.oneway === "-1" || tags.oneway === "reverse";

    for (let i = 0; i < geometry.length - 1; i++) {
      const a = geometry[i];
      const b = geometry[i + 1];
      const aIdx = indexForPoint(a.lat, a.lon);
      const bIdx = indexForPoint(b.lat, b.lon);
      if (aIdx === bIdx) continue;
      const meters = haversine(a.lat, a.lon, b.lat, b.lon);
      if (meters <= 0) continue;

      if (reverseOnly) {
        edges.push([bIdx, aIdx, meters, speed]);
      } else if (oneway) {
        edges.push([aIdx, bIdx, meters, speed]);
      } else {
        edges.push([aIdx, bIdx, meters, speed]);
        edges.push([bIdx, aIdx, meters, speed]);
      }
    }
  }

  console.log(`Узлов: ${nodes.length}, рёбер: ${edges.length}`);

  await mkdir(dirname(outputPath), { recursive: true });
  const temporaryPath = `${outputPath}.tmp`;
  const output = createWriteStream(temporaryPath, { encoding: "utf8" });
  output.write('{"v":1,"s":"OpenStreetMap ODbL","n":[');
  nodes.forEach((n, i) => {
    if (i > 0) output.write(",");
    output.write(`[${n[0]},${n[1]}]`);
  });
  output.write('],"e":[');
  edges.forEach((e, i) => {
    if (i > 0) output.write(",");
    output.write(`[${e[0]},${e[1]},${Math.round(e[2])},${e[3]}]`);
  });
  output.write("]}");
  output.end();
  await new Promise((resolve, reject) => output.once("finish", resolve).once("error", reject));
  await rename(temporaryPath, outputPath);
  console.log(`Offline Russia road graph: ${nodes.length} nodes, ${edges.length} edges`);
}

await main();
