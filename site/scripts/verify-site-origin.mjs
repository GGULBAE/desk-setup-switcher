import { constants, realpathSync } from "node:fs";
import { open } from "node:fs/promises";
import { isIP } from "node:net";
import { fileURLToPath } from "node:url";

const maximumBytes = 4096;
const schemaVersion = "desk-setup-switcher.site-origin/v1";
const exactKeys = ["schemaVersion", "siteURL", "state"];

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
    if (index >= source.length) throw new Error("Site origin approval is not valid JSON");
    let cursor = index + 1;
    while (/\s/.test(source[cursor] ?? "")) cursor += 1;
    if (source[cursor] === ":") {
      keys.push(JSON.parse(source.slice(start, index + 1)));
    }
  }
  return keys;
}

function parseCleanPublicOrigin(value) {
  if (typeof value !== "string") {
    throw new Error("An approved site origin must be a string");
  }

  let origin;
  try {
    origin = new URL(value);
  } catch {
    throw new Error("An approved site origin must be an absolute URL");
  }

  const rawHostname = origin.hostname.toLowerCase();
  if (
    origin.protocol !== "https:" ||
    origin.username ||
    origin.password ||
    origin.search ||
    origin.hash ||
    origin.pathname !== "/" ||
    origin.origin !== value
  ) {
    throw new Error("A public site origin must use HTTPS and be an exact clean origin");
  }
  if (rawHostname.endsWith(".")) {
    throw new Error("An approved site origin must use a canonical hostname without a trailing dot");
  }

  const unbracketedHostname = rawHostname.startsWith("[") && rawHostname.endsWith("]")
    ? rawHostname.slice(1, -1)
    : rawHostname;
  if (isIP(unbracketedHostname) !== 0 || rawHostname === "localhost" || rawHostname.endsWith(".localhost")) {
    throw new Error("An approved site origin must not use a local or IP-literal hostname");
  }
  if (!rawHostname.includes(".")) {
    throw new Error("An approved site origin must use a fully qualified DNS hostname");
  }
  if (
    /(^|\.)example\.(com|org|net)$|(^|\.)example$|\.(invalid|test|local|localhost)$/i.test(
      rawHostname,
    )
  ) {
    throw new Error("Replace the placeholder NEXT_PUBLIC_SITE_URL before building");
  }

  return origin.origin;
}

export function validateSitePublication(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Site origin approval must be an object");
  }

  const record = /** @type {Record<string, unknown>} */ (value);
  if (JSON.stringify(Object.keys(record).sort()) !== JSON.stringify(exactKeys)) {
    throw new Error("Site origin approval has an unexpected schema");
  }
  if (record.schemaVersion !== schemaVersion) {
    throw new Error("Site origin approval has an unexpected schema version");
  }
  if (record.state === "holding") {
    if (record.siteURL !== null) {
      throw new Error("A holding site origin approval must not contain a URL");
    }
  } else if (record.state === "approved") {
    parseCleanPublicOrigin(record.siteURL);
  } else {
    throw new Error("Site origin approval state must be holding or approved");
  }

  return Object.freeze({
    schemaVersion,
    state: record.state,
    siteURL: record.siteURL,
  });
}

export async function validateSitePublicationFile(path) {
  const handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  let bytes;
  try {
    const before = await handle.stat({ bigint: true });
    if (!before.isFile() || before.nlink !== 1n) {
      throw new Error("Site origin approval must be one regular, unlinked file");
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
      throw new Error("Site origin approval changed while it was read");
    }
  } finally {
    await handle.close();
  }
  if (bytes.length === 0 || bytes.length > maximumBytes || bytes.includes(0)) {
    throw new Error("Site origin approval has an invalid size or encoding");
  }
  const source = bytes.toString("utf8");
  if (Buffer.from(source, "utf8").compare(bytes) !== 0) {
    throw new Error("Site origin approval is not canonical UTF-8");
  }
  const keys = objectKeysInSource(source);
  if (keys.length !== new Set(keys).size) {
    throw new Error("Site origin approval contains duplicate keys");
  }
  return validateSitePublication(JSON.parse(source));
}

export async function verifyConfiguredSiteOrigin(configuredOrigin, { allowLocal = false, publicationPath } = {}) {
  if (!configuredOrigin) {
    throw new Error("NEXT_PUBLIC_SITE_URL is required for every site build");
  }

  let origin;
  try {
    origin = new URL(configuredOrigin);
  } catch {
    throw new Error("NEXT_PUBLIC_SITE_URL must be an absolute URL");
  }

  if (origin.username || origin.password || origin.search || origin.hash) {
    throw new Error("NEXT_PUBLIC_SITE_URL must be a clean origin without credentials, query, or fragment");
  }

  const rawHostname = origin.hostname.toLowerCase();
  if (rawHostname.endsWith(".")) {
    throw new Error("NEXT_PUBLIC_SITE_URL must use a canonical hostname without a trailing dot");
  }

  const isExplicitLocalOrigin = origin.protocol === "http:" && [
    "localhost",
    "127.0.0.1",
    "[::1]",
  ].includes(rawHostname);

  const approval = await validateSitePublicationFile(publicationPath);

  if (allowLocal) {
    if (!isExplicitLocalOrigin || origin.pathname !== "/") {
      throw new Error("ALLOW_LOCAL_SITE_ORIGIN is valid only for an explicit HTTP loopback origin");
    }
    return;
  }

  const cleanOrigin = parseCleanPublicOrigin(configuredOrigin);
  if (approval.state !== "approved" || approval.siteURL !== cleanOrigin) {
    throw new Error("Public site builds require the exact tracked approved site origin");
  }
}

if (
  process.argv[1] &&
  realpathSync(fileURLToPath(import.meta.url)) === realpathSync(process.argv[1])
) {
  const publicationPath = fileURLToPath(new URL("../site-publication.json", import.meta.url));
  try {
    await verifyConfiguredSiteOrigin(process.env.NEXT_PUBLIC_SITE_URL, {
      allowLocal: process.env.ALLOW_LOCAL_SITE_ORIGIN === "1",
      publicationPath,
    });
  } catch (error) {
    const reason = error instanceof Error ? error.message : "unknown validation error";
    console.error(`Site origin verification failed: ${reason}`);
    process.exit(1);
  }
}
