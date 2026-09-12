"use client";

import { useEffect, useState } from "react";
import Image from "next/image";
import { releasePresentation } from "../lib/release-copy.mjs";

const repositoryURL = "https://github.com/GGULBAE/desk-setup-switcher";
const siteBasePath = process.env.NEXT_PUBLIC_SITE_BASE_PATH ?? "";
const publicAssetPath = (path: string) => `${siteBasePath}${path}`;

const content = {
  en: {
    languageName: "English",
    switchLabel: "Language",
    skipLabel: "Skip to content",
    homeLabel: "Desk Setup Switcher home",
    nav: [
      ["How it works", "flow"],
      ["Gallery", "gallery"],
      ["Support", "support"],
      ["Privacy", "privacy"],
      ["FAQ", "faq"],
    ],
    title: "Bring your desk back, deliberately.",
    summary:
      "Save available values from seven display and sound setting kinds as a local profile. Review the exact plan before you apply anything.",
    badges: ["Local only", "No account", "No cloud", "No auto-switching"],
    github: "View source on GitHub",
    heroAlt: "Synthetic empty tray with the Capture Current Settings action",
    scopeLabel: "Current profile scope",
    scopeTitle: "Display + Sound",
    scopeItems: [
      "Main display and resolution",
      "Output device, volume, and mute",
      "Input device and volume",
    ],
    scopeNote: "Seven settings · no Network or automatic switching",
    proof: "Synthetic product data · no personal device identifiers",
    flowEyebrow: "One decision at a time",
    flowTitle: "Capture → Edit → Review & Apply",
    flowSummary:
      "Nothing switches automatically. Each step has one clear purpose, and Apply remains a separate confirmation.",
    steps: [
      {
        number: "01",
        title: "Capture",
        body: "Read the Mac’s current Display and Sound values into a local profile. Capture itself changes nothing.",
      },
      {
        number: "02",
        title: "Edit",
        body: "Name the profile and set any available values across the seven current settings. Missing values stay absent.",
      },
      {
        number: "03",
        title: "Review & Apply",
        body: "Inspect planned changes, omissions, and risk. The Mac changes only after the separate Apply Profile or Apply Available Settings confirmation.",
      },
    ],
    galleryEyebrow: "Current interface",
    galleryTitle: "Four screens. One deliberate flow.",
    gallerySummary:
      "These current-interface screens use synthetic product data. They show the Display and Sound workflow without performing or claiming a hardware change.",
    galleryProof: "Synthetic data · No Apply performed · No automatic switching",
    galleryItems: [
      {
        number: "01",
        title: "Capture",
        body: "Read the Mac’s available Display and Sound values into a local profile. Capture itself changes nothing.",
        image: "/gallery/01-capture.png",
        alt: "Synthetic Desk Setup Switcher tray showing the Capture Current Settings action",
      },
      {
        number: "02",
        title: "Edit Display",
        body: "Choose the saved main display and resolution from values available to the profile.",
        image: "/gallery/02-edit-display.png",
        alt: "Synthetic profile editor showing main display and resolution controls",
      },
      {
        number: "03",
        title: "Edit Sound",
        body: "Review output device, volume, and mute alongside input device and volume.",
        image: "/gallery/03-edit-sound.png",
        alt: "Synthetic profile editor showing output and input sound controls",
      },
      {
        number: "04",
        title: "Review",
        body: "Inspect every planned change and omission before a separate Apply decision.",
        image: "/gallery/04-review.png",
        alt: "Synthetic Apply Preview listing planned changes before the separate Apply action",
      },
    ],
    demoTitle: "Watch the workflow",
    demoSummary:
      "This short, silent walkthrough moves through Capture, Display editing, Sound editing, and Review. It never simulates pressing Apply or a successful hardware change.",
    demoLabel: "Desk Setup Switcher Capture, Display, Sound, and Review walkthrough",
    demoFallback: "Download the MP4 walkthrough",
    transcriptTitle: "Transcript summary",
    transcriptItems: [
      "Capture reads available Display and Sound values into a local profile without changing the Mac.",
      "Edit Display sets the saved main display and resolution.",
      "Edit Sound sets available output and input values.",
      "Review lists planned changes and omissions; only a separate explicit Apply can begin a system change.",
    ],
    supportEyebrow: "Honest support boundary",
    supportTitle: "Two areas. Evidence shown plainly.",
    supportSummary:
      "Current-source read-only group paths passed on Apple Silicon. Apply and rollback paths remain deterministic mock evidence; no live setting mutation has been hardware verified.",
    capabilities: [
      {
        name: "Display",
        items: "Main display and resolution. Resolution keeps the current refresh rate; an unavailable combination is skipped.",
        evidence: "Current-source group live-read · apply/rollback mock-only",
      },
      {
        name: "Sound",
        items: "Output device, volume, and mute; input device and volume. Selecting an input device does not record audio.",
        evidence: "Current-source group live-read · apply/rollback mock-only",
      },
    ],
    safetyEyebrow: "Safety before speed",
    safetyTitle: "High-risk changes get a recovery step.",
    safetyBody:
      "Protected display changes remain temporary during a 15-second review. Keeping them requires explicit confirmation; timeout, window close, or confirmation failure requests restoration of the preflight snapshot. Rollback is best-effort, and hardware mutation remains labelled unverified until independently tested.",
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
      ["No capture permission prompt", "Current Capture reads Display and Sound only. It does not request Location or microphone access."],
      ["Review before sharing", "Exports can contain device labels, stable identifiers, and dormant legacy data. Review and redact them before sharing."],
    ],
    hostingNote:
      "This project code sets no cookies and contains no project analytics or client-side tracking. Its hosting provider still processes requests and may retain aggregate operational metrics.",
    installEyebrow: "Install",
    installSteps: [
      "Download the unsigned DMG and checksum from the canonical GitHub Release.",
      "Verify SHA-256, open the DMG, and drag Desk Setup Switcher to Applications.",
      "After the first blocked launch, use Privacy & Security → Open Anyway once. Never disable Gatekeeper.",
    ],
    faqEyebrow: "FAQ",
    faqTitle: "Know the boundary before you install.",
    faqs: [
      ["Does it switch profiles automatically?", "No. Capture reads, Edit changes a draft, Review explains, and only Apply can start a system change."],
      ["Which settings can a profile save?", "Main display, resolution, output device, output volume, output mute, input device, and input volume. Network is not a current profile feature."],
      ["What happens if a risky display change is wrong?", "Protected display changes offer Keep or Revert and request rollback on timeout, close, or confirmation failure."],
      ["Is Intel supported?", "Not in the initial beta. The build contains an x86_64 slice, but physical Intel install and runtime verification are still missing."],
    ],
    contributeTitle: "Small product. Public evidence.",
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
    skipLabel: "본문으로 건너뛰기",
    homeLabel: "Desk Setup Switcher 홈",
    nav: [
      ["사용 흐름", "flow"],
      ["화면 보기", "gallery"],
      ["지원 범위", "support"],
      ["개인정보", "privacy"],
      ["자주 묻는 질문", "faq"],
    ],
    title: "책상 설정을 바꾸기 전에, 먼저 확인하세요.",
    summary:
      "디스플레이와 사운드의 일곱 가지 설정 종류에서 사용할 수 있는 값을 로컬 프로필로 저장하고, 실제 적용 전에 정확한 변경 계획을 확인하세요.",
    badges: ["로컬 전용", "계정 없음", "클라우드 없음", "자동 전환 없음"],
    github: "GitHub에서 소스 보기",
    heroAlt: "현재 설정 캡처 버튼이 있는 합성 빈 트레이 화면",
    scopeLabel: "현재 프로필 범위",
    scopeTitle: "디스플레이 + 사운드",
    scopeItems: [
      "주 디스플레이와 해상도",
      "출력 기기, 음량, 소리 끔",
      "입력 기기와 음량",
    ],
    scopeNote: "일곱 가지 설정 종류 · 네트워크 및 자동 전환 없음",
    proof: "합성 제품 데이터 · 개인 기기 식별자 없음",
    flowEyebrow: "한 번에 하나의 결정",
    flowTitle: "캡처 → 편집 → 검토 후 적용",
    flowSummary:
      "어떤 프로필도 자동으로 전환되지 않습니다. 단계마다 목적은 하나이며, 실제 적용은 별도의 확인입니다.",
    steps: [
      {
        number: "01",
        title: "캡처",
        body: "현재 Mac의 디스플레이와 사운드 값을 로컬 프로필로 읽습니다. 캡처 자체는 어떤 설정도 바꾸지 않습니다.",
      },
      {
        number: "02",
        title: "편집",
        body: "프로필 이름과 일곱 가지 현재 설정 중 사용할 수 있는 값을 정합니다. 없는 값은 임의로 만들지 않습니다.",
      },
      {
        number: "03",
        title: "검토 후 적용",
        body: "변경 계획, 제외 항목, 위험을 먼저 확인합니다. 별도의 프로필 적용 또는 사용 가능한 설정 적용을 눌러야 Mac이 바뀝니다.",
      },
    ],
    galleryEyebrow: "현재 인터페이스",
    galleryTitle: "네 화면으로 보는 명확한 흐름.",
    gallerySummary:
      "현재 인터페이스를 합성 제품 데이터로 구성한 화면입니다. 실제 하드웨어 설정을 바꾸거나 변경 성공을 주장하지 않고 디스플레이와 사운드 흐름을 보여줍니다.",
    galleryProof: "합성 데이터 · Apply 실행 없음 · 자동 전환 없음",
    galleryItems: [
      {
        number: "01",
        title: "캡처",
        body: "Mac에서 사용할 수 있는 디스플레이와 사운드 값을 로컬 프로필로 읽습니다. 캡처 자체는 아무 설정도 바꾸지 않습니다.",
        image: "/gallery/01-capture.png",
        alt: "현재 설정 캡처 동작을 보여주는 Desk Setup Switcher 합성 트레이 화면",
      },
      {
        number: "02",
        title: "디스플레이 편집",
        body: "프로필에서 사용할 수 있는 값 중 저장할 주 디스플레이와 해상도를 정합니다.",
        image: "/gallery/02-edit-display.png",
        alt: "주 디스플레이와 해상도 조절 항목을 보여주는 합성 프로필 편집 화면",
      },
      {
        number: "03",
        title: "사운드 편집",
        body: "출력 기기·음량·소리 끔과 입력 기기·음량을 한곳에서 확인합니다.",
        image: "/gallery/03-edit-sound.png",
        alt: "출력과 입력 사운드 조절 항목을 보여주는 합성 프로필 편집 화면",
      },
      {
        number: "04",
        title: "검토",
        body: "별도의 적용 결정을 내리기 전에 모든 예정 변경과 제외 항목을 확인합니다.",
        image: "/gallery/04-review.png",
        alt: "별도의 적용 동작 전에 예정된 변경을 나열하는 합성 설정 미리보기 화면",
      },
    ],
    demoTitle: "전체 흐름 보기",
    demoSummary:
      "이 짧은 무음 영상은 캡처, 디스플레이 편집, 사운드 편집, 검토로 이어집니다. Apply를 누르거나 하드웨어 변경이 성공한 것처럼 연출하지 않습니다.",
    demoLabel: "Desk Setup Switcher 캡처, 디스플레이, 사운드, 검토 흐름 영상",
    demoFallback: "MP4 흐름 영상 내려받기",
    transcriptTitle: "영상 내용 요약",
    transcriptItems: [
      "캡처는 Mac을 바꾸지 않고 사용할 수 있는 디스플레이와 사운드 값을 로컬 프로필로 읽습니다.",
      "디스플레이 편집에서 저장할 주 디스플레이와 해상도를 정합니다.",
      "사운드 편집에서 사용할 수 있는 출력과 입력 값을 정합니다.",
      "검토에서 예정 변경과 제외 항목을 확인하며, 별도의 명시적인 Apply에서만 시스템 변경을 시작할 수 있습니다.",
    ],
    supportEyebrow: "정직한 지원 경계",
    supportTitle: "두 가지 영역, 검증 수준까지 그대로.",
    supportSummary:
      "현재 소스의 읽기 전용 그룹 경로는 Apple Silicon에서 통과했습니다. 적용과 되돌리기 경로는 결정론적 모의 검증 상태이며, 실제 설정 변경은 하드웨어에서 검증되지 않았습니다.",
    capabilities: [
      {
        name: "디스플레이",
        items: "주 디스플레이와 해상도. 해상도는 현재 주사율을 유지하며 사용할 수 없는 조합은 건너뜁니다.",
        evidence: "현재 소스 그룹 실기 읽기 · 적용/되돌리기 모의 검증",
      },
      {
        name: "사운드",
        items: "출력 기기, 음량, 소리 끔과 입력 기기, 음량. 입력 기기 선택은 소리를 녹음하지 않습니다.",
        evidence: "현재 소스 그룹 실기 읽기 · 적용/되돌리기 모의 검증",
      },
    ],
    safetyEyebrow: "속도보다 안전",
    safetyTitle: "위험한 변경에는 복구 단계를 둡니다.",
    safetyBody:
      "보호 대상 디스플레이 변경은 15초 동안 임시 상태로 유지됩니다. 명시적으로 확인해야 유지되며, 시간 초과·창 닫기·확인 실패 시 변경 전 상태 복원을 요청합니다. 복구는 최선을 다해 시도하며, 실제 하드웨어 변경은 독립 검증 전까지 미검증으로 표시합니다.",
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
      ["캡처 권한 요청 없음", "현재 캡처는 디스플레이와 사운드만 읽으며 위치 또는 마이크 접근 권한을 요청하지 않습니다."],
      ["공유 전 직접 검토", "내보내기에는 기기 이름, 안정 식별자, 사용하지 않는 과거 데이터가 남을 수 있습니다. 공유 전에 확인하고 가리세요."],
    ],
    hostingNote:
      "이 프로젝트 코드는 쿠키, 프로젝트 분석, 클라이언트 추적을 넣지 않습니다. 다만 호스팅 제공자는 요청을 처리하고 집계된 운영 지표를 보관할 수 있습니다.",
    installEyebrow: "설치",
    installSteps: [
      "공식 GitHub 릴리스에서 미서명 DMG와 체크섬을 내려받습니다.",
      "SHA-256을 확인하고 DMG를 연 뒤 앱을 응용 프로그램으로 옮깁니다.",
      "최초 실행이 차단되면 개인정보 보호 및 보안 → 그래도 열기를 한 번 사용합니다. Gatekeeper는 끄지 마세요.",
    ],
    faqEyebrow: "자주 묻는 질문",
    faqTitle: "설치 전에 경계를 확인하세요.",
    faqs: [
      ["프로필이 자동으로 전환되나요?", "아니요. Capture는 읽고, Edit은 초안을 바꾸고, Review는 설명합니다. 시스템 변경은 Apply에서만 시작할 수 있습니다."],
      ["프로필에 어떤 설정을 저장하나요?", "주 디스플레이, 해상도, 출력 기기, 출력 음량, 출력 소리 끔, 입력 기기, 입력 음량입니다. 네트워크는 현재 프로필 기능이 아닙니다."],
      ["위험한 디스플레이 변경이 잘못되면 어떻게 되나요?", "보호 대상 디스플레이 변경은 유지 또는 되돌리기를 제공하며, 시간 초과·닫기·확인 실패 시 복구를 요청합니다."],
      ["Intel Mac도 지원하나요?", "초기 베타에서는 지원하지 않습니다. x86_64 빌드는 포함하지만 실제 Intel 설치·실행 검증이 없습니다."],
    ],
    contributeTitle: "작은 제품, 공개된 검증.",
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

  useEffect(() => {
    document.documentElement.lang = language;
  }, [language]);

  return (
    <div className="site-shell" lang={language}>
      <a className="skip-link" href="#main-content">
        {text.skipLabel}
      </a>
      <header className="site-header">
        <a className="brand" href="#top" aria-label={text.homeLabel}>
          <Image src={publicAssetPath("/app-icon.svg")} alt="" width={30} height={30} unoptimized />
          <span>Desk Setup Switcher</span>
        </a>
        <nav className="primary-nav" aria-label={language === "en" ? "Primary" : "주요 메뉴"}>
          {text.nav.map(([label, target]) => (
            <a key={target} href={`#${target}`}>
              {label}
            </a>
          ))}
        </nav>
        <div className="language-switch" role="group" aria-label={text.switchLabel}>
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

      <main id="main-content" tabIndex={-1}>
        <section className="hero section-wrap" id="top">
          <div className="hero-copy">
            <p className="eyebrow">{release.eyebrow}</p>
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
          <div className="product-stage" aria-label={language === "en" ? "Current product scope" : "현재 제품 범위"}>
            <div className="stage-glow" />
            <figure className="stage-window current-capture">
              <Image
                src={publicAssetPath("/screenshots/capture.png")}
                alt={text.heroAlt}
                width={368}
                height={260}
                priority
                unoptimized
              />
            </figure>
            <article className="scope-card">
              <p className="scope-label">{text.scopeLabel}</p>
              <h2>{text.scopeTitle}</h2>
              <ul>
                {text.scopeItems.map((item) => (
                  <li key={item}>{item}</li>
                ))}
              </ul>
              <p className="scope-note">{text.scopeNote}</p>
            </article>
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
                <span className="step-number">{step.number}</span>
                <h3>{step.title}</h3>
                <p>{step.body}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="gallery-section" id="gallery" aria-labelledby="gallery-title">
          <div className="section-wrap">
            <div className="gallery-heading">
              <div className="section-heading">
                <p className="eyebrow">{text.galleryEyebrow}</p>
                <h2 id="gallery-title">{text.galleryTitle}</h2>
                <p>{text.gallerySummary}</p>
              </div>
              <p className="gallery-proof">{text.galleryProof}</p>
            </div>

            <div className="gallery-grid">
              {text.galleryItems.map((item) => (
                <figure className="gallery-card" key={item.number}>
                  <div className="gallery-frame">
                    <Image
                      src={publicAssetPath(item.image)}
                      alt={item.alt}
                      width={1270}
                      height={760}
                      unoptimized
                    />
                  </div>
                  <figcaption>
                    <span className="gallery-number" aria-hidden="true">
                      {item.number}
                    </span>
                    <div>
                      <h3>{item.title}</h3>
                      <p>{item.body}</p>
                    </div>
                  </figcaption>
                </figure>
              ))}
            </div>

            <div className="demo-panel">
              <div className="demo-media">
                <video
                  key={language}
                  controls
                  preload="metadata"
                  playsInline
                  poster={publicAssetPath("/gallery/04-review.png")}
                  aria-label={text.demoLabel}
                  aria-describedby="demo-description"
                >
                  <source src={publicAssetPath("/demo/desk-setup-switcher.mp4")} type="video/mp4" />
                  <track
                    kind="captions"
                    src={publicAssetPath("/demo/captions.en.vtt")}
                    srcLang="en"
                    label="English"
                    default={language === "en"}
                  />
                  <track
                    kind="captions"
                    src={publicAssetPath("/demo/captions.ko.vtt")}
                    srcLang="ko"
                    label="한국어"
                    default={language === "ko"}
                  />
                  <a href={publicAssetPath("/demo/desk-setup-switcher.mp4")}>{text.demoFallback}</a>
                </video>
              </div>
              <div className="demo-copy">
                <p className="eyebrow">Demo</p>
                <h3>{text.demoTitle}</h3>
                <p id="demo-description">{text.demoSummary}</p>
                <div className="demo-transcript" aria-labelledby="transcript-title">
                  <h4 id="transcript-title">{text.transcriptTitle}</h4>
                  <ol>
                    {text.transcriptItems.map((item) => (
                      <li key={item}>{item}</li>
                    ))}
                  </ol>
                </div>
              </div>
            </div>
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
            <p className="support-note">{release.supportNote}</p>
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
            {releaseURL ? (
              <ol>
                {text.installSteps.map((step) => (
                  <li key={step}>{step}</li>
                ))}
              </ol>
            ) : null}
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
              <p>{release.contributeBody}</p>
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
          <Image src={publicAssetPath("/app-icon.svg")} alt="" width={26} height={26} unoptimized />
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
