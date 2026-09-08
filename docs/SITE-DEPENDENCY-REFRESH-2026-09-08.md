# Site dependency security refresh — 2026-09-08

## Scope and cause

The user requested dependency refresh after the site job in [CI run 34219646963](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/34219646963), for commit `95f1903`, failed its advisory gate. The pre-refresh lockfile reported seven advisories (six high, one moderate). This follow-up changes site build tooling, lockfile resolutions, build-output tests, and verification documentation; it does not change app behavior or authorize production deployment.

## Dependency changes

| Package | Before | After |
| --- | --- | --- |
| `vinext` | `0.0.50` | `1.0.0-beta.9` |
| `@vitejs/plugin-rsc` | `0.5.28` | `0.5.34` |
| `browserslist` | `4.28.2` | `4.28.9` |
| `fast-uri` | `3.1.5` | `3.1.7` |
| `fflate` | `0.7.4` | `0.7.5` |
| `js-yaml` | `4.3.0` | `4.3.2` |
| `nanoid` | `3.3.17` | `3.3.18` |

Vinext requires the updated RSC plugin. Existing Next/React, Cloudflare/Wrangler, Vite, PostCSS, and Undici direct pins remain unchanged. The lockfile also resolves supporting browser-data and Vinext dependencies and removes dependencies no longer exposed by Vinext. Installation and lockfile resolution disable lifecycle scripts; no forced audit fix is used.

## Image-parser limitation and deployment boundary

The image-size [ICNS advisory](https://github.com/advisories/GHSA-w3rx-r6r6-pgpr) and [JPEG XL/HEIF advisory](https://github.com/advisories/GHSA-5p2g-fcmc-qvqq) have no patched package version at this verification date. [Vinext PR 2913](https://github.com/cloudflare/vinext/pull/2913) bundles `image-size` 2.0.2 into build tooling instead of exposing it as a production dependency. The installed Vinext tools still contain that parser. **Zero registry advisories do not mean the parser itself is patched.**

This site uses reviewed local assets, has no upload or image-optimization endpoint, and does not accept visitor-provided build inputs. New regression coverage recursively checks deployable client and Worker JavaScript for distinctive parser implementation strings and checks that the lockfile no longer exposes the old dependency. This verifies the current output boundary, not arbitrary future bundler transformations or the safety of parsing untrusted build assets. Keep build assets reviewed until the upstream parser is fixed.

## Build compatibility and privacy checks

The refreshed toolchain changes emitted chunk locations. Tests now read all nested `.js`, `.mjs`, and `.cjs` output rather than assuming `dist/client/assets`. The scanner rejects symbolic links and empty build output; fixture tests exercise nested chunks and symlink rejection. Existing exact session-storage keys/call counts and cookie, tracking, storage, binding, and observability restrictions remain intact.

Root canonical and Open Graph URL checks normalize equivalent root URLs through the URL parser while still requiring the exact loopback origin and root path. Page content, publication states, release gates, local asset set, Sites metadata, and deployment capabilities remain unchanged.

## Verification

Local environment: macOS 26.6.2, Node 24.18.0, npm 11.16.0. CI uses macOS 15 and Node 22.13.0. The user subsequently approved resolving the separate audit and offscreen-test blockers; see the [CI compatibility record](CI-COMPATIBILITY-2026-09-08.md) for final combined-scope verification.

- `npm ci --ignore-scripts`: passed; clean lockfile installation without lifecycle scripts.
- `npm run audit:dependencies`: passed, zero registry advisories.
- `npm ls --depth=0`: passed, no invalid direct dependency peers.
- `make verify-public-surface`: passed holding, published, and restored-current builds with 11 tests per state, including asset and publication boundaries.
- Local app tests: 355 tests in 39 suites passed; live mutation tests remain opt-in and were not run.
- Initial `make audit-public-release`: fixture suite passed (39 assertions), but repository-history/worktree scanning failed on pre-existing app fixture blobs in four unchanged source/test paths. No site-refresh path was flagged. The separately approved follow-up reviews all fifteen blobs and adds content/path rejection regressions; it does not add blanket exceptions.
- `make verify`: passed, including lint/localization checks, the 355-test app run, release-tooling mock suites, build/static analysis, unsigned universal packaging, and package metadata/resource verification. This ran against the preserved working tree, including pre-existing app edits; it is not an exact site-only commit or macOS 15 CI result.
- Initial lint, JavaScript syntax, and `git diff --check`: passed. Final combined-scope gates and exact-commit CI are tracked in the compatibility record rather than inferred from these initial site-only results.

The earlier app CI job independently reported seven macOS 15 offscreen pixel-test issues. Those are separate from the site advisory failure and are addressed in the approved compatibility follow-up. Local macOS verification and remote CI are separate evidence; no hardware mutation is run.

## Publication and next step

No Site, hosted version, deployment, domain, or public Release is created. No installed app, login-item registration, Keychain, or live display/audio/network/input setting is changed. Existing unrelated working-tree edits are excluded from the dependency commit.

Next bounded task: finish the approved compatibility follow-up, re-run local gates and both CI jobs for the exact resulting commit, keep README/status evidence current, and leave public-release approval gates unchanged.
