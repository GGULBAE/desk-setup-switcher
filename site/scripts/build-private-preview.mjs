import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { validatePrivatePreviewFile } from "./verify-site-origin.mjs";

const npmCLI = process.env.npm_execpath;
if (!npmCLI) {
  console.error("Private preview builds must be started through npm.");
  process.exit(1);
}

const root = new URL("../", import.meta.url);
const approval = await validatePrivatePreviewFile(
  fileURLToPath(new URL("private-preview.json", root)),
);

const child = spawn(process.execPath, [npmCLI, "run", "build"], {
  cwd: root,
  env: {
    ...process.env,
    ALLOW_PRIVATE_SITE_ORIGIN: "1",
    NEXT_PUBLIC_SITE_AUDIENCE: "private",
    NEXT_PUBLIC_SITE_URL: approval.siteURL,
  },
  stdio: "inherit",
});

child.once("error", () => {
  process.exitCode = 1;
});
child.once("exit", (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
    return;
  }
  process.exitCode = code ?? 1;
});
