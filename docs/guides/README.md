# User guides / 사용자 가이드

Desk Setup Switcher is preparing its first public beta. There is no supported download yet. Local and CI-generated DMGs are development evidence and are not end-user releases.

Desk Setup Switcher는 첫 public beta를 준비 중입니다. 아직 지원되는 다운로드는 없습니다. 로컬 및 CI에서 만든 DMG는 개발 검증 자료이며 일반 사용자용 릴리스가 아닙니다.

## Choose a language / 언어 선택

- [English user guide](USER-GUIDE.md)
- [한국어 사용자 가이드](USER-GUIDE.ko.md)

Both guides cover:

- the supported unsigned installation path after the official release;
- **Capture → Edit → Review & Apply**;
- permissions, protected changes, and rollback boundaries;
- profile import and export;
- local diagnostics and troubleshooting; and
- uninstalling the app and deleting its local data.

두 가이드에는 다음 내용이 들어 있습니다.

- 정식 공개 후의 지원되는 unsigned 설치 경로
- **Capture → Edit → Review & Apply**
- 권한, 보호 변경, rollback 경계
- 프로필 가져오기와 내보내기
- 로컬 진단과 문제 해결
- 앱 제거와 로컬 데이터 삭제

## Current boundary / 현재 경계

- Planned public-beta platform: Apple Silicon with a macOS 14 Sonoma deployment target; at least one external exact-candidate lifecycle report must pass on Sonoma before minimum-OS support is claimed.
- Intel is cross-built but physically unverified and is not initially supported.
- The current profile has ten Display, Sound, and Keyboard settings: main display, resolution, output device/volume/mute, input device/volume, key repeat speed, repeat delay, and keyboard brightness. Repeat values are experimental; brightness is experimental, macOS 15+, and requires previously granted Input Monitoring access plus exactly one compatible readable/writable backlight element from a built-in HID device. Background Capture checks access without requesting it. Pointer, scrolling, function-key, and Network values remain dormant.
- On 2026-07-20, opt-in read-only tests passed the then-current Display, Audio, Network, Input, ConditionContext, and ApplyLivePreparation group/base paths on Apple Silicon/macOS 26.5.2. That run predates the current Keyboard surface; Keyboard Capture, Apply, and rollback remain deterministic mock-only, with no live repeat/backlight mutation verified.
- The app is local-only: no account, cloud, telemetry, analytics, or automatic switching.
- The initial GitHub Release is Developer ID-unsigned and not notarized; users verify its SHA-256 and make one explicit **Open Anyway** decision without disabling Gatekeeper.
- Keyboard behavior, accessibility names and values, and non-color cues are maintained; comprehensive assistive-technology certification is outside the initial beta scope.

- public beta 예정 환경: macOS 14 Sonoma deployment target의 Apple Silicon. 최소 OS 지원을 주장하기 전에 외부 exact candidate 한 건 이상이 Sonoma에서 전체 수명주기를 통과해야 함
- Intel 빌드는 가능하지만 실기 검증되지 않아 초기 지원 대상이 아님
- 현재 프로필은 Display·Sound·Keyboard의 열 가지 설정(주 디스플레이, 해상도, 출력 기기·음량·음소거, 입력 기기·음량, 키 반복 속도, 반복 지연 시간, 키보드 밝기)을 제공. 반복 값은 실험적이고 밝기는 macOS 15 이상에서 입력 모니터링 접근이 미리 허용되어 있으며 내장 HID 기기의 읽기·쓰기 가능한 호환 백라이트 요소가 정확히 하나 있을 때만 조건부로 사용 가능. 백그라운드 Capture는 권한을 자동 요청하지 않으며 포인터·스크롤·기능 키·Network 값은 비활성 상태로 유지
- 2026-07-20 Display·Audio·Network·Input·ConditionContext·ApplyLivePreparation 읽기 전용 그룹/기본 경로는 Apple Silicon/macOS 26.5.2에서 통과했지만 현재 Keyboard 화면보다 앞선 기록임. Keyboard Capture·Apply·rollback은 결정론적 mock 전용이고 실제 반복·백라이트 변경은 미검증
- 계정, 클라우드, 텔레메트리, 분석, 자동 전환이 없는 로컬 전용 앱
- 초기 GitHub Release는 Developer ID 미서명·미공증이며, 사용자는 SHA-256을 확인한 뒤 Gatekeeper를 끄지 않고 **그래도 열기**를 한 번 명시적으로 선택
- 키보드 동작, 접근성 이름·값, 비색상 단서는 유지하며 포괄적인 보조 기술 인증은 초기 베타 범위에서 제외

For the evidence behind those statements, see the [support matrix](../SUPPORT-MATRIX.md). For help or a security report, use [SUPPORT.md](../../SUPPORT.md) or [SECURITY.md](../../SECURITY.md).

위 내용의 근거는 [지원표](../SUPPORT-MATRIX.md)에서 확인할 수 있습니다. 일반 문의와 보안 신고는 [SUPPORT.md](../../SUPPORT.md) 및 [SECURITY.md](../../SECURITY.md)를 따르세요.
