import { defineConfig } from "bumpp";

export default defineConfig({
  files: ["package.json"],
  execute: "bun run sync-version",
  all: true,
  commit: "Release v{version}",
  tag: "v{version}",
  push: true,
});
