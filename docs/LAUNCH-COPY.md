# Launch copy and repository metadata

Last reviewed: 2026-07-18

This document is a copy deck and approval checklist. It does not authorize a GitHub setting change, site deployment, release publication, or community post.

Desk Setup Switcher currently has no supported download. The local/CI DMG is ad-hoc signed development evidence, not a Developer ID-signed, notarized, stapled, or Gatekeeper-verified public artifact. Keep every public-download sentence below unpublished until the complete [distribution gate](DISTRIBUTION.md) passes and the maintainer explicitly approves publication.

## Current remote state

A read-only GitHub query on 2026-07-18 returned:

| Field | Current value | Required action |
| --- | --- | --- |
| Repository | Public at [GGULBAE/desk-setup-switcher](https://github.com/GGULBAE/desk-setup-switcher) | Keep public |
| Description | Advertises display, audio, network, mouse, and keyboard profiles | Replace; mouse and keyboard are dormant compatibility data, not the current product surface |
| Topics | None | Add the reviewed topics below |
| Homepage | Blank | Keep blank until the approved site has its final HTTPS URL |
| Discussions | Disabled | The public support issue form is the current deliberate alternative; do not advertise Discussions while disabled |
| Public release | None | Do not link a download until the complete distribution gate passes and the maintainer-approved canonical release exists |

## GitHub repository metadata

### Description

Proposed description:

> Local-only macOS menu bar app to capture, edit, review, and explicitly apply display, audio, and network profiles—with rollback.

This description is safe before or after release because it does not claim that a supported download exists. Capability and verification detail still belongs in the [support matrix](SUPPORT-MATRIX.md).

### Topics

Apply this exact reviewed set unless GitHub rejects a topic:

```text
macos
swift
swiftui
appkit
menu-bar-app
local-first
privacy
display-settings
audio-settings
network-settings
apple-silicon
open-source
```

Do not add `intel`, `homebrew`, `app-store`, `automatic-switching`, `accessibility-certified`, `hardware-verified`, or `notarized` unless the corresponding current evidence and support policy change.

### Homepage

- **Before approval:** leave Homepage blank. Do not use a local URL, preview deployment, Actions artifact, unsigned DMG, or direct object-storage URL.
- **Approval placeholder:** record the final deployed HTTPS origin as `APPROVED_SITE_URL` in the release approval record. This token is an instruction, not a URL to publish.
- **After approval:** replace the blank Homepage field with that exact origin only after the bilingual site, canonical release link, privacy/security links, and no-tracking checks pass on the deployed site.

### Social preview

Upload only the final sanitized social-preview asset recorded in the release-asset provenance document. It must use synthetic profile/device/network data, contain no real identifier, avoid an “applied successfully” claim, and remain legible when cropped.

English alternative text:

> Desk Setup Switcher icon and synthetic Display profile editor beside the Capture, Edit, Review & Apply flow.

한국어 대체 텍스트:

> Desk Setup Switcher 아이콘과 합성 디스플레이 프로필 편집 화면 옆에 Capture, Edit, Review & Apply 흐름이 표시된 이미지.

Use these strings wherever the publishing surface supports alternative text, including the site and announcement images.

## Project introduction

### English short

Capture a desk setup, choose what belongs in the profile, and review every change before applying it. Desk Setup Switcher is a local-only, open-source macOS menu bar app for display, audio, and network profiles.

### English full

Desk Setup Switcher is a free, open-source macOS menu bar app for people who move between desk setups. Capture readable display, audio, and network settings into a local profile, edit only what should be included, then review every planned change before explicitly applying it. Profiles and redacted diagnostics stay on the Mac: there is no account, cloud sync, telemetry, analytics, automatic switching, or in-app updater. The initial public beta targets Apple Silicon on macOS 14 or later. Capability claims follow the support matrix; physical Intel support is not claimed.

### 한국어 짧은 소개

현재 책상 설정을 캡처하고, 프로필에 넣을 값만 고른 뒤, 모든 변경을 검토하고 적용하세요. Desk Setup Switcher는 디스플레이·오디오·네트워크 프로필을 위한 로컬 전용 오픈소스 macOS 메뉴 막대 앱입니다.

### 한국어 전체 소개

Desk Setup Switcher는 여러 책상 환경을 오가는 사용자를 위한 무료 오픈소스 macOS 메뉴 막대 앱입니다. 읽을 수 있는 디스플레이·오디오·네트워크 설정을 로컬 프로필로 Capture하고, 포함할 값만 Edit한 뒤, 예정된 변경을 모두 Review하고 명시적으로 Apply합니다. 프로필과 민감 정보를 제거한 진단은 Mac 안에만 남으며 계정, 클라우드 동기화, 텔레메트리, 분석, 자동 전환, 앱 내 업데이트가 없습니다. 초기 public beta는 Apple Silicon 기반 macOS 14 이상을 대상으로 합니다. 기능 주장은 지원표를 따르며 실제 Intel 지원은 주장하지 않습니다.

## Pre-publication holding copy

Use this only when a status message is needed before the release gate passes:

### English

> Desk Setup Switcher is preparing its first open-source public beta. The source is public, but there is no supported download yet. The current development DMG is not a signed or notarized release. Follow the repository for release evidence and the approved download announcement.

### 한국어

> Desk Setup Switcher의 첫 오픈소스 public beta를 준비하고 있습니다. 소스는 공개되어 있지만 아직 지원되는 다운로드는 없습니다. 현재 개발용 DMG는 서명·공증된 릴리스가 아닙니다. 출시 증거와 승인된 다운로드 공지는 저장소에서 확인해 주세요.

Never attach, link, or rename the current ad-hoc DMG in a holding post.

## Publish-only launch drafts

The drafts in this section are locked until `APPROVED_RELEASE_URL`, `APPROVED_SITE_URL`, and `FINAL_DMG_SHA256` have been replaced from the protected approval record. Never substitute the current unsigned-development hash. Remove all instruction lines and unused capability variants before posting. The workflow-ready version-specific English/Korean copy lives in the [`v0.1.0` Release notes](releases/v0.1.0.md); it contains no completion evidence and does not claim that signing or publication passed.

### GitHub Release notes

Title:

> Desk Setup Switcher v0.1.0 public beta

Body:

> Desk Setup Switcher is a local-only macOS menu bar app for saving and deliberately applying desk profiles.
>
> **Capture → Edit → Review & Apply**
>
> - Capture readable display, audio, and network settings without changing the Mac.
> - Include only the values you want in each profile.
> - Review operations and omissions before an explicit Apply.
> - Use protected confirmation and itemized rollback results for high-risk changes.
> - Keep profiles and redacted diagnostics local—no account, cloud, telemetry, analytics, automatic switching, or updater.
>
> **Initial support:** Apple Silicon, macOS 14 Sonoma or later. Intel is not currently supported.
>
> Download the immutable Developer ID-signed, notarized, and stapled DMG from this release's Assets. Verify SHA-256: `FINAL_DMG_SHA256`.
>
> Read the installation guide, support matrix, privacy policy, and security reporting instructions before applying a profile.

Insert exactly one capability line from the final support matrix:

- If physical apply and independent rollback evidence exists: describe only the exact hardware/OS/capability combinations that passed.
- If it does not exist: `Display, Audio, and Network apply/rollback paths remain mock verified rather than hardware-mutation verified; use the beta within the published support-matrix boundary.`

Suggested Korean summary beneath the English notes:

> Desk Setup Switcher `v0.1.0` public beta는 현재 설정을 Capture하고, 프로필에 포함할 값을 Edit한 뒤, 모든 변경을 Review하고 명시적으로 Apply하는 로컬 전용 macOS 메뉴 막대 앱입니다. 초기 지원 환경은 Apple Silicon 기반 macOS 14 이상입니다. 계정·클라우드·텔레메트리·자동 전환은 없으며 Intel 실기 지원은 주장하지 않습니다. Assets의 서명·공증 DMG와 공개된 SHA-256을 사용하세요.

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
| Release downloads | Public asset-download count for the canonical signed DMG, per version | A download is not an install or active user |
| Stars | Public repository star count | Interest is not satisfaction or retention |
| Issues | Public opened/closed counts, unresolved P0/P1 count, and support-question count from public issue forms | Reports are self-selected; never copy private security reports into this metric |
| Discussions | Public thread/answer counts only if Discussions is deliberately enabled later | Currently disabled; do not invent or privately track an equivalent |

Do not add analytics, cookies, pixels, fingerprinting, campaign IDs, URL shorteners with analytics, email capture, telemetry, crash upload, update checks, unique-user estimation, or any new app/site outbound path. Do not report private vulnerability counts or reporter details as marketing metrics. Public GitHub counts are directional project-health signals, not user surveillance and not proof of product quality.

## Approval and application checklist

Do not apply metadata or publish copy until every applicable box has recorded evidence.

- [ ] The unsafe effective remote unsigned-publication workflow is gone; branch/tag protections, the protected `release-candidate` environment/reviewer, private vulnerability reporting, and immutable releases are configured and confirmed read-only.
- [ ] The protected `v0.1.0` candidate is Developer ID signed, hardened, timestamped, notarized, stapled, Gatekeeper assessed, checksummed, and bound to its tag/commit/build/SBOM plus all three subject-specific attestation bundles without an app rebuild or identity/resource change.
- [ ] Browser download and the extracted DMG preserve a real quarantine attribute; checksum and final-DMG provenance match, and Gatekeeper opens the official candidate without Open Anyway.
- [ ] Exact-candidate first launch and launch-at-login default-off, upgrade, schema 0→1 migration, backup recovery, import/export, diagnostics, uninstall, and optional app-owned data removal each have separate passing evidence.
- [ ] Three external Apple Silicon reports use browser-downloaded protected workflow artifacts and the identical final DMG SHA-256/final-DMG provenance attestation.
- [ ] A public read-only query and maintainer decision show zero unresolved P0/P1 issues, and the security responder records only a yes/no no-confidential-blocker sign-off.
- [ ] The final support matrix states the exact Display/Audio/Network hardware-mutation evidence or preserves the explicit mock-verified limitation.
- [ ] The canonical [GitHub Releases page](https://github.com/GGULBAE/desk-setup-switcher/releases) contains the approved immutable assets and curated English/Korean notes.
- [ ] The bilingual site is deployed at its final HTTPS origin, passes its no-cookie/no-tracking checks, and any download link points only to the canonical release.
- [ ] After the immutable `v0.1.0` Release is public, the reviewed `site/release-publication.json` change sets `state` to `published` and its URL to exactly `https://github.com/GGULBAE/desk-setup-switcher/releases/tag/v0.1.0`; no component or copy rewrite accompanies that activation.
- [ ] The screenshot, silent-captioned demo, social preview, captions, and provenance use synthetic or sanitized data and match actual behavior.
- [ ] Private vulnerability reporting is enabled and tested; public support and security links resolve to the intended routes.
- [ ] `APPROVED_RELEASE_URL`, `APPROVED_SITE_URL`, and `FINAL_DMG_SHA256` are replaced in the copies selected for publication. No instruction line or unused variant remains.
- [ ] The maintainer explicitly approves the description, topics, Homepage URL, social preview, Release publication, site publication, and each external post.
- [ ] After applying metadata, a read-only GitHub query confirms the exact description/topics/Homepage and shows no stale mouse/keyboard, Intel, Homebrew, accessibility-certification, hardware-verification, or unsigned-download claim.
- [ ] After publication, every release/site/download link is opened from a clean browser session and the downloaded asset identity is reverified.
- [ ] Homebrew remains “not offered” at publication; after the canonical Release exists, the project-owned tap passes `install`, `upgrade`, `uninstall`, and `zap` against the exact final SHA-256 before it is advertised.
- [ ] Only the public aggregate signals above are recorded; no analytics or telemetry is introduced.

Actual remote mutation, deployment, Release publication, and promotional posting remain separate maintainer-approved actions.

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
