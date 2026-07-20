const copy = {
  en: {
    holdingEyebrow: "Open-source macOS public beta candidate",
    publishedEyebrow: "Open-source macOS public beta",
    holdingStatus: "v0.1.0 download opens only after the complete release gate passes",
    download: "Download v0.1.0",
    holdingInstallTitle: "A trusted download, once the gate passes.",
    holdingInstallBody:
      "There is no supported public download today. The canonical GitHub Release will open only after the complete release gate—including Developer ID signing, notarization, stapling, Gatekeeper checks, and clean external beta installs—passes.",
    publishedInstallTitle: "Download the signed public beta.",
    publishedInstallBody:
      "Desk Setup Switcher v0.1.0 is available only from the canonical GitHub Release. Download its immutable signed DMG and verify the published SHA-256 before opening it.",
    holdingSupportNote:
      "Planned v0.1.0 platform: Apple Silicon with a macOS 14 deployment target. Exact-candidate lifecycle testing on Sonoma remains a release gate. The packaged Intel slice is not a physical Intel support claim.",
    publishedSupportNote:
      "v0.1.0 support: Apple Silicon on macOS 14 or later. The packaged x86_64 slice is not physical Intel verification, and Intel remains unsupported.",
    holdingContributeBody:
      "Contributions are welcome when they preserve the local-only, explicit-apply, public-API safety boundary. Follow the current SECURITY.md instructions for sensitive reports; private vulnerability reporting must be enabled and tested before release.",
    publishedContributeBody:
      "Contributions are welcome when they preserve the local-only, explicit-apply, public-API safety boundary. Report sensitive issues through the private vulnerability reporting route in SECURITY.md; do not disclose them in a public issue.",
  },
  ko: {
    holdingEyebrow: "오픈소스 macOS 공개 베타 후보",
    publishedEyebrow: "오픈소스 macOS 공개 베타",
    holdingStatus: "v0.1.0은 전체 릴리스 관문을 통과한 뒤에만 다운로드할 수 있습니다",
    download: "v0.1.0 다운로드",
    holdingInstallTitle: "검증 관문을 통과한 다운로드만 제공합니다.",
    holdingInstallBody:
      "현재 지원되는 공개 다운로드는 없습니다. Developer ID 서명, 공증, stapling, Gatekeeper, 외부 clean-install 베타를 포함한 전체 릴리스 관문을 통과한 뒤 GitHub Release를 공식 다운로드로 엽니다.",
    publishedInstallTitle: "서명된 public beta를 다운로드하세요.",
    publishedInstallBody:
      "Desk Setup Switcher v0.1.0은 공식 GitHub Release에서만 제공합니다. 변경할 수 없는 서명 DMG를 다운로드하고 공개된 SHA-256을 확인한 뒤 여세요.",
    holdingSupportNote:
      "v0.1.0 예정 환경: macOS 14 deployment target의 Apple Silicon. Sonoma에서 exact candidate 수명주기 검증을 통과해야 출시할 수 있습니다. 패키지의 Intel slice는 실제 Intel 지원을 뜻하지 않습니다.",
    publishedSupportNote:
      "v0.1.0 지원 환경: Apple Silicon 기반 macOS 14 이상. 패키지의 x86_64 slice는 실제 Intel 검증이 아니며 Intel은 지원하지 않습니다.",
    holdingContributeBody:
      "로컬 전용·명시적 적용·공개 API 안전 경계를 지키는 기여를 환영합니다. 민감한 신고는 현재 SECURITY.md 안내를 따르세요. 비공개 취약점 신고 기능은 출시 전에 활성화하고 검증해야 합니다.",
    publishedContributeBody:
      "로컬 전용·명시적 적용·공개 API 안전 경계를 지키는 기여를 환영합니다. 민감한 문제는 SECURITY.md의 비공개 취약점 신고 경로로 제보하고 공개 이슈에 내용을 남기지 마세요.",
  },
};

export function releasePresentation(language, published) {
  const languageCopy = copy[language];
  if (!languageCopy || typeof published !== "boolean") {
    throw new Error("Release presentation requires a supported language and explicit state");
  }
  return Object.freeze({
    eyebrow: published ? languageCopy.publishedEyebrow : languageCopy.holdingEyebrow,
    actionLabel: published ? languageCopy.download : languageCopy.holdingStatus,
    installTitle: published
      ? languageCopy.publishedInstallTitle
      : languageCopy.holdingInstallTitle,
    installBody: published
      ? languageCopy.publishedInstallBody
      : languageCopy.holdingInstallBody,
    supportNote: published
      ? languageCopy.publishedSupportNote
      : languageCopy.holdingSupportNote,
    contributeBody: published
      ? languageCopy.publishedContributeBody
      : languageCopy.holdingContributeBody,
  });
}
