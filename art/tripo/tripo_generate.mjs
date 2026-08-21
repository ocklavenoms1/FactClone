// tripo_generate.mjs — text-to-model via the Tripo v3 API, GLB out.
// Usage: node tripo_generate.mjs --name chest --prompt "..." [--model v3.1-20260211] [--out-dir ../source]
// Reads TRIPO_API_KEY from the environment (falls back to the user registry on Windows).
// Model URLs expire 5 minutes after task success, so the GLB is downloaded immediately.

import { writeFileSync, mkdirSync } from "node:fs";
import { execSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const BASE = "https://openapi.tripo3d.ai/v3";
const HERE = dirname(fileURLToPath(import.meta.url));

function arg(name, fallback) {
  const i = process.argv.indexOf("--" + name);
  return i >= 0 ? process.argv[i + 1] : fallback;
}

function apiKey() {
  if (process.env.TRIPO_API_KEY) return process.env.TRIPO_API_KEY;
  if (process.platform === "win32") {
    try {
      const out = execSync(
        'reg query "HKCU\\Environment" /v TRIPO_API_KEY',
        { encoding: "utf8" }
      );
      const m = out.match(/TRIPO_API_KEY\s+REG_[A-Z_]+\s+(\S+)/);
      if (m) return m[1];
    } catch {}
  }
  throw new Error("TRIPO_API_KEY is not set");
}

const KEY = apiKey();
const HEADERS = { "Content-Type": "application/json", Authorization: `Bearer ${KEY}` };

async function api(path, opts = {}) {
  const res = await fetch(BASE + path, { headers: HEADERS, ...opts });
  const body = await res.json();
  if (body.code !== 0) throw new Error(`API error on ${path}: ${JSON.stringify(body)}`);
  return body.data;
}

async function main() {
  const name = arg("name");
  const prompt = arg("prompt");
  const model = arg("model", "v3.1-20260211");
  const outDir = arg("out-dir", join(HERE, "..", "source"));
  if (!name || !prompt) throw new Error("--name and --prompt are required");

  const { task_id } = await api("/generation/text-to-model", {
    method: "POST",
    body: JSON.stringify({ prompt, model, texture: true }),
  });
  console.log(`task ${task_id} created (${model})`);

  let task;
  for (;;) {
    await new Promise((r) => setTimeout(r, 2000));
    task = await api(`/tasks/${task_id}`);
    process.stdout.write(`\r${task.status} ${task.progress ?? 0}%   `);
    if (task.status === "success") break;
    if (["failed", "cancelled", "banned"].includes(task.status))
      throw new Error(`task ${task_id} ended: ${task.status}`);
  }
  console.log();

  mkdirSync(outDir, { recursive: true });
  const glbPath = join(outDir, `${name}.glb`);
  const glb = await fetch(task.output.model_url);
  writeFileSync(glbPath, Buffer.from(await glb.arrayBuffer()));
  console.log(`GLB_SAVED: ${glbPath}`);
  if (task.output.rendered_image_url) {
    const img = await fetch(task.output.rendered_image_url);
    const ext = task.output.rendered_image_url.split("?")[0].split(".").pop() || "webp";
    const imgPath = join(outDir, `${name}_tripo_preview.${ext}`);
    writeFileSync(imgPath, Buffer.from(await img.arrayBuffer()));
    console.log(`PREVIEW_SAVED: ${imgPath}`);
  }
  console.log(`TASK_ID: ${task_id}`);
}

main().catch((e) => {
  console.error("FAILED:", e.message);
  process.exit(1);
});
