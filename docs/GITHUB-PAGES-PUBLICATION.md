# GitHub Pages publication

Last updated: 2026-09-12

The maintainer has approved publishing the bilingual project landing page at
<https://ggulbae.github.io/desk-setup-switcher/>. This approval covers the
public **holding** page only. It does not publish an app build, enable a
download, approve `v0.1.0`, or change `site/release-publication.json` from
`holding`.

## Hosting boundary

The public site is a static GitHub Pages project site built from the tracked
`site/` source. It uses no Cloudflare credential, account, Worker deployment,
database, object storage, service binding, or repository secret. The existing
`.openai/hosting.json` and Worker-compatible build remain scoped to the
separate owner-only preview path; they are not used by the GitHub Pages
deployment.

GitHub Pages is available for public repositories on GitHub Free, and GitHub
Actions use in public repositories is free, subject to GitHub's documented
Pages and Actions limits. Future plan, visibility, or usage changes can affect
billing, so the repository owner remains responsible for checking the account's
current GitHub billing page. See [GitHub Pages availability and billing](https://docs.github.com/en/pages/getting-started-with-github-pages/creating-a-github-pages-site)
and [GitHub Pages limits](https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits).

The project adds no analytics, tracking, advertising, account, form, or cookie
code. GitHub nevertheless handles every Pages request and states that it logs a
visitor's IP address for security. GitHub's provider processing is governed by
its own privacy terms; see [What is GitHub Pages?](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages)
and the [GitHub General Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).

## Deployment contract

The public artifact is built locally from an exact reviewed `master` commit
with `npm run build:pages`, then committed to the root of the dedicated
`gh-pages` branch. Repository **Settings → Pages → Build and deployment →
Source** points to that branch and its root. GitHub's branch-source deployment
publishes the already generated static files; `.nojekyll` prevents a Jekyll
transformation.

The builder strictly reads both publication records, accepts only the approved
`https://ggulbae.github.io` origin and fixed `/desk-setup-switcher` base path,
and rejects any release state other than `holding` with a null release URL. It
disables Next.js build telemetry and writes only `site/out`. Before a branch
update, `npm run test:pages`, the repository public-surface gate, and a clean
diff check must pass. The generated branch contains no credential, workflow,
source configuration, server code, or app package.

GitHub implements branch-source Pages publishing through a GitHub-managed
deployment workflow. It is not a repository-authored workflow and receives no
project or Cloudflare secret. The resulting dynamic workflow inventory must be
accounted for in the separate release remote-controls audit before any app
Release is approved; this holding-site deployment is not release evidence.
GitHub documents branch publishing in
[Configuring a publishing source](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site).

## Publication checks

Before treating a run as published:

- `site/site-publication.json` approves only the exact
  `https://ggulbae.github.io` origin, while the Pages builder fixes the base
  path to `/desk-setup-switcher` and composes the canonical URL above;
- `site/release-publication.json` remains `holding` with a null release URL;
- the Pages build and repository public-surface verification pass on the exact
  source commit recorded by the generated branch commit;
- the artifact contains a top-level `index.html` and no symbolic links;
- the deployed URL, canonical metadata, Open Graph URL, navigation, images,
  video, captions, English/Korean copy, and repository/support links work from
  a clean browser session; and
- the page still exposes no supported download or install instructions.

No `master` push publishes the site automatically. Updating the public branch
is a deliberate maintainer action after the source commit and generated output
are reviewed. Publishing future download copy requires a separate authorization
that deliberately changes both the release record and the static builder's
holding-only guard; a release-record edit by itself cannot make that copy live.

## Rollback and unpublish

To roll back content, revert the relevant `master` commit, rebuild and verify
the static output, then publish that exact result as a new `gh-pages` commit.
To stop public serving, use **Settings → Pages** to unpublish the site; deleting
or changing source files alone does not reliably remove an already deployed
site.

Neither action changes or deletes app profiles, release artifacts, tags, or the
owner-only preview. Record any public rollback or unpublish event in the
completion ledger without presenting it as an app-release event.
