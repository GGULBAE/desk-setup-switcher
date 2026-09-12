export const githubPagesOrigin = "https://ggulbae.github.io";
export const githubPagesBasePath = "/desk-setup-switcher";
export const githubPagesURL = `${githubPagesOrigin}${githubPagesBasePath}/`;

export function validateGitHubPagesPublication(sitePublication, releasePublication) {
  if (
    sitePublication?.state !== "approved" ||
    sitePublication?.siteURL !== githubPagesOrigin
  ) {
    throw new Error(`GitHub Pages publication requires the approved origin ${githubPagesOrigin}`);
  }
  if (releasePublication?.state !== "holding" || releasePublication?.releaseURL !== null) {
    throw new Error("GitHub Pages publication is authorized only for the no-download holding page");
  }

  return Object.freeze({
    basePath: githubPagesBasePath,
    origin: githubPagesOrigin,
    siteURL: githubPagesURL,
  });
}
