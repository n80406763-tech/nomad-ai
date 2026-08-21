import { createReadStream, existsSync, statSync } from "node:fs";
import { createServer } from "node:http";
import { extname, resolve, sep } from "node:path";

const root = resolve(process.cwd(), "Resources", "VectorMap");
const types = {
  ".html": "text/html",
  ".js": "application/javascript",
  ".css": "text/css",
  ".pmtiles": "application/octet-stream",
};

createServer((request, response) => {
  const requestURL = new URL(request.url ?? "/", "http://127.0.0.1");
  const requestedPath =
    decodeURIComponent(requestURL.pathname).replace(/^\/+/, "") || "index.html";
  const filePath = resolve(root, requestedPath);

  if (!filePath.startsWith(`${root}${sep}`) || !existsSync(filePath)) {
    response.writeHead(404);
    response.end();
    return;
  }

  const stat = statSync(filePath);
  const mimeType = types[extname(filePath)] ?? "application/octet-stream";
  const range = request.headers.range?.match(/bytes=(\d*)-(\d*)/);

  if (range) {
    const start = range[1] ? Number(range[1]) : 0;
    const end = range[2]
      ? Math.min(Number(range[2]), stat.size - 1)
      : stat.size - 1;
    response.writeHead(206, {
      "Content-Type": mimeType,
      "Accept-Ranges": "bytes",
      "Content-Range": `bytes ${start}-${end}/${stat.size}`,
      "Content-Length": end - start + 1,
      "Access-Control-Allow-Origin": "*",
    });
    createReadStream(filePath, { start, end }).pipe(response);
    return;
  }

  response.writeHead(200, {
    "Content-Type": mimeType,
    "Content-Length": stat.size,
    "Accept-Ranges": "bytes",
    "Access-Control-Allow-Origin": "*",
  });
  createReadStream(filePath).pipe(response);
}).listen(4173, "127.0.0.1", () => {
  console.log("Vector map test server: http://127.0.0.1:4173/index.html");
});
