import { LandingPage } from "./landing-page";
import releasePublication from "../release-publication.json";
import holdingFixture from "../tests/fixtures/release-holding.json";
import publishedFixture from "../tests/fixtures/release-published.json";
import { validateReleasePublication } from "../lib/release-publication.mjs";

export const dynamic = "force-static";

export default function Home() {
  const fixtureName = process.env.NEXT_PUBLIC_RELEASE_FIXTURE;
  const siteOrigin = process.env.NEXT_PUBLIC_SITE_URL;
  const localFixtureOrigins = new Set([
    "http://localhost:3000",
    "http://127.0.0.1:3000",
    "http://[::1]:3000",
  ]);
  if (fixtureName && (!siteOrigin || !localFixtureOrigins.has(siteOrigin))) {
    throw new Error("Release publication fixtures are restricted to explicit local verification");
  }

  const rawPublication = fixtureName === "holding"
    ? holdingFixture
    : fixtureName === "published"
      ? publishedFixture
      : fixtureName
        ? (() => { throw new Error("Unknown release publication fixture"); })()
        : releasePublication;
  const publication = validateReleasePublication(rawPublication);

  return <LandingPage releaseURL={publication.releaseURL} />;
}
