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

for (const [block, required] of Object.entries({
  shared_scripts: ["@ox_lib/init.lua"],
  client_scripts: ["client/callback.lua", "client/capture.lua", "client/vehicle-classes.lua"],
  server_scripts: ["adapters/capture/**/server.lua", "server/callback.lua", "server/capture.lua", "server/vehicle-classes.lua"],
  dependencies: ["ox_lib"],
})) {
  const contents = manifest.match(new RegExp(`${block}\\s*\\{([^}]+)\\}`))?.[1] ?? "";
  for (const file of required) {
    if (!contents.includes(`'${file}'`)) throw new Error(`Missing ${block} entry: ${file}`);
  }
}
if (manifest.indexOf("'server/vehicle-classes.lua'") > manifest.indexOf("'server/vehicle.lua'")) {
  throw new Error("Vehicle classes must load before vehicle services");
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
for (const file of ["tests/services.test.lua", "tests/inventory.test.lua", "tests/vehicle-classes.test.lua"]) {
  const test = spawnSync(process.env.LUA ?? "lua", [join(root, file), root], {
    stdio: "inherit",
  });
  if (test.error) throw test.error;
  if (test.status !== 0) process.exit(test.status ?? 1);
}
console.log(`Checked ${files.length} Lua files and version ${version}`);
