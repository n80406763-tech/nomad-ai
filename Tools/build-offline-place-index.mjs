import { createWriteStream } from "node:fs";
import { mkdir, rename } from "node:fs/promises";
import { dirname } from "node:path";
import { spawn } from "node:child_process";
import readline from "node:readline";

const [archivePath, outputPath] = process.argv.slice(2);

if (!archivePath || !outputPath) {
  throw new Error(
    "Usage: node build-offline-place-index.mjs RU.zip OUTPUT.json",
  );
}

const kindForCode = (code) => {
  if (code === "PPLC") return "столица";
  if (code.startsWith("PPLA")) return "административный центр";
  if (code === "PPL") return "населённый пункт";
  return "поселение";
};

const uniqueAliases = (name, asciiName, alternateNames) => {
  const seen = new Set([name.toLocaleLowerCase("ru")]);
  const aliases = [];
  const candidates = [asciiName, ...alternateNames.split(",")];
  const orderedCandidates = [
    ...candidates.filter((value) => /[А-Яа-яЁё]/.test(value)),
    ...candidates.filter((value) => !/[А-Яа-яЁё]/.test(value)),
  ];
  for (const value of orderedCandidates) {
    const trimmed = value.trim();
    const key = trimmed.toLocaleLowerCase("ru");
    if (trimmed.length < 2 || trimmed.length > 80 || seen.has(key)) continue;
    seen.add(key);
    aliases.push(trimmed);
    if (aliases.length === 8) break;
  }
  return aliases;
};

const extractor = process.platform === "win32" ? "tar" : "unzip";
const extractorArguments =
  process.platform === "win32"
    ? ["-xOf", archivePath, "RU.txt"]
    : ["-p", archivePath, "RU.txt"];
const child = spawn(extractor, extractorArguments, {
  stdio: ["ignore", "pipe", "inherit"],
});
const childError = new Promise((_, reject) => child.once("error", reject));
const places = [];
const lines = readline.createInterface({
  input: child.stdout,
  crlfDelay: Infinity,
});

for await (const line of lines) {
  const fields = line.split("\t");
  if (fields.length < 19 || fields[6] !== "P" || fields[8] !== "RU") continue;

  const latitude = Number(fields[4]);
  const longitude = Number(fields[5]);
  if (
    !Number.isFinite(latitude) ||
    !Number.isFinite(longitude) ||
    !fields[1].trim()
  )
    continue;

  places.push({
    id: fields[0],
    n: fields[1].trim(),
    a: uniqueAliases(fields[1].trim(), fields[2], fields[3]),
    lat: latitude,
    lon: longitude,
    k: kindForCode(fields[7]),
    p: Number(fields[14]) || 0,
  });
}

const exitCode = await Promise.race([
  new Promise((resolve) => child.once("close", resolve)),
  childError,
]);
if (exitCode !== 0) throw new Error(`Could not read ${archivePath}`);

places.sort(
  (left, right) => right.p - left.p || left.n.localeCompare(right.n, "ru"),
);
await mkdir(dirname(outputPath), { recursive: true });
const temporaryPath = `${outputPath}.tmp`;
const output = createWriteStream(temporaryPath, { encoding: "utf8" });
output.write('{"v":1,"s":"GeoNames CC BY 4.0","p":[');
places.forEach((place, index) => {
  if (index > 0) output.write(",");
  output.write(JSON.stringify(place));
});
output.end("]}");
await new Promise((resolve, reject) =>
  output.once("finish", resolve).once("error", reject),
);
await rename(temporaryPath, outputPath);
console.log(`Offline Russia place index: ${places.length} places`);
