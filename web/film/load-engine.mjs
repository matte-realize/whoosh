// Loads src/lib/sim/engine.ts in plain Node by stripping its types with the repo's TypeScript.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const web = path.resolve(here, "..");
const require = createRequire(path.join(web, "package.json"));

export async function load() {
  const ts = require("typescript");
  const source = fs.readFileSync(path.join(web, "src/lib/sim/engine.ts"), "utf8");
  const out = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
  }).outputText;
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "whoosh-film-"));
  const file = path.join(dir, "engine.mjs");
  fs.writeFileSync(file, out);
  return import(pathToFileURL(file).href);
}
