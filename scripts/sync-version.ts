import { spawnSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const version = JSON.parse(readFileSync(join(root, "package.json"), "utf8"))
  .version as string;
if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(version)) {
  throw new Error(`Invalid version: ${version}`);
}

const path = join(root, "fxmanifest.lua");
const original = readFileSync(path, "utf8");
const pattern = /^version '[^']+'$/m;
if (!pattern.test(original)) throw new Error("fxmanifest.lua has no version");
const updated = original.replace(pattern, `version '${version}'`);
if (updated !== original) writeFileSync(path, updated);

const result = spawnSync(process.execPath, ["install", "--lockfile-only"], {
  cwd: root,
  stdio: "inherit",
});
if (result.error) throw result.error;
if (result.status !== 0) process.exit(result.status ?? 1);
