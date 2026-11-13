# DMG delivery dependency preflight — 2026-11-13

The requested DMG delivery exposed a failing CI preflight: the existing site lockfile reported 22 dependency advisories (11 moderate, nine high, two critical). This is independent of the native app's setting adapters, but the repository requires the public-site CI job before release.

## Changes

Preserve the existing Next.js/Vinext, Cloudflare preview, and static GitHub Pages architecture. Refresh pinned versions and lockfile integrity records without enabling an automatic deploy or adding a service:

- Next.js and its ESLint config: 16.4.6.
- React, React DOM, and RSC: 19.3.1, matching Vinext 1.4.5's peer contract.
- Vite 8.3.8, RSC plugin 0.5.37, Cloudflare Vite plugin 1.69.1, Wrangler 4.161.0.
- Existing overrides: PostCSS 8.5.32, Sharp 0.35.5, Undici 7.30.1. Undici stays on major 7 to retain the existing Node 22.13 CI boundary.
- Scope the patched Minimatch 11.0.1 override to TypeScript ESTree, preserving other consumers' compatible major-3 versions.
- Scope Fflate 0.7.5 to Satori's dependency subtree, taking the patched 0.7 branch rather than introducing an unnecessary major-line change.

The updated Cloudflare output imports platform modules, so rendering tests now use the pinned Miniflare Worker runtime with telemetry disabled and outbound requests rejected. New connect/K2 bindings must remain empty, and source-map uploads are explicitly disabled rather than adopting a new tooling default. Wrangler build metrics are disabled for this project before importing the provider plugin.

The privacy/history audit's exact-blob fixture review was also refreshed after inspecting constructed validation IPs, invalid coordinate boundaries, and mock device labels. The detector, suppression of matched values, and path/content/category binding remain intact. Positive fixture coverage includes the current validation files; future edits still require review.

## Verification

`npm install --ignore-scripts` and `npm audit` report zero vulnerabilities. The clean locked install reports zero vulnerabilities. The current-state rendering/privacy suite passes all 12 tests; the complete site/public-surface matrix passes, and final CI provides exact-commit evidence. The native app source remains covered by the preceding full non-live `make verify` result. No app setting mutation or public website deployment is part of this dependency change.

Primary advisory references: [React RSC](https://github.com/advisories/GHSA-xqc2-xf4c-x3h3), [Next.js](https://github.com/advisories/GHSA-673q-mjm6-r5xr), [Minimatch](https://github.com/advisories/GHSA-g3hv-75wg-m249), [Fflate](https://github.com/advisories/GHSA-px8p-9vwx-vf98).
