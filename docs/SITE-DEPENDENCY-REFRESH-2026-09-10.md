# Site dependency advisory follow-up — 2026-09-10

## Trigger and scope

- The networked dependency-audit job for commits `f1af22a` and `6fc1c35` began failing after the registry reported two critical Next.js advisories plus high-severity Sharp and downstream Cloudflare-tooling findings.
- The application behavior and installed package were already verified independently. This follow-up changes only the static site's dependency manifest, lockfile, and evidence documentation.
- Next.js and `eslint-config-next` move from `16.3.0` to patched `16.3.4`. A root override pins all direct and transitive Sharp paths to patched `0.35.4`; React, Vinext, Vite, Cloudflare Vite plugin, Wrangler, PostCSS, and Undici pins stay unchanged.

## Verification

- `npm ci --ignore-scripts` completed from the regenerated lockfile.
- `npm audit` reported zero registry advisories.
- `npm run verify` passed lint, published/holding/current builds, and 11 rendered-output tests for each state (33 test executions total). The existing deployment-output audit continued to reject the build-time image parser from client and Worker chunks.
- The exact staged snapshot passed the canonical non-live `make verify`: lint/localization, 359 Swift Testing tests, the native popover XCTest, release-policy and safety mocks, Debug/Release builds, Xcode universal build and Analyze, and mounted universal-DMG verification. Final staged and working-tree diff checks also passed.

No deployment, account, service, network configuration, application setting, profile, login item, display, audio, mouse, or keyboard mutation was performed. The network access was limited to package metadata/downloads and the advisory audit.
