"use client";

import { useState } from "react";
import Image from "next/image";
import { releasePresentation } from "../lib/release-copy.mjs";

const repositoryURL = "https://github.com/GGULBAE/desk-setup-switcher";

const content = {
  en: {
    languageName: "English",
    switchLabel: "Language",
    nav: [
      ["How it works", "flow"],
      ["Support", "support"],
      ["Privacy", "privacy"],
      ["FAQ", "faq"],
    ],
    eyebrow: "Open-source macOS public beta candidate",
    title: "Bring your desk back, deliberately.",
    summary:
      "Capture display, audio, and network settings. Edit only what matters. Review every proposed change before anything happens.",
    badges: ["Local only", "No account", "No cloud", "No telemetry"],
    github: "View source on GitHub",
    heroAlt: {
      edit: "Synthetic Desk Setup Switcher profile editor showing display settings",
      capture: "Synthetic empty tray with the Capture Current Settings action",
      review: "Synthetic Apply Preview listing planned display and audio changes",
    },
    proof: "Synthetic product data · no personal devices or networks",
    flowEyebrow: "One decision at a time",
    flowTitle: "Capture → Edit → Review & Apply",
    flowSummary:
      "Nothing switches automatically. Each step has one clear purpose, and Apply remains a separate confirmation.",
    steps: [
      {
        number: "01",
        title: "Capture",
        body: "Read the Mac’s current readable snapshot into a new profile. Only values that can complete apply, verification, and rollback appear as runnable. Capture itself changes nothing.",
        image: "/screenshots/capture.png",
        width: 368,
        height: 260,
        alt: "Empty tray with Capture Current Settings",
      },
      {
        number: "02",
        title: "Edit",
        body: "Choose which Display, Audio, and Network values belong to the profile. Excluded values stay untouched.",
        image: "/screenshots/edit.png",
        width: 900,
        height: 568,
        alt: "Profile editor with display settings",
      },
      {
        number: "03",
        title: "Review & Apply",
        body: "Inspect planned changes, omissions, and risk. The Mac changes only after the separate Apply Profile or Apply Available Settings confirmation.",
        image: "/screenshots/review.png",
        width: 620,
        height: 500,
        alt: "Apply Preview with planned changes",
      },
    ],
    supportEyebrow: "Honest support boundary",
    supportTitle: "Three areas. Evidence shown plainly.",
    supportSummary:
      "Current-source read-only group/base paths passed on Apple Silicon. Individual ColorSync-profile, input-volume, and service-IPv4 field presence/read was not itemized; every listed apply and rollback path remains deterministic mock evidence. No live setting mutation has been hardware verified.",
    capabilities: [
      {
        name: "Displays",
        items: "Output mode, primary display, resolution, refresh rate, ColorSync ICC profile",
        evidence: "Current-source group/base live-read · item-level read unclaimed · apply/rollback mock-only",
      },
      {
        name: "Audio",
        items: "Default input/output and settable device volume",
        evidence: "Current-source group/base live-read · item-level read unclaimed · apply/rollback mock-only",
      },
      {
        name: "Network",
        items: "Exact Ethernet/Wi-Fi service DHCP or manual IPv4",
        evidence: "Current-source group/base live-read · service-IPv4 item read unclaimed · apply/rollback mock-only",
      },
    ],
    supportNote:
      "Planned v0.1.0 platform: Apple Silicon with a macOS 14 deployment target. Exact-candidate lifecycle testing on Sonoma remains a release gate. The packaged Intel slice is not a physical Intel support claim.",
    safetyEyebrow: "Safety before speed",
    safetyTitle: "High-risk changes get a recovery step.",
    safetyBody:
      "Display and network changes remain temporary during a 15-second review. Keeping them requires explicit confirmation; timeout, window close, or confirmation failure asks the adapters to restore the preflight snapshot. Rollback is best-effort, and hardware mutation remains labelled unverified until independently tested.",
    safetyPoints: [
      "Fresh snapshot before execution",
      "15-second Keep / Revert window",
      "Itemized success, failure, omission, and rollback result",
    ],
    safetyChoices: ["Keep Changes", "Revert Now"],
    privacyEyebrow: "Private by architecture",
    privacyTitle: "Your desk profile stays on your Mac.",
    privacyCards: [
      ["No outbound app service", "No account, sync server, updater, product analytics, ads, or telemetry path."],
      ["Permission at the boundary", "Location authorization is requested only when macOS requires it to reveal the current Wi-Fi name. The app never requests coordinates, and you can capture without Wi-Fi."],
      ["Review before sharing", "Exports never contain Wi-Fi passwords, but labels, SSIDs, network ranges, and legacy location conditions can be sensitive. Dormant or snapshot-only values can remain in JSON with inclusion off."],
    ],
    hostingNote:
      "This project code sets no cookies and contains no project analytics or client-side tracking. Its hosting provider still processes requests and may retain aggregate operational metrics.",
    installEyebrow: "Install",
    installSteps: [
      "Download the signed DMG and checksum from the canonical GitHub Release.",
      "Verify SHA-256, open the DMG, and drag Desk Setup Switcher to Applications.",
      "Launch the menu-bar app. Launch at login stays off until you opt in.",
    ],
    demoTitle: "37-second silent walkthrough",
    demoBody: "Synthetic screens, captions on, no live system changes.",
    demoLabel: "Desk Setup Switcher silent product walkthrough",
    faqEyebrow: "FAQ",
    faqTitle: "Know the boundary before you install.",
    faqs: [
      ["Does it switch profiles automatically?", "No. Capture reads, Edit changes a draft, Review explains, and only Apply can start a system change."],
      ["Why can Wi-Fi capture ask for Location?", "macOS can require Location authorization to reveal the current Wi-Fi name. The app explains this first and offers a Wi-Fi-free capture path."],
      ["What happens if a risky change is wrong?", "Protected display and network changes offer Keep or Revert and attempt rollback on timeout, close, or confirmation failure."],
      ["Is Intel supported?", "Not in the initial beta. The build contains an x86_64 slice, but physical Intel install and runtime verification are still missing."],
    ],
    contributeTitle: "Small product. Public evidence.",
    contributeBody:
      "Contributions are welcome when they preserve the local-only, explicit-apply, public-API safety boundary. Follow the current SECURITY.md instructions for sensitive reports; private vulnerability reporting must be enabled and tested before release.",
    contribute: "Contributing guide",
    security: "Security reporting",
    userGuide: "User guide",
    userGuidePath: "docs/guides/USER-GUIDE.md",
    supportMatrix: "Support matrix",
    supportHelp: "Support",
    privacyPolicy: "Privacy policy",
    source: "Source",
    license: "MIT License",
    footer: "No project-set cookies. No project analytics. No client-side tracking.",
  },
  ko: {
    languageName: "한국어",
    switchLabel: "언어",
    nav: [
      ["사용 흐름", "flow"],
      ["지원 범위", "support"],
      ["개인정보", "privacy"],
      ["자주 묻는 질문", "faq"],
    ],
    eyebrow: "오픈소스 macOS 공개 베타 후보",
    title: "내 책상 설정을, 내가 확인하고 되돌립니다.",
    summary:
      "디스플레이·오디오·네트워크 설정을 캡처하고 필요한 값만 편집하세요. 실제 변경 전에는 항상 모든 변경 내용을 검토합니다.",
    badges: ["로컬 전용", "계정 없음", "클라우드 없음", "텔레메트리 없음"],
    github: "GitHub에서 소스 보기",
    heroAlt: {
      edit: "합성 데이터로 만든 Desk Setup Switcher 디스플레이 프로필 편집 화면",
      capture: "현재 설정 캡처 버튼이 있는 합성 빈 트레이 화면",
      review: "디스플레이와 오디오 변경 계획이 표시된 합성 적용 미리보기",
    },
    proof: "합성 제품 데이터 · 개인 기기 및 네트워크 정보 없음",
    flowEyebrow: "한 번에 하나의 결정",
    flowTitle: "Capture → Edit → Review & Apply",
    flowSummary:
      "어떤 프로필도 자동으로 전환되지 않습니다. 단계마다 목적은 하나이며, 실제 적용은 별도의 확인입니다.",
    steps: [
      {
        number: "01",
        title: "Capture",
        body: "현재 Mac에서 읽을 수 있는 snapshot을 새 프로필로 기록합니다. 적용·확인·rollback까지 수행 가능한 값만 실행 가능한 항목으로 표시됩니다. Capture 자체는 아무 설정도 바꾸지 않습니다.",
        image: "/screenshots/capture.png",
        width: 368,
        height: 260,
        alt: "현재 설정 캡처 버튼이 있는 빈 트레이",
      },
      {
        number: "02",
        title: "Edit",
        body: "프로필에 포함할 디스플레이·오디오·네트워크 값을 고릅니다. 제외한 값은 건드리지 않습니다.",
        image: "/screenshots/edit.png",
        width: 900,
        height: 568,
        alt: "디스플레이 설정을 보여주는 프로필 편집 화면",
      },
      {
        number: "03",
        title: "Review & Apply",
        body: "변경 계획·제외 항목·위험을 먼저 확인합니다. 별도의 프로필 적용 또는 사용 가능한 설정 적용 확인을 눌러야 Mac이 바뀝니다.",
        image: "/screenshots/review.png",
        width: 620,
        height: 500,
        alt: "변경 계획이 표시된 적용 미리보기",
      },
    ],
    supportEyebrow: "정직한 지원 경계",
    supportTitle: "세 가지 영역, 검증 수준까지 그대로.",
    supportSummary:
      "현재 소스의 읽기 전용 그룹/기본 경로는 Apple Silicon에서 통과했습니다. ColorSync 프로필·입력 볼륨·서비스 IPv4 개별 필드의 실제 존재/읽기는 항목별로 확인하지 않았고, 나열한 모든 적용·롤백 경로는 결정론적 mock 증거입니다. 실제 설정 변경은 하드웨어에서 검증되지 않았습니다.",
    capabilities: [
      {
        name: "디스플레이",
        items: "출력 방식, 주 디스플레이, 해상도, 주사율, ColorSync ICC 프로필",
        evidence: "현재 소스 그룹/기본 실기 읽기 · 개별 필드 읽기 미주장 · 적용/롤백 mock 전용",
      },
      {
        name: "오디오",
        items: "기본 입력/출력과 설정 가능한 기기 볼륨",
        evidence: "현재 소스 그룹/기본 실기 읽기 · 개별 필드 읽기 미주장 · 적용/롤백 mock 전용",
      },
      {
        name: "네트워크",
        items: "정확한 Ethernet/Wi-Fi 서비스의 DHCP 또는 수동 IPv4",
        evidence: "현재 소스 그룹/기본 실기 읽기 · 서비스 IPv4 개별 읽기 미주장 · 적용/롤백 mock 전용",
      },
    ],
    supportNote:
      "v0.1.0 예정 환경: macOS 14 deployment target의 Apple Silicon. Sonoma에서 exact candidate 수명주기 검증을 통과해야 출시할 수 있습니다. 패키지의 Intel slice는 실제 Intel 지원을 뜻하지 않습니다.",
    safetyEyebrow: "속도보다 안전",
    safetyTitle: "위험한 변경에는 복구 단계를 둡니다.",
    safetyBody:
      "디스플레이와 네트워크 변경은 15초 검토 중 임시 상태로 유지됩니다. 명시적으로 확인해야 유지되며, 시간 초과·창 닫기·확인 실패 시 어댑터에 사전 스냅샷 복원을 요청합니다. 롤백은 최선의 시도이며 하드웨어 변경은 독립 검증 전까지 미검증으로 표시합니다.",
    safetyPoints: [
      "실행 직전 새 스냅샷",
      "15초 유지 / 되돌리기 창",
      "성공·실패·제외·롤백 결과를 항목별 표시",
    ],
    safetyChoices: ["변경 사항 유지", "지금 되돌리기"],
    privacyEyebrow: "구조부터 개인정보 보호",
    privacyTitle: "책상 프로필은 내 Mac에만 남습니다.",
    privacyCards: [
      ["앱의 외부 서비스 없음", "계정, 동기화 서버, 업데이터, 제품 분석, 광고, 텔레메트리 경로가 없습니다."],
      ["필요한 순간에만 권한", "macOS가 현재 Wi-Fi 이름을 제공할 때 요구하는 경우에만 위치 접근 권한을 요청합니다. 앱은 좌표를 요청하지 않으며 Wi-Fi 없이 캡처할 수도 있습니다."],
      ["공유 전 직접 검토", "내보내기에 Wi-Fi 비밀번호는 없지만 이름, SSID, 네트워크 범위, 과거 위치 조건은 민감할 수 있습니다. Dormant 또는 snapshot 전용 값은 포함이 꺼진 채 JSON에 남을 수 있습니다."],
    ],
    hostingNote:
      "이 프로젝트 코드는 쿠키, 프로젝트 분석, 클라이언트 추적을 넣지 않습니다. 다만 호스팅 제공자는 요청을 처리하고 집계된 운영 지표를 보관할 수 있습니다.",
    installEyebrow: "설치",
    installSteps: [
      "공식 GitHub Release에서 서명된 DMG와 checksum을 다운로드합니다.",
      "SHA-256을 확인하고 DMG를 연 뒤 앱을 Applications로 옮깁니다.",
      "메뉴 막대 앱을 실행합니다. 로그인 시 실행은 직접 켜기 전까지 꺼져 있습니다.",
    ],
    demoTitle: "37초 무음 둘러보기",
    demoBody: "합성 화면과 자막만 사용하며 실제 시스템 설정은 바꾸지 않습니다.",
    demoLabel: "Desk Setup Switcher 무음 제품 둘러보기",
    faqEyebrow: "자주 묻는 질문",
    faqTitle: "설치 전에 경계를 확인하세요.",
    faqs: [
      ["프로필이 자동으로 전환되나요?", "아니요. Capture는 읽고, Edit은 초안을 바꾸고, Review는 설명합니다. 시스템 변경은 Apply에서만 시작할 수 있습니다."],
      ["Wi-Fi 캡처에 왜 위치 권한이 필요한가요?", "macOS가 현재 Wi-Fi 이름 공개에 위치 권한을 요구할 수 있습니다. 앱은 먼저 이유를 설명하고 Wi-Fi 없이 캡처하는 선택지도 제공합니다."],
      ["위험한 변경이 잘못되면 어떻게 되나요?", "보호된 디스플레이·네트워크 변경은 유지 또는 되돌리기를 제공하며, 시간 초과·닫기·확인 실패 시 롤백을 시도합니다."],
      ["Intel Mac도 지원하나요?", "초기 베타에서는 지원하지 않습니다. x86_64 slice는 있지만 실제 Intel 설치·실행 검증이 없습니다."],
    ],
    contributeTitle: "작은 제품, 공개된 검증.",
    contributeBody:
      "로컬 전용·명시적 적용·공개 API 안전 경계를 지키는 기여를 환영합니다. 민감한 신고는 현재 SECURITY.md 안내를 따르세요. 비공개 취약점 신고 기능은 출시 전에 활성화하고 검증해야 합니다.",
    contribute: "기여 가이드",
    security: "보안 신고",
    userGuide: "사용 가이드",
    userGuidePath: "docs/guides/USER-GUIDE.ko.md",
    supportMatrix: "지원표",
    supportHelp: "일반 지원",
    privacyPolicy: "개인정보 처리방침",
    source: "소스",
    license: "MIT 라이선스",
    footer: "프로젝트가 설정하는 쿠키 없음. 프로젝트 분석 없음. 클라이언트 추적 없음.",
  },
} as const;

