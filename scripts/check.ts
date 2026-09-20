import { spawnSync } from "node:child_process";
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const version = JSON.parse(readFileSync(join(root, "package.json"), "utf8"))
  .version as string;
const manifest = readFileSync(join(root, "fxmanifest.lua"), "utf8");

if (!manifest.includes("name '402studio_bridge'") ||
    !manifest.includes(`version '${version}'`) ||
    !manifest.includes("    '*',") ||
    !manifest.includes("    '**/*',")) {
  throw new Error("Bridge manifest name, version, or escrow exclusions differ");
}

function luaFiles(directory: string): string[] {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    return entry.isDirectory() ? luaFiles(path) : path.endsWith(".lua") ? [path] : [];
  });
}

const files = [
  join(root, "fxmanifest.lua"),
  join(root, "config.lua"),
  ...["adapters", "client", "server", "shared", "examples"].flatMap((dir) =>
    luaFiles(join(root, dir)),
  ),
];
const result = spawnSync(process.env.LUAC ?? "luac", ["-p", ...files], {
  stdio: "inherit",
});
if (result.error) throw result.error;
if (result.status !== 0) process.exit(result.status ?? 1);
console.log(`Checked ${files.length} Lua files and version ${version}`);
