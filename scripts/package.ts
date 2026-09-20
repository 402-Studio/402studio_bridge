import { readFileSync, readdirSync, mkdirSync, writeFileSync, existsSync, statSync } from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { zipSync } from "fflate";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const name = "402studio_bridge";
const version = JSON.parse(readFileSync(join(root, "package.json"), "utf8"))
  .version as string;
const manifest = readFileSync(join(root, "fxmanifest.lua"), "utf8");
if (!manifest.includes(`version '${version}'`)) {
  throw new Error("fxmanifest.lua version differs from package.json");
}

const include = [
  "fxmanifest.lua",
  "config.lua",
  "README.md",
  "LICENSE",
  "adapters",
  "client",
  "server",
  "shared",
  "examples",
];
const files: Record<string, Uint8Array> = {};

function add(path: string): void {
  const entries = readdirSync(path, { withFileTypes: true });
  for (const entry of entries) {
    const child = join(path, entry.name);
    if (entry.isDirectory()) add(child);
    else if (entry.isFile()) {
      const archivePath = `${name}/${relative(root, child).split(sep).join("/")}`;
      files[archivePath] = readFileSync(child);
    }
  }
}

for (const item of include) {
  const path = join(root, item);
  if (!existsSync(path)) throw new Error(`Missing release file: ${item}`);
  if (statSync(path).isDirectory()) add(path);
  else files[`${name}/${item}`] = readFileSync(path);
}

const output = join(root, "dist-release", `${name}-v${version}.zip`);
if (existsSync(output)) throw new Error(`Release ZIP already exists: ${output}`);
mkdirSync(dirname(output), { recursive: true });
writeFileSync(output, zipSync(files, { level: 6 }));
console.log(`Packaged ${Object.keys(files).length} files: ${output}`);
