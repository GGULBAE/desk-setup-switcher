const copy = {
  en: {
    holdingStatus: "v0.1.0 download opens only after the complete release gate passes",
    download: "Download v0.1.0",
    holdingInstallTitle: "A trusted download, once the gate passes.",
    holdingInstallBody:
      "There is no supported public download today. The canonical GitHub Release will open only after the complete release gate—including Developer ID signing, notarization, stapling, Gatekeeper checks, and clean external beta installs—passes.",
    publishedInstallTitle: "Download the signed public beta.",
    publishedInstallBody:
      "Desk Setup Switcher v0.1.0 is available only from the canonical GitHub Release. Download its immutable signed DMG and verify the published SHA-256 before opening it.",
  },
  ko: {
    holdingStatus: "v0.1.0은 전체 릴리스 관문을 통과한 뒤에만 다운로드할 수 있습니다",
    download: "v0.1.0 다운로드",
    holdingInstallTitle: "검증 관문을 통과한 다운로드만 제공합니다.",
    holdingInstallBody:
      "현재 지원되는 공개 다운로드는 없습니다. Developer ID 서명, 공증, stapling, Gatekeeper, 외부 clean-install 베타를 포함한 전체 릴리스 관문을 통과한 뒤 GitHub Release를 공식 다운로드로 엽니다.",
    publishedInstallTitle: "서명된 public beta를 다운로드하세요.",
    publishedInstallBody:
      "Desk Setup Switcher v0.1.0은 공식 GitHub Release에서만 제공합니다. 변경할 수 없는 서명 DMG를 다운로드하고 공개된 SHA-256을 확인한 뒤 여세요.",
  },
};

export function releasePresentation(language, published) {
  const languageCopy = copy[language];
  if (!languageCopy || typeof published !== "boolean") {
    throw new Error("Release presentation requires a supported language and explicit state");
  }
  return Object.freeze({
    actionLabel: published ? languageCopy.download : languageCopy.holdingStatus,
    installTitle: published
      ? languageCopy.publishedInstallTitle
      : languageCopy.holdingInstallTitle,
    installBody: published
      ? languageCopy.publishedInstallBody
      : languageCopy.holdingInstallBody,
  });
}
