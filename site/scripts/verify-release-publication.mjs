import { constants } from "node:fs";
import { open } from "node:fs/promises";
import { fileURLToPath, pathToFileURL } from "node:url";
import { validateReleasePublication } from "../lib/release-publication.mjs";

const maximumBytes = 4096;

function objectKeysInSource(source) {
  const keys = [];
  for (let index = 0; index < source.length; index += 1) {
    if (source[index] !== '"') continue;
    const start = index;
    index += 1;
    while (index < source.length) {
      if (source[index] === "\\") {
        index += 2;
        continue;
      }
      if (source[index] === '"') break;
      index += 1;
    }
    if (index >= source.length) throw new Error("Release publication metadata is not valid JSON");
    let cursor = index + 1;
    while (/\s/.test(source[cursor] ?? "")) cursor += 1;
    if (source[cursor] === ":") {
      keys.push(JSON.parse(source.slice(start, index + 1)));
    }
  }
  return keys;
}

export async function validateReleasePublicationFile(path) {
  const handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  let bytes;
  try {
    const before = await handle.stat({ bigint: true });
    if (!before.isFile() || before.nlink !== 1n) {
      throw new Error("Release publication metadata must be one regular, unlinked file");
    }
    bytes = await handle.readFile();
    const after = await handle.stat({ bigint: true });
    if (
      before.dev !== after.dev ||
      before.ino !== after.ino ||
      before.size !== after.size ||
      before.mtimeNs !== after.mtimeNs ||
      before.ctimeNs !== after.ctimeNs
    ) {
      throw new Error("Release publication metadata changed while it was read");
    }
  } finally {
    await handle.close();
  }
  if (bytes.length === 0 || bytes.length > maximumBytes || bytes.includes(0)) {
    throw new Error("Release publication metadata has an invalid size or encoding");
  }
  const source = bytes.toString("utf8");
  if (Buffer.from(source, "utf8").compare(bytes) !== 0) {
    throw new Error("Release publication metadata is not canonical UTF-8");
  }
  const keys = objectKeysInSource(source);
  if (keys.length !== new Set(keys).size) {
    throw new Error("Release publication metadata contains duplicate keys");
  }
  return validateReleasePublication(JSON.parse(source));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const root = new URL("../", import.meta.url);
  const paths = [
    new URL("release-publication.json", root),
    new URL("tests/fixtures/release-holding.json", root),
    new URL("tests/fixtures/release-published.json", root),
  ];
  try {
    await Promise.all(paths.map((url) => validateReleasePublicationFile(fileURLToPath(url))));
  } catch {
    console.error("Release publication metadata verification failed.");
    process.exit(1);
  }
}
