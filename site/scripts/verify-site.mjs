import { spawn } from "node:child_process";
import { rmSync } from "node:fs";
import { constants as osConstants } from "node:os";

const npmCLI = process.env.npm_execpath;
if (!npmCLI) {
  console.error("Site verification must be started through npm.");
  process.exit(1);
}

const siteRoot = new URL("../", import.meta.url);
let activeChild = null;
let interruptedSignal = null;
let restoring = false;

function runScript(name) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [npmCLI, "run", name], {
      cwd: siteRoot,
      env: process.env,
      stdio: "inherit",
    });
    activeChild = child;
    let settled = false;
    const finish = (error) => {
      if (settled) return;
      settled = true;
      if (activeChild === child) activeChild = null;
      if (error) reject(error);
      else resolve();
    };
    child.once("error", () => finish(new Error(`npm run ${name} failed`)));
    child.once("exit", (code) => {
      finish(code === 0 ? null : new Error(`npm run ${name} failed`));
    });
  });
}

for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"]) {
  process.on(signal, () => {
    interruptedSignal ??= signal;
    if (!restoring) activeChild?.kill(signal);
  });
}

let failed = false;
try {
  for (const name of [
    "lint",
    "build:test-published",
    "test:published",
    "build:test-holding",
    "test:holding",
  ]) {
    if (interruptedSignal) throw new Error("Site verification was interrupted");
    await runScript(name);
  }
} catch {
  failed = true;
}

restoring = true;
try {
  // Always leave dist aligned with the reviewed, tracked launch state—even if
  // one of the synthetic state checks above fails midway through.
  await runScript("build:local");
} catch {
  rmSync(new URL("../dist", import.meta.url), { force: true, recursive: true });
  failed = true;
}
restoring = false;

if (!failed && !interruptedSignal) {
  try {
    await runScript("test");
  } catch {
    failed = true;
  }
}

if (interruptedSignal) {
  process.exitCode = 128 + osConstants.signals[interruptedSignal];
} else if (failed) {
  console.error("Site verification failed; no non-current dist output was retained.");
  process.exitCode = 1;
}
