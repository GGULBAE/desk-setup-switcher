import { isIP } from "node:net";

const configuredOrigin = process.env.NEXT_PUBLIC_SITE_URL;
const allowLocal = process.env.ALLOW_LOCAL_SITE_ORIGIN === "1";

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

const unbracketedHostname = rawHostname.startsWith("[") && rawHostname.endsWith("]")
  ? rawHostname.slice(1, -1)
  : rawHostname;
const isIPAddress = isIP(unbracketedHostname) !== 0;
const isLocalhostName = rawHostname === "localhost" || rawHostname.endsWith(".localhost");
const isExplicitLocalOrigin = origin.protocol === "http:" && [
  "localhost",
  "127.0.0.1",
  "[::1]",
].includes(rawHostname);

if (isIPAddress || isLocalhostName) {
  if (!allowLocal || !isExplicitLocalOrigin) {
    throw new Error(
      "A local or IP-literal site origin is allowed only as explicit HTTP loopback for a local build",
    );
  }
} else if (origin.protocol !== "https:") {
  throw new Error("A public site origin must use HTTPS");
}

if (!isExplicitLocalOrigin || !allowLocal) {
  if (!rawHostname.includes(".")) {
    throw new Error("A public site origin must use a fully qualified DNS hostname");
  }

  if (
    /(^|\.)example\.(com|org|net)$|(^|\.)example$|\.(invalid|test|local|localhost)$/i.test(
      rawHostname,
    )
  ) {
    throw new Error("Replace the placeholder NEXT_PUBLIC_SITE_URL before building");
  }
}

if (origin.pathname !== "/") {
  throw new Error("NEXT_PUBLIC_SITE_URL must contain only the deployment origin");
}
