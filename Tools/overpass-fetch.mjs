import { mkdtemp, readFile, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { spawn } from "node:child_process";

// Публичный Overpass регулярно отдаёт 504/429/таймауты под нагрузкой, поэтому
// на этапе сборки CI перебираем несколько зеркал с повторами и задержкой,
// вместо того чтобы падать с первой же временной ошибки.
const DEFAULT_ENDPOINTS = [
  "https://overpass.kumi.systems/api/interpreter",
  "https://overpass-api.de/api/interpreter",
  "https://overpass.private.coffee/api/interpreter",
  "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
];

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function curlOnce(endpoint, query, destPath, maxTimeSeconds) {
  return new Promise((resolve, reject) => {
    const child = spawn("curl", [
      "--fail",
      "--silent",
      "--show-error",
      "--location",
      "--max-time",
      String(maxTimeSeconds),
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
}

/**
 * Выполнить Overpass-запрос устойчиво: несколько зеркал, повторы с нарастающей
 * задержкой. curl вместо fetch() — потоковая запись больших ответов на диск.
 *
 * @param {string} query Overpass QL
 * @param {object} [opts]
 * @param {string} [opts.endpointArg] Явный единственный endpoint (для тестов) — отключает перебор зеркал
 * @param {number} [opts.maxTimeSeconds] Таймаут одной попытки curl
 * @param {number} [opts.attempts] Сколько попыток всего
 */
export async function fetchOverpass(query, opts = {}) {
  const endpoints = opts.endpointArg ? [opts.endpointArg] : DEFAULT_ENDPOINTS;
  const maxTimeSeconds = opts.maxTimeSeconds ?? 1500;
  const attempts = opts.attempts ?? 8;

  const dir = await mkdtemp(join(tmpdir(), "nomad-overpass-"));
  const destPath = join(dir, "response.json");
  try {
    let lastError;
    for (let attempt = 0; attempt < attempts; attempt++) {
      const endpoint = endpoints[attempt % endpoints.length];
      try {
        console.log(`Overpass: попытка ${attempt + 1}/${attempts} → ${endpoint}`);
        await curlOnce(endpoint, query, destPath, maxTimeSeconds);
        const raw = await readFile(destPath, "utf8");
        // Overpass иногда отдаёт 200 с телом "runtime error"/"rate_limited" —
        // ловим это через провал JSON.parse и уходим на повтор.
        return JSON.parse(raw);
      } catch (error) {
        lastError = error;
        const backoff = Math.min(60_000, 5_000 * 2 ** attempt);
        console.error(`Overpass не ответил (${error.message}). Пауза ${Math.round(backoff / 1000)} с и повтор.`);
        if (attempt < attempts - 1) await sleep(backoff);
      }
    }
    throw new Error(`Overpass недоступен после ${attempts} попыток: ${lastError?.message ?? "неизвестная ошибка"}`);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}