type Language = keyof typeof content;

export function LandingPage({ releaseURL }: { releaseURL: string | null }) {
  const [language, setLanguage] = useState<Language>("en");
  const text = content[language];
  const release = releasePresentation(language, releaseURL !== null);

  return (
    <div className="site-shell" lang={language}>
      <header className="site-header">
        <a className="brand" href="#top" aria-label="Desk Setup Switcher home">
          <Image src="/app-icon.svg" alt="" width={30} height={30} unoptimized />
          <span>Desk Setup Switcher</span>
        </a>
        <nav className="primary-nav" aria-label={language === "en" ? "Primary" : "주요 메뉴"}>
          {text.nav.map(([label, target]) => (
            <a key={target} href={`#${target}`}>
              {label}
            </a>
          ))}
        </nav>
        <div className="language-switch" aria-label={text.switchLabel}>
          {(["en", "ko"] as const).map((key) => (
            <button
              key={key}
              type="button"
              aria-pressed={language === key}
              onClick={() => setLanguage(key)}
            >
              {key === "en" ? "EN" : "한국어"}
            </button>
          ))}
        </div>
      </header>

      <main id="top">
        <section className="hero section-wrap">
          <div className="hero-copy">
            <p className="eyebrow">{text.eyebrow}</p>
            <h1>{text.title}</h1>
            <p className="hero-summary">{text.summary}</p>
            <ul className="trust-list" aria-label={language === "en" ? "Privacy promises" : "개인정보 보호 원칙"}>
              {text.badges.map((badge) => (
                <li key={badge}>{badge}</li>
              ))}
            </ul>
            <div className="hero-actions">
              {releaseURL ? (
                <a className="primary-action" href={releaseURL}>
                  {release.actionLabel}
                </a>
              ) : (
                <span className="release-status" aria-disabled="true">
                  {release.actionLabel}
                </span>
              )}
              <a className={releaseURL ? "secondary-action" : "primary-action"} href={repositoryURL}>
                {text.github}
              </a>
            </div>
          </div>
          <div className="product-stage" aria-label={language === "en" ? "Product screens" : "제품 화면"}>
            <div className="stage-glow" />
            <figure className="stage-window stage-edit">
              <Image src="/screenshots/edit.png" alt={text.heroAlt.edit} width={900} height={568} priority unoptimized />
            </figure>
            <figure className="stage-window stage-capture">
              <Image src="/screenshots/capture.png" alt={text.heroAlt.capture} width={368} height={260} priority unoptimized />
            </figure>
            <figure className="stage-window stage-review">
              <Image src="/screenshots/review.png" alt={text.heroAlt.review} width={620} height={500} priority unoptimized />
            </figure>
            <p className="proof-note">{text.proof}</p>
          </div>
        </section>

        <section className="flow-section section-wrap" id="flow">
          <div className="section-heading">
            <p className="eyebrow">{text.flowEyebrow}</p>
            <h2>{text.flowTitle}</h2>
            <p>{text.flowSummary}</p>
          </div>
          <div className="flow-grid">
            {text.steps.map((step) => (
              <article className="flow-card" key={step.number}>
                <div className="flow-card-copy">
                  <span className="step-number">{step.number}</span>
                  <h3>{step.title}</h3>
                  <p>{step.body}</p>
                </div>
                <div className="flow-image-wrap">
                  <Image
                    src={step.image}
                    alt={step.alt}
                    width={step.width}
                    height={step.height}
                    loading="lazy"
                    unoptimized
                  />
                </div>
              </article>
            ))}
          </div>
        </section>

        <section className="support-section" id="support">
          <div className="section-wrap support-inner">
            <div className="section-heading light-heading">
              <p className="eyebrow">{text.supportEyebrow}</p>
              <h2>{text.supportTitle}</h2>
              <p>{text.supportSummary}</p>
            </div>
            <div className="capability-grid">
              {text.capabilities.map((capability) => (
                <article className="capability-card" key={capability.name}>
                  <div className="capability-mark" aria-hidden="true" />
                  <h3>{capability.name}</h3>
                  <p>{capability.items}</p>
                  <span>{capability.evidence}</span>
                </article>
              ))}
            </div>
            <p className="support-note">{text.supportNote}</p>
          </div>
        </section>

        <section className="safety-section section-wrap">
          <div className="safety-copy">
            <p className="eyebrow">{text.safetyEyebrow}</p>
            <h2>{text.safetyTitle}</h2>
            <p>{text.safetyBody}</p>
            <ul className="check-list">
              {text.safetyPoints.map((point) => (
                <li key={point}>{point}</li>
              ))}
            </ul>
          </div>
          <div className="safety-visual" aria-hidden="true">
            <div className="safety-timer">15</div>
            <div className="safety-line" />
            <div className="safety-choice">
              <span>{text.safetyChoices[0]}</span>
              <span>{text.safetyChoices[1]}</span>
            </div>
          </div>
        </section>

        <section className="privacy-section" id="privacy">
          <div className="section-wrap">
            <div className="section-heading">
              <p className="eyebrow">{text.privacyEyebrow}</p>
              <h2>{text.privacyTitle}</h2>
            </div>
            <div className="privacy-grid">
              {text.privacyCards.map(([title, body], index) => (
                <article key={title}>
                  <span aria-hidden="true">0{index + 1}</span>
                  <h3>{title}</h3>
                  <p>{body}</p>
                </article>
              ))}
            </div>
            <p className="privacy-note">{text.hostingNote}</p>
          </div>
        </section>

        <section className="install-section section-wrap">
          <div className="install-copy">
            <p className="eyebrow">{text.installEyebrow}</p>
            <h2>{release.installTitle}</h2>
            <p>{release.installBody}</p>
            <ol>
              {text.installSteps.map((step) => (
                <li key={step}>{step}</li>
              ))}
            </ol>
          </div>
          <div className="demo-card">
            <div>
              <p className="eyebrow">Demo</p>
              <h3>{text.demoTitle}</h3>
              <p>{text.demoBody}</p>
            </div>
            <video controls muted preload="metadata" poster="/screenshots/edit.png" aria-label={text.demoLabel}>
              <source src="/demo/desk-setup-switcher.mp4" type="video/mp4" />
              <track kind="captions" src="/demo/captions.en.vtt" srcLang="en" label="English" default={language === "en"} />
              <track kind="captions" src="/demo/captions.ko.vtt" srcLang="ko" label="한국어" default={language === "ko"} />
            </video>
          </div>
        </section>

        <section className="faq-section section-wrap" id="faq">
          <div className="section-heading faq-heading">
            <p className="eyebrow">{text.faqEyebrow}</p>
            <h2>{text.faqTitle}</h2>
          </div>
          <div className="faq-list">
            {text.faqs.map(([question, answer]) => (
              <details key={question}>
                <summary>{question}</summary>
                <p>{answer}</p>
              </details>
            ))}
          </div>
        </section>

        <section className="contribute-section">
          <div className="section-wrap contribute-inner">
            <div>
              <p className="eyebrow">Open source</p>
              <h2>{text.contributeTitle}</h2>
              <p>{text.contributeBody}</p>
            </div>
            <div className="contribute-links">
              <a href={`${repositoryURL}/blob/master/CONTRIBUTING.md`}>{text.contribute}</a>
              <a href={`${repositoryURL}/security/policy`}>{text.security}</a>
              <a href={`${repositoryURL}/blob/master/${text.userGuidePath}`}>{text.userGuide}</a>
              <a href={`${repositoryURL}/blob/master/docs/SUPPORT-MATRIX.md`}>{text.supportMatrix}</a>
              <a href={`${repositoryURL}/blob/master/SUPPORT.md`}>{text.supportHelp}</a>
              <a href={`${repositoryURL}/blob/master/docs/PRIVACY.md`}>{text.privacyPolicy}</a>
            </div>
          </div>
        </section>
      </main>

      <footer className="site-footer section-wrap">
        <div className="brand footer-brand">
          <Image src="/app-icon.svg" alt="" width={26} height={26} unoptimized />
          <span>Desk Setup Switcher</span>
        </div>
        <p>{text.footer}</p>
        <div>
          <a href={repositoryURL}>{text.source}</a>
          <a href={`${repositoryURL}/blob/master/LICENSE`}>{text.license}</a>
        </div>
      </footer>
    </div>
  );
}
