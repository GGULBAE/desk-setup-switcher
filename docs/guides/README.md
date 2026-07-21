# User guides / 사용자 가이드

Desk Setup Switcher is preparing its first public beta. There is no supported download yet. Local and CI-generated DMGs are development evidence and are not end-user releases.

Desk Setup Switcher는 첫 public beta를 준비 중입니다. 아직 지원되는 다운로드는 없습니다. 로컬 및 CI에서 만든 DMG는 개발 검증 자료이며 일반 사용자용 릴리스가 아닙니다.

## Choose a language / 언어 선택

- [English user guide](USER-GUIDE.md)
- [한국어 사용자 가이드](USER-GUIDE.ko.md)

Both guides cover:

- the supported installation path after the official release;
- **Capture → Edit → Review & Apply**;
- permissions, protected changes, and rollback boundaries;
- profile import and export;
- local diagnostics and troubleshooting; and
- uninstalling the app and deleting its local data.

두 가이드에는 다음 내용이 들어 있습니다.

- 정식 공개 후의 지원되는 설치 경로
- **Capture → Edit → Review & Apply**
- 권한, 보호 변경, rollback 경계
- 프로필 가져오기와 내보내기
- 로컬 진단과 문제 해결
- 앱 제거와 로컬 데이터 삭제

## Current boundary / 현재 경계

- Planned public-beta platform: Apple Silicon with a macOS 14 Sonoma deployment target; at least one external exact-candidate lifecycle report must pass on Sonoma before minimum-OS support is claimed.
- Intel is cross-built but physically unverified and is not initially supported.
- On 2026-07-20, opt-in read-only tests passed the then-current Display, Audio, Network, Input, ConditionContext, and ApplyLivePreparation group/base paths on Apple Silicon/macOS 26.5.2. That dated run did not itemize actual ColorSync-profile, input-volume, or service-IPv4 field presence/read on the host; those item-level claims and all Display, Audio, and Network apply/rollback paths remain mock-only, with no live mutation verified.
- The app is local-only: no account, cloud, telemetry, analytics, or automatic switching.
- Keyboard behavior, accessibility names and values, and non-color cues are maintained; comprehensive assistive-technology certification is outside the initial beta scope.

- public beta 예정 환경: macOS 14 Sonoma deployment target의 Apple Silicon. 최소 OS 지원을 주장하기 전에 외부 exact candidate 한 건 이상이 Sonoma에서 전체 수명주기를 통과해야 함
- Intel 빌드는 가능하지만 실기 검증되지 않아 초기 지원 대상이 아님
- 2026-07-20 현재 소스의 Display·Audio·Network·Input·ConditionContext·ApplyLivePreparation 읽기 전용 그룹/기본 경로는 Apple Silicon/macOS 26.5.2에서 통과. 해당 호스트의 ColorSync 프로필·입력 볼륨·서비스 IPv4 개별 필드 존재/읽기는 항목별 증거가 없으며, 그 주장과 모든 Display·Audio·Network 적용/rollback은 mock 전용이고 실제 설정 변경은 미검증
- 계정, 클라우드, 텔레메트리, 분석, 자동 전환이 없는 로컬 전용 앱
- 키보드 동작, 접근성 이름·값, 비색상 단서는 유지하며 포괄적인 보조 기술 인증은 초기 베타 범위에서 제외

For the evidence behind those statements, see the [support matrix](../SUPPORT-MATRIX.md). For help or a security report, use [SUPPORT.md](../../SUPPORT.md) or [SECURITY.md](../../SECURITY.md).

위 내용의 근거는 [지원표](../SUPPORT-MATRIX.md)에서 확인할 수 있습니다. 일반 문의와 보안 신고는 [SUPPORT.md](../../SUPPORT.md) 및 [SECURITY.md](../../SECURITY.md)를 따르세요.
