import type { NextConfig } from "next";

const pagesBuild = process.env.DESK_SETUP_GITHUB_PAGES === "1";
const pagesBasePath = "/desk-setup-switcher";
const configuredBasePath = process.env.NEXT_PUBLIC_SITE_BASE_PATH ?? "";

if (pagesBuild && configuredBasePath !== pagesBasePath) {
  throw new Error(
    `GitHub Pages builds require NEXT_PUBLIC_SITE_BASE_PATH=${pagesBasePath}`,
  );
}

if (!pagesBuild && configuredBasePath !== "") {
  throw new Error("A site base path is allowed only for the reviewed GitHub Pages build");
}

const nextConfig: NextConfig = pagesBuild
  ? {
      basePath: pagesBasePath,
      images: { unoptimized: true },
      output: "export",
      trailingSlash: true,
      typescript: { tsconfigPath: "tsconfig.pages.json" },
    }
  : {};

export default nextConfig;
