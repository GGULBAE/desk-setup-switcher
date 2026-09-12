# Launch copy and repository metadata

Last reviewed: 2026-09-12

This document is a copy deck and approval checklist. It does not authorize a GitHub setting change, site deployment, release publication, or community post.

Desk Setup Switcher currently has no supported download. Local and ordinary CI DMGs are ad-hoc-signed development evidence, not approved public artifacts. The planned first supported beta is also Developer ID-unsigned and not notarized, but it becomes supported only when the exact DMG and checksum pass the complete [distribution gate](DISTRIBUTION.md) and a maintainer publishes them on GitHub Releases. Keep every public-download sentence below unpublished until then.

## Current remote state

An authenticated read-only GitHub query on 2026-09-12 confirmed this public-surface state after the approved metadata refresh:

| Field | Current value | Required action |
| --- | --- | --- |
| Repository | Public at [GGULBAE/desk-setup-switcher](https://github.com/GGULBAE/desk-setup-switcher) | Keep public |
| Description | “A local-first macOS menu bar app for saving, reviewing, and deliberately applying display and sound profiles.” | Keep synchronized with the current product boundary |
| Topics | `appkit`, `audio`, `display-management`, `local-first`, `macos`, `macos-app`, `menu-bar-app`, `open-source`, `privacy-first`, `productivity`, `swift`, `swiftui` | Keep this focused discovery set unless product scope changes |
| Homepage | Blank | Keep blank until the approved site has its final HTTPS URL |
| Social preview | Custom `1280×640` current-scope Capture composition | Keep synchronized with the verified `site/public/og.png` asset |
| Discussions | Disabled | The public support issue form is the current deliberate alternative; do not advertise Discussions while disabled |
| Public release | None | Do not link a download until the complete distribution gate passes and the maintainer-approved canonical release exists |

## Promotion sequence

The repository is the current acquisition surface. No external launch post or directory submission is authorized by this plan, and Threads is deliberately deferred.

| Stage | Channel | Evidence-based rule |
| --- | --- | --- |
| Now | GitHub README, About, Topics, and social preview | Keep the product purpose, supported scope, and first visual consistent. GitHub uses Topics for repository classification and recommends a custom `1280×640` social image for link previews. |
| Supported beta | GitHub Release and existing followers | Make one canonical, checksummed download the source of truth. Keep a Developer ID-unsigned beta bounded to users who can follow the documented Gatekeeper path; Apple recommends Developer ID signing and notarization for software distributed outside the App Store. |
| Runnable public build | Show HN and a rule-compliant macOS community post | Show HN requires something people can actually try, not a landing page or signup. Community posts must follow each community's current self-promotion and disclosure rules. |
| Polished public launch | Product Hunt | Prepare the direct product URL, square thumbnail, gallery images, pricing/status, description, and maker context as a draft; do not ask for votes or launch an unavailable download. |
| Post-launch discovery | AlternativeTo and MacUpdate | Submit only after a public beta/download and accurate platform, license, version, support, and pricing information exist. |
| Signed, notarized, and demanded | Homebrew Cask | Treat Homebrew as an installation channel, not discovery. The official cask policy requires Gatekeeper-compatible software and popularity evidence for self-submissions. |

Primary references: [GitHub Topics](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/classifying-your-repository-with-topics), [GitHub social preview](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/customizing-your-repositorys-social-media-preview), [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [Show HN](https://news.ycombinator.com/showhn.html), [Product Hunt launch preparation](https://www.producthunt.com/launch/preparing-for-launch), [AlternativeTo FAQ](https://alternativeto.net/faq/), [MacUpdate submission guide](https://www.macupdate.com/help/submit-app), and [Homebrew cask policy](https://docs.brew.sh/Acceptable-Casks).

## GitHub repository metadata

### Description

Applied description:

> A local-first macOS menu bar app for saving, reviewing, and deliberately applying display and sound profiles.

This description is safe before or after release because it does not claim that a supported download exists. Capability and verification detail still belongs in the [support matrix](SUPPORT-MATRIX.md).

### Topics

Applied exact set:

```text
macos
macos-app
swift
swiftui
appkit
menu-bar-app
productivity
display-management
audio
local-first
privacy-first
open-source
```

Do not add `intel`, `homebrew`, `app-store`, `automatic-switching`, `accessibility-certified`, `hardware-verified`, or `notarized` unless the corresponding current evidence and support policy change.

### Homepage

- **Before approval:** leave Homepage blank. Do not use a local URL, preview deployment, Actions artifact, unsigned DMG, or direct object-storage URL.
- **Approval placeholder:** record the final HTTPS origin as `APPROVED_SITE_URL` in the separately reviewed tracked site-origin record. The release approval record deliberately grants no site authority. This token is an instruction, not a URL to publish.
- **After approval:** replace the blank Homepage field with that exact origin only after the bilingual site, canonical release link, privacy/security links, and no-tracking checks pass on the deployed site.

### Social preview

Upload only the final sanitized social-preview asset recorded in the release-asset provenance document. It must use synthetic Display/Sound profile data, contain no real identifier, avoid an “applied successfully” claim, and remain legible when cropped.

English alternative text:

> Desk Setup Switcher icon and synthetic Capture screen beside the tagline Bring your desk back, deliberately.

한국어 대체 텍스트:

> Desk Setup Switcher 아이콘과 합성 Capture 화면 옆에 “Bring your desk back, deliberately.” 문구가 표시된 이미지.

Use these strings wherever the publishing surface supports alternative text, including the site and announcement images.

## Launch gallery kit

The repository and owner-only site may show this exact-commit synthetic kit before a supported download exists. Keep the holding-state notice adjacent to it; the screenshots demonstrate the workflow, not release availability or hardware verification.

| Order | Asset | Public-facing message | Boundary |
| --- | --- | --- | --- |
| 1 | `site/public/gallery/01-capture.png` | Capture current settings | Reads the synthetic Display/Sound state; no live Capture was run |
| 2 | `site/public/gallery/02-edit-display.png` | Shape the display profile | Shows main-display and supported-resolution editing; no Save or hardware operation occurred |
| 3 | `site/public/gallery/03-edit-sound.png` | Set the sound profile | Shows output/input, volume, and output mute with synthetic devices |
| 4 | `site/public/gallery/04-review.png` | Review before Apply | Ends at the review decision; no Apply click, success state, or hardware effect is shown |

The companion `site/public/demo/desk-setup-switcher.mp4` is a silent 40-second Capture → Display → Sound → Review tour with English and Korean WebVTT captions. Site playback must expose controls, must not autoplay or loop, and should use the Review gallery card as its poster. The durable transcript summary is: capture available Display/Sound values locally, edit the display and sound steps, inspect the proposed changes, then choose separately whether to Apply. Profiles remain local and never switch automatically.

## Project introduction

### English short

Save available values from seven Display and Sound setting kinds as a local profile, edit them, and review every change before applying it. Desk Setup Switcher is a local-only, open-source macOS menu bar app that never switches profiles automatically.

### English full

Desk Setup Switcher is a free, open-source macOS menu bar app for people who move between desk setups. Save available values from seven setting kinds—main display, resolution, output device/volume/mute, and input device/volume—into a local profile, edit them, then review every planned change before explicitly applying it. There are no per-setting inclusion switches or editable refresh-rate setting; resolution keeps the current refresh rate or is skipped. Network and other legacy fields remain dormant compatibility data. Profiles and redacted diagnostics stay on the Mac: there is no account, cloud sync, telemetry, analytics, automatic switching, or in-app updater. Capture queries only Display and Audio and does not request Location permission. The initial public beta targets Apple Silicon with a macOS 14 deployment target, pending the exact-candidate Sonoma lifecycle gate. Capability claims follow the support matrix; physical Intel support is not claimed.

### 한국어 짧은 소개

Display와 Sound의 일곱 가지 설정 종류에서 사용할 수 있는 값을 로컬 프로필로 저장하고, 편집한 뒤, 모든 변경을 검토하고 적용하세요. Desk Setup Switcher는 프로필을 자동으로 전환하지 않는 로컬 전용 오픈소스 macOS 메뉴 막대 앱입니다.

### 한국어 전체 소개

Desk Setup Switcher는 여러 책상 환경을 오가는 사용자를 위한 무료 오픈소스 macOS 메뉴 막대 앱입니다. 주 디스플레이, 해상도, 출력 기기·음량·음소거, 입력 기기·음량의 일곱 가지 설정 종류에서 사용할 수 있는 값을 로컬 프로필로 Capture하고, Edit한 뒤, 예정된 변경을 모두 Review하고 명시적으로 Apply합니다. 설정별 포함 스위치와 편집 가능한 재생률 설정은 없으며, 해상도는 현재 재생률을 유지할 수 없으면 적용에서 제외됩니다. Network와 다른 과거 필드는 호환성을 위한 비활성 데이터로만 남습니다. Capture는 Display와 Audio만 조회하고 위치 권한을 요청하지 않습니다. 프로필과 민감 정보를 제거한 진단은 Mac 안에만 남으며 계정, 클라우드 동기화, 텔레메트리, 분석, 자동 전환, 앱 내 업데이트가 없습니다. 초기 public beta는 macOS 14 배포 타깃의 Apple Silicon을 대상으로 하며 정확한 후보의 Sonoma 수명주기 검증이 먼저 필요합니다. 기능 주장은 지원표를 따르며 실제 Intel 지원은 주장하지 않습니다.

## Pre-publication holding copy

Use this only when a status message is needed before the release gate passes:

### English

> Desk Setup Switcher is preparing its first open-source public beta. The source is public, but there is no supported download yet. Local and CI DMGs are development evidence, not approved releases. The planned beta will be Developer ID-unsigned and not notarized; follow the repository for checksum evidence and the approved GitHub Release announcement.

### 한국어

> Desk Setup Switcher의 첫 오픈소스 public beta를 준비하고 있습니다. 소스는 공개되어 있지만 아직 지원되는 다운로드는 없습니다. 로컬·CI DMG는 개발 증거일 뿐 승인된 릴리스가 아닙니다. 계획된 beta는 Developer ID 미서명·미공증이며, checksum 증거와 승인된 GitHub Release 공지는 저장소에서 확인해 주세요.

Never attach, link, or rename the current ad-hoc DMG in a holding post.

## Publish-only launch drafts

The drafts in this section are locked until `APPROVED_RELEASE_URL`, `APPROVED_SITE_URL`, and `FINAL_DMG_SHA256` have been replaced from their separately approved release/site evidence. Never substitute the current unsigned-development hash. Remove all instruction lines and unused capability variants before posting. The workflow-ready version-specific English/Korean copy lives in the [`v0.1.0` Release notes](releases/v0.1.0.md); it contains no completion evidence and does not claim that publication gates passed.

### GitHub Release notes

Title:

> Desk Setup Switcher v0.1.0 public beta

Body:

> Desk Setup Switcher is a local-only macOS menu bar app for saving and deliberately applying desk profiles.
>
> **Capture → Edit → Review & Apply**
>
> - Capture available values from seven Display and Sound setting kinds without changing the Mac or requesting Location permission: main display, resolution, output device/volume/mute, and input device/volume.
> - Edit the available saved values; missing values remain absent, without per-setting inclusion switches.
> - Review operations and omissions before an explicit Apply.
> - Use protected confirmation and itemized rollback results for high-risk changes.
> - Keep profiles and redacted diagnostics local—no account, cloud, telemetry, analytics, automatic switching, or updater.
>
> **Initial support:** Apple Silicon, macOS 14 Sonoma or later. Intel is not currently supported.
>
> Download the exact Developer ID-unsigned, ad-hoc integrity-signed DMG and checksum from this release's Assets. It is not notarized. Verify SHA-256: `FINAL_DMG_SHA256`, then follow the documented one-time **Open Anyway** procedure.
>
> Read the installation guide, support matrix, privacy policy, and security reporting instructions before applying a profile.

Insert exactly one capability line from the final support matrix:

- If physical apply and independent rollback evidence exists: describe only the exact hardware/OS/capability combinations that passed.
- If it does not exist: `Display and Sound apply/rollback paths remain mock verified rather than hardware-mutation verified; use the beta within the published support-matrix boundary. Network and other legacy fields remain dormant and never reach the current Apply path.`

Suggested Korean summary beneath the English notes:

> Desk Setup Switcher `v0.1.0` public beta는 Display와 Sound의 일곱 가지 설정 종류(주 디스플레이, 해상도, 출력 기기·음량·음소거, 입력 기기·음량)에서 사용할 수 있는 값을 Capture하고 Edit한 뒤, 모든 변경을 Review하고 명시적으로 Apply하는 로컬 전용 macOS 메뉴 막대 앱입니다. 초기 지원 환경은 Apple Silicon 기반 macOS 14 이상입니다. 계정·클라우드·텔레메트리·자동 전환은 없으며 Intel 실기 지원은 주장하지 않습니다. Assets의 Developer ID 미서명·미공증 DMG와 공개된 SHA-256을 확인한 뒤 안내된 일회성 **그래도 열기** 절차를 따르세요.

### English developer-community post

Title:

> Open-source macOS desk profiles with explicit review and rollback

Body:

> Desk Setup Switcher `v0.1.0` public beta is available for Apple Silicon Macs on macOS 14+. It is a Swift/SwiftUI/AppKit menu-bar app with a deliberately small flow: Capture → Edit → Review & Apply.
>
> The safety boundary is the interesting part: adapters follow snapshot → validate → plan → apply → verify → rollback, previews do not mutate, high-risk work has protected confirmation, and results are itemized. Profiles and redacted diagnostics stay local; there is no account, cloud, telemetry, analytics, automatic switching, private API, UI automation, or updater.
>
> Source and architecture: https://github.com/GGULBAE/desk-setup-switcher
>
> Signed/notarized beta and support boundary: `APPROVED_RELEASE_URL`
>
> Contributions around deterministic tests, public macOS APIs, documentation, and redacted hardware evidence are welcome.

Before posting, replace “is available” with the holding copy if the release is not actually public. Add the exact final capability-evidence sentence from the support matrix; do not shorten mock/live-read evidence to “hardware verified.”

### 한국어 개발 커뮤니티 게시물

제목:

> 책상 설정을 3단계로 저장·적용하는 오픈소스 macOS 앱을 공개합니다

본문:

> Desk Setup Switcher `v0.1.0` public beta를 공개합니다. Apple Silicon 기반 macOS 14 이상에서 현재 설정을 **Capture → Edit → Review & Apply** 흐름으로 저장하고 명시적으로 적용하는 Swift/SwiftUI/AppKit 메뉴 막대 앱입니다.
>
> preview에서는 설정을 바꾸지 않고, adapter는 snapshot → validate → plan → apply → verify → rollback 계약을 따릅니다. 위험도가 높은 변경은 보호 확인을 거치며 결과는 항목별로 보여줍니다. 프로필과 민감 정보를 제거한 진단은 Mac 안에만 남고 계정, 클라우드, 텔레메트리, 분석, 자동 전환, private API, UI automation, 앱 내 updater가 없습니다.
>
> 소스·구조: https://github.com/GGULBAE/desk-setup-switcher
>
> 서명·공증 beta와 지원 범위: `APPROVED_RELEASE_URL`
>
> 결정론적 테스트, 공개 macOS API, 영·한 문서, 개인정보를 제거한 실기 증거 관련 기여를 환영합니다.

실제 공개 전에는 “공개합니다”를 사전 안내 문구로 바꾸세요. 최종 지원표의 capability 검증 문장을 그대로 추가하고 mock/live-read 검증을 “하드웨어 검증”으로 축약하지 마세요.

### Short social post in English

> Capture a desk setup. Edit only what belongs. Review every change before Apply. Desk Setup Switcher `v0.1.0` is a local-only, open-source macOS menu bar public beta for Apple Silicon on macOS 14+. No account, cloud, telemetry, analytics, or automatic switching. Site: `APPROVED_SITE_URL` · Verification boundary: `APPROVED_RELEASE_URL`

### 한국어 짧은 게시물

> 현재 책상 설정을 Capture하고, 포함할 값만 Edit한 뒤, 모든 변경을 Review하고 Apply하세요. Desk Setup Switcher `v0.1.0`은 Apple Silicon 기반 macOS 14 이상을 위한 로컬 전용 오픈소스 메뉴 막대 public beta입니다. 계정·클라우드·텔레메트리·분석·자동 전환이 없습니다. 사이트: `APPROVED_SITE_URL` · 검증 경계: `APPROVED_RELEASE_URL`

## No-tracking launch signals

Record only aggregate values already visible on public GitHub surfaces. A manual snapshot at 7 and 30 days is enough.

| Signal | Definition | Limitation |
| --- | --- | --- |
| Release downloads | Public asset-download count for the canonical unsigned DMG, per version | A download is not an install or active user |
| Stars | Public repository star count | Interest is not satisfaction or retention |
| Issues | Public opened/closed counts, unresolved P0/P1 count, and support-question count from public issue forms | Reports are self-selected; never copy private security reports into this metric |
| Discussions | Public thread/answer counts only if Discussions is deliberately enabled later | Currently disabled; do not invent or privately track an equivalent |

Do not add analytics, cookies, pixels, fingerprinting, campaign IDs, URL shorteners with analytics, email capture, telemetry, crash upload, update checks, unique-user estimation, or any new app/site outbound path. Do not report private vulnerability counts or reporter details as marketing metrics. Public GitHub counts are directional project-health signals, not user surveillance and not proof of product quality.

## Approval and application checklist

Do not apply metadata or publish copy until every applicable box has recorded evidence.

- [ ] The active `unsigned-release.yml` path remains manual-only, any historical signed-publication route stays contained, and branch/tag protections plus private vulnerability reporting are configured and confirmed read-only.
- [ ] The exact `v0.1.0` candidate is ad-hoc integrity-signed with no Developer ID identity or notarization ticket, checksummed, and bound to its tag, commit, version, build, architecture, minimum OS, SBOM, and final-DMG provenance without an app rebuild or byte substitution.
- [ ] Browser download and the extracted DMG preserve a real quarantine attribute; checksum and final-DMG provenance match; the first launch receives the expected unidentified-developer block; and the documented one-time **Open Anyway** path opens that exact candidate without disabling Gatekeeper or removing quarantine.
- [ ] Exact-candidate first launch and launch-at-login default-off, upgrade, schema 0→1 migration, backup recovery, import/export, diagnostics, uninstall, and optional app-owned data removal each have separate passing evidence.
- [ ] Three external Apple Silicon reports use browser-downloaded protected workflow artifacts and the identical final DMG SHA-256/final-DMG provenance attestation.
- [ ] At least one of those reports passes the full exact-candidate lifecycle on macOS 14 Sonoma before any launch copy states macOS 14 support.
- [ ] A public read-only query and maintainer decision show zero unresolved P0/P1 issues, and the security responder records only a yes/no no-confidential-blocker sign-off.
- [ ] The final support matrix states the exact evidence for all seven current Display/Sound setting kinds or preserves the explicit mock-verified limitation; Network and other legacy fields remain clearly dormant.
- [ ] The canonical [GitHub Releases page](https://github.com/GGULBAE/desk-setup-switcher/releases) contains only the approved versioned unsigned DMG, matching checksum, and curated English/Korean notes.
- [ ] The Release body is self-contained: it links no branch-lifecycle document and permits only the tag-pinned distribution procedure plus the exact public-support and private-advisory action routes.
- [ ] The final HTTPS site origin and deployment configuration are separately approved. The tracked site-origin record remains `holding`/null before that approval, and a public build must reject any `NEXT_PUBLIC_SITE_URL` that is not the exact approved origin.
- [ ] Before Release publication, prepare and review locally—but do not push or merge—a bounded public-copy finalization patch and record its base commit, tree digest, and file allowlist. It contains no component-code rewrite.
- [ ] After the `v0.1.0` Release and assets are visibly public and reverified, publish that prepared patch for review. It sets `site/release-publication.json` to the exact canonical Release URL, sets the separately approved site-origin record, and synchronizes README, the English/Korean guide index and user guides, PRIVACY, SUPPORT-MATRIX, SECURITY, SUPPORT, and directly required status records. If `master` moved or the tree differs, stop and re-review instead of rebasing silently.
- [ ] Both required CI jobs pass on the finalization review head. Merge through the protected branch, read back the exact `master` SHA and tree digest, then require one `master`-push CI run on that exact SHA with exactly **Verify macOS app** and **Verify public site and release assets** successful.
- [ ] Only after that exact `master` run passes is the bilingual site deployed. A clean session proves the approved canonical/`og:url` metadata, no-cookie/no-tracking boundary, current support/security routes, and that every download link points only to the canonical Release.
- [ ] The screenshot, silent-captioned demo, social preview, captions, and provenance use synthetic or sanitized data and match actual behavior.
- [ ] Private vulnerability reporting is enabled and tested; public support and security links resolve to the intended routes.
- [ ] `APPROVED_RELEASE_URL`, `APPROVED_SITE_URL`, and `FINAL_DMG_SHA256` are replaced in the copies selected for publication. No instruction line or unused variant remains.
- [ ] The maintainer explicitly approves the description, topics, Homepage URL, social preview, Release publication, site publication, and each external post.
- [ ] After applying metadata, a read-only GitHub query confirms the exact description/topics/Homepage and shows no stale current-scope claim for Network/mouse/keyboard, no Intel/Homebrew/accessibility-certification/hardware-verification overclaim, and no claim that the beta is Developer ID-signed or notarized.
- [ ] After publication, every release/site/download link is opened from a clean browser session and the downloaded asset identity is reverified.
- [ ] Homebrew remains “not offered” at publication; after the canonical Release exists, the project-owned tap passes `install`, `upgrade`, `uninstall`, and `zap` against the exact final SHA-256 before it is advertised.
- [ ] Only the public aggregate signals above are recorded; no analytics or telemetry is introduced.

Actual remote metadata mutation, public site deployment, Release publication, and promotional posting remain separate maintainer-approved actions. An owner-only internal preview does not authorize any of them.

## Stable references

- [GitHub repository](https://github.com/GGULBAE/desk-setup-switcher)
- [GitHub Releases](https://github.com/GGULBAE/desk-setup-switcher/releases)
- [User support](../SUPPORT.md)
- [Security reporting](../SECURITY.md)
- [Privacy policy](PRIVACY.md)
- [Support matrix](SUPPORT-MATRIX.md)
- [Distribution gate](DISTRIBUTION.md)
- [Release evidence template](RELEASE-EVIDENCE-TEMPLATE.md)
- [External beta report template](EXTERNAL-BETA-REPORT-TEMPLATE.md)
- [`v0.1.0` curated Release notes](releases/v0.1.0.md)
- [Release incident runbook](RELEASE-INCIDENT-RUNBOOK.md)
- [Governance and release approval](../GOVERNANCE.md)
