const schemaVersion = "desk-setup-switcher.site-release/v1";
const version = "0.1.0";
const tag = "v0.1.0";
const releaseURL = "https://github.com/GGULBAE/desk-setup-switcher/releases/tag/v0.1.0";
const exactKeys = ["releaseURL", "schemaVersion", "state", "tag", "version"];

/**
 * @param {unknown} value
 * @returns {{schemaVersion: string, state: "holding" | "published", version: string, tag: string, releaseURL: string | null}}
 */
export function validateReleasePublication(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Release publication metadata must be an object");
  }

  const record = /** @type {Record<string, unknown>} */ (value);
  if (JSON.stringify(Object.keys(record).sort()) !== JSON.stringify(exactKeys)) {
    throw new Error("Release publication metadata has an unexpected schema");
  }
  if (record.schemaVersion !== schemaVersion || record.version !== version || record.tag !== tag) {
    throw new Error("Release publication identity does not match v0.1.0");
  }
  if (record.state === "holding") {
    if (record.releaseURL !== null) {
      throw new Error("Holding metadata must not expose a release URL");
    }
  } else if (record.state === "published") {
    if (record.releaseURL !== releaseURL) {
      throw new Error("Published metadata must use the exact canonical GitHub Release URL");
    }
  } else {
    throw new Error("Release publication state must be holding or published");
  }

  return Object.freeze({
    schemaVersion,
    state: record.state,
    version,
    tag,
    releaseURL: record.releaseURL,
  });
}

export const canonicalReleaseURL = releaseURL;
