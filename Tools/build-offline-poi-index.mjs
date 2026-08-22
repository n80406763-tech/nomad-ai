import { createWriteStream } from "node:fs";
import { mkdir, mkdtemp, readFile, rename, rm } from "node:fs/promises";
import { dirname, join } from "node:path";
import { tmpdir } from "node:os";
import { spawn } from "node:child_process";

// Строит офлайн-базу точек интереса (АЗС, отели, супермаркеты, кафе, аптеки,
// шиномонтаж/СТО, банкоматы) для всей России через Overpass API — один раз
// на этапе сборки CI, чтобы в приложении эти данные уже лежали в бандле
// и не требовали сети во время поездки.
//
// Usage: node build-offline-poi-index.mjs OUTPUT.json [overpass-endpoint]

const [outputPath, endpointArg] = process.argv.slice(2);
if (!outputPath) {
  throw new Error("Usage: node build-offline-poi-index.mjs OUTPUT.json [overpass-endpoint]");
}
const endpoint = endpointArg || "https://overpass-api.de/api/interpreter";

// Код категории -> тег OSM. Держим соответствие с OverpassService.category(fromTags:) в Swift.
const CATEGORIES = [
  { code: "f", tag: 'node["amenity"="fuel"]' },
  { code: "h", tag: 'node["tourism"="hotel"]' },
  { code: "s", tag: 'node["shop"="supermarket"]' },
  { code: "c", tag: 'node["amenity"="cafe"]' },
  { code: "p", tag: 'node["amenity"="pharmacy"]' },
  { code: "r", tag: 'node["shop"="car_repair"]' },
  { code: "a", tag: 'node["amenity"="atm"]' },
];

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
        "1200",
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

const codeForTags = (tags) => {
  if (tags.amenity === "fuel") return "f";
  if (tags.tourism === "hotel") return "h";
  if (tags.shop === "supermarket") return "s";
  if (tags.amenity === "cafe") return "c";
  if (tags.amenity === "pharmacy") return "p";
  if (tags.shop === "car_repair") return "r";
  if (tags.amenity === "atm") return "a";
  return null;
};

async function main() {
  const areaFilter = process.env.OFFLINE_POI_BBOX
    ? `(${process.env.OFFLINE_POI_BBOX})`
    : "(area.ru)";
  const areaSetup = process.env.OFFLINE_POI_BBOX
    ? ""
    : 'area["ISO3166-1"="RU"][admin_level=2]->.ru;\n';

  const query = `[out:json][timeout:600];\n${areaSetup}(\n${CATEGORIES.map(
    ({ tag }) => `  ${tag}${areaFilter};`,
  ).join("\n")}\n);\nout body;`;

  console.log("Запрашиваю Overpass...");
  const data = await fetchOverpass(query);
  const elements = data.elements || [];
  console.log(`Получено элементов: ${elements.length}`);

  const seen = new Set();
  const pois = [];
  for (const el of elements) {
    if (el.type !== "node" || typeof el.lat !== "number" || typeof el.lon !== "number") continue;
    const tags = el.tags || {};
    const code = codeForTags(tags);
    if (!code) continue;
    const key = `${code}:${el.id}`;
    if (seen.has(key)) continue;
    seen.add(key);

    const name = tags.name || tags.brand || null;
    const addr = [tags["addr:street"], tags["addr:housenumber"]].filter(Boolean).join(" ");
    pois.push({
      id: el.id,
      k: code,
      n: name,
      lat: Math.round(el.lat * 1e6) / 1e6,
      lon: Math.round(el.lon * 1e6) / 1e6,
      ...(addr ? { d: addr } : {}),
      ...(tags.phone ? { ph: tags.phone } : {}),
      ...(tags.brand ? { b: tags.brand } : {}),
    });
  }

  pois.sort((left, right) => left.k.localeCompare(right.k) || left.id - right.id);

  await mkdir(dirname(outputPath), { recursive: true });
  const temporaryPath = `${outputPath}.tmp`;
  const output = createWriteStream(temporaryPath, { encoding: "utf8" });
  output.write('{"v":1,"s":"OpenStreetMap ODbL","p":[');
  pois.forEach((poi, index) => {
    if (index > 0) output.write(",");
    output.write(JSON.stringify(poi));
  });
  output.end("]}");
  await new Promise((resolve, reject) => output.once("finish", resolve).once("error", reject));
  await rename(temporaryPath, outputPath);
  console.log(`Offline Russia POI index: ${pois.length} points`);
}

await main();
